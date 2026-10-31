import 'dart:math' as math;

import 'layout.dart';

/// 区域控制的 3D 视图怎么带着画板变(摄像机和体块本身在 `camera.dart`):
/// 转镜头时框跟着体块走,2D 里改了框时体块跟着框走。文字块贴在画面上,没有体块。

/// 照 [l] 的镜头重新算各块的框:有体块的投到画布上(出了画布的截掉,整个出去或转到
/// 镜头后面的缩成没有面积,见 [LayoutBox.offscreen]),再按离镜头的远近重排前后:
/// 各层的块数不变,离镜头近的排在前面、拿前面的层。文字块和没有体块的不动。
/// 交回新的各块,每一块带着它原来是第几块(选中的要跟着走)。
List<(int, LayoutBox)> reprojectBoxes(Layout l) {
  final view = CameraView(l.camera, l.width, l.height);
  final kept = <(int, LayoutBox)>[];
  final seen = <(int, LayoutBox, double)>[];
  for (final (i, b) in l.boxes.indexed) {
    final body = b.body;
    if (body == null || b.label == 'text') {
      kept.add((i, b));
      continue;
    }
    final p = projectBody(body, view);
    final box = p == null
        ? null
        : b.copyWith(
            left: p.left.round().clamp(0, l.width),
            top: p.top.round().clamp(0, l.height),
            right: p.right.round().clamp(0, l.width),
            bottom: p.bottom.round().clamp(0, l.height),
          );
    if (box == null || box.offscreen) {
      kept.add((i, b.copyWith(left: 0, top: 0, right: 0, bottom: 0)));
    } else {
      seen.add((i, box, view.toCamera(body.center).z));
    }
  }
  final layers = [for (final s in seen) s.$2.layer]
    ..sort((a, b) => layoutLayers.indexOf(b) - layoutLayers.indexOf(a));
  seen.sort((a, b) => a.$3.compareTo(b.$3));
  return [
    ...kept,
    for (final (k, s) in seen.indexed) (s.$1, s.$2.copyWith(layer: layers[k])),
  ];
}

/// 2D 里改了框(拖动、改大小、换画布):体块跟着调到投影正好是这个框,
/// 远近和朝向不变。调不了(没有面积、在镜头后面)就原样;斜着看时拉到头了
/// (见 [fitBody])框就贴着体块实际投出来的样子。
LayoutBox refitBody(LayoutBox b, Layout l) {
  final body = b.body;
  if (body == null || b.offscreen) return b;
  final view = CameraView(l.camera, l.width, l.height);
  final fitted = fitBody(body, b.span, view);
  return fitted == null ? b : _snap(b.copyWith(body: () => fitted), view, l);
}

/// 给一块立起体块:照 Agent 写的 [hint],没写就按类别和图层猜一个(记成 guessed)。
/// 文字块不立,有的话也去掉。
LayoutBox liftBox(LayoutBox b, Layout l, [BodyHint? hint]) {
  if (b.label == 'text') return b.copyWith(body: () => null);
  if (b.offscreen) return b;
  final view = CameraView(l.camera, l.width, l.height);
  final guess = guessBodyHint(b.label, b.layer);
  final ground = _groundDistance(b, l);
  final body = liftBody(
    b.span,
    view,
    hint ??
        (ground == null
            ? guess
            : (distance: ground, depth: guess.depth, yaw: guess.yaw)),
    guessed: hint == null,
  );
  return _snap(b.copyWith(body: () => body), view, l);
}

/// 框和体块的投影差出两个像素以上(体块拉到头了)时,框改成投影的样子,
/// 免得框是一个样、体块是另一个样。截到画布里后没有面积就不改。
LayoutBox _snap(LayoutBox b, CameraView view, Layout l) {
  final p = b.body == null ? null : projectBody(b.body!, view);
  if (p == null) return b;
  final off = [
    p.left - b.left,
    p.top - b.top,
    p.right - b.right,
    p.bottom - b.bottom,
  ].any((d) => d.abs() > 2);
  if (!off) return b;
  final snapped = b.copyWith(
    left: p.left.round().clamp(0, l.width),
    top: p.top.round().clamp(0, l.height),
    right: p.right.round().clamp(0, l.width),
    bottom: p.bottom.round().clamp(0, l.height),
  );
  return snapped.offscreen ? b : snapped;
}

/// 还没有体块的块(文字块除外)都猜一个。
List<LayoutBox> liftMissing(Layout l) => [
  for (final b in l.boxes)
    b.body == null && b.label != 'text' ? liftBox(b, l) : b,
];

String _deg(double v) => '${v.round()}°';

