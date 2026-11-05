import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/draft_block.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/studio_page.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

/// 区域控制页也有「清空」:限定在工作台里找。
Finder _inStudio(Finder f) =>
    find.descendant(of: find.byType(StudioPage), matching: f);

/// 中间那段被固定,成稿隔成上下两栏。
StudioViewModel _split() => StudioViewModel(
  config: tempConfig(),
  streamChat: (_) => const Stream.empty(),
  blocks: const [
    (text: '【主体】a fox', pinned: false),
    (text: 'flat light', pinned: true),
    (text: '\n【构图】wide shot\n【情绪】calm', pinned: false),
  ],
);

void main() {
  group('把新成稿分到几栏上', () {
    test('每段去它标注所在的那一栏;新标注接在最后一栏;没提到的栏不动', () {
      expect(
        mergeAcross([
          '【主体】a fox',
          '【构图】wide\n【情绪】calm',
          '【画质】8k',
        ], '【情绪】tense\n【主体】a cat\n【花饰】roses'),
        ['【主体】a cat', '【构图】wide\n【情绪】tense', '【画质】8k\n【花饰】roses'],
      );
    });

    test('只来了新标注:接在最后一栏后面,不会把那一栏换掉', () {
      expect(mergeAcross(['【主体】a fox', '【构图】wide'], '【主体】a cat\n【花饰】roses'), [
        '【主体】a cat',
        '【构图】wide\n【花饰】roses',
      ]);
    });

    test('只写标注是删掉那段;一个标注都对不上算整篇重写', () {
      expect(mergeAcross(['【主体】a fox', '【构图】wide\n【情绪】calm'], '【情绪】'), [
        '【主体】a fox',
        '【构图】wide',
      ]);
      expect(mergeAcross(['【主体】a fox', '【构图】wide'], '【全新】x'), ['【全新】x', '']);
    });

    test('只有一栏时和 mergeSections 一样', () {
      const column = '【主体】a fox\n【构图】wide';
      const draft = '【构图】close\n【花饰】roses';
      expect(mergeAcross([column], draft), [mergeSections(column, draft)]);
    });
  });

  group('成稿被固定区隔成几栏', () {
    test('Agent 的成稿照样放得进来:每栏一处改动,一处一处确认', () {
      final vm = _split();

      expect(vm.proposeDraft('【情绪】tense\n【主体】a cat'), isNull);

      expect(vm.pending!.added, '【主体】a cat');
      expect(vm.queuedDiffs, 1);
      expect(vm.pendingAdded, contains('【情绪】tense'));

      vm.acceptDiff();
      expect(vm.pending!.added, '\n【构图】wide shot\n【情绪】tense');
      expect(vm.queuedDiffs, 0);

      vm.acceptDiff();
      expect(vm.pending, isNull);
      expect(vm.blocks[1], (text: 'flat light', pinned: true));
      expect(vm.finalPrompt, 'a cat flat light\nwide shot\ntense');
      // 固定区后面那一栏的标注还在行首,存档再放回来分段不会丢。
      expect(vm.labeledPrompt, contains('\n【构图】wide shot'));
    });

    test('只改到一栏时只有一处;驳回这一处后轮到下一处;逐段处理完也会轮到', () {
      final one = _split()..proposeDraft('【情绪】tense');
      expect(one.queuedDiffs, 0);
      expect(one.pending!.segmentIndex, 2);

      final vm = _split()..proposeDraft('【主体】a cat\n【情绪】tense');
      vm.rejectDiff();
      expect(vm.pending!.added, contains('【情绪】tense'));
      expect(vm.blocks.first.text, '【主体】a fox');

      final bySection = _split()..proposeDraft('【主体】a cat\n【情绪】tense');
      bySection.acceptSection('主体');
      expect(bySection.pending!.added, contains('【情绪】tense'));
    });

    test('全是固定区时,新成稿放进后面那个空栏', () {
      final vm = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
        blocks: const [(text: 'masterpiece,', pinned: true)],
      );

      expect(vm.proposeDraft('【主体】a fox'), isNull);
      vm.acceptDiff();

      expect(vm.finalPrompt, 'masterpiece, a fox');
    });
  });

  group('清空工作区', () {
    test('成稿、固定区、待确认改动、中文对照都清掉;清之前记进历史,能放回来', () {
      final vm = _split()..proposeDraft('【主体】a cat\n【情绪】tense');

      vm.clearDraft();

      expect(vm.body, isEmpty);
      expect(vm.finalPrompt, isEmpty);
      expect(vm.pending, isNull);
      expect(vm.queuedDiffs, 0);
      expect(vm.promptLog.first.text, contains('【主体】a fox'));

      vm.restorePrompt(vm.promptLog.first);
      expect(vm.finalPrompt, contains('a fox'));
    });

    testWidgets('点清空要先确认;最终提示词跟着清掉', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final vm = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
        blocks: const [(text: '【主体】a fox', pinned: false)],
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: pennaTheme(),
          home: AppShell(vm: vm, config: vm.config, skills: tempSkills()),
        ),
      );
      expect(find.text('最终提示词'), findsOneWidget);

      await tester.tap(_inStudio(find.text('清空')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(vm.body, isNotEmpty);

      await tester.tap(_inStudio(find.text('清空')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(vm.body, isEmpty);
      expect(find.text('最终提示词'), findsNothing);
      expect(find.text('历史提示词'), findsOneWidget);
    });
  });
}
