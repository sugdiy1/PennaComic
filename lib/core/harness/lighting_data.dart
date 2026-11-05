part of 'lighting.dart';

// 角色、预设、氛围效果:由 lighting-kit 的 data/lighting_data.json 生成,文字一个不改
// (短语要和原项目逐字一致)。

typedef LightRoleInfo = ({String zh, String en, String short});

const lightRoleInfo = <String, LightRoleInfo>{
  'key': (zh: '主光', en: 'key light', short: '主'),
  'fill': (zh: '补光', en: 'fill light', short: '补'),
  'rim': (zh: '轮廓光', en: 'rim light', short: '轮'),
  'bg': (zh: '背景光', en: 'background light', short: '背'),
  'practical': (zh: '实景光源', en: 'practical light', short: '实'),
};

/// 氛围效果:[label] 是界面上的名字,[zh] / [en] 写进提示词。
typedef LightExtra = ({String id, String label, String zh, String en});

const lightExtras = <LightExtra>[
  (
    id: 'volumetric',
    label: '体积光',
    zh: '体积光光束（丁达尔效应）',
    en: 'volumetric light rays',
  ),
  (id: 'haze', label: '薄雾', zh: '空气中弥漫薄雾', en: 'atmospheric haze'),
  (id: 'flare', label: '镜头光晕', zh: '镜头光晕', en: 'lens flare'),
  (
    id: 'bokeh',
    label: '背景光斑',
    zh: '背景虚化光斑',
    en: 'bokeh highlights in the background',
  ),
  (id: 'shadows', label: '清晰投影', zh: '清晰的投影', en: 'crisp cast shadows'),
  (
    id: 'blinds',
    label: '百叶窗光影',
    zh: '百叶窗条纹光影',
    en: 'venetian blind shadow stripes',
  ),
  (
    id: 'dappled',
    label: '树影斑驳',
    zh: '透过树叶的斑驳光影',
    en: 'dappled light through leaves',
  ),
  (id: 'wet', label: '湿地反光', zh: '湿润地面上的反光', en: 'reflections on wet ground'),
  (
    id: 'bloom',
    label: '柔光辉光',
    zh: '高光处柔和辉光',
    en: 'soft glow and bloom on highlights',
  ),
  (
    id: 'caustics',
    label: '水波焦散',
    zh: '水波焦散光纹',
    en: 'water caustics light patterns',
  ),
];

/// 打光预设:灯的方位相对套用时的镜头。[name] 是界面上的名字,[desc] 是一句说明,
/// [zh] / [en] 写进提示词。
typedef LightPreset = ({
  String id,
  String name,
  String desc,
  String zh,
  String en,
  double ambient,
  int ambientKelvin,
  List<String> extras,
  List<Light> lights,
});

Light _p(
  String role,
  double az,
  double el,
  double i,
  double s, {
  int? k,
  String? c,
}) => Light(
  id: '',
  role: role,
  azimuth: az,
  elevation: el,
  intensity: i,
  kelvin: k,
  color: c ?? '#ffffff',
  softness: s,
);