/// 告诉 Agent 摄像机现在什么样(发给模型的话,不翻译)。
String describeCamera(Layout l, {required bool threeD}) {
  final c = l.camera;
  final view = threeD ? '用户开着 3D 视图,能转镜头、看到每块的体块' : '用户现在用平面视图';
  final shot = c.isDefault
      ? '镜头正对着画面,没转过。'
      : '镜头水平环绕 ${_deg(c.orbit)}(这是镜头相对地面、墙、桌沿这些场景走向转的角度,'
            '照透视线算出来的,不是人物的朝向:人物可以正对着这个镜头。'
            '每个人物朝哪看下面的【朝向】,不要从环绕角去推),'
            '俯仰 ${_deg(c.pitch)}(正数是俯视,负数是仰视),画面歪 ${_deg(c.roll)},'
            '视角 ${_deg(c.fov)},离主体 ${c.distance.toStringAsFixed(2)}(1 是原来的距离)'
            '${c.shift == 0 ? '' : ',移轴 ${c.shift.toStringAsFixed(2)}(镜头保持水平、底片上下平移,地平线不在正中,竖线依然竖直)'}。'
            'bbox 是从这个镜头拍到的样子,描述也要照这个视角写:从背后拍写背影、看不到脸,'
            '俯视写看得到头顶和地面,仰视写看得到下巴和天空,谁挡着谁照现在的前后。';
  final camView = CameraView(c, l.width, l.height);
  final facing = [
    for (final (i, b) in l.boxes.indexed)
      if (b.label == 'character' && b.body != null && !b.offscreen)
        '- ${b.name.isEmpty ? '第 ${i + 1} 块' : b.name}:${facingOf(b.body!, camView)}',
  ];
  return '【摄像机】$view。$shot'
      'items 里的 body 是每块的体块(相对这个镜头量的),写法见技能里的说明。'
      '${facing.isEmpty ? '' : '\n【朝向】人物相对这个镜头面朝哪边(按体块的 yaw 算),描述里的朝向照这里写:\n${facing.join('\n')}'}';
}

/// 一个体块的正面相对镜头朝哪边:面朝镜头、斜侧、侧身、背对(水平方向上算)。
String facingOf(Body b, CameraView view) {
  final r = b.yaw * math.pi / 180;
  final front = (x: -math.sin(r), z: -math.cos(r));
  final e = view.eye;
  final to = (x: e.x - b.x, z: e.z - b.z);
  final len = math.sqrt(to.x * to.x + to.z * to.z);
  if (len <= 0) return '面朝镜头';
  final cos = (front.x * to.x + front.z * to.z) / len;
  final a = math.acos(cos.clamp(-1.0, 1.0)) * 180 / math.pi;
  // 正面往镜头右边偏还是左边偏(画面上的左右)。
  final side = front.x * view.right.x + front.z * view.right.z > 0
      ? '画面右边'
      : '画面左边';
  return a < 25
      ? '面朝镜头,正面对着画面'
      : a < 65
      ? '身体斜向$side,四分之三侧面,脸和正面大半看得到'
      : a < 115
      ? '侧身,脸朝$side,看到的是侧脸'
      : a < 155
      ? '大半背对镜头,斜向$side'
      : '背对镜头,看到背影';
}

// ---- 透视线和镜头互相换算 ----

/// 消失点放到画布外这么远就算"在无穷远"(那个方向和画面平行)。
const _far = 50;

/// 眼下的地平线在画布的哪个 y:透视辅助线开着就用它的,镜头转过就照镜头算
/// (俯仰 p 时地平线在 cy − f·tan p);都没有是 null。
double? horizonOf(Layout l) {
  final per = l.perspective;
  if (per != null) return per.horizon.toDouble();
  if (l.camera.isDefault) return null;
  final view = CameraView(l.camera, l.width, l.height);
  return view.cy - view.f * math.tan(l.camera.pitch * math.pi / 180);
}

/// 站在地上的东西离镜头多远:底边离地平线越远越近(Hoiem 等,《Putting Objects in
/// Perspective》,CVPR 2006:地面上的物体,距离和底边到地平线的距离成反比)。
/// 底边贴着画布下边时算 0.75;底边在地平线上面(飞着、挂着的)时是 null,照图层猜。
double? _groundDistance(LayoutBox b, Layout l) {
  final h = horizonOf(l);
  if (h == null || h >= l.height) return null;
  final below = b.bottom - h;
  if (below < l.height * 0.02) return null;
  return (0.75 * (l.height - h) / below).clamp(0.3, 10.0);
}

double _dot(Vec3 a, Vec3 b) => a.x * b.x + a.y * b.y + a.z * b.z;

/// 世界里某个方向在画布上的消失点(像素);和画面平行的(在无穷远)放到 [_far] 倍远处。
({double u, double v}) _vanish(Vec3 d, CameraView view, int w, int h) {
  final x = _dot(d, view.right), y = _dot(d, view.down), z = _dot(d, view.fwd);
  final far = _far * math.max(w, h).toDouble();
  if (z.abs() < 1e-6) {
    final len = math.sqrt(x * x + y * y);
    return len < 1e-9
        ? (u: view.cx, v: view.cy)
        : (u: view.cx + x / len * far, v: view.cy + y / len * far);
  }
  // 一条线朝两头的消失点是同一个(x/z、y/z 不随方向反过来变)。
  return (
    u: (view.cx + view.f * x / z).clamp(view.cx - far, view.cx + far),
    v: (view.cy + view.f * y / z).clamp(view.cy - far, view.cy + far),
  );
}

