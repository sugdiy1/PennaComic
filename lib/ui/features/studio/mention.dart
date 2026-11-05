import 'package:flutter/material.dart';

import '../../../data/services/skill_store.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../../l10n/l10n.dart';

/// 输入框里正在打的「@关键词」:@ 所在的位置,和它后面已经打出的字。
typedef MentionQuery = ({int start, String query});

/// 光标前如果是「@关键词」(@ 在开头或空白之后),返回它;否则返回 null。
MentionQuery? mentionQueryAt(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final match = RegExp(r'(?:^|\s)@([^\s@]*)$')
      .firstMatch(text.substring(0, cursor));
  if (match == null) return null;
  final query = match.group(1)!;
  return (start: cursor - query.length - 1, query: query);
}

/// 名字或编号里含有 [query] 的 Skill(不分大小写);[query] 为空时全部返回。
List<UserSkill> matchSkills(Iterable<UserSkill> skills, String query) {
  final q = query.toLowerCase();
  return [
    for (final s in skills)
      if (q.isEmpty ||
          s.name.toLowerCase().contains(q) ||
          tr(s.name).toLowerCase().contains(q) ||
          s.id.contains(q))
        s,
  ];
}

/// 打 @ 时弹出的 Skill 列表。
class MentionList extends StatelessWidget {
  const MentionList({
    super.key,
    required this.skills,
    required this.selected,
    required this.onPick,
  });

  final List<UserSkill> skills;

  /// 键盘当前选中的那一项。
  final int selected;
  final ValueChanged<UserSkill> onPick;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      radius: 10,
      padding: const EdgeInsets.all(4),
      child: skills.isEmpty
          ? Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                tr('没有匹配的 Skill'),
                style: TextStyle(fontSize: 12, color: PennaColors.slate400),
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 196),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: skills.length,
                itemBuilder: (_, i) => _MentionRow(
                  skill: skills[i],
                  selected: i == selected,
                  onTap: () => onPick(skills[i]),
                ),
              ),
            ),
    );
  }
}

class _MentionRow extends StatelessWidget {
  const _MentionRow({
    required this.skill,
    required this.selected,
    required this.onTap,
  });

  final UserSkill skill;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? PennaColors.primaryBg : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Text(
                tr(skill.name),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? PennaColors.primary : PennaColors.slate700,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(skill.description),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: PennaColors.slate400),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一个已引用的 Skill 标签;给了 [onRemove] 就带一个叉。
class MentionChip extends StatelessWidget {
  const MentionChip({
    super.key,
    required this.name,
    this.onRemove,
    this.prefix = '@',
  });

  final String name;

  /// 名字前面的记号;引用成稿里的一段时换成别的。
  final String prefix;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      color: PennaColors.primaryBg,
      borderColor: PennaColors.primaryBorder,
      radius: 6,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '$prefix$name',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: PennaColors.primary,
              ),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onRemove,
                child: Icon(Icons.close, size: 12, color: PennaColors.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
