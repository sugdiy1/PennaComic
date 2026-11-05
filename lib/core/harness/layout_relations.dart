import 'dart:math' as math;

import 'layout.dart';

/// 程序按框算出来的位置关系,发给 Agent 前接在【布局画板】后面(发给模型的话,不翻译)。
/// MOSS-Image 看不到图层,前后遮挡只能靠描述写出来;模型自己看坐标常漏掉谁压着谁、
/// 谁贴着画面的边被裁掉,出图时位置关系就乱了。所以这里替它算好,让它照着写进描述。
///
/// 写三样:每块在画面的哪里、占多大、贴着哪条边;两块重叠时谁在前、挡住后面那块的
/// 哪一部分、挡住多少;一块整个落在另一块里面。转到镜头外的块不算。
String layoutRelations(Layout l) {
  final shown = [
    for (final (i, b) in l.boxes.indexed)
      if (!b.offscreen) (i, b),
  ];
  if (shown.isEmpty) return '';
  final lines = <String>[
    for (final (i, b) in shown) '- ${_name(b, i)}:${_where(b, l)}',
  ];
  // boxes 从前往后排,所以一对里序号小的在前面。
  for (var x = 0; x < shown.length; x++) {
    for (var y = x + 1; y < shown.length; y++) {
      final line = _overlap(shown[x], shown[y]);
      if (line != null) lines.add('- $line');
    }
  }
  return '【位置关系】程序按框算的,写布局和描述时照这个把位置、前后遮挡写清楚'
      '(MOSS-Image 看不到图层,只能从描述里知道谁在前、谁挡着谁):\n'
      '${lines.join('\n')}\n'
      '要求:summary.caption 把上面每一处遮挡都写出来;重叠的两块,各自的 caption 里也要写'
      '(前面那块写它挡在谁前面、压住对方哪部分,后面那块写哪部分被谁挡住、露出哪部分);'
      '贴着画面边、被裁掉的写 "cropped by the bottom edge" 这类话;每块的 caption 写上它在画面的位置'
      '("in the upper left of the frame")。$_shotRule改了框或前后,这些关系跟着变,照新的写。';
}

String _name(LayoutBox b, int i) =>
    '「${b.name.trim().isEmpty ? '第 ${i + 1} 块' : b.name.trim()}」';

/// 一块在画面的哪里(按中心落在九宫格的哪一格)、占多大、贴着哪条边。
String _where(LayoutBox b, Layout l) {
  final cx = (b.left + b.right) / 2 / l.width;
  final cy = (b.top + b.bottom) / 2 / l.height;
  final area = b.width * b.height * 100 / (l.width * l.height);
  final edges = [
    if (b.top <= l.height * 0.01) '上边',
    if (b.bottom >= l.height * 0.99) '下边',
    if (b.left <= l.width * 0.01) '左边',
    if (b.right >= l.width * 0.99) '右边',
  ];
  final across = b.width >= l.width * 0.9 ? ',横贯整个宽度' : '';
  return '画面${_cell(cx, cy)},占画面 ${area.round()}%$across${_shot(b, l)}'
      '${edges.isEmpty ? '' : ',贴着画面${edges.join('、')}(超出的部分被裁掉)'}';
}

/// 人物块的景别,按框占画面多高算。MOSS-Image 读描述时爱把主角画成占满画面的特写,
/// 框再小也一样(用户反馈:3D 里人只占四成高,出图成了大半身近景),所以要直说多大。
String _shot(LayoutBox b, Layout l) {
  if (b.label != 'character') return '';
  final h = (b.height * 100 / l.height).round();
  final cropped = b.top <= l.height * 0.01 || b.bottom >= l.height * 0.99;
  final scale = cropped && h >= 60
      ? '近景,人物被画面边裁掉一部分(medium / close shot)'
      : h < 30
      ? '远景,人物很小、四周是大片场景(long shot, small figure)'
      : h < 70
      ? '全景,全身完整、四周留出不少场景(full shot)'
      : '全身几乎撑满画面高度(full-body shot filling the frame)';
  return ',高约画面的 $h%,$scale';
}

/// 两种位置关系末尾都加的一条:景别要写进描述。
const _shotRule =
    '人物照上面的景别写,并写明大约占画面多高'
    '("a full shot, she fills only about 40% of the frame height, surrounded by wide empty street"),'
    '框小的不要写成特写、近景或大半身,也不要用 close-up、portrait 这类词,'
    '否则出图时人会被放大到占满画面。';

/// 按 0–1 的位置说在画面哪一格:左上、上方居中、正中……
String _cell(double x, double y) {
  final (h, v) = _thirds(x, y);
  if (h.isEmpty && v.isEmpty) return '正中';
  if (h.isEmpty) return '$v方居中';
  if (v.isEmpty) return '$h侧居中';
  return '$h$v';
}

