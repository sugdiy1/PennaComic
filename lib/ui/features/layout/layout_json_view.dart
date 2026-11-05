import 'package:flutter/material.dart';

import '../../../core/harness/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'layout_canvas.dart';
import '../../../l10n/l10n.dart';

/// 一份布局 JSON 按功能区分框显示:整体一个框,每一块一个框,颜色和画布上的框对得上。
/// 只是显示上分开,原文还是一整份;不是布局 JSON 时不要用它(先 [layoutJsonRegions] 看一下)。
class LayoutJsonView extends StatelessWidget {
  const LayoutJsonView({
    super.key,
    required this.text,
    required this.regions,
    this.names = const [],
    this.style,
  });

  final String text;
  final List<LayoutRegion> regions;

  /// 各块的名字(布局页上有,交出去的 JSON 里没有);没给就用 JSON 里的。
  final List<String> names;
  final TextStyle? style;

  String _title(LayoutRegion r) {
    if (r.item < 0) return tr('整体');
    final given = r.item < names.length ? names[r.item].trim() : '';
    final name = given.isNotEmpty
        ? given
        : r.name.isNotEmpty
        ? r.name
        : layoutLabelName(r.label);
    return [
      '${r.item + 1} · $name',
      if (r.text.isNotEmpty) '「${r.text}」',
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, r) in regions.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _Area(
            title: _title(r),
            color: r.item < 0 ? PennaColors.slate500 : layoutBoxColor(r.item),
            body: text.substring(r.start, r.end),
            style: style,
          ),
        ],
      ],
    );
  }
}

class _Area extends StatelessWidget {
  const _Area({
    required this.title,
    required this.color,
    required this.body,
    this.style,
  });

  final String title;
  final Color color;
  final String body;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(7),
              ),
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: SelectableText(
              body,
              contextMenuBuilder: pennaTextMenu,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

/// 成稿里的一栏布局 JSON:平时按功能区分框看,点「编辑」换回一整块输入框改。
/// 不管怎么显示,成稿里都只是这一整份 JSON,不会被拆成分段。
class LayoutJsonColumn extends StatefulWidget {
  const LayoutJsonColumn({
    super.key,
    required this.text,
    required this.regions,
    required this.editor,
    this.style,
  });

  final String text;
  final List<LayoutRegion> regions;

  /// 编辑时用的那个输入框(和普通文字栏是同一个)。
  final Widget editor;
  final TextStyle? style;

  @override
  State<LayoutJsonColumn> createState() => _LayoutJsonColumnState();
}

class _LayoutJsonColumnState extends State<LayoutJsonColumn> {
  var _editing = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: PennaButton(
            label: _editing ? tr('分区查看') : tr('编辑'),
            icon: _editing ? Icons.view_agenda_outlined : Icons.edit_outlined,
            onPressed: () => setState(() => _editing = !_editing),
          ),
        ),
        const SizedBox(height: 6),
        if (_editing)
          widget.editor
        else
          LayoutJsonView(
            text: widget.text,
            regions: widget.regions,
            style: widget.style,
          ),
      ],
    );
  }
}
