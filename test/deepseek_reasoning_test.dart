import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comic/reasoning_controls.dart';
import 'package:penna/core/harness/comic/novel_ai_designer.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/novel_comic.dart';
import 'package:penna/ui/features/studio/chat_model_controls.dart';
import 'package:penna/ui/features/studio/chat_pane.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/l10n/l10n.dart';

import 'novel_ai_designer_test.dart' show aiConfig, aiResult, assetResult;

import 'package:penna/data/models/app_config.dart';

import 'fixtures.dart';

void main() {
  testWidgets('实际聊天栏随连接启用官方 DeepSeek 菜单', (tester) async {
    final cfg = tempConfig();
    await tester.runAsync(() async {
      cfg.update(
        cfg.config.copyWith(
          llms: const [
            LlmProfile(
              id: 'ds',
              name: 'deepseek',
              baseUrl: 'https://api.deepseek.com/v1',
              model: 'deepseek-flash',
            ),
          ],
          activeLlmId: () => 'ds',
        ),
      );
      await cfg.flushed();
    });
    final vm = StudioViewModel(
      config: cfg,
      streamChat: (_) => const Stream.empty(),
    );
    final input = TextEditingController(), focus = FocusNode();
    useLanguage('zh-Hans');
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: ChatPane(
                vm: vm,
                config: cfg,
                input: input,
                inputFocus: focus,
                onQuickAction: (_) {},
                onOpenSettings: () {},
              ),
            ),
          ),
        ),
      );
      final selector = tester.widget<ReasoningSelector>(
        find.byType(ReasoningSelector),
      );
      expect(selector.enabled, isTrue);
      expect(selector.control, ReasoningControl.deepseek);
      await tester.tap(find.byType(ReasoningSelector));
      await tester.pumpAndSettle();
      expect(find.byType(CheckedPopupMenuItem<String>), findsNWidgets(4));
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
    } finally {
      await tester.pumpWidget(const SizedBox());
      input.dispose();
      focus.dispose();
      vm.dispose();
      cfg.dispose();
    }
  });
  test('能力只匹配已适配协议、真实主机和支持模型', () {
    for (final model in ['deepseek-flash', 'deepseek-v4-pro']) {
      expect(
        reasoningControlFor('https://api.deepseek.com/v1', model),
        ReasoningControl.deepseek,
      );
    }
    for (final url in [
      'https://api.deepseek.com.evil.test/v1',
      'https://example.com/v1',
    ]) {
      expect(
        reasoningControlFor(url, 'deepseek-flash'),
        ReasoningControl.unsupported,
      );
    }
    expect(
      reasoningControlFor('https://api.deepseek.com', 'unknown'),
      ReasoningControl.unsupported,
    );
    expect(
      reasoningControlFor(
        'https://api.deepseek.com',
        'deepseek-flash',
        protocol: 'google',
      ),
      ReasoningControl.unsupported,
    );
    expect(
      reasoningControlFor('http://localhost:8090/v1', 'bonsai'),
      ReasoningControl.bonsai,
    );
    expect(ReasoningControl.bonsai.plan('max').effort, 'xhigh');
  });
  for (final level in ['none', 'low', 'medium', 'high', 'xhigh', 'max']) {
    test('DeepSeek 实际请求序列化 $level，思考参数不混用', () {
      final plan = ReasoningControl.deepseek.plan(level);
      final body = openAiRequestBody(
        LlmRequest(
          baseUrl: 'https://api.deepseek.com/v1',
          model: 'deepseek-flash',
          apiKey: '',
          messages: const [],
          enableThinking: plan.enabled,
          reasoningEffort: plan.effort,
          reasoningBudgetTokens: 4096,
          maxOutputTokens: plan.maxOutputTokens,
        ),
      );
      expect(body['thinking'], {
        'type': level == 'none' ? 'disabled' : 'enabled',
      });
      if (level == 'none') {
        expect(body.containsKey('reasoning_effort'), isFalse);
      } else {
        expect(
          body['reasoning_effort'],
          level == 'low'
              ? 'low'
              : level == 'max'
              ? 'max'
              : 'high',
        );
      }
      for (final key in [
        'chat_template_kwargs',
        'reasoning_format',
        'reasoning_budget_tokens',
      ]) {
        expect(body.containsKey(key), isFalse, reason: key);
      }
      expect(body['max_tokens'], 32768);
    });
  }
  testWidgets('DeepSeek 菜单可选四档，旧中档显示实际高档', (tester) async {
    useLanguage('zh-Hans');
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReasoningSelector(
            value: 'medium',
            enabled: true,
            control: ReasoningControl.deepseek,
            onChanged: (v) => chosen = v,
          ),
        ),
      ),
    );
    expect(find.text('思考：高'), findsOneWidget);
    await tester.tap(find.byType(ReasoningSelector));
    await tester.pumpAndSettle();
    expect(find.byType(CheckedPopupMenuItem<String>), findsNWidgets(4));
    expect(find.text('思考：中'), findsNothing);
    await tester.tap(find.byType(CheckedPopupMenuItem<String>).last);
    await tester.pumpAndSettle();
    expect(chosen, 'max');
  });
  for (final level in ['none', 'max']) {
    test('小说资产、分镜及JSON纠错继承 DeepSeek 档位 $level', () async {
      final cfg = aiConfig().copyWith(
        reasoningEffort: level,
        llms: const [
          LlmProfile(
            id: 'local',
            name: 'DeepSeek',
            baseUrl: 'https://api.deepseek.com/v1',
            model: 'deepseek-flash',
          ),
        ],
      );
      final seen = <LlmRequest>[];
      final ai = NovelAiDesigner(
        config: () => cfg,
        streamChat: (r) async* {
          seen.add(r);
          if (seen.length.isOdd) {
            yield '{"broken": [}';
            return;
          }
          yield jsonEncode(seen.length == 2 ? assetResult() : aiResult('L034'));
        },
      );
      await ai.prepareAssets(
        options: const ComicOptions(),
        sourceText: '小蓝接住箱子',
        knownNames: [],
      );
      await ai.design(
        options: const ComicOptions(),
        sourceText: '小蓝接住箱子',
        pageNumber: 1,
        pageTotal: 1,
        memories: [],
        cast: {},
      );
      expect(seen, hasLength(4));
      for (final r in seen) {
        expect(r.enableThinking, level != 'none');
        expect(r.reasoningEffort, level == 'none' ? null : 'max');
        expect(r.reasoningBudgetTokens, isNull);
      }
    });
  }
}
