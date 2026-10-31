import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/l10n/l10n.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/chat_model_controls.dart';

void main() {
  setUp(() => useLanguage('zh-Hans'));

  Widget host(Widget child) => MaterialApp(
    theme: pennaTheme(),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('五档思考程度可以选择并回调', (tester) async {
    const values = ['none', 'low', 'medium', 'high', 'xhigh'];
    const labels = ['思考：关闭', '思考：低', '思考：中', '思考：高', '思考：极高'];
    final chosen = <String>[];
    await tester.pumpWidget(
      host(
        ReasoningSelector(
          value: 'medium',
          enabled: true,
          onChanged: chosen.add,
        ),
      ),
    );
    for (var i = 0; i < values.length; i++) {
      await tester.tap(find.byType(ReasoningSelector));
      await tester.pumpAndSettle();
      expect(find.text(labels[i]), findsWidgets);
      // 点菜单项本身而不是里面的文字:文字被选项的点击层包着,
      // 按文字中心点在部分平台会触发 hit-test 警告。
      await tester.tap(find.byType(CheckedPopupMenuItem<String>).at(i));
      await tester.pumpAndSettle();
      expect(chosen.last, values[i]);
    }
    expect(chosen, values);
  });

  testWidgets('生成中和不支持时不可切换，且说明原因', (tester) async {
    final chosen = <String>[];
    for (final busy in [true, false]) {
      await tester.pumpWidget(
        host(
          ReasoningSelector(
            value: 'high',
            enabled: busy,
            busy: busy,
            onChanged: chosen.add,
          ),
        ),
      );
      await tester.tap(find.byType(ReasoningSelector));
      await tester.pumpAndSettle();
      expect(find.byType(CheckedPopupMenuItem<String>), findsNothing);
      expect(chosen, isEmpty);
      expect(
        find.byTooltip(busy ? '正在生成，结束后可调整思考程度' : '思考程度仅适用于本地 Bonsai'),
        findsOneWidget,
      );
    }
  });

  testWidgets('详情区分实际用量和估算，展示已用、容量和剩余', (tester) async {
    for (final estimated in [false, true]) {
      await tester.pumpWidget(
        host(
          ContextUsageRing(
            usedTokens: 250,
            capacity: 1000,
            estimated: estimated,
          ),
        ),
      );
      expect(find.text('25%'), findsOneWidget);
      await tester.tap(find.byType(ContextUsageRing));
      await tester.pumpAndSettle();
      expect(find.text(estimated ? '用量估算' : '实际用量'), findsOneWidget);
      expect(find.text('已用：250 tokens'), findsOneWidget);
      expect(find.text('总容量：1,000 tokens'), findsOneWidget);
      expect(find.text('剩余：750 tokens'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('未知容量不虚构百分比和剩余', (tester) async {
    await tester.pumpWidget(host(const ContextUsageRing(usedTokens: 72)));
    expect(find.text('—'), findsOneWidget);
    await tester.tap(find.byType(ContextUsageRing));
    await tester.pumpAndSettle();
    expect(find.text('已用：72 tokens'), findsOneWidget);
    expect(find.text('总容量：未知'), findsOneWidget);
    expect(find.text('剩余：未知'), findsOneWidget);
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '新对话继续'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('接近满额时变色，满额仍可新对话，刷新更新详情', (tester) async {
    var newChats = 0;
    var used = 800;
    late StateSetter update;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ContextUsageRing(
              usedTokens: used,
              capacity: 1000,
              onNewChat: () => newChats++,
              onRefresh: () => update(() => used = 1000),
            );
          },
        ),
      ),
    );
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color,
      PennaColors.amber,
    );
    await tester.tap(find.byType(ContextUsageRing));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新上下文用量'));
    await tester.pumpAndSettle();
    expect(find.text('已用：1,000 tokens'), findsOneWidget);
    expect(find.text('剩余：0 tokens'), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color,
      PennaColors.diffDelText,
    );
    expect(find.text('新对话保留画板和角色信息，上下文占用不一定归零。'), findsOneWidget);
    await tester.tap(find.text('新对话继续'));
    await tester.pumpAndSettle();
    expect(newChats, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('窄屏和英文下两个控件合计不超过150且详情可滚动', (tester) async {
    useLanguage('en');
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReasoningSelector(value: 'xhigh', enabled: true, onChanged: (_) {}),
            const SizedBox(width: 4),
            const ContextUsageRing(usedTokens: 950, capacity: 1000),
          ],
        ),
      ),
    );
    final selectorWidth = tester.getSize(find.byType(ReasoningSelector)).width;
    final ringWidth = tester.getSize(find.byType(ContextUsageRing)).width;
    expect(selectorWidth + ringWidth + 4, lessThanOrEqualTo(150));
    await tester.tap(find.byType(ContextUsageRing));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
