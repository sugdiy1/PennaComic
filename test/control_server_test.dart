import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/agent_control/control_server.dart';

void main() {
  late Directory home;
  late ControlServer server;
  late HttpClient client;
  late Map<String, dynamic> discovery;

  Future<({int status, Map<String, dynamic> body})> request({
    String method = 'GET',
    String path = '/v1/tools',
    bool authorized = true,
    String? origin,
    String? body,
  }) async {
    final req = await client.openUrl(method, Uri.parse('${server.url}$path'));
    if (authorized) {
      req.headers.set('Authorization', 'Bearer ${discovery['token']}');
    }
    if (origin != null) req.headers.set('Origin', origin);
    if (body != null) req.write(body);
    final response = await req.close();
    return (
      status: response.statusCode,
      body: jsonDecode(
        await utf8.decoder.bind(response).join(),
      ) as Map<String, dynamic>,
    );
  }

  setUp(() async {
    home = await Directory.systemTemp.createTemp('penna-control-test-');
    client = HttpClient();
    server = ControlServer(
      home: home,
      listTools: () => [
        {'name': 'echo'},
      ],
      callTool: (name, args) async {
        if (name == 'conflict') {
          throw const ControlException('revision_conflict', 'Refresh page.');
        }
        if (name == 'crash') throw StateError('secret-token-private-path');
        return {'name': name, 'arguments': args};
      },
    );
    await server.start();
    discovery = jsonDecode(
      await File(server.discoveryPath).readAsString(),
    ) as Map<String, dynamic>;
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await home.delete(recursive: true);
  });

  test('binds loopback and publishes authenticated discovery', () async {
    expect(server.running, isTrue);
    expect(Uri.parse(server.url!).host, '127.0.0.1');
    expect(discovery['url'], server.url);
    expect((discovery['token'] as String).length, greaterThanOrEqualTo(43));
    expect((await request()).body, {
      'tools': [
        {'name': 'echo'},
      ],
    });
  });

  test('rejects missing token and every browser Origin', () async {
    expect((await request(authorized: false)).status, 401);
    expect((await request(origin: 'null')).status, 403);
    expect((await request(origin: '')).status, 403);
  });

  test('dispatches validated calls and returns direct results', () async {
    final response = await request(
      method: 'POST',
      path: '/v1/tools/call',
      body: jsonEncode({
        'name': 'echo',
        'arguments': {'n': 3},
      }),
    );
    expect(response.status, 200);
    expect(response.body, {
      'name': 'echo',
      'arguments': {'n': 3},
    });
  });

  test('rejects malformed JSON, arguments and oversized bodies', () async {
    for (final body in [
      '{',
      '[]',
      '{"name":"echo","arguments":[]}',
      '{"name":4,"arguments":{}}',
    ]) {
      expect(
        (await request(
          method: 'POST',
          path: '/v1/tools/call',
          body: body,
        )).status,
        400,
      );
    }
    expect(
      (await request(
        method: 'POST',
        path: '/v1/tools/call',
        body: ' ' * (2 * 1024 * 1024 + 1),
      )).status,
      413,
    );
  });

  test(
    'returns structured domain errors and hides unexpected failures',
    () async {
      final conflict = await request(
        method: 'POST',
        path: '/v1/tools/call',
        body: '{"name":"conflict","arguments":{}}',
      );
      expect(conflict.status, 409);
      expect(conflict.body['error'], {
        'code': 'revision_conflict',
        'message': 'Refresh page.',
      });
      final crash = await request(
        method: 'POST',
        path: '/v1/tools/call',
        body: '{"name":"crash","arguments":{}}',
      );
      expect(crash.status, 500);
      expect(jsonEncode(crash.body), isNot(contains('secret-token')));
    },
  );

  test('same home collision never hijacks active discovery', () async {
    final second = ControlServer(
      home: home,
      listTools: () => [],
      callTool: (_, _) async => {},
    );
    await expectLater(second.start(), throwsA(isA<ControlException>()));
    await second.stop();
    expect(
      jsonDecode(await File(server.discoveryPath).readAsString()),
      discovery,
    );
    expect((await request()).status, 200);
  });

  test(
    'stop deletes only own discovery and permits restart with fresh token',
    () async {
      await server.stop();
      expect(server.running, isFalse);
      expect(server.url, isNull);
      expect(await File(server.discoveryPath).exists(), isFalse);
      final oldToken = discovery['token'];
      await server.start();
      discovery = jsonDecode(
        await File(server.discoveryPath).readAsString(),
      ) as Map<String, dynamic>;
      expect(discovery['token'], isNot(oldToken));
      await File(server.discoveryPath).writeAsString('{"token":"replacement"}');
      await server.stop();
      expect(
        await File(server.discoveryPath).readAsString(),
        '{"token":"replacement"}',
      );
    },
  );

  test(
    'serializes concurrent tool mutations even after a failed call',
    () async {
      await server.stop();
      var active = 0;
      var maximum = 0;
      server = ControlServer(
        home: home,
        listTools: () => [],
        callTool: (name, arguments) async {
          active++;
          if (active > maximum) maximum = active;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          active--;
          if (name == 'fail') throw StateError('failure');
          return {'ok': true};
        },
      );
      await server.start();
      discovery = jsonDecode(
        await File(server.discoveryPath).readAsString(),
      ) as Map<String, dynamic>;
      final responses = await Future.wait([
        for (final name in ['fail', 'ok', 'ok'])
          request(
            method: 'POST',
            path: '/v1/tools/call',
            body: jsonEncode({'name': name, 'arguments': {}}),
          ),
      ]);
      expect(maximum, 1);
      expect(responses.map((r) => r.status), [500, 200, 200]);
    },
  );
}
