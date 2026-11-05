import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/harness/layout.dart';

/// 椭圆的柱体取这么多个点。
const _ovalSegments = 24;

/// 体块的截面(它自己的坐标:左右、上下,原点在中心):方框是四个角,椭圆取一圈点,
/// 多边形就是它的顶点。形状按框的比例存,这里换成体块的宽高。
List<(double, double)> _outline(Body b, LayoutShape? s) {
  final w = b.w / 2, h = b.h / 2;
  if (s == null) return [(-w, -h), (w, -h), (w, h), (-w, h)];
  if (s.isEllipse) {
    return [
      for (var k = 0; k < _ovalSegments; k++)
        (
          math.cos(2 * math.pi * k / _ovalSegments) * w,
          math.sin(2 * math.pi * k / _ovalSegments) * h,
        ),
    ];
  }
  return [for (final (u, v) in s.points) ((u - 0.5) * b.w, (v - 0.5) * b.h)];
}

/// 一个体块:截面按 [shape] 从前往后挤成柱体(没形状就是长方体),投到屏幕上画
/// ([project] 把世界坐标的点换成屏幕上的,镜头后面的是 null,那就整块不画)。
/// 正面淡淡涂一层看得出朝哪,棱用实线;椭圆柱侧面只画四条线,不然一圈密密麻麻。
/// [lit] 不为 null 时是光影预览:照它的灯光把从 [eye] 看得到的面涂上明暗,远的先涂。
/// 形状是 3D 的(跟着体块转、有厚度),不是一直正对镜头的一个面(用户要求)。
void paintBody(
  Canvas canvas,
  Body body,
  LayoutShape? shape,
  Offset? Function(Vec3) project,
  Color color, {
  double width = 1.2,
  Layout? lit,
  Vec3? eye,
}) {
  final a = body.yaw * math.pi / 180;
  final c = math.cos(a), s = math.sin(a);
  // 和 Body.corners 同一个转法:正面在 -z 那一侧。
  Vec3 world(double lx, double ly, double lz) => (
    x: body.x + lx * c + lz * s,
    y: body.y + ly,
    z: body.z - lx * s + lz * c,
  );
  Vec3 turn(double nx, double ny, double nz) =>
      (x: nx * c + nz * s, y: ny, z: -nx * s + nz * c);
  final ring = _outline(body, shape);
  final n = ring.length;
  final front = [for (final (x, y) in ring) world(x, y, -body.d / 2)];
  final back = [for (final (x, y) in ring) world(x, y, body.d / 2)];
  final f2 = [for (final p in front) project(p)];
  final b2 = [for (final p in back) project(p)];
  if (f2.contains(null) || b2.contains(null)) return;
  final fs = f2.cast<Offset>(), bs = b2.cast<Offset>();
  final view = eye;
  if (lit != null && view != null) {
    // 截面的中心:侧面的法线朝外(背着它)。
    final cx = ring.map((p) => p.$1).reduce((p, q) => p + q) / n;
    final cy = ring.map((p) => p.$2).reduce((p, q) => p + q) / n;
    final faces = <(List<Offset>, Vec3, Vec3)>[
      (fs, turn(0, 0, -1), world(cx, cy, -body.d / 2)),
      (bs, turn(0, 0, 1), world(cx, cy, body.d / 2)),
      for (var i = 0; i < n; i++)
        () {
          final (x0, y0) = ring[i];
          final (x1, y1) = ring[(i + 1) % n];
          var (nx, ny) = (y1 - y0, x0 - x1);
          final mx = (x0 + x1) / 2, my = (y0 + y1) / 2;
          if (nx * (mx - cx) + ny * (my - cy) < 0) (nx, ny) = (-nx, -ny);
          final len = math.sqrt(nx * nx + ny * ny);
          return (
            [fs[i], fs[(i + 1) % n], bs[(i + 1) % n], bs[i]],
            turn(nx / (len == 0 ? 1 : len), ny / (len == 0 ? 1 : len), 0),
            world(mx, my, 0),
          );
        }(),
    ];
    double far(Vec3 p) =>
        (p.x - view.x) * (p.x - view.x) +
        (p.y - view.y) * (p.y - view.y) +
        (p.z - view.z) * (p.z - view.z);
    final seen = [
      for (final f in faces)
        if (f.$2.x * (view.x - f.$3.x) +
                f.$2.y * (view.y - f.$3.y) +
                f.$2.z * (view.z - f.$3.z) >
            0)
          f,
    ]..sort((p, q) => far(q.$3).compareTo(far(p.$3)));
    for (final (pts, normal, _) in seen) {
      final (r, g, b) = shade(
        normal,
        (color.r, color.g, color.b),
        lit.lighting,
        lit.camera,
      );
      canvas.drawPath(
        Path()..addPolygon(pts, true),
        Paint()..color = Color.from(alpha: 0.92, red: r, green: g, blue: b),
      );
    }
  }
  canvas.drawPath(
    Path()..addPolygon(fs, true),
    Paint()..color = color.withValues(alpha: 0.14),
  );
  final line = Paint()
    ..color = color.withValues(alpha: 0.9)
    ..strokeWidth = width
    ..style = PaintingStyle.stroke;
  canvas
    ..drawPath(Path()..addPolygon(fs, true), line)
    ..drawPath(Path()..addPolygon(bs, true), line);
  final oval = shape?.isEllipse ?? false;
  for (var i = 0; i < n; i++) {
    if (oval && i % (_ovalSegments ~/ 4) != 0) continue;
    canvas.drawLine(fs[i], bs[i], line);
  }
}

