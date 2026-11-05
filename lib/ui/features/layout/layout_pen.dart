part of 'layout_canvas.dart';

/// 钢笔(形状工具里的最后一个):一下一下点出多边形的顶点,点回起点或回车封口成一块,
/// Esc 取消、退格删掉上一个点;点满 [maxShapePoints] 个自己封口。框是这些点的外框,
/// 交出去的还是那个方框(形状交给 Agent 写进描述,见 `describeShapes`)。
extension _Pen on _LayoutCanvasState {
  /// 钢笔开着(自由镜头里左键是转头,不算)。
  bool get _penOn =>
      _board.shapeTool.value.tool == ShapeTool.pen && !_board.freeCam;

  void _penTap(Offset p, double scale) {
    if (_pen.length >= minShapePoints &&
        (p - _pen.first).distance * scale <= _handle) {
      return _penClose();
    }
    _redraw(() => _pen.add(p));
    if (_pen.length >= maxShapePoints) _penClose();
  }

  /// 鼠标在画布上移动:钢笔画着时,最后一个点连到鼠标这儿。
  void _penHover(Offset p) {
    if (!_penOn || _pen.isEmpty) return;
    _redraw(() => _hover = p);
  }

  void _penClose() {
    final box = boxFromPolygon([
      for (final p in _pen) (p.dx, p.dy),
    ], minSide: _minBox);
    _penClear();
    if (box != null) _board.addBox(box);
  }

  void _penClear() => _redraw(() {
    _pen.clear();
    _hover = null;
  });

  KeyEventResult _penKey(KeyEvent e) {
    if (e is! KeyDownEvent || !_penOn || _pen.isEmpty) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _penClose();
    } else if (k == LogicalKeyboardKey.escape) {
      _penClear();
    } else if (k == LogicalKeyboardKey.backspace ||
        k == LogicalKeyboardKey.delete) {
      _redraw(_pen.removeLast);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }
}

/// 钢笔画到一半的样子:点过的连成折线,最后一个点到鼠标是一段淡线;
/// 起点画大一圈(够了三个点时,点回它就封口)。坐标是屏幕上的。
class _PenPainter extends CustomPainter {
  _PenPainter(this.points, this.hover, this.color);

  final List<Offset> points;
  final Offset? hover;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    if (points.length >= 3) {
      canvas.drawPath(
        Path()..addPolygon(points, true),
        Paint()..color = color.withValues(alpha: 0.08),
      );
    }
    canvas.drawPath(Path()..addPolygon(points, false), line);
    final h = hover;
    if (h != null) {
      canvas.drawLine(
        points.last,
        h,
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 1.2,
      );
    }
    for (final (i, p) in points.indexed) {
      final r = i == 0 ? 6.0 : 4.0;
      canvas
        ..drawCircle(p, r, Paint()..color = Colors.white)
        ..drawCircle(p, r, line);
    }
  }

  @override
  bool shouldRepaint(_PenPainter old) =>
      old.hover != hover ||
      old.color != color ||
      !listEquals(old.points, points);
}
