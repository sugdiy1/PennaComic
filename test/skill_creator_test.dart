import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/draft_block.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/skill_store.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

const _film = '---\nname: Film\ndescription: 胶片感\n---\n\n# Film\n\n用胶片的语言描述画面。';
const _reply = '写好了。\n<new-skill>\n$_film\n</new-skill>\n在聊天框输入 @ 引用它。';

/// 配好一个模型、带一个空 Skills 目录的工作台,回复由 [stream] 决定。
StudioViewModel _studio(ChatStreamer stream, {SkillStore? skills}) {
  final config = tempConfig()
    ..update(
      const AppConfig().putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://x', model: 'm'),
      ),
    );
  return StudioViewModel(
    config: config,
    streamChat: stream,
    skills: skills ?? tempSkills(),
  );
}

/// 等回复结束、写盘也做完。
Future<void> _settle() async {
  await pumpEventQueue();
  await Future<void>.delayed(const Duration(milliseconds: 200));
}

void main() {
  group('从回复里拆出新 Skill', () {
    test('没有时原样返回;半截标签不显示', () {
      expect(splitNewSkill('你好').skill, isNull);
      expect(splitNewSkill('你好 <new-sk').prose, '你好 ');
    });

    test('完整的:标签外的话留作正文,标签里是整篇 SKILL.md', () {
      final made = splitNewSkill(_reply);

      expect(made.complete, isTrue);
      expect(made.skill, _film);
      expect(made.prose, '写好了。\n\n在聊天框输入 @ 引用它。');
    });

    test('还在生成时标成不完整;外面套的代码块去掉', () {
      final writing = splitNewSkill(
        '好\n<new-skill>\n---\nname: F\n---\n正文</new-sk',
      );
      expect(writing.complete, isFalse);
      expect(writing.skill, '---\nname: F\n---\n正文');

      final fenced = splitNewSkill(
        '<new-skill>\n```markdown\n$_film\n```\n</new-skill>',
      );
      expect(fenced.skill, _film);
    });

    test('话里顺口提到标签不算;提到之后真写了,取真的那一个', () {
      expect(splitNewSkill('我会放进 <new-skill> 标签里').skill, isNull);

      final made = splitNewSkill('我放进 <new-skill> 标签:\n$_reply');
      expect(made.skill, _film);
      expect(made.prose, startsWith('我放进 <new-skill> 标签:'));
    });

    test('Skill 正文里举例的成稿标签不会被当成成稿', () {
      final made = splitNewSkill(
        '<new-skill>\n# 例子\n\n输出 <draft>\n【主体】a fox\n</draft>\n</new-skill>',
      );
      expect(splitDraft(made.prose).draft, isNull);
    });
  });

  group('对话写出的 Skill 自动加入', () {
    test('回复正常结束:加进 Skills,成稿不受影响', () async {
      final vm = _studio(
        (_) => Stream.value(
          '<new-skill>\n$_film\n\n例子:<draft>\n【主体】a fox\n</draft>\n</new-skill>',
        ),
      );
      vm.send('帮我写一个胶片感的 Skill');
      await _settle();

      final added = vm.skills!.skills.single;
      expect(added.name, 'Film');
      expect(added.description, '胶片感');
      expect(vm.body, isEmpty);
      expect(vm.pending, isNull);
    });

    test('已有同名的不自动覆盖;半截的、没名字的不加', () async {
      final skills = tempSkills();
      await skills.addText('---\nname: Film\n---\n旧的正文');
      final vm = _studio((_) => Stream.value(_reply), skills: skills);
      vm.send('改一下');
      await _settle();
      expect(skills.skills.single.body, '旧的正文');

      // 用户点了替换:只换 SKILL.md,这个 Skill 附带的其他文件还在。
      final extra = File('${skills.dir.path}/film/refs.md')
        ..writeAsStringSync('柯达');
      await skills.addText(_film);
      expect(skills.skills.single.body, contains('用胶片的语言'));
      expect(extra.existsSync(), isTrue);

      final half = _studio(
        (_) => Stream.value('<new-skill>\n---\nname: Half\n---\n写到一半'),
      );
      half.send('写');
      await _settle();
      expect(half.skills!.skills, isEmpty);

      await expectLater(
        skills.addText('只有正文,没有名字'),
        throwsA(isA<SkillException>()),
      );
    });

    test('内置的 Skill 创作师带着输出格式的说明', () {
      final creator = builtinSkillList.firstWhere(
        (s) => s.id == 'skill-creator',
      );
      expect(creator.body, contains('<new-skill>'));
      expect(creator.body, contains('name:'));
    });
  });

  testWidgets('聊天里的新 Skill 卡片:同名的点一下才替换', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final skills = tempSkills();
    await tester.runAsync(() => skills.addText('---\nname: Film\n---\n旧的正文'));
    final time = DateTime(2026, 10, 9, 20);
    final vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      skills: skills,
      messages: [
        ChatMessage(fromUser: true, text: '改一下', time: time),
        ChatMessage(fromUser: false, text: _reply, time: time),
      ],
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: AppShell(vm: vm, config: vm.config, skills: skills),
      ),
    );

    expect(find.text('新 Skill · Film'), findsOneWidget);
    expect(find.text('胶片感'), findsOneWidget);

    await tester.tap(find.text('替换同名 Skill'));
    for (
      var i = 0;
      i < 100 && find.text('已加入 Skills').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(skills.skills.single.body, contains('用胶片的语言描述画面'));
    expect(find.text('替换同名 Skill'), findsNothing);
  });
}
