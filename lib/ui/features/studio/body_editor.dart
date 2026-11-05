part of 'body_card.dart';

// 成稿里可以打字的那一栏,以及固定区拖进文字时找落点。

final _separator = RegExp(r'[\s,.;!?,。;、!?]');

/// 把落点挪到最近的词缝(开头、结尾、空白或标点之后、两个汉字之间),
/// 免得把一个英文词劈成两半。
int snapToGap(String text, int offset) {
  bool sep(int i) => _separator.hasMatch(text[i]);
  bool cjk(int i) => text.codeUnitAt(i) >= 0x2E80;
  // 表情符号这类字占两个位置,不能从中间劈开。
  bool low(int i) => text.codeUnitAt(i) & 0xFC00 == 0xDC00;
  bool gap(int i) =>
      i <= 0 ||
      i >= text.length ||
      !sep(i) && !low(i) && (sep(i - 1) || cjk(i - 1) && cjk(i));
  final at = offset.clamp(0, text.length);
  for (var d = 0; ; d++) {
    if (gap(at - d)) return (at - d).clamp(0, text.length);
    if (gap(at + d)) return (at + d).clamp(0, text.length);
  }
}

class _BodyEditor extends StatefulWidget {
  const _BodyEditor({
    required this.body,
    required this.minLines,
    required this.onChanged,
    required this.onSelection,
    required this.onDropPin,
    this.acceptPins = true,
    this.selectionMenu = const [],
  });

  /// 选中文字后右键菜单里多出来的几项:名字、图标和要做的事。
  final List<(String, IconData, VoidCallback)> selectionMenu;

  /// 固定区能不能拖进这栏文字的中间。分段框里的不能:固定区落在整段的前面。
  final bool acceptPins;

  final String body;
  final int minLines;
  final ValueChanged<String> onChanged;

  /// 选区变化时报告(起、止);没有选中内容时为 null。
  final ValueChanged<(int, int)?> onSelection;

  /// 一个固定区(blocks 下标)被拖到了这栏文字的某个位置。
  final void Function(int from, int at) onDropPin;

  @override
  State<_BodyEditor> createState() => _BodyEditorState();
}

class _BodyEditorState extends State<_BodyEditor> {
  late final _controller = TextEditingController(text: widget.body)
    ..addListener(_reportSelection);
  final _focus = FocusNode();

  void _reportSelection() {
    final s = _controller.selection;
    widget.onSelection(s.isValid && !s.isCollapsed ? (s.start, s.end) : null);
  }

  /// 屏幕上的一点落在这栏文字的第几个字符,已对齐到词缝。
  int _offsetAt(Offset global) {
    RenderEditable? editable;
    void visit(Element e) {
      final render = e.renderObject;
      if (render is RenderEditable) {
        editable = render;
      } else {
        e.visitChildren(visit);
      }
    }

    context.visitChildElements(visit);
    final text = _controller.text;
    final raw = editable?.getPositionForPoint(global).offset ?? text.length;
    return snapToGap(text, raw);
  }

  @override
  void didUpdateWidget(_BodyEditor old) {
    super.didUpdateWidget(old);
    // 成稿被别处改了(比如采纳了 diff)才同步;用户正在打字时两边本来就相等。
    if (widget.body != _controller.text) _controller.text = widget.body;
    // 别的栏变长变短、或固定区挪动后,这栏在全文里的位置会变:
    // 正在用的这栏把选区按新位置重报一次。
    if (_focus.hasFocus) _reportSelection();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.acceptPins) return _field();
    return DragTarget<int>(
      // 拖着固定区经过时,把光标放到将要落下的位置给用户看。
      onMove: (d) {
        _focus.requestFocus();
        _controller.selection = TextSelection.collapsed(
          offset: _offsetAt(d.offset),
        );
      },
      onAcceptWithDetails: (d) => widget.onDropPin(d.data, _offsetAt(d.offset)),
      builder: (context, _, _) => _field(),
    );
  }

  Widget _field() => TextField(
    controller: _controller,
    focusNode: _focus,
    onChanged: widget.onChanged,
    minLines: widget.minLines,
    maxLines: null,
    style: monoStyle,
    contextMenuBuilder: (context, state) =>
        pennaTextMenu(context, state, extra: widget.selectionMenu),
    decoration: InputDecoration(
      hintText: tr('正面提示词…'),
      hintStyle: TextStyle(color: PennaColors.slate400),
      border: InputBorder.none,
      isDense: true,
    ),
  );
}