/// 按 0–1 的位置说是一块里的哪一部分:左上部、上部、中间……
String _part(double x, double y) {
  final (h, v) = _thirds(x, y);
  if (h.isEmpty && v.isEmpty) return '中间';
  return '$h$v部';
}

(String, String) _thirds(double x, double y) => (
  x < 1 / 3 ? '左' : (x > 2 / 3 ? '右' : ''),
  y < 1 / 3 ? '上' : (y > 2 / 3 ? '下' : ''),
);

/// [inner] 的中心在 [outer] 里的位置(0–1)。
(double, double) _inside(
  int left,
  int top,
  int right,
  int bottom,
  LayoutBox outer,
) => (
  ((left + right) / 2 - outer.left) / outer.width,
  ((top + bottom) / 2 - outer.top) / outer.height,
);

/// 两块重叠时的一句话;不重叠或重叠很少(不到小的那块的 2%)时是 null。
/// [front] 在前面([LayoutBox] 按从前到后排)。
String? _overlap((int, LayoutBox) front, (int, LayoutBox) back) {
  final (fi, f) = front;
  final (bi, b) = back;
  final left = f.left > b.left ? f.left : b.left;
  final right = f.right < b.right ? f.right : b.right;
  final top = f.top > b.top ? f.top : b.top;
  final bottom = f.bottom < b.bottom ? f.bottom : b.bottom;
  if (right <= left || bottom <= top) return null;
  final shared = (right - left) * (bottom - top);
  final smaller = [
    f.width * f.height,
    b.width * b.height,
  ].reduce((a, c) => a < c ? a : c);
  if (shared < smaller * 0.02) return null;
  final a = _name(f, fi), c = _name(b, bi);
  final (x, y) = _inside(left, top, right, bottom, b);
  if (left == f.left &&
      right == f.right &&
      top == f.top &&
      bottom == f.bottom) {
    return '$a整个落在$c的范围里、在它前面,压在$c的${_part(x, y)}';
  }
  final covered = shared * 100 / (b.width * b.height);
  final part = _part(x, y);
  return covered >= 90
      ? '$a在$c前面,几乎整个挡住了它(${covered.round()}%):'
            '要么换前后,要么描述里写清$c从哪里露出来'
      : '$a在$c前面,挡住$c的$part约 ${covered.round()}%';
}

// ---- 3D 视图开着时 ----

typedef _P = ({double x, double y});

/// 3D 视图开着时的位置关系:用户在 3D 视图里摆好的镜头就是要画的画面,所以按
/// 3D 场景算,不按 2D 的框和图层名:有体块的按离镜头远近排,遮挡按体块投到画面上的
/// 实际轮廓(8 个角围成的凸多边形)算——轮廓叠在一起才算挡住,近的挡远的;
/// 再写每样东西从这个镜头看得到哪几面。文字块不在场景里,贴在画面最上层,单说。
/// (用户反馈:3D 里摆的构图和 2D 的框对不上,Agent 按框写出来的关系是 2D 的。)
String sceneRelations(Layout l) {
  final view = CameraView(l.camera, l.width, l.height);
  final solids = <({int i, LayoutBox b, List<_P> hull, double z})>[];
  final flats = <(int, LayoutBox)>[];
  for (final (i, b) in l.boxes.indexed) {
    if (b.offscreen) continue;
    final body = b.body;
    final pts = body == null || b.label == 'text'
        ? null
        : [for (final c in body.corners) view.project(c)];
    if (pts == null || pts.contains(null)) {
      flats.add((i, b));
      continue;
    }
    solids.add((
      i: i,
      b: b,
      hull: _hull([for (final p in pts) (x: p!.u, y: p.v)]),
      z: view.toCamera(body!.center).z,
    ));
  }
  if (solids.isEmpty && flats.isEmpty) return '';
  solids.sort((a, c) => a.z.compareTo(c.z));
  final lines = <String>[
    for (final (k, s) in solids.indexed)
      '- ${_name(s.b, s.i)}:离镜头第 ${k + 1} 近(${s.z.toStringAsFixed(2)}),'
          '${_where(s.b, l)};${_faces(s.b.body!, view)}',
    for (final (i, b) in flats)
      '- ${_name(b, i)}:${b.label == 'text' ? '文字' : '平面'},贴在画面最上层、'
          '不在 3D 场景里,${_where(b, l)}',
  ];
  for (var x = 0; x < solids.length; x++) {
    for (var y = x + 1; y < solids.length; y++) {
      final near = solids[x], far = solids[y];
      final shared = _clip(far.hull, near.hull);
      final area = _area(shared), farArea = _area(far.hull);
      final smaller = [
        _area(near.hull),
        farArea,
      ].reduce((a, c) => a < c ? a : c);
      if (area < smaller * 0.02 || farArea <= 0) continue;
      final covered = area * 100 / farArea;
      lines.add(
        '- ${_name(near.b, near.i)}离镜头更近,挡住${_name(far.b, far.i)}的'
        '${_partOf(shared, far.b)}约 ${covered.round()}%',
      );
    }
  }
  for (final (i, t) in flats) {
    final rect = <_P>[
      (x: t.left.toDouble(), y: t.top.toDouble()),
      (x: t.right.toDouble(), y: t.top.toDouble()),
      (x: t.right.toDouble(), y: t.bottom.toDouble()),
      (x: t.left.toDouble(), y: t.bottom.toDouble()),
    ];
    for (final s in solids) {
      final shared = _clip(s.hull, _hull(rect));
      if (_area(shared) < _area(s.hull) * 0.02) continue;
      lines.add(
        '- ${_name(t, i)}压在${_name(s.b, s.i)}的${_partOf(shared, s.b)}上面',
      );
    }
  }
  return '【位置关系 · 3D 构图】用户在 3D 视图里摆好了镜头和每样东西,'
      '下面就是要画的画面:从这个镜头看出去的样子,前后按离镜头的远近、遮挡按实际挡住的部分算。'
      '写布局和描述照这个写,不要按正面平视写,也不要按图层名去猜前后:\n'
      '${lines.join('\n')}\n'
      '要求:summary.caption 交代镜头(机位高低、俯仰、从哪一侧拍)和上面每一处遮挡;'
      '每块的 caption 写它在画面的位置、从这个镜头看得到它的哪几面'
      '("seen from above, showing the top of the suitcase"、"seen from behind")、'
      '挡在谁前面或被谁挡住哪部分;文字压在什么上面也写清;贴着画面边的写被裁掉。$_shotRule';
}

