part of 'lighting.dart';

// 灯光 → 提示词短语(和 lighting-kit 的 phrase.ts 逐字一致),给 Agent 看的灯光现状,
// 和 Agent 写的 `<lighting>` 标签。

/// 套用的预设在当前镜头下还成立吗:镜头转过以后主光可能已经不在预设规定的方向
/// (水平差超过 30° 或高度差超过 25°),这时短语里不写预设名,免得误导画图模型。
bool presetMatches(Lighting lg, Camera? cam) {
  final p = _presetById[lg.preset];
  if (p == null || p.lights.isEmpty) return false;
  final pl = p.lights.first;
  final l = lg.lights.where((x) => x.enabled && x.role == pl.role).firstOrNull;
  if (l == null) return false;
  final r = relDir(l, lg, cam);
  return (r.h.abs() - pl.azimuth.abs()).abs() <= 30 &&
      (r.v - pl.elevation).abs() <= 25;
}

double _keyIntensity(List<Light> on) {
  final keys = [
    for (final l in on)
      if (l.role == 'key') l,
  ];
  final pool = keys.isEmpty ? on : keys;
  return pool.isEmpty ? 0 : pool.map((l) => l.intensity).reduce(math.max);
}

String _strengthWord(Light l, double keyI, bool zh) {
  if (l.role == 'key') {
    if (l.intensity >= 1.25) return zh ? '强烈' : 'strong';
    if (l.intensity <= 0.5) return zh ? '微弱' : 'dim';
    return '';
  }
  final ratio = keyI > 0 ? l.intensity / keyI : 1;
  if (ratio < 0.3) return zh ? '微弱' : 'faint';
  if (ratio >= 1.1) return zh ? '强烈' : 'strong';
  return '';
}

String _qualityWord(double s, bool zh) => s <= 0.25
    ? (zh ? '硬朗' : 'hard')
    : s >= 0.7
    ? (zh ? '柔和漫射' : 'soft diffused')
    : '';

/// 一盏灯 → 一个分句。
String _lightClause(Light l, Lighting lg, Camera? cam, double keyI, bool zh) {
  final r = relDir(l, lg, cam);
  final dir = directionText(r.h, r.v, zh: zh);
  final strength = _strengthWord(l, keyI, zh);
  final quality = _qualityWord(l.softness, zh);
  final color = colorWord(l, zh: zh);
  final role = lightRoleInfo[l.role]!;
  if (zh) {
    final adj = [strength, quality].where((s) => s.isNotEmpty).join('、');
    final light = '${adj.isEmpty ? '' : '$adj的'}$color光';
    final plain = light == '光';
    switch (l.role) {
      case 'bg':
        return plain ? '背景光照亮主体身后的背景' : '背景光为$light，照亮主体身后的背景';
      case 'practical':
        final what = plain ? '' : '${light.substring(0, light.length - 1)}的';
        return '场景中有$what实景光源，从$dir照来';
      case 'rim':
        return plain ? '轮廓光从$dir勾勒边缘' : '轮廓光为$light，从$dir勾勒边缘';
    }
    return plain ? '${role.zh}从$dir照来' : '${role.zh}为$light，从$dir照来';
  }
  final adj = [strength, quality, color].where((s) => s.isNotEmpty).join(' ');
  final pre = adj.isEmpty ? '' : '$adj ';
  return switch (l.role) {
    'bg' =>
      '${pre}background light illuminating the backdrop behind the subject',
    'practical' =>
      '${pre}practical light source visible in the scene, coming from $dir',
    'rim' => '${pre}rim light from $dir, outlining the edges',
    _ => '$pre${role.en} from $dir',
  };
}