/// 画布背景在这套灯光下的颜色(光影预览:暗调的灯光下画布也暗)。
Color litBackdrop(Layout layout) {
  final (r, g, b) = backdropShade(
    (0.97, 0.97, 0.97),
    layout.lighting,
    layout.camera,
  );
  return Color.from(alpha: 1, red: r, green: g, blue: b);
}

/// 主画布上(3D 视图)每块的体块:投到画布上,[scale] 是画布像素到屏幕。屏蔽了的不画。
/// [lit] 为真时按灯光给看得到的面上明暗(光影预览)。
class BodiesPainter extends CustomPainter {
  BodiesPainter(
    this.layout,
    this.scale,
    this.colorOf,
    this.selected, {
    this.lit = false,
  });

  final Layout layout;
  final double scale;
  final Color Function(int) colorOf;
  final int? selected;
  final bool lit;

  @override
  void paint(Canvas canvas, Size size) {
    final view = CameraView(layout.camera, layout.width, layout.height);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final (i, b) in layout.boxes.indexed.toList().reversed) {
      final body = b.body;
      if (body == null || b.offscreen || !b.shownIn(threeD: true)) continue;
      paintBody(
        canvas,
        body,
        b.shape,
        (p) => switch (view.project(p)) {
          null => null,
          final q => Offset(q.u * scale, q.v * scale),
        },
        colorOf(i),
        width: i == selected ? 2 : 1.2,
        lit: lit ? layout : null,
        eye: view.eye,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BodiesPainter old) =>
      old.layout != layout ||
      old.scale != scale ||
      old.selected != selected ||
      old.lit != lit;
}

/// 摄像机面板里的小场景:斜上方看下去的一个固定视角,画出各块的体块、
/// 粉色的水平环绕圈、青色的俯仰弧和黄色的摄像机(连着它看的目标点)。
class OrbitPainter extends CustomPainter {
  OrbitPainter(this.layout, this.colorOf, {required this.grid});

  final Layout layout;
  final Color Function(int) colorOf;
  final Color grid;

  static const _ring = Color(0xFFF43F5E);
  static const _arc = Color(0xFF06B6D4);
  static const _eye = Color(0xFFF59E0B);

