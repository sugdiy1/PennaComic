import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 区域控制画板上的透视辅助线(像 Photoshop 拉的透视线):一条地平线,
/// 地平线上一到两个消失点,三点透视再加一个竖直方向的消失点。
/// 坐标是左上角原点的画布像素,和框一样。只在 Penna 里用,交出去的 JSON 里没有它;
/// 发给模型时换成一段话([describe]),让它照这个透视写机位和每一块。
@immutable
class Perspective {
  const Perspective({required this.horizon, required this.xs, this.third});

  /// 一点(1)、两点(2)、三点(3)透视的默认样子:地平线在正中。
  factory Perspective.preset(int points, int width, int height) => Perspective(
    horizon: height ~/ 2,
    xs: points == 1 ? [width ~/ 2] : [0, width],
    third: points == 3 ? (x: width ~/ 2, y: 0) : null,
  );

  /// 地平线的 y。
  final int horizon;

  /// 地平线上各消失点的 x(一个或两个)。
  final List<int> xs;

  /// 竖直方向的第三个消失点(三点透视才有)。
  final ({int x, int y})? third;

  int get points => xs.length + (third == null ? 0 : 1);

  Perspective copyWith({
    int? horizon,
    List<int>? xs,
    ({int x, int y})? third,
  }) => Perspective(
    horizon: horizon ?? this.horizon,
    xs: List.unmodifiable(xs ?? this.xs),
    third: third ?? this.third,
  );

  /// 换画布尺寸时按比例跟着缩放。
  Perspective scaled(double sx, double sy) => Perspective(
    horizon: (horizon * sy).round(),
    xs: List.unmodifiable([for (final x in xs) (x * sx).round()]),
    third: third == null
        ? null
        : (x: (third!.x * sx).round(), y: (third!.y * sy).round()),
  );

  Map<String, Object> toJson() => {
    'horizon': horizon,
    'xs': xs,
    if (third != null) 'third': [third!.x, third!.y],
  };

  static Perspective? fromJson(Object? j) {
    if (j is! Map || j['horizon'] is! num || j['xs'] is! List) return null;
    final xs = [
      for (final x in j['xs'] as List)
        if (x is num) x.round(),
    ];
    if (xs.isEmpty || xs.length > 2) return null;
    final t = j['third'];
    return Perspective(
      horizon: (j['horizon'] as num).round(),
      xs: List.unmodifiable(xs),
      third: t is List && t.length == 2 && t[0] is num && t[1] is num
          ? (x: (t[0] as num).round(), y: (t[1] as num).round())
          : null,
    );
  }

  /// 写成 Agent 用的 `<perspective>` 里那份 JSON(画布像素,每个点是 [x, y]),
  /// 让它照着现在的数改。
  String get spec => jsonEncode({
    'vanishing': [
      for (final x in xs) [x, horizon],
    ],
    if (third != null) 'third': [third!.x, third!.y],
  });

  /// 说给模型听:几点透视、地平线和各消失点在画面哪里、这意味着什么机位。
  String describe(int width, int height) {
    String pct(int v, int side) => '${(v * 100 / side).round()}%';
    final h = horizon / height;
    final eye = h < 0.4
        ? '地平线偏高,镜头朝下看(俯视)'
        : h > 0.6
        ? '地平线偏低,镜头朝上看(仰视),人物和高的东西显得高大'
        : '地平线在中间附近,平视';
    final vps = [
      for (final (i, x) in xs.indexed)
        '${xs.length == 1 ? '消失点' : '消失点 ${i + 1}'}在 ($x, $horizon)'
            '(横向 ${pct(x, width)})',
    ];
    final t = third;
    final vertical = t == null
        ? ''
        : '第三个消失点在 (${t.x}, ${t.y})(横向 ${pct(t.x, width)}、纵向 ${pct(t.y, height)}),'
              '${t.y < horizon ? '竖直的线往上收拢,越高的地方越窄,是从下往上看的仰视' : '竖直的线往下收拢,是从上往下看的俯视'}。';
    return '【透视辅助】用户在画板上拉了透视线(坐标和 bbox 一样是画布像素,从左上角量):'
        '$points 点透视。地平线在 y=$horizon(纵向 ${pct(horizon, height)}),$eye。'
        '${vps.join(';')}。$vertical'
        '照这个透视写:summary.caption 写清机位高低、视角和透视的强弱;'
        '每一块的 caption 写它朝哪个消失点延伸、近大远小的方向,'
        '人物写清从这个视角看到的样子(仰视看得到下巴和下侧,俯视看得到头顶和肩)。'
        '框的位置和大小也要顺着透视:离消失点越近的东西越小。'
        '现在的写法是 <perspective>$spec</perspective>。';
  }
}

