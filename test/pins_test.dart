import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/body_card.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

const _llm = LlmProfile(id: 'a', name: 'A', baseUrl: 'http://x', model: 'm');

StudioViewModel _studio({
  ChatStreamer? stream,
  String text = 'a red fox, in the rain, 35mm',
}) {
  final config = tempConfig()..update(const AppConfig().putLlm(_llm));
  return StudioViewModel(
    config: config,
    streamChat: stream ?? (_) => const Stream.empty(),
  )..setText(0, text);
}

List<String> _show(StudioViewModel vm) => [
  for (final b in vm.blocks) b.pinned ? '[${b.text}]' : b.text,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('固定区', () {
    test('新增的固定区在最前面,和正文之间自动隔一个空格', () {
      final vm = _studio()..addPin('  masterpiece,  ');

      expect(_show(vm), ['[masterpiece,]', 'a red fox, in the rain, 35mm']);
      expect(vm.finalPrompt, 'masterpiece, a red fox, in the rain, 35mm');
    });

    test('选中一段就地固定;只选了空白或没选时不固定', () {
      final vm = _studio();

      expect(vm.pinSelection(), isFalse);
      vm.bodySelection = (1, 2);
      expect(vm.pinSelection(), isFalse);

      vm.bodySelection = (11, 22); // "in the rain"
      expect(vm.pinSelection(), isTrue);
      expect(_show(vm), ['a red fox, ', '[in the rain]', ', 35mm']);
      expect(vm.finalPrompt, 'a red fox, in the rain , 35mm');
      expect(vm.bodySelection, isNull);
    });

    test('拖到开头、中间、末尾;中间落下时把那栏文字切开', () {
      final vm = _studio()..addPin('PIN');

      vm.movePin(0, 3 + 11); // 落在 "in the rain" 前
      expect(_show(vm), ['a red fox, ', '[PIN]', 'in the rain, 35mm']);
      expect(vm.finalPrompt, 'a red fox, PIN in the rain, 35mm');

      vm.movePin(1, vm.body.length);
      expect(_show(vm), ['a red fox, in the rain, 35mm', '[PIN]']);

      vm.movePin(1, 0);
      expect(_show(vm), ['[PIN]', 'a red fox, in the rain, 35mm']);

      // 往后拖:落点在自己后面的文字里。
      vm.movePin(0, 3 + 11);
      expect(_show(vm), ['a red fox, ', '[PIN]', 'in the rain, 35mm']);
    });

    test('取消固定后文字留在原处,不和两边粘在一起', () {
      final vm = _studio(text: 'a fox')..addPin('PIN');
      vm.movePin(0, vm.body.length);
      expect(vm.finalPrompt, 'a fox PIN');

      vm.unpin(1);

      expect(_show(vm), ['a fox PIN']);

      // 邻居是固定区时不往文字里塞空格。
      final two = _studio(text: '')
        ..addPin('B')
        ..addPin('A')
        ..unpin(1);
      expect(_show(two), ['[A]', 'B']);
      expect(two.finalPrompt, 'A B');
    });

    test('只有固定区时仍有一栏可以打字;打的字接在后面', () {
      final vm = _studio(text: '')..addPin('PIN');
      final empty = vm.parts.last;
      expect(empty.pinned, isFalse);

      vm.setText(empty.index, 'a fox');

      expect(_show(vm), ['[PIN]', 'a fox']);
    });

    test('编辑一栏文字不影响固定区和另一栏', () {
      final vm = _studio()..bodySelection = (11, 22);
      vm.pinSelection();

      vm.setText(2, ', 50mm');
      vm.setText(0, 'a blue fox, ');

      expect(_show(vm), ['a blue fox, ', '[in the rain]', ', 50mm']);
    });

    test('不选内容润色时只改可编辑的那栏,固定区原样保留', () async {
      late LlmRequest seen;
      final vm = _studio(
        stream: (r) {
          seen = r;
          return Stream.value('a crimson fox');
        },
        text: 'a red fox',
      )..addPin('masterpiece,');

      expect(await vm.polish(''), isNull);
      expect(vm.pending!.removed, 'a red fox');
      expect(seen.messages.last['content'], contains('masterpiece, a red fox'));

      vm.acceptDiff();
      expect(_show(vm), ['[masterpiece,]', 'a crimson fox']);
    });

    test('选区碰到固定区时不润色;润色途中目标被固定了也作废', () async {
      var calls = 0;
      final vm = _studio(
        stream: (_) {
          calls++;
          return Stream.value('X');
        },
        text: 'a red fox',
      )..addPin('PIN');

      vm.bodySelection = (1, 6); // 跨过固定区和正文
      expect(await vm.polish(''), '固定区不能改写');
      expect(calls, 0);

      vm.bodySelection = (3, 12);
      final running = vm.polish('');
      vm.bodySelection = (3, 12);
      vm.pinSelection();
      expect(await running, '固定区不能改写');
      expect(vm.pending, isNull);
      expect(_show(vm), ['[PIN]', '[a red fox]']);
    });

    test('有待确认改动时不能动固定区', () {
      final vm = sampleStudio();
      final before = _show(vm);

      vm
        ..addPin('P')
        ..unpin(0)
        ..movePin(0, vm.body.length);
      expect(_show(vm), before);
    });

    test('发给 Agent 的系统提示里列出固定区', () async {
      late LlmRequest seen;
      final vm = _studio(
        stream: (r) {
          seen = r;
          return Stream.value('ok');
        },
      )..addPin('masterpiece,');

      vm.send('你好');
      await pumpEventQueue();

      expect(
        seen.messages.first['content'],
        contains('一个字都不能改,也不能挪走:\nmasterpiece,'),
      );
    });
  });

  test('落点对齐到词缝', () {
    const text = 'a red fox, in the rain';
    expect(snapToGap(text, 0), 0);
    expect(snapToGap(text, 3), 2); // "r|ed" → "red" 前
    expect(snapToGap(text, 9), 11); // "fox" 末尾 → 逗号和空格之后
    expect(snapToGap(text, 21), 22);
    expect(snapToGap(text, 99), 22);
    expect(snapToGap('', 5), 0);
    expect(snapToGap('cat😀dog', 4), isNot(4)); // 不从表情符号中间劈开
    expect(snapToGap('红狐,雨中', 1), 1); // 汉字之间可以落
    expect(snapToGap('红狐,雨中', 2), anyOf(1, 3)); // 不落在标点前
  });

  testWidgets('把固定区拖进正文中间', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = _studio(text: 'a red fox, in the rain, 35mm')..addPin('PIN');
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: AppShell(vm: vm, config: vm.config, skills: tempSkills()),
      ),
    );
    final editor = find.widgetWithText(
      TextField,
      'a red fox, in the rain, 35mm',
    );
    final box = tester.getRect(editor);

    final drag = await tester.startGesture(
      tester.getCenter(find.text('PIN')),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(0, 20));
    await tester.pump();
    // 落到那行文字的中段。
    await drag.moveTo(Offset(box.left + 110, box.top + 8));
    await tester.pump();
    await drag.up();
    await tester.pump();

    expect(vm.blocks, hasLength(3));
    expect(vm.blocks[1], (text: 'PIN', pinned: true));
    expect(vm.blocks.first.text, endsWith(' '));

    // 前一栏变长后,后一栏里的选区要跟着挪,固定的仍是选中的那几个字。
    final tail = find.widgetWithText(TextField, vm.blocks[2].text);
    await tester.tap(tail);
    tester.widget<TextField>(tail).controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 2,
    );
    final picked = vm.blocks[2].text.substring(0, 2);
    vm.setText(0, 'xx${vm.blocks[0].text}');
    await tester.pump();
    expect(
      vm.body.substring(vm.bodySelection!.$1, vm.bodySelection!.$2),
      picked,
    );

    await tester.tap(find.byTooltip('取消固定'));
    await tester.pump();
    expect(vm.blocks, hasLength(1));
  });
}
