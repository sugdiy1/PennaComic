import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'camera.dart';

part 'lighting_data.dart';
part 'lighting_phrase.dart';

/// 打光辅助:几盏灯(主光、补光、轮廓光……)加环境光和氛围,本质是一句光影提示词,
/// 交出去时接在 summary.caption 后面;灯光球、手柄只是方便用户和 Agent 看。
/// 照 MOSS Prompt Studio 的 lighting-kit 移植(数据、算法、短语逐字一致,单测用它的样例校验);
/// lighting-kit 由朋友韶韵提供。
///
/// 方向:azimuth 是水平方位(0 = 从初始机位一侧照向主体,正 = 画面右侧,±180 = 背后),
/// elevation 是高度角(正 = 从上往下照)。存的是世界方位(固定在场景里);
/// [Lighting.follow] 为真时存的是相对镜头的方位(灯跟着镜头转)。
/// lighting-kit 的环绕角和 Penna 的 [Camera.orbit] 方向相反(Penna 90 是从左侧拍),
/// 换算只在 [_camOrbit] 一处。

const lightRoles = ['key', 'fill', 'rim', 'bg', 'practical'];
const maxLights = 8, maxLightNote = 400;

final _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

/// 一盏灯。[kelvin] 为 null 时用 [color](彩色灯),否则 [color] 由色温算出。
/// [intensity] 0–2(1 正常),[softness] 0 硬光到 1 柔光。
@immutable
class Light {
  const Light({
    required this.id,
    this.role = 'key',
    this.enabled = true,
    this.azimuth = 0,
    this.elevation = 30,
    this.intensity = 1,
    this.kelvin = 5600,
    this.color = '#ffffff',
    this.softness = 0.5,
  });