final List<LightPreset> lightPresets = List.unmodifiable(<LightPreset>[
  (
    id: 'natural',
    name: '自然光',
    desc: '柔和的日光，阴影自然',
    zh: '自然光',
    en: 'natural daylight',
    ambient: 0.45,
    ambientKelvin: 6500,
    extras: const [],
    lights: [
      _p('key', -35.0, 40.0, 0.9, 0.7, k: 5600),
      _p('fill', 50.0, 15.0, 0.35, 0.9, k: 6500),
    ],
  ),
  (
    id: 'rembrandt',
    name: '伦勃朗光',
    desc: '侧上方 45° 主光，暗侧脸颊有三角光斑',
    zh: '伦勃朗光，暗侧脸颊上有一小块三角形光斑',
    en: 'Rembrandt lighting, a small triangle of light on the shadowed cheek',
    ambient: 0.12,
    ambientKelvin: 4500,
    extras: const [],
    lights: [
      _p('key', -45.0, 40.0, 1.0, 0.45, k: 4300),
      _p('fill', 60.0, 5.0, 0.12, 0.8, k: 5000),
    ],
  ),
  (
    id: 'butterfly',
    name: '蝴蝶光',
    desc: '正前上方主光（派拉蒙光），鼻下蝶形阴影',
    zh: '蝴蝶光（派拉蒙光），鼻下有蝶形阴影',
    en: 'butterfly (Paramount) lighting with a small shadow under the nose',
    ambient: 0.3,
    ambientKelvin: 5500,
    extras: const [],
    lights: [
      _p('key', 0.0, 50.0, 1.0, 0.55, k: 5200),
      _p('fill', 0.0, -20.0, 0.3, 0.9, k: 5500),
    ],
  ),
  (
    id: 'loop',
    name: '环形光',
    desc: '略偏一侧的主光，鼻影呈小环',
    zh: '环形光，鼻影呈小环状',
    en: 'loop lighting',
    ambient: 0.25,
    ambientKelvin: 5500,
    extras: const [],
    lights: [
      _p('key', -35.0, 30.0, 0.95, 0.55, k: 5000),
      _p('fill', 45.0, 5.0, 0.3, 0.85, k: 5500),
    ],
  ),
  (
    id: 'split',
    name: '分割光',
    desc: '正侧面主光，一半在阴影里',
    zh: '分割光，脸部一半在阴影中',
    en: 'split lighting, half of the face in shadow',
    ambient: 0.08,
    ambientKelvin: 5000,
    extras: const [],
    lights: [_p('key', -90.0, 10.0, 1.0, 0.35, k: 4800)],
  ),
  (
    id: 'three_point',
    name: '三点布光',
    desc: '主光 + 补光 + 轮廓光',
    zh: '经典三点布光',
    en: 'classic three-point lighting',
    ambient: 0.25,
    ambientKelvin: 5500,
    extras: const [],
    lights: [
      _p('key', -40.0, 35.0, 1.0, 0.55, k: 5200),
      _p('fill', 45.0, 10.0, 0.4, 0.85, k: 5600),
      _p('rim', 150.0, 35.0, 0.7, 0.3, k: 6000),
    ],
  ),
  (
    id: 'rim',
    name: '轮廓光',
    desc: '两侧后方的光勾出边缘',
    zh: '强烈的轮廓光勾勒主体边缘',
    en: 'strong rim lighting outlining the subject\'s edges',
    ambient: 0.12,
    ambientKelvin: 6000,
    extras: const [],
    lights: [
      _p('rim', 140.0, 25.0, 1.0, 0.3, k: 6500),
      _p('rim', -140.0, 25.0, 0.8, 0.3, k: 6500),
      _p('fill', 0.0, 0.0, 0.15, 0.9, k: 5500),
    ],
  ),
  (
    id: 'backlight',
    name: '逆光',
    desc: '光从主体背后来，边缘发光',
    zh: '逆光，主体周围有发光的光晕',
    en: 'backlit, a glowing halo around the subject',
    ambient: 0.3,
    ambientKelvin: 5000,
    extras: const ['haze', 'flare'],
    lights: [
      _p('key', 180.0, 15.0, 1.2, 0.5, k: 4500),
      _p('fill', 0.0, 5.0, 0.25, 0.9, k: 5500),
    ],
  ),
  (
    id: 'silhouette',
    name: '剪影',
    desc: '明亮背景前主体几乎全黑',
    zh: '剪影，主体在明亮背景前几乎全黑',
    en: 'silhouette against a bright background, the subject almost completely in shadow',
    ambient: 0.03,
    ambientKelvin: 6000,
    extras: const [],
    lights: [_p('bg', 180.0, 5.0, 1.3, 0.6, k: 6000)],
  ),
  (
    id: 'golden_hour',
    name: '黄金时刻',
    desc: '低角度暖色夕阳',
    zh: '黄金时刻，低角度的暖色阳光',
    en: 'golden hour sunlight, a low warm sun',
    ambient: 0.35,
    ambientKelvin: 3800,
    extras: const ['flare'],
    lights: [
      _p('key', -70.0, 8.0, 1.0, 0.6, k: 2800),
      _p('fill', 60.0, 10.0, 0.3, 0.9, k: 7000),
    ],
  ),
  (
    id: 'blue_hour',
    name: '蓝调时刻',
    desc: '冷色暮光 + 暖色灯光',
    zh: '蓝调时刻，冷色暮光与暖色灯光',
    en: 'blue hour twilight, cool ambient light with warm practical lights',
    ambient: 0.35,
    ambientKelvin: 10000,
    extras: const [],
    lights: [
      _p('key', -30.0, 15.0, 0.45, 0.9, k: 9500),
      _p('practical', 40.0, 0.0, 0.6, 0.6, k: 2700),
    ],
  ),
  (
    id: 'overcast',
    name: '阴天柔光',
    desc: '大面积漫射，几乎没有硬阴影',
    zh: '阴天柔光，阴影柔和',
    en: 'soft overcast light with diffused shadows',
    ambient: 0.6,
    ambientKelvin: 7000,
    extras: const [],
    lights: [
      _p('key', 0.0, 60.0, 0.7, 1.0, k: 6500),
      _p('fill', 0.0, 0.0, 0.3, 1.0, k: 6500),
    ],
  ),
  (
    id: 'window',
    name: '窗户光',
    desc: '侧面窗户透进的柔光',
    zh: '侧面窗户透进的柔和自然光',
    en: 'soft window light from the side',
    ambient: 0.18,
    ambientKelvin: 6000,
    extras: const [],
    lights: [
      _p('key', -80.0, 20.0, 1.0, 0.75, k: 5600),
      _p('fill', 80.0, 0.0, 0.12, 0.9, k: 5000),
    ],
  ),
  (
    id: 'top',
    name: '顶光',
    desc: '正上方硬光，眼窝下巴阴影深',
    zh: '顶光，眼窝和下巴下方有深阴影',
    en: 'harsh top lighting with deep shadows in the eye sockets',
    ambient: 0.1,
    ambientKelvin: 5000,
    extras: const [],
    lights: [_p('key', 0.0, 85.0, 1.1, 0.3, k: 5000)],
  ),
  (
    id: 'under',
    name: '底光',
    desc: '从下往上照，诡异感',
    zh: '从下往上的底光，诡异感',
    en: 'eerie under-lighting from below',
    ambient: 0.08,
    ambientKelvin: 4000,
    extras: const [],
    lights: [_p('key', 0.0, -50.0, 1.0, 0.4, k: 3500)],
  ),
  (
    id: 'moonlight',
    name: '月光',
    desc: '冷色月光的夜景',
    zh: '冷色月光，夜景',
    en: 'cold moonlight in a dark night scene',
    ambient: 0.15,
    ambientKelvin: 11000,
    extras: const [],
    lights: [_p('key', -40.0, 45.0, 0.55, 0.45, k: 8500)],
  ),
  (
    id: 'neon',
    name: '霓虹',
    desc: '品红 + 青色双色光',
    zh: '霓虹灯光，品红与青色的双色光',
    en: 'neon lighting with magenta and cyan colored light',
    ambient: 0.1,
    ambientKelvin: 8000,
    extras: const ['wet', 'bloom'],
    lights: [
      _p('key', -75.0, 10.0, 0.9, 0.5, c: '#ff2e88'),
      _p('rim', 80.0, 15.0, 0.9, 0.45, c: '#20c8ff'),
    ],
  ),
  (
    id: 'candle',
    name: '烛光',
    desc: '摇曳的暖光，四周昏暗',
    zh: '温暖摇曳的烛光，四周昏暗',
    en: 'warm flickering candlelight with dark surroundings',
    ambient: 0.06,
    ambientKelvin: 3000,
    extras: const ['bloom'],
    lights: [_p('practical', 30.0, -10.0, 0.9, 0.6, k: 1900)],
  ),
  (
    id: 'spotlight',
    name: '舞台聚光',
    desc: '黑暗中从上方打下的一束光',
    zh: '舞台聚光灯从上方照下，黑暗中的一束光',
    en: 'theatrical spotlight from above, a pool of light in darkness',
    ambient: 0.03,
    ambientKelvin: 5000,
    extras: const ['haze', 'volumetric'],
    lights: [_p('key', 0.0, 60.0, 1.3, 0.15, k: 5500)],
  ),
  (
    id: 'high_key',
    name: '高调光',
    desc: '明亮干净，几乎没有阴影',
    zh: '明亮的高调光，几乎没有阴影',
    en: 'bright high-key lighting with minimal shadows and clean white tones',
    ambient: 0.8,
    ambientKelvin: 6500,
    extras: const [],
    lights: [
      _p('key', -20.0, 25.0, 0.9, 0.95, k: 6000),
      _p('fill', 30.0, 0.0, 0.7, 1.0, k: 6000),
      _p('bg', 180.0, 0.0, 0.8, 1.0, k: 6500),
    ],
  ),
  (
    id: 'low_key',
    name: '低调光',
    desc: '大面积暗部，戏剧性强',
    zh: '戏剧性的低调光，大面积暗部',
    en: 'dramatic low-key lighting, mostly dark with deep shadows',
    ambient: 0.04,
    ambientKelvin: 5000,
    extras: const [],
    lights: [_p('key', -60.0, 30.0, 1.0, 0.35, k: 4500)],
  ),
  (
    id: 'noon',
    name: '正午硬光',
    desc: '头顶直射阳光，影子短而硬',
    zh: '正午强烈的直射阳光，阴影短而硬',
    en: 'harsh midday sun with short hard shadows',
    ambient: 0.4,
    ambientKelvin: 7000,
    extras: const ['shadows'],
    lights: [_p('key', 20.0, 75.0, 1.2, 0.05, k: 5800)],
  ),
]);

final Map<String, LightPreset> _presetById = {
  for (final p in lightPresets) p.id: p,
};
final Map<String, LightExtra> _extraById = {
  for (final e in lightExtras) e.id: e,
};

/// 按 id、中文名或英文名(不分大小写)找预设。
LightPreset? findPreset(String key) {
  final k = key.trim();
  return _presetById[k] ??
      lightPresets
          .where(
            (p) =>
                p.name == k ||
                p.zh == k ||
                p.en.toLowerCase() == k.toLowerCase(),
          )
          .firstOrNull;
}
