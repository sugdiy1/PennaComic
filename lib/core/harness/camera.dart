import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 区域控制的 3D 视图:一台绕着画面中心转的摄像机,和每一块的体块(长方体)。
/// 画布就是摄像机的底片,框是体块在底片上占的地方(8 个角投上去、取最小的外框)。
///
/// 世界坐标:x 向右、y 向下(和画布一样)、z 往画面里面;长度单位是"主体离镜头的距离",
/// 所以默认的摄像机在原点、看着 z = 1 那一层。只在 Penna 里用,交出去的 JSON 里没有。

typedef Vec3 = ({double x, double y, double z});

Vec3 _add(Vec3 a, Vec3 b) => (x: a.x + b.x, y: a.y + b.y, z: a.z + b.z);
Vec3 _sub(Vec3 a, Vec3 b) => (x: a.x - b.x, y: a.y - b.y, z: a.z - b.z);
Vec3 _mul(Vec3 a, double k) => (x: a.x * k, y: a.y * k, z: a.z * k);
double _dot(Vec3 a, Vec3 b) => a.x * b.x + a.y * b.y + a.z * b.z;
Vec3 _cross(Vec3 a, Vec3 b) => (
  x: a.y * b.z - a.z * b.y,
  y: a.z * b.x - a.x * b.z,
  z: a.x * b.y - a.y * b.x,
);

double _rad(double deg) => deg * math.pi / 180;

/// 角度收到 -180 到 180。
double wrapDegrees(double deg) => (deg + 180) % 360 - 180;

const defaultFov = 50.0;

/// 比这个近的点算在镜头后面,投不到底片上。
const _near = 0.01;

/// 摄像机:绕着目标点([panX] / [panY] / [panZ] 是它离画面中心 (0, 0, 1) 挪了多少)转。
/// [orbit] 水平环绕(0 正面,90 从左侧拍,±180 从背后拍),[pitch] 俯仰(正数俯视),
/// [roll] 画面歪多少,[distance] 离目标多远(1 是原来的距离),[fov] 长边对着的视角。
/// [shift] 是移轴:底片上下平移多少(画布高的几倍,正数往下),镜头不低头也能把地平线
/// 放到别处,竖线保持竖直(一点、两点透视就是这样)。角度都是度。
@immutable
class Camera {
  const Camera({
    this.orbit = 0,
    this.pitch = 0,
    this.roll = 0,
    this.distance = 1,
    this.fov = defaultFov,
    this.panX = 0,
    this.panY = 0,
    this.panZ = 0,
    this.shift = 0,
  });

  final double orbit, pitch, roll, distance, fov, panX, panY, panZ, shift;

  bool get isDefault => this == const Camera();

  Vec3 get target => (x: panX, y: panY, z: 1 + panZ);

  /// 改几项,顺便收进合理的范围。
  Camera copyWith({
    double? orbit,
    double? pitch,
    double? roll,
    double? distance,
    double? fov,
    double? panX,
    double? panY,
    double? panZ,
    double? shift,
  }) => Camera(
    orbit: wrapDegrees(orbit ?? this.orbit),
    pitch: (pitch ?? this.pitch).clamp(-89.0, 89.0),
    roll: wrapDegrees(roll ?? this.roll),
    distance: (distance ?? this.distance).clamp(0.05, 20.0),
    fov: (fov ?? this.fov).clamp(10.0, 120.0),
    panX: (panX ?? this.panX).clamp(-20.0, 20.0),
    panY: (panY ?? this.panY).clamp(-20.0, 20.0),
    panZ: (panZ ?? this.panZ).clamp(-20.0, 20.0),
    shift: (shift ?? this.shift).clamp(-2.0, 2.0),
  );

  Map<String, double> toJson() => {
    'orbit': orbit,
    'pitch': pitch,
    'roll': roll,
    'distance': distance,
    'fov': fov,
    'panX': panX,
    'panY': panY,
    'panZ': panZ,
    'shift': shift,
  };