/// 消失点最远能放到画面外多远(画布边长的倍数):参考图里的消失点常在画面外。
const _minSides = -3.0, _maxSides = 4.0;

/// 读 Agent 写的 `<perspective>` 里的内容,放到 [width]×[height] 的画布上。
/// `off` 是关掉([off] 为真);否则是 JSON,坐标和 bbox 一样是画布像素(从左上角量,
/// 可以小于 0 或大于宽高,表示在画面外),每个点写成 [x, y]:
/// `{"vanishing": [[120, 750], [790, 750]], "third": [416, -480]}`。
/// 地平线是 vanishing 那几个点的高度(写得不一样高就取平均)。
/// 也认只有一个点的 `"vanishing": [416, 600]`,和带 horizon 的
/// `{"horizon": 750, "vanishing": [120, 790]}`(vanishing 是地平线上各点的 x)。
/// 读不了返回 null。
({bool off, Perspective? value})? parsePerspective(
  String spec,
  int width,
  int height,
) {
  final text = spec.trim();
  if (text.toLowerCase() == 'off') return (off: true, value: null);
  final Object? j;
  try {
    j = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (j is! Map || j['vanishing'] is! List) return null;
  int px(num v, int side) =>
      v.toDouble().clamp(_minSides * side, _maxSides * side).round();
  ({int x, int y})? point(Object? p) =>
      p is List && p.length == 2 && p[0] is num && p[1] is num
      ? (x: px(p[0] as num, width), y: px(p[1] as num, height))
      : null;
  final list = j['vanishing'] as List;
  final h = j['horizon'];
  final List<({int x, int y})> points;
  if (list.isNotEmpty && list.every((v) => v is num)) {
    // 一串数:带 horizon 是地平线上各点的 x,不带是一个点的 [x, y]。
    points = h is num
        ? [for (final x in list) (x: px(x as num, width), y: px(h, height))]
        : [?point(list)];
  } else {
    points = [for (final p in list) ?point(p)];
  }
  if (points.isEmpty || points.length > 2) return null;
  final horizon =
      points.map((p) => p.y).reduce((a, b) => a + b) ~/ points.length;
  return (
    off: false,
    value: Perspective(
      horizon: horizon,
      xs: List.unmodifiable([for (final p in points) p.x]),
      third: point(j['third']),
    ),
  );
}

final _tag = RegExp(r'<perspective>([\s\S]*?)</perspective>');
const _open = '<perspective>';

/// 把回复里的 `<perspective>` 拆出来(有好几个时取最后一个):[spec] 是里面的内容,
/// [prose] 是去掉它之后给人看的话;还没写完的那一个先不显示,[spec] 为 null。
({String prose, String? spec}) splitPerspective(String reply) {
  final done = _tag.allMatches(reply).lastOrNull;
  var prose = reply.replaceAll(_tag, '');
  var spec = done?[1]!.trim();
  final half = prose.indexOf(_open);
  if (half >= 0) {
    prose = prose.substring(0, half);
    spec = null;
  } else {
    // 开始标签只到了一半(流式生成中)。
    for (var n = _open.length - 1; n > 1; n--) {
      if (prose.endsWith(_open.substring(0, n))) {
        prose = prose.substring(0, prose.length - n);
        break;
      }
    }
  }
  return (prose: prose.trim(), spec: spec);
}

/// 发给模型的旧回复里,整个 `<perspective>…</perspective>` 换成一句不带标签的话
/// (同 `forgetLayouts`):用户之后可能拖过消失点,现在的样子只看【透视辅助】。
String forgetPerspectives(String reply) =>
    reply.replaceAll(_tag, '(这里调过一次透视,已放到画板上,内容省略;现在的样子看【透视辅助】)');
