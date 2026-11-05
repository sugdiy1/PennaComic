import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/core/harness/comic/layout_context_policy.dart';

void main() {
  setUp(() => HttpOverrides.global = null);
  test('思考与正文分开，末尾空choices仍上报实际usage，缓存不重复相加', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    Map? body;
    server.listen((request) async {
      body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      final response = request.response;
      response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      for (final packet in [
        {
          'choices': [
            {
              'delta': {'reasoning_content': 'internal reasoning sample'},
              'finish_reason': null,
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {'content': '42'},
              'finish_reason': null,
            },
          ],
        },
        {
          'choices': [
            {'delta': {}, 'finish_reason': 'stop'},
          ],
        },
        {
          'choices': [],
          'usage': {
            'prompt_tokens': 120,
            'completion_tokens': 10,
            'total_tokens': 130,
            'prompt_tokens_details': {'cached_tokens': 30},
          },
        },
      ]) {
        response.write('data: ${jsonEncode(packet)}\n\n');
      }
      response.write('data: [DONE]\n\n');
      await response.close();
    });
    LlmUsage? usage;
    var thought = 0, answer = 0;
    final output = await streamOpenAiChat(
      LlmRequest(
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'test',
        apiKey: '',
        messages: const [],
        reasoningEffort: 'xhigh',
        enableThinking: true,
        reasoningBudgetTokens: 8192,
        maxOutputTokens: 24576,
        onUsage: (v) => usage = v,
        onReasoning: () => thought++,
        onAnswer: () => answer++,
      ),
    ).join();
    expect(output, '42');
    expect(thought, 1);
    expect(answer, 1);
    expect(usage!.totalTokens, 130);
    expect(usage!.cachedTokens, 30);
    expect(body!['chat_template_kwargs'], {'enable_thinking': true});
    expect(body!['reasoning_budget_tokens'], 8192);
    expect(body!['reasoning_effort'], 'xhigh');
    expect(body!['max_tokens'], 24576);
    expect(body!['stream_options'], {'include_usage': true});
  });

  test('只有思考没有正文时明确报错，不把思考当正文', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      final r = request.response;
      r.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      r.write(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'reasoning_content': '想了很久但没有答'},
              'finish_reason': null,
            },
          ],
        })}\n\n',
      );
      r.write(
        'data: ${jsonEncode({
          'choices': [
            {'delta': {}, 'finish_reason': 'stop'},
          ],
        })}\n\ndata: [DONE]\n\n',
      );
      await r.close();
    });
    var answer = 0;
    final stream = streamOpenAiChat(
      LlmRequest(
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'test',
        apiKey: '',
        messages: const [],
        enableThinking: true,
        onAnswer: () => answer++,
      ),
    );
    await expectLater(stream.join(), throwsA(isA<LlmException>()));
    expect(answer, 0);
  });

  for (final truncated in [false, true]) {
    test('带思考的结构化布局${truncated ? '截断报错' : '只解析正文JSON'}', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final envelope = jsonEncode({
        'pages': [
          {
            'target': 'current',
            'name': '安全测试',
            'layout': {
              'summary': {'caption': 'A test panel'},
              'items': [
                {
                  'name': '第1格',
                  'label': 'object',
                  'caption': 'A quiet street',
                  'bbox': [0, 0, 400, 500],
                  'text': '',
                },
              ],
              'bbox_coord_space': 'abs',
              'bbox_format': 'xyxy',
            },
          },
        ],
      });
      server.listen((request) async {
        await request.drain<void>();
        final r = request.response;
        r.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        r.write(
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'reasoning_content': 'not part of layout'},
              },
            ],
          })}\n\n',
        );
        r.write(
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': truncated ? envelope.substring(0, 40) : envelope},
                'finish_reason': truncated ? 'length' : 'stop',
              },
            ],
          })}\n\ndata: [DONE]\n\n',
        );
        await r.close();
      });
      final stream = streamOpenAiChat(
        LlmRequest(
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'test',
          apiKey: '',
          messages: const [],
          enableThinking: true,
          layoutSchema: localLayoutSchema,
        ),
      );
      if (truncated) {
        await expectLater(stream.join(), throwsA(isA<LlmException>()));
      } else {
        final output = await stream.join();
        expect(output, startsWith('<layout'));
        expect(output, isNot(contains('not part of layout')));
      }
    });
  }
}