  /// 读不了的项用默认值。
  static Camera fromJson(Object? j) {
    if (j is! Map) return const Camera();
    double v(String k, double fallback) =>
        j[k] is num ? (j[k] as num).toDouble() : fallback;
    return const Camera().copyWith(
      orbit: v('orbit', 0),
      pitch: v('pitch', 0),
      roll: v('roll', 0),
      distance: v('distance', 1),
      fov: v('fov', defaultFov),
      panX: v('panX', 0),
      panY: v('panY', 0),
      panZ: v('panZ', 0),
      shift: v('shift', 0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Camera &&
      other.orbit == orbit &&
      other.pitch == pitch &&
      other.roll == roll &&
      other.distance == distance &&
      other.fov == fov &&
      other.panX == panX &&
      other.panY == panY &&
      other.panZ == panZ &&
      other.shift == shift;

  @override
  int get hashCode =>
      Object.hash(orbit, pitch, roll, distance, fov, panX, panY, panZ, shift);
}

/// 摄像机对着一块 [width]×[height] 的画布:镜头的位置和朝向、焦距(像素)、画布中心。
/// 世界 ↔ 镜头 ↔ 画布像素的换算都在这里。
class CameraView {
  factory CameraView(Camera c, int width, int height) {
    final o = _rad(c.orbit), p = _rad(c.pitch), r = _rad(c.roll);
    final fwd = (
      x: math.sin(o) * math.cos(p),
      y: math.sin(p),
      z: math.cos(o) * math.cos(p),
    );
    final right0 = (x: math.cos(o), y: 0.0, z: -math.sin(o));
    final down0 = _cross(fwd, right0);
    return CameraView._(
      eye: _sub(c.target, _mul(fwd, c.distance)),
      fwd: fwd,
      right: _add(_mul(right0, math.cos(r)), _mul(down0, math.sin(r))),
      down: _sub(_mul(down0, math.cos(r)), _mul(right0, math.sin(r))),
      f: math.max(width, height) / 2 / math.tan(_rad(c.fov) / 2),
      cx: width / 2,
      // 移轴:底片的中心跟着上下挪。
      cy: height / 2 + c.shift * height,
      orbit: c.orbit,
    );
  }

  CameraView._({
    required this.eye,
    required this.fwd,
    required this.right,
    required this.down,
    required this.f,
    required this.cx,
    required this.cy,
    required this.orbit,
  });

  final Vec3 eye, fwd, right, down;
  final double f, cx, cy, orbit;

  /// 世界里的点换到镜头里:x 向画面右、y 向画面下、z 是离镜头多远。
  Vec3 toCamera(Vec3 p) {
    final d = _sub(p, eye);
    return (x: _dot(d, right), y: _dot(d, down), z: _dot(d, fwd));
  }

  Vec3 toWorld(Vec3 c) =>
      _add(eye, _add(_mul(right, c.x), _add(_mul(down, c.y), _mul(fwd, c.z))));

  /// 投到画布上(像素);在镜头后面是 null。
  ({double u, double v})? project(Vec3 p) {
    final c = toCamera(p);
    if (c.z < _near) return null;
    return (u: cx + f * c.x / c.z, v: cy + f * c.y / c.z);
  }

  /// 画布上 ([u], [v]) 那个像素、离镜头 [z] 远的那个点。
  Vec3 unproject(double u, double v, double z) =>
      toWorld((x: (u - cx) / f * z, y: (v - cy) / f * z, z: z));
}

/// 画布上的一个范围(像素,可以有小数)。
typedef Span = ({double left, double top, double right, double bottom});

/// 一块的体块:中心 ([x], [y], [z])、宽高厚 ([w], [h], [d])、绕竖直轴转了 [yaw] 度
/// (0 是正面朝着默认的镜头,正数往画面左边转)。[guessed] 是程序按图层猜的,
/// 还没让 Agent 估过。
@immutable
class Body {
  const Body({
    required this.x,
    required this.y,
    required this.z,
    required this.w,
    required this.h,
    required this.d,
    this.yaw = 0,
    this.guessed = false,
  });

  final double x, y, z, w, h, d, yaw;
  final bool guessed;

  Vec3 get center => (x: x, y: y, z: z);

  Body copyWith({
    double? x,
    double? y,
    double? z,
    double? w,
    double? h,
    double? d,
    double? yaw,
    bool? guessed,
  }) => Body(
    x: x ?? this.x,
    y: y ?? this.y,
    z: z ?? this.z,
    w: w ?? this.w,
    h: h ?? this.h,
    d: d ?? this.d,
    yaw: yaw ?? this.yaw,
    guessed: guessed ?? this.guessed,
  );

  Body moved(Vec3 by) => copyWith(x: x + by.x, y: y + by.y, z: z + by.z);

  /// 8 个角。第 i 个:i 的第 0 位是左右、第 1 位是上下、第 2 位是前后
  /// (0 是正面那一侧)。相差一位的两个角连成一条棱。
  List<Vec3> get corners {
    final c = math.cos(_rad(yaw)), s = math.sin(_rad(yaw));
    return [
      for (var i = 0; i < 8; i++)
        () {
          final lx = (i & 1 == 0 ? -w : w) / 2;
          final ly = (i & 2 == 0 ? -h : h) / 2;
          final lz = (i & 4 == 0 ? -d : d) / 2;
          return (x: x + lx * c + lz * s, y: y + ly, z: z - lx * s + lz * c);
        }(),
    ];
  }

  Map<String, Object> toJson() => {
    'at': [_r(x), _r(y), _r(z)],
    'size': [_r(w), _r(h), _r(d)],
    'yaw': _r(yaw),
    if (guessed) 'guessed': true,
  };

  static Body? fromJson(Object? j) {
    if (j is! Map || j['at'] is! List || j['size'] is! List) return null;
    final at = [
      for (final v in j['at'] as List)
        if (v is num) v.toDouble(),
    ];
    final size = [
      for (final v in j['size'] as List)
        if (v is num) v.toDouble(),
    ];
    if (at.length != 3 || size.length != 3 || size.any((v) => v < 0)) {
      return null;
    }
    return Body(
      x: at[0],
      y: at[1],
      z: at[2],
      w: size[0],
      h: size[1],
      d: size[2],
      yaw: j['yaw'] is num ? (j['yaw'] as num).toDouble() : 0,
      guessed: j['guessed'] == true,
    );
  }
}

double _r(double v) => (v * 10000).round() / 10000;

/// 体块投到画布上的外框;有角在镜头后面时是 null。
Span? projectBody(Body b, CameraView view) {
  double? l, t, r, bt;
  for (final c in b.corners) {
    final p = view.project(c);
    if (p == null) return null;
    l = l == null ? p.u : math.min(l, p.u);
    t = t == null ? p.v : math.min(t, p.v);
    r = r == null ? p.u : math.max(r, p.u);
    bt = bt == null ? p.v : math.max(bt, p.v);
  }
  return (left: l!, top: t!, right: r!, bottom: bt!);
}

/// 调整 [b] 的大小和位置,让它投到画布上正好是 [box],再平移;离镜头的远近和朝向不变。
/// 宽、高、厚各按它在画面上朝哪个方向缩放(见 [_axisScale]):正面看时框变宽就是宽变大,
/// 从上往下看时框变高是厚变大。框没有面积或体块在镜头后面时是 null。
// ponytail: 只迭代三次,转得很斜、离镜头很近的体块会差一两个像素;不够准再加次数。
Body? fitBody(Body b, Span box, CameraView view) {
  final bw = box.right - box.left, bh = box.bottom - box.top;
  if (bw <= 0 || bh <= 0 || projectBody(b, view) == null) return null;
  // 每样尺寸最多变成原来的四倍或四分之一:斜着看时有的边几乎朝着镜头,
  // 要把框拉到那么大只能把它拉得很长,一直拉会伸到镜头后面去。拉到头就停,
  // 框照体块实际投出来的样子摆(见 layout_3d.dart 的 refitBody)。
  double keep(double v, double from) => v.clamp(from / 4, from * 4);
  var body = b;
  for (var k = 0; k < 4; k++) {
    final p = projectBody(body, view)!;
    final pw = p.right - p.left, ph = p.bottom - p.top;
    if (pw <= 0 || ph <= 0) break;
    final sx = bw / pw, sy = bh / ph;
    final c = math.cos(_rad(body.yaw)), s = math.sin(_rad(body.yaw));
    final next = body.copyWith(
      w: keep(body.w * _axisScale((x: c, y: 0, z: -s), view, sx, sy), b.w),
      h: keep(body.h * _axisScale((x: 0, y: 1, z: 0), view, sx, sy), b.h),
      d: keep(body.d * _axisScale((x: s, y: 0, z: c), view, sx, sy), b.d),
    );
    final q = projectBody(next, view);
    if (q == null) break; // 这一步伸到了镜头后面:停在上一步
    final z = view.toCamera(next.center).z;
    final du = (box.left + box.right - q.left - q.right) / 2;
    final dv = (box.top + box.bottom - q.top - q.bottom) / 2;
    final moved = next.moved(
      _add(_mul(view.right, du / view.f * z), _mul(view.down, dv / view.f * z)),
    );
    if (projectBody(moved, view) == null) break;
    body = moved;
  }
  return body;
}

/// 体块的一条边([axis] 是它在世界里的方向)该放大几倍:看它在画面上朝左右多还是朝上下多,
/// 按这个比例混合左右的倍数 [sx] 和上下的倍数 [sy]。几乎正对着镜头的那条边(画面上
/// 只是一个点)两样各算一半。以前固定成"左右管宽和厚、上下管高",俯视时框一拉高,
/// 体块的高就被拉成很长的一根。
double _axisScale(Vec3 axis, CameraView view, double sx, double sy) {
  final across = _dot(axis, view.right).abs(), up = _dot(axis, view.down).abs();
  final t = across + up < 1e-6 ? 0.5 : across / (across + up);
  // 每一轮最多放大缩小两倍,免得一下拉飞。
  return (math.pow(sx, t) * math.pow(sy, 1 - t)).toDouble().clamp(0.5, 2.0);
}

/// 和 Agent 来回说体块时用的写法(相对眼前的镜头):[distance] 离镜头多远
/// (1 是主体那一层),[depth] 厚度是宽度的几倍,[yaw] 正面从正对镜头往画面左边转了几度。
typedef BodyHint = ({double distance, double depth, double yaw});

/// 读 Agent 写的 `"body": {"distance": 1.2, "depth": 0.5, "yaw": 30}`;读不了是 null。
BodyHint? parseBodyHint(Object? j) {
  if (j is! Map || j['distance'] is! num) return null;
  final distance = (j['distance'] as num).toDouble();
  if (distance <= 0) return null;
  final depth = j['depth'] is num ? (j['depth'] as num).toDouble() : 0.6;
  return (
    distance: distance.clamp(0.05, 50.0),
    depth: depth.clamp(0.0, 10.0),
    yaw: j['yaw'] is num ? wrapDegrees((j['yaw'] as num).toDouble()) : 0.0,
  );
}

/// 体块在 [view] 这个镜头下的说法(写进给 Agent 看的 JSON)。
Map<String, num> bodyHintJson(Body b, CameraView view) {
  final h = hintOf(b, view);
  return {
    'distance': (h.distance * 100).round() / 100,
    'depth': (h.depth * 100).round() / 100,
    'yaw': h.yaw.round(),
  };
}

/// 体块相对 [view] 这个镜头的说法:离镜头多远、厚是宽的几倍、正面从正对镜头转了几度。
/// 换镜头时拿它在新镜头下把体块重新立起来,框就不用动。
BodyHint hintOf(Body b, CameraView view) => (
  distance: view.toCamera(b.center).z,
  depth: b.w > 0 ? b.d / b.w : 0,
  yaw: wrapDegrees(b.yaw - view.orbit),
);

/// 照 [hint] 把画布上的 [box] 立成体块:沿着镜头的视线推到 distance 那么远,
/// 再调到投影正好是这个框。
Body liftBody(
  Span box,
  CameraView view,
  BodyHint hint, {
  bool guessed = false,
}) {
  final z = hint.distance;
  final c = view.unproject(
    (box.left + box.right) / 2,
    (box.top + box.bottom) / 2,
    z,
  );
  final w = (box.right - box.left) / view.f * z;
  final body = Body(
    x: c.x,
    y: c.y,
    z: c.z,
    w: w,
    h: (box.bottom - box.top) / view.f * z,
    d: w * hint.depth,
    yaw: wrapDegrees(hint.yaw + view.orbit),
    guessed: guessed,
  );
  return fitBody(body, box, view) ?? body;
}

/// Agent 还没估过时,按类别和图层猜一个:前景近、后景远,人比东西薄。
BodyHint guessBodyHint(String label, String layer) => (
  distance: switch (layer) {
    'front' => 0.75,
    'back' => 1.8,
    _ => 1.0,
  },
  depth: label == 'character' ? 0.5 : 0.8,
  yaw: 0,
);

/// 平移镜头:画面跟着鼠标挪 ([du], [dv]) 个画布像素(按目标点那么远算)。
Camera panned(Camera c, double du, double dv, int width, int height) {
  final view = CameraView(c, width, height);
  final k = c.distance / view.f;
  final t = _sub(
    c.target,
    _add(_mul(view.right, du * k), _mul(view.down, dv * k)),
  );
  return c.copyWith(panX: t.x, panY: t.y, panZ: t.z - 1);
}

/// 自由镜头里转头:镜头位置不动,朝向转 [dOrbit] / [dPitch] 度(目标点跟着挪到正前方)。
Camera lookAround(Camera c, double dOrbit, double dPitch) {
  final eye = CameraView(c, 1, 1).eye;
  final turned = c.copyWith(orbit: c.orbit + dOrbit, pitch: c.pitch + dPitch);
  final t = _add(eye, _mul(CameraView(turned, 1, 1).fwd, c.distance));
  return turned.copyWith(panX: t.x, panY: t.y, panZ: t.z - 1);
}

/// 自由镜头里走动:镜头和目标点一起往前 [forward]、往右 [right]、往上 [up] 挪
/// (都是世界里的长度,方向按镜头现在的朝向)。
Camera walk(Camera c, {double forward = 0, double right = 0, double up = 0}) {
  final v = CameraView(c, 1, 1);
  final t = _add(
    c.target,
    _add(_mul(v.fwd, forward), _add(_mul(v.right, right), _mul(v.down, -up))),
  );
  return c.copyWith(panX: t.x, panY: t.y, panZ: t.z - 1);
}

/// 绕着 [p] 转:目标点挪到它身上,角度和距离不变。
Camera focusOn(Camera c, Vec3 p) =>
    c.copyWith(panX: p.x, panY: p.y, panZ: p.z - 1);
