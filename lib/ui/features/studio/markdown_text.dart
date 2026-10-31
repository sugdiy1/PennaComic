import 'package:flutter/material.dart';

import '../../core/theme.dart';

final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
final _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final _numbered = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
final _rule = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');
final _quote = RegExp(r'^\s*>\s?(.*)$');

/// 行内的粗体和代码:`**粗**`、`__粗__`、`` `代码` ``。
final _inline = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|`([^`\n]+)`');

/// 把模型回复里常见的 Markdown 画成带样式的文字:标题、粗体、行内代码、列表、引用、分割线。
/// 整条回复还是一段文字,所以能连着选中复制。
// ponytail: 只认这几样,表格、链接、多行代码块原样显示;
// 模型开始大量用它们时换成 flutter_markdown_plus 这类现成的包。
TextSpan markdownSpan(String text, TextStyle base) {
  final bold = base.copyWith(fontWeight: FontWeight.w700);
  List<InlineSpan> inline(String line, TextStyle style) {
    final out = <InlineSpan>[];
    var at = 0;
    for (final m in _inline.allMatches(line)) {
      if (m.start > at) out.add(TextSpan(text: line.substring(at, m.start)));
      final code = m[3];
      out.add(
        code != null
            ? TextSpan(
                text: code,
                style: style.copyWith(
                  backgroundColor: PennaColors.slate100,
                  color: PennaColors.slate700,
                ),
              )
            : TextSpan(
                text: m[1] ?? m[2],
                style: style.copyWith(fontWeight: FontWeight.w700),
              ),
      );
      at = m.end;
    }
    if (at < line.length) out.add(TextSpan(text: line.substring(at)));
    return out;
  }

  final lines = text.split('\n');
  final spans = <InlineSpan>[];
  for (final (i, line) in lines.indexed) {
    final nl = i == lines.length - 1 ? '' : '\n';
    final h = _heading.firstMatch(line);
    final b = _bullet.firstMatch(line);
    final n = _numbered.firstMatch(line);
    final q = _quote.firstMatch(line);
    if (_rule.hasMatch(line)) {
      spans.add(
        TextSpan(
          text: '────────────$nl',
          style: base.copyWith(color: PennaColors.border, height: 1.2),
        ),
      );
    } else if (h != null) {
      // 一级最大,往下每级小一点,最小也比正文粗。
      final size = (base.fontSize ?? 14) + (4 - h[1]!.length).clamp(0, 3) * 1.5;
      spans.add(
        TextSpan(
          style: bold.copyWith(fontSize: size),
          children: [
            ...inline(h[2]!, bold),
            TextSpan(text: nl),
          ],
        ),
      );
    } else if (b != null) {
      spans.add(
        TextSpan(
          children: [
            TextSpan(
              text: '${b[1]}  •  ',
              style: base.copyWith(color: PennaColors.slate400),
            ),
            ...inline(b[2]!, base),
            TextSpan(text: nl),
          ],
        ),
      );
    } else if (n != null) {
      spans.add(
        TextSpan(
          children: [
            TextSpan(text: '${n[1]}  ${n[2]}.  ', style: bold),
            ...inline(n[3]!, base),
            TextSpan(text: nl),
          ],
        ),
      );
    } else if (q != null) {
      spans.add(
        TextSpan(
          style: base.copyWith(color: PennaColors.slate500),
          children: [
            const TextSpan(text: '▏ '),
            ...inline(q[1]!, base.copyWith(color: PennaColors.slate500)),
            TextSpan(text: nl),
          ],
        ),
      );
    } else {
      spans.add(
        TextSpan(
          children: [
            ...inline(line, base),
            TextSpan(text: nl),
          ],
        ),
      );
    }
  }
  return TextSpan(style: base, children: spans);
}