/// 整体反差、环境色调。
String _toneClause(Lighting lg, List<Light> on, bool zh) {
  final amb = lg.ambient;
  final fill = on
      .where((l) => l.role == 'fill')
      .fold(0.0, (s, l) => s + l.intensity);
  String out;
  if (on.isEmpty) {
    if (amb >= 0.6) {
      out = zh ? '整体明亮通透，光线均匀' : 'bright, even ambient light';
    } else if (amb <= 0.1) {
      out = zh ? '环境非常昏暗' : 'very dark surroundings';
    } else {
      return '';
    }
  } else {
    final ratio = (_keyIntensity(on) + 0.001) / (fill + amb + 0.05);
    if (amb >= 0.65 && ratio < 2.2) {
      out = zh
          ? '整体明亮通透，反差低，阴影柔和'
          : 'bright, airy, low-contrast lighting with soft shadows';
    } else if (ratio >= 6 || amb <= 0.08) {
      out = zh
          ? '环境昏暗，阴影浓重，明暗对比强烈'
          : 'dark surroundings, deep shadows and high contrast (chiaroscuro)';
    } else if (ratio >= 3) {
      out = zh ? '中等反差，阴影清晰' : 'moderate contrast with defined shadows';
    } else {
      out = zh ? '反差柔和，暗部通透' : 'gentle contrast with soft, open shadows';
    }
  }
  if (amb >= 0.25) {
    if (lg.ambientKelvin >= 8500) {
      out += zh ? '，环境色调偏冷蓝' : ', with a cool blue ambient tone';
    } else if (lg.ambientKelvin <= 3800) {
      out += zh ? '，环境色调偏暖' : ', with a warm ambient tone';
    }
  }
  return out;
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
final _trailing = RegExp(r'[\s。.!！;；,，]+$', unicode: true);

/// 灯光 → 提示词短语;灯光关着或什么都没有时是空串。
String lightingPhrase(Lighting lg, Camera? cam, {required bool zh}) {
  if (!lg.enabled) return '';
  final on = lg.active;
  final p = _presetById[lg.preset];
  final keyI = _keyIntensity(on);
  // 按 主光 → 补光 → 轮廓光 → 背景光 → 实景光源,同角色强的在前(先后相同保持原顺序)。
  final sorted = [...on.indexed]
    ..sort((a, b) {
      final role = lightRoles
          .indexOf(a.$2.role)
          .compareTo(lightRoles.indexOf(b.$2.role));
      if (role != 0) return role;
      final strength = b.$2.intensity.compareTo(a.$2.intensity);
      return strength != 0 ? strength : a.$1.compareTo(b.$1);
    });
  final parts = [
    if (p != null && presetMatches(lg, cam)) zh ? p.zh : p.en,
    for (final (_, l) in sorted.take(5)) _lightClause(l, lg, cam, keyI, zh),
  ];
  final ex = [
    for (final id in lg.extras)
      if (_extraById[id] case final e?) zh ? e.zh : e.en,
  ];
  final sentences = [
    parts.join(zh ? '；' : '; '),
    _toneClause(lg, on, zh),
    ex.join(zh ? '，' : ', '),
    lg.note.trim().replaceFirst(_trailing, ''),
  ].where((s) => s.isNotEmpty).toList();
  if (sentences.isEmpty) return '';
  if (zh) return '光线：${sentences.join('。')}。';
  return 'Lighting: ${sentences.map(_cap).join('. ')}.';
}

final _cjk = RegExp(r'[㐀-鿿豈-﫿]');
bool isCjk(String text) => _cjk.hasMatch(text);

/// 把一句话接到描述后面:补句号,中文句号后不加空格。
String appendSentence(String base, String extra) {
  final b0 = base.trimRight();
  if (extra.isEmpty) return b0;
  final zh = isCjk(b0);
  final b = b0.isNotEmpty && !'.。!！?？;；'.contains(b0[b0.length - 1])
      ? '$b0${zh ? '。' : '.'}'
      : b0;
  if (b.isEmpty) return extra;
  return zh && '。！？；'.contains(b[b.length - 1]) ? '$b$extra' : '$b $extra';
}

/// 交出去时用:描述里有中文就接中文的灯光短语,否则接英文的。已经接过就不再接。
String appendLighting(String caption, Lighting lg, Camera? cam) {
  final phrase = lightingPhrase(lg, cam, zh: isCjk(caption));
  if (phrase.isEmpty || caption.contains(phrase)) return caption;
  return appendSentence(caption, phrase);
}

String _fmt(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

/// 给 Agent 看的灯光现状(系统提示里的【灯光】,发给模型的话,不翻译):
/// 每盏灯在画面里从哪来、相对当前镜头的方位,以及怎么用 `<lighting>` 改。
String describeLighting(Lighting lg, Camera? cam) {
  final presets = lightPresets.map((p) => '${p.id}(${p.name})').join('、');
  final extras = lightExtras.map((e) => '${e.id}(${e.label})').join('、');
  const how =
      '要改灯光就写 <lighting>{…}</lighting>(只在 Penna 里用,不进布局 JSON):'
      '套预设写 {"preset": "rembrandt"};自己摆灯写 {"lights": [{"role": "key", "azimuth": -40, '
      '"elevation": 35, "intensity": 1, "kelvin": 4300, "softness": 0.45}], "ambient": 0.2, '
      '"ambient_kelvin": 5000, "extras": ["haze"], "note": ""}'
      '(role 是 key 主光 / fill 补光 / rim 轮廓光 / bg 背景光 / practical 实景光源;'
      'azimuth 相对当前镜头:0 是从镜头这边照向主体,负数在画面左、正数在画面右,±180 是背后;'
      'elevation 正数从上往下照;intensity 0–2,1 是正常;softness 0 硬光到 1 柔光;'
      '彩色灯不写 kelvin,写 "color": "#ff2e88")。两样一起写时先套预设再换灯;'
      '只写 ambient、extras、note 这些会在现在的灯光上改;关掉写 off。';
  if (!lg.enabled) {
    return '【灯光】现在关着。用户要打光、说了光从哪来、或照参考图的光影排时,打开它:$how'
        '\n预设有:$presets。\n氛围效果有:$extras。';
  }
  final p = _presetById[lg.preset];
  final lights = [
    for (final (i, l) in lg.lights.indexed)
      () {
        final r = relDir(l, lg, cam);
        return '${i + 1}. ${lightRoleInfo[l.role]!.zh}(${l.role})${l.enabled ? '' : '(关着)'}:'
            '从${directionText(r.h, r.v, zh: true)}照来;azimuth ${_fmt(_r1(r.h))}、elevation ${_fmt(l.elevation)}、'
            'intensity ${_fmt(l.intensity)}、${l.kelvin != null ? 'kelvin ${l.kelvin}' : 'color ${l.color}'}、'
            'softness ${_fmt(l.softness)}';
      }(),
  ].join('\n');
  final phrase = lightingPhrase(lg, cam, zh: false);
  return '【灯光】开着'
      '${p == null ? ',自定义' : ',预设「${p.name}」${presetMatches(lg, cam) ? '' : '(镜头转过,主光已不在预设的方向,提示词里不再写预设名)'}'}'
      '${lg.follow ? ',灯跟着镜头转' : ',灯固定在场景里(转镜头时光线相对画面会变)'}。'
      '环境光 ${_fmt(lg.ambient)}、${lg.ambientKelvin}K'
      '${lg.extras.isEmpty ? '' : ';氛围:${lg.extras.map((e) => _extraById[e]!.label).join('、')}'}'
      '${lg.note.trim().isEmpty ? '' : ';补充:${lg.note.trim()}'}。\n'
      '${lights.isEmpty ? '(没有灯)' : lights}\n'
      '交出去时程序把灯光写成一句英文接在 summary.caption 最后:「$phrase」。'
      'summary.caption 里不用再写整体光照;各块 caption 里的受光面、阴影、投影方向和高光要和这里对得上'
      '(主光从左边来,人物的左脸亮、影子落在右边)。用户改了灯光、要你按灯光改描述时,照这里重写各块的光影。\n'
      '$how\n预设有:$presets。\n氛围效果有:$extras。';
}

/// 照 Agent 写的 `<lighting>` 改灯光([cur] 是现在的,[cam] 是当前镜头;方位相对镜头)。
/// 读不了返回 null。
Lighting? applyLightingSpec(String spec, Lighting cur, Camera? cam) {
  final text = spec
      .trim()
      .replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '')
      .replaceFirst(RegExp(r'\s*```$'), '')
      .trim();
  if (text == 'off' || text == '"off"') return cur.patch({'enabled': false});
  final Object? j;
  try {
    j = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (j is! Map) return null;
  final preset = j['preset'] is String
      ? findPreset(j['preset'] as String)
      : null;
  final lights = j['lights'] is List ? j['lights'] as List : null;
  if (j['preset'] != null && preset == null && lights == null) return null;
  // 先定跟不跟镜头:后面的方位按它换算。
  var lg = j['follow'] is bool ? setFollow(cur, j['follow'] as bool, cam) : cur;
  if (preset != null) lg = presetLighting(preset.id, cam, lg);
  if (lights != null) {
    lg = lg.patch({
      'preset': '',
      'lights': [
        for (final (i, raw) in lights.indexed)
          if (raw is Map)
            {
              ...raw,
              'id': newLightId(),
              'azimuth': toStoredAzimuth(_num(raw['azimuth'], 0), lg, cam),
              if (i == 0 && raw['role'] == null) 'role': 'key',
            },
      ],
    });
  }
  return lg.patch({
    for (final k in ['ambient', 'ambient_kelvin', 'extras', 'note'])
      if (j.containsKey(k)) k: j[k],
    'enabled': j['enabled'] != false,
  });
}

final _tag = RegExp(r'<lighting>([\s\S]*?)</lighting>');
const _open = '<lighting>';

/// 把回复里的 `<lighting>` 拆出来(有好几个时取最后一个):[spec] 是里面的内容,
/// [prose] 是去掉它之后给人看的话;还没写完的那一个先不显示,[spec] 为 null。
({String prose, String? spec}) splitLighting(String reply) {
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

/// 发给模型的旧回复里,整个 `<lighting>…</lighting>` 换成一句不带标签的话
/// (同 `forgetPerspectives`):用户之后可能拖过灯,现在的样子只看【灯光】。
String forgetLighting(String reply) =>
    reply.replaceAll(_tag, '(这里调过一次灯光,已放到画板上,内容省略;现在的样子看【灯光】)');
