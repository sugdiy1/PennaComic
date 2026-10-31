import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/harness/layout.dart';

/// 透视线上能拖的几个消失点(画布像素):先是地平线上的,三点透视最后是竖直方向那个。
List<Offset> vanishingPoints(Perspective p) => [
  for (final x in p.xs) Offset(x.toDouble(), p.horizon.toDouble()),
  if (p.third != null) Offset(p.third!.x.toDouble(), p.third!.y.toDouble()),
];

/// 画面外的消失点在画布边上放一个替身(离边 [inset]),按住它照样拖;拖的时候
/// 消失点本身可以一直往外走(以前只能拖到画布里,点都卡在边上)。
const markerInset = 8.0;

Offset vanishMarker(Offset v, Size canvas, double inset) => Offset(
  v.dx.clamp(inset, canvas.width - inset),
  v.dy.clamp(inset, canvas.height - inset),
);

/// 每个消失点放出去的辐射线条数。
const _rays = 28;

/// 画透视辅助线:地平线、每个消失点放出的辐射线和能拖的圆点。[scale] 是画布像素到屏幕。
class PerspectivePainter extends CustomPainter {
  PerspectivePainter(this.perspective, this.scale, this.color);

  final Perspective perspective;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final rays = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    final points = [for (final v in vanishingPoints(perspective)) v * scale];
    final edge = _perimeter(size);
    for (final v in points) {
      for (final e in edge) {
        canvas.drawLine(v, e, rays);
      }
    }
    final y = perspective.horizon * scale;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color
        ..strokeWidth = 1.6,
    );
    canvas.restore();
    // 圆点画在裁剪外面:贴着边的消失点也看得全。画面外的在画布边上画一个小一点的替身,
    // 再朝真正的方向伸出一小截线,按住它照样能拖(见 vanishMarker)。
    final room = (Offset.zero & size).inflate(8);
    for (final v in points) {
      final inside = room.contains(v);
      final at = inside ? v : vanishMarker(v, size, markerInset);
      if (!inside) {
        final dir = v - at;
        canvas.drawLine(
          at,
          at + dir / dir.distance * 14,
          Paint()
            ..color = color
            ..strokeWidth = 2,
        );
      }
      final r = inside ? 6.0 : 4.5;
      canvas
        ..drawCircle(at, r, Paint()..color = Colors.white)
        ..drawCircle(
          at,
          r,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
    }
  }

  /// 画布四条边上均匀取的点,辐射线连到这里。
  static List<Offset> _perimeter(Size s) {
    final total = 2 * (s.width + s.height);
    return [
      for (var k = 0; k < _rays; k++)
        () {
          var d = total * k / _rays;
          if (d < s.width) return Offset(d, 0);
          d -= s.width;
          if (d < s.height) return Offset(s.width, d);
          d -= s.height;
          if (d < s.width) return Offset(s.width - d, s.height);
          return Offset(0, s.height - math.min(d - s.width, s.height));
        }(),
    ];
  }

  @override
  bool shouldRepaint(PerspectivePainter old) =>
      old.perspective != perspective ||
      old.scale != scale ||
      old.color != color;
}
