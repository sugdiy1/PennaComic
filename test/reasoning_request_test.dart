import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/core/harness/providers/llm_http.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
  for (final level in ['none', 'low', 'medium', 'high', 'xhigh', 'max']) {
    test('官方 DeepSeek 对话传递思考档位 $level，不发送本机预算', () async {
      final cfg = tempConfig();
      cfg.update(
        cfg.config.copyWith(
          reasoningEffort: level,
          llms: const [
            LlmProfile(
              id: 'ds',
              name: 'DeepSeek',
              baseUrl: 'https://api.deepseek.com/v1',
              model: 'deepseek-flash',
            ),
          ],
          activeLlmId: () => 'ds',
        ),
      );
      final board = LayoutBoard();
      LlmRequest? seen;
      final vm = StudioViewModel(
        config: cfg,
        layout: board,
        layoutOnly: true,
        streamChat: (request) async* {
          seen = request;
          yield '说明。';
        },
      );
      try {
        await vm.sendAndWait('只解释景别，不修改画板。');
        expect(seen!.enableThinking, level != 'none');
        expect(seen!.reasoningEffort, switch (level) {
          'none' => null,
          'low' => 'low',
          'max' => 'max',
          _ => 'high',
        });
        expect(seen!.reasoningBudgetTokens, isNull);
      } finally {
        vm.dispose();
        board.dispose();
        await cfg.flushed();
        cfg.dispose();
      }
    });
  }
  test('最高档 max 跨重启保留', () {
    final cfg = const AppConfig().copyWith(reasoningEffort: 'max');
    expect(AppConfig.fromJson(cfg.toJson()).reasoningEffort, 'max');
  });
  test('思考档位序列化保留，异常旧配置回退中档', () {
    final c = const AppConfig().copyWith(reasoningEffort: 'high');
    expect(AppConfig.fromJson(c.toJson()).reasoningEffort, 'high');
    expect(
      AppConfig.fromJson({'reasoningEffort': 'invalid'}).reasoningEffort,
      'medium',
    );
  });
  test('关闭思考生效，真实用量清零后开新对话仍保留画板', () async {
    final cfg = tempConfig();
    cfg.update(
      cfg.config.copyWith(
        reasoningEffort: 'none',
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
    final board = LayoutBoard();
    final before = board.layout.toJson();
    LlmRequest? seen;
    final vm = StudioViewModel(
      config: cfg,
      layout: board,
      layoutOnly: true,
      streamChat: (r) async* {
        seen = r;
        r.onUsage?.call(
          const LlmUsage(
            promptTokens: 100,
            completionTokens: 20,
            cachedTokens: 50,
          ),
        );
        yield '已解释。';
      },
    );
    await vm.sendAndWait('只解释特写，不修改画板。');
    expect(seen!.enableThinking, isFalse);
    expect(seen!.reasoningEffort, isNull);
    expect(seen!.reasoningBudgetTokens, 0);
    expect(vm.contextStatus.usedTokens, 120);
    expect(vm.contextStatus.estimated, isFalse);
    expect(vm.newChat(), isTrue);
    expect(vm.contextStatus.usedTokens, isNull);
    expect(vm.messages, isEmpty);
    expect(board.layout.toJson(), before);
    vm.dispose();
    board.dispose();
    await cfg.flushed();
    cfg.dispose();
  });
  test('本地分镜助手不再硬编码关闭思考，默认中档', () async {
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
    final seen = <LlmRequest>[];
    final board = LayoutBoard();
    final vm = StudioViewModel(
      config: cfg,
      layout: board,
      layoutOnly: true,
      streamChat: (r) async* {
        seen.add(r);
        yield '这是一个景别的说明。';
      },
    );
    await vm.sendAndWait('只解释什么是特写，不修改画板。');
    expect(seen.single.reasoningEffort, 'medium');
    vm.dispose();
    board.dispose();
    await cfg.flushed();
    cfg.dispose();
  });
  test('远程模型不塞本机思考参数', () async {
    final cfg = tempConfig();
    cfg.update(
      cfg.config.copyWith(
        llms: [
          const LlmProfile(
            id: 'r',
            name: 'Remote',
            baseUrl: 'https://api.example.com/v1',
            model: 'gpt-x',
          ),
        ],
        activeLlmId: () => 'r',
      ),
    );
    final seen = <LlmRequest>[];
    final board = LayoutBoard();
    final vm = StudioViewModel(
      config: cfg,
      layout: board,
      layoutOnly: true,
      streamChat: (r) async* {
        seen.add(r);
        yield '这是说明。';
      },
    );
    await vm.sendAndWait('只解释什么是特写，不修改画板。');
    final r = seen.single;
    expect(r.enableThinking, isNull);
    expect(r.reasoningEffort, isNull);
    expect(r.reasoningBudgetTokens, isNull);
    expect(r.maxOutputTokens, isNull);
    vm.dispose();
    board.dispose();
    await cfg.flushed();
    cfg.dispose();
  });
}
