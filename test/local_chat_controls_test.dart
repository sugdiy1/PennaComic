import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comic/local_chat_controls.dart';
import 'package:penna/core/harness/providers/llm_http.dart';

void main() {
  test(
    'Bonsai plans preserve response allowance and valid template efforts',
    () {
      final expected = {
        'none': (false, null, 0),
        'low': (true, 'low', 1024),
        'medium': (true, 'medium', 4096),
        'high': (true, 'xhigh', 8192),
        'xhigh': (true, 'xhigh', 16384),
        'unknown': (true, 'medium', 4096),
      };
      for (final entry in expected.entries) {
        final plan = bonsaiReasoningPlan(entry.key);
        expect(plan.enabled, entry.value.$1);
        expect(plan.effort, entry.value.$2);
        expect(plan.budgetTokens, entry.value.$3);
        expect(plan.maxOutputTokens, 16384 + entry.value.$3);
      }
    },
  );

  test(
    'measures active capacity and exact templated tokens; caches props',
    () async {
      final calls = <String>[];
      final bodies = <String, dynamic>{};
      final server = await _server((request) async {
        calls.add(request.uri.path);
        if (request.method == 'POST') {
          bodies[request.uri.path] = jsonDecode(
            await utf8.decodeStream(request),
          );
        }
        return switch (request.uri.path) {
          '/props' => {
            'default_generation_settings': {'n_ctx': 32768},
            'model_context_length': 131072,
          },
          '/apply-template' => {'prompt': '<bos>hello<think>'},
          '/tokenize' => {
            'tokens': [1, 2, 3, 4, 5],
          },
          _ => throw StateError('Unexpected endpoint'),
        };
      });
      final service = LocalContextService();
      final request = _request(server, enableThinking: true, effort: 'xhigh');
      final snapshot = await service.measure(request);
      expect(snapshot.capacity, 32768);
      expect(snapshot.usedTokens, 5);
      expect(snapshot.estimated, isFalse);
      expect(bodies['/apply-template']['messages'], request.messages);
      expect(bodies['/apply-template']['chat_template_kwargs'], {
        'enable_thinking': true,
        'reasoning_effort': 'xhigh',
      });
      expect(bodies['/tokenize'], {
        'content': '<bos>hello<think>',
        'add_special': false,
        'parse_special': true,
      });
      await service.measure(_request(server, enableThinking: false));
      expect(bodies['/apply-template']['chat_template_kwargs'], {
        'enable_thinking': false,
      });
      expect(calls.where((path) => path == '/props'), hasLength(1));
      expect(
        calls,
        everyElement(isIn(['/props', '/apply-template', '/tokenize'])),
      );
    },
  );

  test(
    'failed tokenization falls back to an estimate and retains capacity',
    () async {
      final server = await _server((request) async {
        if (request.uri.path == '/props') {
          return {
            'default_generation_settings': {'n_ctx': 8192},
          };
        }
        if (request.uri.path == '/apply-template') return {'prompt': 'hello'};
        request.response.statusCode = HttpStatus.notFound;
        return {'error': 'unsupported'};
      });
      final snapshot = await LocalContextService().measure(_request(server));
      expect(snapshot.capacity, 8192);
      expect(snapshot.usedTokens, greaterThan(0));
      expect(snapshot.estimated, isTrue);
    },
  );

  test('missing props never substitutes the model training context', () async {
    final server = await _server((request) async {
      return switch (request.uri.path) {
        '/props' => {'model_context_length': 131072},
        '/apply-template' => {'prompt': 'text'},
        '/tokenize' => {
          'tokens': [1, 2],
        },
        _ => null,
      };
    });
    final snapshot = await LocalContextService().measure(_request(server));
    expect(snapshot.capacity, isNull);
    expect(snapshot.usedTokens, 2);
    expect(snapshot.estimated, isFalse);
  });

  test('images mark text-only tokenization as estimated', () async {
    final server = await _server((request) async {
      if (request.method == 'POST') {
        final body = jsonDecode(await utf8.decodeStream(request));
        expect(jsonEncode(body), isNot(contains('image_url')));
      }
      return switch (request.uri.path) {
        '/props' => {
          'default_generation_settings': {'n_ctx': 8192},
        },
        '/apply-template' => {'prompt': 'text only'},
        '/tokenize' => {
          'tokens': [1, 2, 3],
        },
        _ => null,
      };
    });
    final snapshot = await LocalContextService().measure(
      _request(
        server,
        images: {
          0: [
            (mime: 'image/png', bytes: Uint8List.fromList([1, 2, 3])),
          ],
        },
      ),
    );
    expect(snapshot.usedTokens, 3);
    expect(snapshot.estimated, isTrue);
  });

  test(
    'remote addresses are rejected locally with a conservative estimate',
    () async {
      final service = LocalContextService();
      for (final url in [
        'https://example.com/v1',
        'http://192.168.1.2:8080/v1',
        'http://localhost.example.com/v1',
        'file:///v1',
      ]) {
        final snapshot = await service.measure(
          LlmRequest(
            baseUrl: url,
            model: 'Bonsai',
            apiKey: '',
            messages: const [],
          ),
        );
        expect(snapshot.capacity, isNull);
        expect(snapshot.usedTokens, greaterThan(0));
        expect(snapshot.estimated, isTrue);
      }
      Future<int?> estimate(String text) async => (await service.measure(
        LlmRequest(
          baseUrl: 'https://example.com/v1',
          model: 'Bonsai',
          apiKey: '',
          messages: [
            {'role': 'user', 'content': text},
          ],
        ),
      )).usedTokens;
      expect(await estimate('中文内容'), greaterThan((await estimate('text'))!));
    },
  );

  test(
    'loopback endpoints cannot redirect measurement to another server',
    () async {
      var redirectedCalls = 0;
      final destination = await _server((request) async {
        redirectedCalls++;
        return {};
      });
      final server = await _server((request) async {
        request.response.statusCode = HttpStatus.temporaryRedirect;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${destination.port}/redirected',
        );
        return {};
      });
      final snapshot = await LocalContextService().measure(_request(server));
      expect(snapshot.estimated, isTrue);
      expect(redirectedCalls, 0);
    },
  );
}

LlmRequest _request(
  HttpServer server, {
  bool? enableThinking,
  String? effort,
  Map<int, List<LlmImage>> images = const {},
}) => LlmRequest(
  baseUrl: 'http://127.0.0.1:${server.port}/v1/',
  model: 'Bonsai',
  apiKey: '',
  messages: const [
    {'role': 'user', 'content': 'hello'},
  ],
  enableThinking: enableThinking,
  reasoningEffort: effort,
  images: images,
);

Future<HttpServer> _server(
  Future<Object?> Function(HttpRequest request) handle,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    final body = await handle(request);
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  });
  return server;
}