/// 从镜头看得到这个体块的哪几面。
String _faces(Body b, CameraView view) {
  final r = b.yaw * math.pi / 180;
  final s = math.sin(r), c = math.cos(r);
  final e = view.eye;
  final to = (x: e.x - b.x, y: e.y - b.y, z: e.z - b.z);
  final len = math.sqrt(to.x * to.x + to.y * to.y + to.z * to.z);
  if (len <= 0) return '';
  double facing(double nx, double ny, double nz) =>
      (nx * to.x + ny * to.y + nz * to.z) / len;
  const seen = 0.15;
  final faces = [
    if (facing(-s, 0, -c) > seen) '正面',
    if (facing(s, 0, c) > seen) '背面',
    if (facing(c, 0, -s).abs() > seen) '侧面',
    if (facing(0, -1, 0) > seen) '顶面',
    if (facing(0, 1, 0) > seen) '底面',
  ];
  return faces.isEmpty ? '' : '看得到它的${faces.join('、')}';
}

/// [shared] 那一片落在 [b] 的哪一部分(按它的中心在 [b] 的框里的位置)。
String _partOf(List<_P> shared, LayoutBox b) {
  var x = 0.0, y = 0.0;
  for (final p in shared) {
    x += p.x;
    y += p.y;
  }
  final n = shared.isEmpty ? 1 : shared.length;
  return _part(
    b.width <= 0 ? 0.5 : (x / n - b.left) / b.width,
    b.height <= 0 ? 0.5 : (y / n - b.top) / b.height,
  );
}

double _cross(_P o, _P a, _P b) =>
    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

/// 一堆点的凸包(按 cross 为正的方向绕一圈)。
List<_P> _hull(List<_P> pts) {
  final p = [...pts]
    ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  if (p.length < 3) return p;
  List<_P> half(Iterable<_P> seq) {
    final h = <_P>[];
    for (final q in seq) {
      while (h.length >= 2 && _cross(h[h.length - 2], h.last, q) <= 0) {
        h.removeLast();
      }
      h.add(q);
    }
    return h..removeLast();
  }

  return [...half(p), ...half(p.reversed)];
}

/// 凸多边形 [subject] 被凸多边形 [window] 裁剩下的部分(Sutherland–Hodgman)。
List<_P> _clip(List<_P> subject, List<_P> window) {
  var out = subject;
  for (var k = 0; k < window.length && out.isNotEmpty; k++) {
    final a = window[k], b = window[(k + 1) % window.length];
    bool inside(_P p) => _cross(a, b, p) >= 0;
    _P cut(_P p, _P q) {
      final t = _cross(a, b, p) / (_cross(a, b, p) - _cross(a, b, q));
      return (x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t);
    }

    final input = out;
    out = [];
    for (var i = 0; i < input.length; i++) {
      final p = input[i], q = input[(i + 1) % input.length];
      if (inside(q)) {
        if (!inside(p)) out.add(cut(p, q));
        out.add(q);
      } else if (inside(p)) {
        out.add(cut(p, q));
      }
    }
  }
  return out;
}

/// 多边形的面积。
double _area(List<_P> poly) {
  var s = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i], b = poly[(i + 1) % poly.length];
    s += a.x * b.y - b.x * a.y;
  }
  return s.abs() / 2;
}
