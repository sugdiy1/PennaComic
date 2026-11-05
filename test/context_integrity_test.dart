import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/core/harness/providers/llm_http.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
  setUp(() => HttpOverrides.global = null);
  test('备用模型完成后的空草稿刷新保留备用模型实际用量和容量', () async {
    final cfg = tempConfig();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((r) async {
      await r.drain<void>();
      final result = switch (r.uri.path) {
        '/props' => {
          'default_generation_settings': {'n_ctx': 65536},
        },
        '/apply-template' => {'prompt': 'test'},
        _ => {
          'tokens': [1, 2, 3],
        },
      };
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(result));
      await r.response.close();
    });
    cfg.update(
      cfg.config.copyWith(
        llms: [
          const LlmProfile(
            id: 'a',
            name: 'remote-primary',
            baseUrl: 'https://example.invalid/v1',
            model: 'remote',
          ),
          LlmProfile(
            id: 'b',
            name: 'Bonsai-backup',
            baseUrl: 'http://127.0.0.1:${server.port}/v1',
            model: 'ternary-bonsai-27b',
          ),
        ],
        activeLlmId: () => 'a',
      ),
    );
    final vm = StudioViewModel(
      config: cfg,
      streamChat: (r) async* {
        if (r.model == 'remote') {
          throw const LlmException('Synthetic primary failure');
        }
        r.onUsage?.call(const LlmUsage(promptTokens: 90, completionTokens: 10));
        yield '已说明';
      },
    );
    addTearDown(() async {
      vm.dispose();
      await cfg.flushed();
      cfg.dispose();
    });
    await vm.sendAndWait('简单说明');
    expect(vm.contextStatus.usedTokens, 100);
    await vm.refreshContext();
    expect(vm.contextStatus.usedTokens, 100);
    expect(vm.contextStatus.capacity, 65536);
    expect(vm.contextStatus.estimated, isFalse);
  });
  test('测量包括引用，空草稿刷新保留实际用量，编辑草稿才显示估算', () async {
    List<Map<String, dynamic>> measured = [];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((r) async {
      Object response;
      if (r.uri.path == '/props') {
        response = {
          'default_generation_settings': {'n_ctx': 131072},
        };
      } else if (r.uri.path == '/apply-template') {
        final body = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
        measured = [
          for (final m in body['messages'] as List)
            Map<String, dynamic>.from(m as Map),
        ];
        response = {'prompt': 'synthetic template'};
      } else {
        await r.drain<void>();
        response = {'tokens': List.generate(12, (i) => i)};
      }
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(response));
      await r.response.close();
    });
    final cfg = tempConfig();
    cfg.update(
      cfg.config.copyWith(
        llms: [
          LlmProfile(
            id: 'b',
            name: 'Bonsai',
            baseUrl: 'http://127.0.0.1:${server.port}/v1',
            model: 'ternary-bonsai-27b',
          ),
        ],
        activeLlmId: () => 'b',
      ),
    );
    LlmRequest? sent;
    final vm = StudioViewModel(
      config: cfg,
      streamChat: (r) async* {
        sent = r;
        r.onUsage?.call(const LlmUsage(promptTokens: 90, completionTokens: 10));
        yield '已说明。';
      },
    );
    addTearDown(() async {
      vm.dispose();
      await cfg.flushed();
      cfg.dispose();
    });
    vm.quoteSection('UNIQUE_QUOTED_CONTEXT_' * 30);
    await vm.refreshContext(draft: '只解释这一段。');
    final measuredMessages = jsonEncode(measured);
    await vm.sendAndWait('只解释这一段。');
    expect(measuredMessages, contains('UNIQUE_QUOTED_CONTEXT_'));
    expect(sent!.messages.last['content'], measured.last['content']);
    expect(vm.contextStatus.usedTokens, 100);
    await vm.refreshContext();
    expect(vm.contextStatus.usedTokens, 100);
    expect(vm.contextStatus.estimated, isFalse);
    expect(vm.contextStatus.capacity, 131072);
    await vm.refreshContext(draft: '下一个问题');
    expect(vm.contextStatus.usedTokens, 12);
    expect(vm.contextStatus.estimated, isTrue);
    await vm.refreshContext();
    expect(vm.contextStatus.usedTokens, 100);
    expect(vm.contextStatus.estimated, isFalse);
  });
  test('停止后旧请求的用量与思考回调不能再更新状态', () async {
    final cfg = tempConfig();
    cfg.update(
      cfg.config.copyWith(
        llms: [
          const LlmProfile(
            id: 'b',
            name: 'Bonsai',
            baseUrl: 'http://127.0.0.1:8090/v1',
            model: 'ternary-bonsai-27b',
          ),
        ],
        activeLlmId: () => 'b',
      ),
    );
    final pipe = StreamController<String>();
    final started = Completer<void>();
    LlmRequest? captured;
    final vm = StudioViewModel(
      config: cfg,
      streamChat: (r) {
        captured = r;
        started.complete();
        return pipe.stream;
      },
    );
    addTearDown(() async {
      vm.dispose();
      await pipe.close();
      await cfg.flushed();
      cfg.dispose();
    });
    vm.send('只回答一句说明。');
    await started.future;
    vm.stop();
    captured!.onReasoning?.call();
    captured!.onUsage?.call(
      const LlmUsage(promptTokens: 999, completionTokens: 1),
    );
    expect(vm.isStreaming, isFalse);
    expect(vm.isThinking, isFalse);
    expect(vm.contextStatus.usedTokens, isNull);
  });
  test('同ID改模型端点使配置指纹变化，清掉旧容量并查询新容量', () async {
    Future<HttpServer> serve(int capacity) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((r) async {
        await r.drain<void>();
        final result = switch (r.uri.path) {
          '/props' => {
            'default_generation_settings': {'n_ctx': capacity},
          },
          '/apply-template' => {'prompt': 'test'},
          _ => {
            'tokens': [1, 2, 3],
          },
        };
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode(result));
        await r.response.close();
      });
      return server;
    }

    final first = await serve(131072), second = await serve(65536);
    final cfg = tempConfig();
    LlmProfile profile(HttpServer s) => LlmProfile(
      id: 'same',
      name: 'Bonsai',
      baseUrl: 'http://127.0.0.1:${s.port}/v1',
      model: 'ternary-bonsai-27b',
    );
    cfg.update(
      cfg.config.copyWith(llms: [profile(first)], activeLlmId: () => 'same'),
    );
    final vm = StudioViewModel(
      config: cfg,
      streamChat: (r) async* {
        r.onUsage?.call(const LlmUsage(promptTokens: 100, completionTokens: 2));
        yield '说明';
      },
    );
    addTearDown(() async {
      vm.dispose();
      await cfg.flushed();
      cfg.dispose();
    });
    await vm.refreshContext();
    await vm.sendAndWait('说明');
    final before = vm.contextConfigurationKey;
    expect(vm.contextStatus.capacity, 131072);
    expect(vm.contextStatus.estimated, isFalse);
    cfg.update(cfg.config.copyWith(llms: [profile(second)]));
    expect(vm.contextConfigurationKey, isNot(before));
    final changed = vm.refreshContext();
    expect(vm.contextStatus.capacity, isNull, reason: '不可在查询新端点时显示旧端点容量');
    await changed;
    expect(vm.contextStatus.capacity, 65536);
    expect(vm.contextStatus.estimated, isTrue);
  });
}
