part of 'body_card.dart';

// 待确认改动的红绿对比。

/// 按行比对两段文字:返回每一行和它的去向(-1 删掉、0 没变、1 新增)。
/// 空行不算改动。成稿每段一行,所以这样比出来正好是「哪几段变了」。
List<(String, int)> lineDiff(String before, String after) {
  final a = before.split('\n');
  final b = after.split('\n');
  // same[i][j]:a 从第 i 行起、b 从第 j 行起,最多有几行能对上。
  final same = [
    for (var i = 0; i <= a.length; i++) List.filled(b.length + 1, 0),
  ];
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      same[i][j] = a[i] == b[j]
          ? same[i + 1][j + 1] + 1
          : (same[i + 1][j] >= same[i][j + 1]
                ? same[i + 1][j]
                : same[i][j + 1]);
    }
  }
  final out = <(String, int)>[];
  var i = 0, j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      out.add((a[i++], 0));
      j++;
    } else if (i < a.length &&
        (j == b.length || same[i + 1][j] >= same[i][j + 1])) {
      out.add((a[i++], -1));
    } else {
      out.add((b[j++], 1));
    }
  }
  return [
    for (final line in out)
      if (line.$1.isNotEmpty) line,
  ];
}

/// 待确认改动的标题和「采纳 / 驳回」。
class _DiffHeader extends StatelessWidget {
  const _DiffHeader({
    required this.diff,
    required this.onAccept,
    required this.onReject,
    this.all = false,
  });

  /// 下面每段另有自己的按钮:这一行管的是全部。
  final bool all;
  final DiffProposal diff;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.auto_awesome, size: 13, color: PennaColors.primary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            diff.title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: PennaColors.primary,
            ),
          ),
        ),
        PennaButton(
          label: all ? tr('全部采纳') : tr('采纳'),
          background: PennaColors.diffAdd,
          foreground: PennaColors.diffAddText,
          onPressed: onAccept,
        ),
        const SizedBox(width: 4),
        PennaButton(
          label: all ? tr('全部驳回') : tr('驳回'),
          background: PennaColors.diffDel,
          foreground: PennaColors.diffDelText,
          onPressed: onReject,
        ),
      ],
    );
  }
}

/// 按行比对出来的红绿对比;没变的行灰色原样。每行开头的 [strip] 不显示
/// (分段框里已经有标注了)。
List<Widget> _diffLines(String before, String after, {String strip = ''}) => [
  for (final (raw, kind) in lineDiff(before, after))
    if (raw.replaceFirst(strip, '') case final line)
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: kind == 0
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '  $line',
                  style: monoStyle.copyWith(
                    fontSize: 11.5,
                    color: PennaColors.slate500,
                  ),
                ),
              )
            : _DiffLine(text: '${kind < 0 ? '-' : '+'} $line', added: kind > 0),
      ),
];

/// 没有分段标注的成稿用的整块对比。
class _DiffBlock extends StatelessWidget {
  const _DiffBlock({
    required this.diff,
    required this.onAccept,
    required this.onReject,
  });

  final DiffProposal diff;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      color: PennaColors.slate50,
      radius: 4,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DiffHeader(diff: diff, onAccept: onAccept, onReject: onReject),
          const SizedBox(height: 4),
          ..._diffLines(diff.removed, diff.added),
        ],
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.text, required this.added});

  final String text;
  final bool added;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: added ? PennaColors.diffAdd : PennaColors.diffDel,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: monoStyle.copyWith(
          fontSize: 11.5,
          color: added ? PennaColors.diffAddText : PennaColors.diffDelText,
          fontWeight: added ? FontWeight.w600 : FontWeight.w400,
          decoration: added ? null : TextDecoration.lineThrough,
        ),
      ),
    );
  }
}