  final String id, role, color;
  final bool enabled;
  final double azimuth, elevation, intensity, softness;
  final int? kelvin;

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role,
    'enabled': enabled,
    'azimuth': azimuth,
    'elevation': elevation,
    'intensity': intensity,
    'kelvin': kelvin,
    'color': color,
    'softness': softness,
  };

  /// 清洗一盏灯:缺的补默认值,超范围的夹回来;第 0 盏默认主光,其余默认补光。
  static Light fromJson(Object? raw, [int i = 0]) {
    final l = raw is Map ? raw : const {};
    final role = lightRoles.contains(l['role'])
        ? l['role'] as String
        : i == 0
        ? 'key'
        : 'fill';
    final hex = l['color'] is String && _hex.hasMatch(l['color'] as String)
        ? (l['color'] as String).toLowerCase()
        : null;
    final k = l['kelvin'];
    final int? kelvin = l.containsKey('kelvin') && k == null
        ? null
        : k is num && k.isFinite
        ? _jsRound(_clamp(k.toDouble(), 1000, 20000)).toInt()
        : hex != null
        ? null
        : 5600;
    final id = l['id'];
    return Light(
      id: id is String && id.isNotEmpty ? id : newLightId(),
      role: role,
      enabled: l['enabled'] != false,
      azimuth: _r1(_wrap(_num(l['azimuth'], 0))),
      elevation: _r1(_clamp(_num(l['elevation'], 30), -89, 89)),
      intensity: _r2(_clamp(_num(l['intensity'], 1), 0, 2)),
      kelvin: kelvin,
      color: kelvin != null ? kelvinHex(kelvin) : hex ?? '#ffffff',
      softness: _r2(_clamp(_num(l['softness'], 0.5), 0, 1)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Light && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// 一整套灯光。[preset] 是套用的预设 id(手动改了灯就清空,算自定义);
/// [ambient] 环境光 0–1;[extras] 是氛围效果的 id(体积光、薄雾……);[note] 原样追加。
@immutable
class Lighting {
  const Lighting({
    this.enabled = false,
    this.preset = '',
    this.lights = const [],
    this.ambient = 0.35,
    this.ambientKelvin = 6500,
    this.extras = const [],
    this.note = '',
    this.follow = false,
  });

  final bool enabled, follow;
  final String preset, note;
  final List<Light> lights;
  final double ambient;
  final int ambientKelvin;
  final List<String> extras;

  /// 开着、亮度不接近 0 的灯。
  List<Light> get active => [
    for (final l in lights)
      if (l.enabled && l.intensity > 0.02) l,
  ];

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'preset': preset,
    'lights': [for (final l in lights) l.toJson()],
    'ambient': ambient,
    'ambient_kelvin': ambientKelvin,
    'extras': extras,
    'note': note,
    'follow': follow,
  };

  /// 清洗整套灯光(存档、Agent 写的都先过这里):最多 [maxLights] 盏,id 去重。
  static Lighting fromJson(Object? raw) {
    if (raw is! Map) return const Lighting();
    final lights = <Light>[];
    for (final (i, l)
        in (raw['lights'] is List ? raw['lights'] as List : [])
            .take(maxLights)
            .indexed) {
      var n = Light.fromJson(l, i);
      while (lights.any((x) => x.id == n.id)) {
        n = Light.fromJson({...n.toJson(), 'id': newLightId()}, i);
      }
      lights.add(n);
    }
    final extras = <String>[];
    for (final e in raw['extras'] is List ? raw['extras'] as List : []) {
      if (e is String && _extraById.containsKey(e) && !extras.contains(e)) {
        extras.add(e);
      }
    }
    final note = raw['note'] is String ? raw['note'] as String : '';
    return Lighting(
      enabled: raw['enabled'] == true,
      preset: _presetById.containsKey(raw['preset'])
          ? raw['preset'] as String
          : '',
      lights: List.unmodifiable(lights),
      ambient: _r2(_clamp(_num(raw['ambient'], 0.35), 0, 1)),
      ambientKelvin: _jsRound(
        _clamp(_num(raw['ambient_kelvin'], 6500), 1000, 20000),
      ).toInt(),
      extras: List.unmodifiable(extras),
      note: note.length > maxLightNote ? note.substring(0, maxLightNote) : note,
      follow: raw['follow'] == true,
    );
  }

  /// 合并几个字段(JSON 的键)再清洗一遍,返回新的一份。
  Lighting patch(Map<String, Object?> fields) =>
      Lighting.fromJson({...toJson(), ...fields});

  @override
  bool operator ==(Object other) =>
      other is Lighting && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

var _seq = 0;
final _rand = math.Random();
String newLightId() =>
    'l${_rand.nextInt(1 << 20).toRadixString(36)}${(_seq++).toRadixString(36)}';

// ---------- 小工具(照 lighting-kit 的 math.ts,取整按 JS 的 Math.round) ----------

double _jsRound(double v) => (v + 0.5).floorToDouble();
double _r1(double v) => _jsRound(v * 10) / 10;
double _r2(double v) => _jsRound(v * 100) / 100;
double _clamp(double v, double lo, double hi) => math.max(lo, math.min(hi, v));
double _num(Object? v, double d) => v is num && v.isFinite ? v.toDouble() : d;
double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

/// 角度折回 [-180, 180)。
double _wrap(double d) => (d + 180) % 360 - 180;

/// 镜头在 lighting-kit 里的环绕角:和 Penna 的方向相反。没有镜头当作 0。
double _camOrbit(Camera? cam) => cam == null ? 0 : -cam.orbit;

typedef _V3 = (double, double, double);
double _dot(_V3 a, _V3 b) => a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3;
_V3 _cross(_V3 a, _V3 b) => (
  a.$2 * b.$3 - a.$3 * b.$2,
  a.$3 * b.$1 - a.$1 * b.$3,
  a.$1 * b.$2 - a.$2 * b.$1,
);
_V3 _norm(_V3 a) {
  final l = math.sqrt(_dot(a, a));
  final d = l == 0 ? 1 : l;
  return (a.$1 / d, a.$2 / d, a.$3 / d);
}

// ---------- 编辑(都返回新对象) ----------

/// 套用预设:预设的方位相对当前镜头;保留 follow 和 note。认 id、中文名、英文名。
Lighting presetLighting(String id, Camera? cam, [Lighting? cur]) {
  final p = findPreset(id);
  final base = cur ?? const Lighting();
  if (p == null) return base;
  final o = base.follow ? 0 : _camOrbit(cam);
  return base.patch({
    'enabled': true,
    'preset': p.id,
    'ambient': p.ambient,
    'ambient_kelvin': p.ambientKelvin,
    'extras': p.extras,
    'lights': [
      for (final l in p.lights)
        {...l.toJson(), 'id': newLightId(), 'azimuth': _wrap(l.azimuth + o)},
    ],
  });
}

const _newLightDefaults = {
  'key': (
    azimuth: -40.0,
    elevation: 35.0,
    intensity: 1.0,
    kelvin: 5200,
    softness: 0.5,
  ),
  'fill': (
    azimuth: 45.0,
    elevation: 10.0,
    intensity: 0.35,
    kelvin: 5600,
    softness: 0.85,
  ),
  'rim': (
    azimuth: 150.0,
    elevation: 30.0,
    intensity: 0.7,
    kelvin: 6500,
    softness: 0.3,
  ),
  'bg': (
    azimuth: 180.0,
    elevation: 5.0,
    intensity: 0.6,
    kelvin: 6000,
    softness: 0.9,
  ),
  'practical': (
    azimuth: 35.0,
    elevation: 0.0,
    intensity: 0.7,
    kelvin: 2700,
    softness: 0.6,
  ),
};

/// 加一盏 [role] 的灯(方位相对当前镜头);满了 [maxLights] 盏不加。
Lighting addLight(Lighting lg, String role, Camera? cam) {
  if (lg.lights.length >= maxLights) return lg;
  final x = _newLightDefaults[role] ?? _newLightDefaults['fill']!;
  final o = lg.follow ? 0 : _camOrbit(cam);
  return lg.patch({
    'enabled': true,
    'preset': '',
    'lights': [
      ...lg.lights.map((l) => l.toJson()),
      {
        'role': role,
        'azimuth': _wrap(x.azimuth + o),
        'elevation': x.elevation,
        'intensity': x.intensity,
        'kelvin': x.kelvin,
        'softness': x.softness,
      },
    ],
  });
}

/// 改一盏灯([fields] 是 JSON 的键);手动改过就不再算某个预设。
Lighting updateLight(Lighting lg, String id, Map<String, Object?> fields) =>
    lg.patch({
      'preset': '',
      'lights': [
        for (final l in lg.lights)
          l.id == id ? {...l.toJson(), ...fields, 'id': id} : l.toJson(),
      ],
    });

Lighting removeLight(Lighting lg, String id) => lg.patch({
  'preset': '',
  'lights': [
    for (final l in lg.lights)
      if (l.id != id) l.toJson(),
  ],
});

Lighting toggleExtra(Lighting lg, String id) => lg.patch({
  'extras': lg.extras.contains(id)
      ? [
          for (final e in lg.extras)
            if (e != id) e,
        ]
      : [...lg.extras, id],
});

/// 打开灯光:还没有灯时先套「自然光」,免得打开了却什么都没有。
Lighting enableLighting(Lighting lg, bool on, Camera? cam) =>
    on && lg.lights.isEmpty
    ? presetLighting('natural', cam, lg)
    : lg.patch({'enabled': on});

/// 切换「灯光跟随镜头」:画面里的光向不变,换算存的方位。
Lighting setFollow(Lighting lg, bool follow, Camera? cam) {
  if (lg.follow == follow) return lg;
  final k = follow ? -_camOrbit(cam) : _camOrbit(cam);
  return lg.patch({
    'follow': follow,
    'lights': [
      for (final l in lg.lights)
        {...l.toJson(), 'azimuth': _wrap(l.azimuth + k)},
    ],
  });
}

// ---------- 方向 ----------

/// 镜头的右、下、指向镜头三个方向(世界坐标,y 朝下)。和 [CameraView] 的一致。
({_V3 right, _V3 down, _V3 toCam}) _camBasis(Camera? cam) {
  final o = _rad(_camOrbit(cam));
  final p = _rad(_clamp(cam?.pitch ?? 0, -85, 85));
  final rr = _rad(cam?.roll ?? 0);
  final dir = (
    math.sin(o) * math.cos(p),
    -math.sin(p),
    -math.cos(o) * math.cos(p),
  );
  final fwd = (-dir.$1, -dir.$2, -dir.$3);
  final right0 = _norm(_cross(fwd, (0, -1, 0)));
  final down0 = _cross(fwd, right0);
  final c = math.cos(rr), s = math.sin(rr);
  return (
    right: (
      right0.$1 * c + down0.$1 * s,
      right0.$2 * c + down0.$2 * s,
      right0.$3 * c + down0.$3 * s,
    ),
    down: (
      down0.$1 * c - right0.$1 * s,
      down0.$2 * c - right0.$2 * s,
      down0.$3 * c - right0.$3 * s,
    ),
    toCam: dir,
  );
}

double _worldAzimuth(Light l, Lighting lg, Camera? cam) =>
    _wrap(l.azimuth + (lg.follow ? _camOrbit(cam) : 0));

/// 方位、高度 → 从主体指向灯的单位向量。
_V3 _lightVec(double az, double el) {
  final a = _rad(az), e = _rad(el);
  return (math.sin(a) * math.cos(e), -math.sin(e), -math.cos(a) * math.cos(e));
}

/// 灯相对镜头的方向。[h] 是画面里的水平角(0 正面,负左正右,±180 背后),
/// [v] 是灯的高度角;side / up / front 是镜头坐标里的分量(灯光球用,front 朝镜头)。
typedef RelDir = ({double h, double v, double side, double up, double front});

RelDir relDir(Light l, Lighting lg, Camera? cam) {
  final b = _camBasis(cam);
  final az = _worldAzimuth(l, lg, cam);
  final v = _lightVec(az, l.elevation);
  return (
    h: _wrap(az - _camOrbit(cam)),
    v: l.elevation,
    side: _dot(v, b.right),
    up: -_dot(v, b.down),
    front: _dot(v, b.toCam),
  );
}

/// 灯光球上拖出来的相对镜头方向 → 存的方位、高度。
({double azimuth, double elevation}) fromRel(
  double side,
  double up,
  double front,
  Lighting lg,
  Camera? cam,
) {
  final b = _camBasis(cam);
  final v = _norm((
    b.right.$1 * side - b.down.$1 * up + b.toCam.$1 * front,
    b.right.$2 * side - b.down.$2 * up + b.toCam.$2 * front,
    b.right.$3 * side - b.down.$3 * up + b.toCam.$3 * front,
  ));
  final az = _r1(_wrap(_deg(math.atan2(v.$1, -v.$3))));
  return (
    azimuth: _r1(_wrap(az - (lg.follow ? _camOrbit(cam) : 0))),
    elevation: _r1(_clamp(_deg(math.asin(_clamp(-v.$2, -1, 1))), -89, 89)),
  );
}

/// 相对镜头的水平角 [h](Agent 写的、滑杆上的)→ 存的方位。
double toStoredAzimuth(double h, Lighting lg, Camera? cam) =>
    _r1(_wrap(h + (lg.follow ? 0 : _camOrbit(cam))));

/// 灯光球拖拽:球面上的点(x 右、y 上,半径 1)→ 相对镜头的方向。
/// [frontSign] 是按下时灯在正面(1)还是背面(-1);拖出球边(半径 1–2 的环)就翻到另一面。
({double side, double up, double front}) ballPointToRel(
  double x,
  double y,
  int frontSign,
) {
  final rr = math.sqrt(x * x + y * y);
  if (rr <= 1) {
    return (
      side: x,
      up: y,
      front: frontSign * math.sqrt(math.max(0, 1 - rr * rr)),
    );
  }
  final back = math.max(0.0, 2 - rr);
  return (
    side: x / rr * back,
    up: y / rr * back,
    front: -frontSign * math.sqrt(math.max(0, 1 - back * back)),
  );
}

/// 方向说成人话:「左前方高处(约 40°)」/ "the front left, high above (about 40 degrees)"。
String directionText(double h, double v, {required bool zh}) {
  if (v >= 65) return zh ? '正上方' : 'directly overhead';
  if (v <= -65) return zh ? '正下方' : 'directly below';
  final ah = h.abs();
  final left = h < 0;
  final horiz = ah <= 20
      ? (zh ? '正前方' : 'the front')
      : ah <= 65
      ? (zh
            ? (left ? '左前方' : '右前方')
            : left
            ? 'the front left'
            : 'the front right')
      : ah <= 115
      ? (zh
            ? (left ? '左侧' : '右侧')
            : left
            ? 'the left side'
            : 'the right side')
      : ah <= 160
      ? (zh
            ? (left ? '左后方' : '右后方')
            : left
            ? 'behind on the left'
            : 'behind on the right')
      : zh
      ? '正后方'
      : 'directly behind';
  final d = (v.abs() / 5 + 0.5).floor() * 5;
  final vert = v >= 30
      ? (zh ? '高处（约 $d°）' : 'high above (about $d degrees)')
      : v >= 10
      ? (zh ? '略高处' : 'slightly above')
      : v > -10
      ? (zh ? '平视高度' : 'at eye level')
      : zh
      ? '低处（约 $d°，由下往上）'
      : 'from below (about $d degrees)';
  return zh ? horiz + vert : '$horiz, $vert';
}

// ---------- 颜色 ----------

typedef Rgb = (double, double, double);

/// 色温(K)→ 0–1 的 RGB(Tanner Helland 的近似公式)。
Rgb kelvinRgb(num k) {
  final t = _clamp(k.toDouble(), 1000, 40000) / 100;
  final r = t <= 66 ? 255.0 : 329.698727446 * math.pow(t - 60, -0.1332047592);
  final g = t <= 66
      ? 99.4708025861 * math.log(t) - 161.1195681661
      : 288.1221695283 * math.pow(t - 60, -0.0755148492);
  final b = t >= 66
      ? 255.0
      : t <= 19
      ? 0.0
      : 138.5177312231 * math.log(t - 10) - 305.0447927307;
  return (
    _clamp(r, 0, 255) / 255,
    _clamp(g, 0, 255) / 255,
    _clamp(b, 0, 255) / 255,
  );
}

Rgb hexRgb(String h) {
  final m = _hex.hasMatch(h) ? h : '#ffffff';
  int at(int i) => int.parse(m.substring(i, i + 2), radix: 16);
  return (at(1) / 255, at(3) / 255, at(5) / 255);
}

String rgbHex(Rgb c) =>
    '#${[c.$1, c.$2, c.$3].map((v) => (_clamp(v, 0, 1) * 255).round().toRadixString(16).padLeft(2, '0')).join()}';

String kelvinHex(num k) => rgbHex(kelvinRgb(k));
Rgb lightRgb(Light l) =>
    l.kelvin != null ? kelvinRgb(l.kelvin!) : hexRgb(l.color);

const _hueBins = [
  (15, '红色', 'red'),
  (40, '橙色', 'orange'),
  (65, '黄色', 'yellow'),
  (160, '绿色', 'green'),
  (200, '青色', 'cyan'),
  (250, '蓝色', 'blue'),
  (290, '紫色', 'purple'),
  (345, '品红色', 'magenta'),
  (361, '红色', 'red'),
];

/// 彩色灯的色相词;接近白光(饱和度太低)时是空串。
String _hueWord(String hex, bool zh) {
  final (r, g, b) = hexRgb(hex);
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final l = (mx + mn) / 2;
  final s = mx == mn
      ? 0
      : l > 0.5
      ? (mx - mn) / (2 - mx - mn)
      : (mx - mn) / (mx + mn);
  if (s < 0.2) return '';
  final h6 = mx == r
      ? ((g - b) / (mx - mn)) % 6
      : mx == g
      ? (b - r) / (mx - mn) + 2
      : (r - g) / (mx - mn) + 4;
  final h = ((h6 * 60) % 360 + 360) % 360;
  final hit = _hueBins.firstWhere((x) => h < x.$1);
  return zh ? hit.$2 : hit.$3;
}

/// 灯的颜色词:色温灯按档说冷暖,彩色灯说色相;接近日光白时是空串。
String colorWord(Light l, {required bool zh}) {
  final k = l.kelvin;
  if (k == null) return _hueWord(l.color, zh);
  if (k < 2300) return zh ? '橙红色' : 'deep orange';
  if (k < 3300) return zh ? '暖金色' : 'warm golden';
  if (k < 4500) return zh ? '偏暖' : 'warm';
  if (k < 6800) return '';
  if (k < 8000) return zh ? '偏冷' : 'cool';
  return zh ? '冷蓝色' : 'cold blue';
}

// ---------- 光影预览(给体块的面、背景板上明暗) ----------

/// 曝光曲线:亮度加起来再压回 0–1,亮处不会一下子过曝。
double _tone(double x) =>
    math.pow(1 - math.exp(-1.5 * math.max(0, x)), 1.7).toDouble();

/// 开着的灯在世界里的方向(从主体指向灯)、颜色和强弱。
List<(_V3, Rgb, Light)> _worldLights(Lighting lg, Camera? cam) => [
  for (final l in lg.active)
    (_lightVec(_worldAzimuth(l, lg, cam), l.elevation), lightRgb(l), l),
];

/// 环境光加上各盏灯照来的颜色,再过曝光曲线;[base] 是本来的颜色(0–1)。
Rgb _lit(Rgb base, Rgb ambient, Iterable<(Rgb, double)> lights) {
  var (r, g, b) = ambient;
  for (final (c, k) in lights) {
    r += c.$1 * k;
    g += c.$2 * k;
    b += c.$3 * k;
  }
  return (base.$1 * _tone(r), base.$2 * _tone(g), base.$3 * _tone(b));
}

/// 朝 [normal](世界坐标的单位向量)的一个面在这套灯光下的颜色:漫反射带柔光包裹,
/// 背景光只带一半,加环境光。[cam] 是主镜头(灯跟着镜头时按它算方位)。
Rgb shade(Vec3 normal, Rgb base, Lighting lg, Camera? cam) {
  final n = (normal.x, normal.y, normal.z);
  final amb = kelvinRgb(lg.ambientKelvin);
  return _lit(
    base,
    (amb.$1 * lg.ambient, amb.$2 * lg.ambient, amb.$3 * lg.ambient),
    [
      for (final (dir, rgb, l) in _worldLights(lg, cam))
        (
          rgb,
          math.max(
                0,
                (_dot(n, dir) + l.softness * 0.6) / (1 + l.softness * 0.6),
              ) *
              l.intensity *
              (l.role == 'bg' ? 0.5 : 1),
        ),
    ],
  );
}

/// 背景板(画面底色)的亮度:背景光照亮它,别的灯只带一点。
Rgb backdropShade(Rgb base, Lighting lg, Camera? cam) {
  final amb = kelvinRgb(lg.ambientKelvin);
  final a = lg.ambient * 1.1;
  return _lit(
    base,
    (amb.$1 * a, amb.$2 * a, amb.$3 * a),
    [
      for (final (dir, rgb, l) in _worldLights(lg, cam))
        (
          rgb,
          l.intensity *
              (l.role == 'bg' ? 0.9 : 0.22 + 0.15 * math.max(0, -dir.$3)),
        ),
    ],
  );
}

// ---------- 灯光球的像素 ----------

/// 被灯照亮的球(RGBA,[size] × [size]),球外是透明的。灯光球用。
Uint8List renderLitSphere(int size, Lighting lg, Camera? cam) {
  final out = Uint8List(size * size * 4);
  final rel = [for (final l in lg.active) (relDir(l, lg, cam), lightRgb(l), l)];
  final amb = kelvinRgb(lg.ambientKelvin);
  final radius = size / 2 - 1;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final sx = (x + 0.5 - size / 2) / radius,
          sy = -(y + 0.5 - size / 2) / radius;
      final rr = sx * sx + sy * sy;
      if (rr > 1) continue;
      final sz = math.sqrt(1 - rr);
      var cr = amb.$1 * lg.ambient,
          cg = amb.$2 * lg.ambient,
          cb = amb.$3 * lg.ambient;
      for (final (d, rgb, l) in rel) {
        final dd = sx * d.side + sy * d.up + sz * d.front;
        final w = l.softness * 0.6;
        final k =
            math.max(0, (dd + w) / (1 + w)) *
            l.intensity *
            (l.role == 'bg' ? 0.35 : 1);
        final rz = 2 * dd * sz - d.front;
        final spec = dd > 0
            ? math.pow(math.max(0, rz), 12 + (1 - l.softness) * 50) *
                  (1 - l.softness) *
                  0.45 *
                  l.intensity
            : 0;
        cr += rgb.$1 * (k + spec);
        cg += rgb.$2 * (k + spec);
        cb += rgb.$3 * (k + spec);
      }
      // 边上一圈渐隐,抗锯齿。
      final edge = math.min(1.0, (1 - math.sqrt(rr)) * radius * 1.2);
      final i = (y * size + x) * 4;
      out[i] = (_tone(cr) * 255).round();
      out[i + 1] = (_tone(cg) * 255).round();
      out[i + 2] = (_tone(cb) * 255).round();
      out[i + 3] = (edge * 255).round();
    }
  }
  return out;
}