/// 镜头对着画布时透视辅助线该在哪:地平线在俯仰定下的高度,消失点是世界的
/// 前后方向(一点透视)、再加左右方向(两点)、再加竖直方向(三点)投到画布上的点。
/// 3D 视图里透视线就是镜头本身,只能这样跟着镜头走(画面歪着时地平线照不歪算)。
// ponytail: 不管滚转;镜头歪着时地平线其实是斜的,Perspective 只能画水平的。
Perspective perspectiveFromCamera(Camera c, int w, int h, int points) {
  final view = CameraView(c.copyWith(roll: 0), w, h);
  final horizon = view.cy - view.f * math.tan(c.pitch * math.pi / 180);
  final depthVp = _vanish((x: 0, y: 0, z: 1), view, w, h);
  final sideVp = _vanish((x: 1, y: 0, z: 0), view, w, h);
  final upVp = _vanish((x: 0, y: 1, z: 0), view, w, h);
  return Perspective(
    horizon: horizon.round(),
    xs: List.unmodifiable([
      if (points >= 2) sideVp.u.round(),
      depthVp.u.round(),
    ]),
    third: points >= 3 ? (x: upVp.u.round(), y: upVp.v.round()) : null,
  );
}

/// 反过来,照透视辅助线定镜头(fSpy 的做法,单视图几何的标准结论):
/// - 一点、两点透视(没有竖直方向的消失点):竖线保持竖直,所以镜头不低头,用移轴
///   ([Camera.shift])把底片中心挪到地平线上;两个消失点互相垂直,定出焦距
///   f² = −(F₁ − P)·(F₂ − P)(P 是底片中心)。
/// - 三点透视:三个互相垂直方向的消失点围成的三角形,垂心就是底片中心;焦距同上,
///   俯仰 tan p = (P 的 y − 地平线)/f。
/// 前后方向的消失点离中心多远定环绕;哪个消失点算前后、哪个算左右、朝前还是朝后,
/// 挑和 [c] 现在的环绕最接近的那种,拖动时镜头不会一下转 90° 或 180°。
// ponytail: 底片中心只上下挪,不左右挪(竖直消失点不在正中时照正中算)。
Camera cameraFromPerspective(Perspective p, Camera c, int w, int h) {
  final cx = w / 2;
  final hz = p.horizon.toDouble();
  var f = CameraView(c, w, h).f;
  // 底片中心的 y:没有竖直消失点时就在地平线上(镜头水平)。
  var py = hz;
  final third = p.third;
  // 垂心法要两个水平消失点分在竖直消失点两边;有一个在无穷远时(正对前方低头、
  // 抬头,一个点在正中、另一个跑到很远)式子退化,改用下面的办法。
  final ortho =
      third != null &&
      p.xs.length == 2 &&
      (hz - third.y).abs() > 1 &&
      (third.x - p.xs[0]) * (third.x - p.xs[1]) < 0;
  if (ortho) {
    // 垂心:过竖直消失点的高是竖线 x = x3;再和过 F₁、垂直于 F₂F₃ 的高相交。
    final x3 = third.x.toDouble();
    py = hz + (x3 - p.xs[0]) * (x3 - p.xs[1]) / (hz - third.y);
  }
  if (p.xs.length == 2 && (third == null || ortho)) {
    final f2 = -((p.xs[0] - cx) * (p.xs[1] - cx) + (hz - py) * (hz - py));
    if (f2 > 1) f = math.sqrt(f2);
  }
  final double pitch;
  if (third != null && !ortho && (third.y - hz).abs() > 1) {
    // 退化时:地平线到竖直消失点的距离 = f(tan p + cot p) = 2f / sin 2p,
    // 和环绕无关;焦距用现在的。
    pitch = 0.5 * math.asin((2 * f / (third.y - hz)).clamp(-1.0, 1.0));
    py = hz + f * math.tan(pitch);
  } else {
    pitch = math.atan2(py - hz, f);
  }
  final cosP = math.cos(pitch);
  double deg(double r) => r * 180 / math.pi;
  // u 当成前后方向的消失点:u = cx − f·tan o / cos p。
  double asDepth(int u) => deg(math.atan(-(u - cx) * cosP / f));
  // u 当成左右方向的消失点:u = cx + f / (tan o · cos p)。
  double asSide(int u) => deg(math.atan2(f, (u - cx) * cosP));
  final base = [
    asDepth(p.xs.last),
    if (p.xs.length == 2) ...[
      asDepth(p.xs.first),
      asSide(p.xs.first),
      asSide(p.xs.last),
    ],
  ];
  // 朝前看和朝后看,消失点落在同一个地方:两种都算候选。
  final options = [
    for (final o in base) ...[wrapDegrees(o), wrapDegrees(o + 180)],
  ];
  double gap(double o) => wrapDegrees(o - c.orbit).abs();
  final orbit = options.reduce((a, b) => gap(a) <= gap(b) ? a : b);
  return c.copyWith(
    orbit: orbit,
    pitch: deg(pitch),
    roll: 0,
    fov: deg(2 * math.atan(math.max(w, h) / 2 / f)),
    shift: (py - h / 2) / h,
  );
}