  @override
  void paint(Canvas canvas, Size size) {
    final cam = layout.camera;
    final t = cam.target;
    final r = cam.distance;
    // 看场景的那台"观察镜头":离得远、视角窄,近似平行投影。
    final watcher = CameraView(
      Camera(
        orbit: -35,
        pitch: 28,
        distance: 20,
        fov: 10,
        panX: t.x,
        panY: t.y,
        panZ: t.z - 1,
      ),
      100,
      100,
    );
    Offset? at(Vec3 p) {
      final q = watcher.project(p);
      return q == null ? null : Offset(q.u, q.v);
    }

    final o = cam.orbit * math.pi / 180;
    Vec3 orbitPoint(double a, double e) => (
      x: t.x - r * math.sin(a) * math.cos(e),
      y: t.y - r * math.sin(e),
      z: t.z - r * math.cos(a) * math.cos(e),
    );
    final ring = [
      for (var k = 0; k <= 48; k++) at(orbitPoint(k * math.pi / 24, 0)),
    ];
    final arc = [
      for (var e = -80; e <= 80; e += 5) at(orbitPoint(o, e * math.pi / 180)),
    ];
    final eyeView = CameraView(cam, layout.width, layout.height);
    final eye = at(eyeView.eye);
    final look = at((
      x: eyeView.eye.x + eyeView.fwd.x * r * 0.35,
      y: eyeView.eye.y + eyeView.fwd.y * r * 0.35,
      z: eyeView.eye.z + eyeView.fwd.z * r * 0.35,
    ));
    // 角只用来把场景框进面板;画的时候按形状挤成柱体。
    final bodies = <(int, LayoutBox, List<Offset?>)>[
      for (final (i, b) in layout.boxes.indexed)
        if (b.body != null && b.shownIn(threeD: true))
          (i, b, [for (final c in b.body!.corners) at(c)]),
    ];
    // 把用到的点都框进面板里。
    final all = [
      ...ring,
      ...arc,
      eye,
      at(t),
      for (final b in bodies) ...b.$3,
    ].whereType<Offset>().toList();
    if (all.isEmpty) return;
    var box = Rect.fromPoints(all.first, all.first);
    for (final p in all) {
      box = box.expandToInclude(Rect.fromPoints(p, p));
    }
    const pad = 14.0;
    final k = math.min(
      (size.width - 2 * pad) / math.max(box.width, 1e-6),
      (size.height - 2 * pad) / math.max(box.height, 1e-6),
    );
    final shift = size.center(Offset.zero) - box.center * k;
    Offset? fit(Offset? p) => p == null ? null : p * k + shift;

    void polyline(List<Offset?> pts, Paint paint) {
      for (var i = 0; i + 1 < pts.length; i++) {
        final a = fit(pts[i]), b = fit(pts[i + 1]);
        if (a != null && b != null) canvas.drawLine(a, b, paint);
      }
    }

    polyline(
      ring,
      Paint()
        ..color = _ring.withValues(alpha: 0.85)
        ..strokeWidth = 2.5,
    );
    polyline(
      arc,
      Paint()
        ..color = _arc.withValues(alpha: 0.35)
        ..strokeWidth = 2,
    );
    // 从水平到现在的俯仰角,每 2° 一段。
    final steps = (cam.pitch.abs() / 2).ceil();
    final pitchArc = [
      for (var k = 0; k <= steps; k++)
        at(orbitPoint(o, cam.pitch * k / steps * math.pi / 180)),
    ];
    if (steps > 0) {
      polyline(
        pitchArc,
        Paint()
          ..color = _arc
          ..strokeWidth = 3,
      );
    }
    for (final (i, b, _) in bodies) {
      paintBody(canvas, b.body!, b.shape, (p) => fit(at(p)), colorOf(i));
    }
    final target = fit(at(t));
    final e = fit(eye), l = fit(look);
    if (target != null) {
      canvas.drawCircle(target, 2.5, Paint()..color = grid);
    }
    if (e != null && target != null) {
      canvas.drawLine(
        e,
        target,
        Paint()
          ..color = _eye.withValues(alpha: 0.6)
          ..strokeWidth = 1.5,
      );
    }
    final ringDot = fit(at(orbitPoint(o, 0)));
    if (ringDot != null) canvas.drawCircle(ringDot, 5, Paint()..color = _ring);
    if (e != null) {
      if (l != null) {
        canvas.drawLine(
          e,
          l,
          Paint()
            ..color = _eye
            ..strokeWidth = 3,
        );
      }
      canvas
        ..drawCircle(e, 6.5, Paint()..color = _eye)
        ..drawCircle(
          e,
          6.5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
    }
  }

  @override
  bool shouldRepaint(OrbitPainter old) =>
      old.layout != layout || old.grid != grid;
}
