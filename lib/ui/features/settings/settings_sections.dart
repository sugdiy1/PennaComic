import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../../l10n/l10n.dart';

const gap = SizedBox(height: 12);

/// 删除前问一句;用户点了"删除"才返回 true。
/// 确认框。[action] 是确认按钮上的字,不给就是红色的「删除」。
Future<bool> confirmDelete(
  BuildContext context,
  String title,
  String body, {
  String? action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: Text(body, style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr('取消')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: action == null
              ? TextButton.styleFrom(foregroundColor: PennaColors.diffDelText)
              : null,
          child: Text(action ?? tr('删除')),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, this.note, {super.key});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            note,
            style: TextStyle(fontSize: 12, color: PennaColors.slate500),
          ),
        ],
      ),
    );
  }
}

const titleStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
