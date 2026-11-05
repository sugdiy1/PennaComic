import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 横着的一排小按钮:最多露出前 [visible] 个那么宽,多出来的横着滚
/// (底下有滚动条,鼠标滚轮也能滚;[bar] 为假时不画滚动条,只能用滚轮)。
/// 地方不够时照样缩窄、能滚。
class ScrollStrip extends StatefulWidget {
  const ScrollStrip({
    super.key,
    required this.children,
    required this.visible,
    this.gap = 6,
    this.bar = true,
  });

  final List<Widget> children;
  final int visible;
  final double gap;
  final bool bar;

  @override
  State<ScrollStrip> createState() => _ScrollStripState();
}

class _ScrollStripState extends State<ScrollStrip> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _row(Iterable<Widget> items) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, w) in items.indexed) ...[
        if (i > 0) SizedBox(width: widget.gap),
        w,
      ],
    ],
  );

  /// 鼠标滚轮本来是上下滚的,这里把它当成左右滚。
  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    _scroll.jumpTo(
      (_scroll.offset + delta).clamp(0, _scroll.position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scrolls = widget.bar && widget.children.length > widget.visible;
    // 底下留给滚动条,免得压在按钮上。
    final pad = EdgeInsets.only(bottom: scrolls ? 8 : 0);
    return Stack(
      children: [
        // 看不见,只用来量出前 visible 个有多宽多高;整排就是这么大。
        ExcludeSemantics(
          child: IgnorePointer(
            child: Opacity(
              opacity: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: pad,
                child: _row(widget.children.take(widget.visible)),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Listener(
            onPointerSignal: _wheel,
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: scrolls,
              thickness: 4,
              radius: const Radius.circular(2),
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: pad,
                child: _row(widget.children),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
