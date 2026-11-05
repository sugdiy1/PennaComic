import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/camera.dart';
import 'package:penna/core/harness/lighting.dart';

/// lighting-kit 的标准答案(原项目生成的 89 条短语 + 22 个预设)。
final _fix = jsonDecode(
  File('test/fixtures/lighting_cases.json').readAsStringSync(),
) as Map<String, dynamic>;

/// lighting-kit 的机位 → Penna 的镜头:环绕角方向相反;关着的机位就是默认镜头。
Camera? _cam(Object? c) {
  if (c is! Map || c['enabled'] != true) return null;
  return Camera(
    orbit: -(c['orbit'] as num).toDouble(),
    pitch: (c['pitch'] as num? ?? 0).toDouble(),
    roll: (c['roll'] as num? ?? 0).toDouble(),
  );
}

Map<String, Object?> _noIds(Lighting lg) => {
  ...lg.toJson(),
  'lights': [
    for (final l in lg.lights) {...l.toJson()}..remove('id'),
  ],
};

void main() {
  test('短语和 lighting-kit 逐字一致(全部样例)', () {
    for (final c in _fix['cases'] as List) {
      final lg = Lighting.fromJson(c['lighting']);
      final cam = _cam(c['camera']);
      expect(lightingPhrase(lg, cam, zh: true), c['zh'], reason: c['name']);
      expect(lightingPhrase(lg, cam, zh: false), c['en'], reason: c['name']);
    }
  });

  test('套用预设和 lighting-kit 一致,且在当时的镜头下成立', () {
    final presets = _fix['presets'] as List;
    expect(presets, hasLength(lightPresets.length));
    for (final p in presets) {
      final cam = _cam(p['camera']);
      final got = presetLighting(p['id'] as String, cam);
      expect(
        _noIds(got),
        _noIds(Lighting.fromJson(p['lighting'])),
        reason: p['id'],
      );
      expect(presetMatches(got, cam), isTrue, reason: p['id']);
    }
  });

  test('灯光球:拖到哪,灯就在镜头里的哪个方向(含翻到背面)', () {
    const cam = Camera(orbit: 40, pitch: 18);
    final lg = presetLighting('three_point', cam);
    for (final (x, y, s) in [
      (0.5, 0.3, 1),
      (-0.7, -0.2, 1),
      (1.4, 0.2, 1),
      (0.1, 0.9, -1),
    ]) {
      final rel = ballPointToRel(x, y, s);
      final a = fromRel(rel.side, rel.up, rel.front, lg, cam);
      final moved = updateLight(lg, lg.lights.first.id, {
        'azimuth': a.azimuth,
        'elevation': a.elevation,
      });
      final back = relDir(moved.lights.first, moved, cam);
      expect(back.side, closeTo(rel.side, 0.02));
      expect(back.up, closeTo(rel.up, 0.02));
      expect(back.front.sign == 0 ? 1 : back.front.sign, rel.front.sign);
    }
    expect(ballPointToRel(1.5, 0, 1).front, lessThan(0));
  });

  test('固定 / 跟随:切换时画面里的光向不变;转镜头后固定的灯相对画面变、跟随的不变', () {
    const c0 = Camera(orbit: -30, pitch: 10);
    final fixed = presetLighting('rembrandt', c0);
    final follow = setFollow(fixed, true, c0);
    for (final (i, l) in fixed.lights.indexed) {
      expect(
        relDir(follow.lights[i], follow, c0).h,
        closeTo(relDir(l, fixed, c0).h, 0.15),
      );
    }
    const c1 = Camera(orbit: -120, pitch: 10);
    expect(
      relDir(follow.lights.first, follow, c1).h,
      closeTo(relDir(follow.lights.first, follow, c0).h, 0.15),
    );
    expect(
      (relDir(fixed.lights.first, fixed, c1).h -
              relDir(fixed.lights.first, fixed, c0).h)
          .abs(),
      greaterThan(60),
    );
  });

  test('Penna 的镜头从左侧拍(orbit 90)时,画面左边来的主光其实在主体正面', () {
    // 主光放在世界里主体的左侧(-90);镜头绕到左边拍,它就是正对镜头照过来。
    final lg = presetLighting('split', null);
    expect(relDir(lg.lights.first, lg, const Camera(orbit: 90)).h.abs(), 0);
  });

  test('Agent 写的 <lighting>:套预设、自己摆灯(方位相对镜头)、只改环境光、关掉', () {
    const cam = Camera(orbit: 30);
    final p = applyLightingSpec('{"preset": "伦勃朗光"}', const Lighting(), cam)!;
    expect((p.enabled, p.preset), (true, 'rembrandt'));
    expect(presetMatches(p, cam), isTrue);

    final own = applyLightingSpec(
      '```json\n{"lights": [{"role": "key", "azimuth": -90, "elevation": 10}], '
      '"ambient": 0.1, "extras": ["haze", "nope"]}\n```',
      p,
      cam,
    )!;
    expect(own.preset, '');
    expect(relDir(own.lights.single, own, cam).h, closeTo(-90, 0.1));
    expect(own.ambient, 0.1);
    expect(own.extras, ['haze']);

    final dim = applyLightingSpec('{"ambient": 0.6}', own, cam)!;
    expect(dim.lights, own.lights);
    expect(dim.ambient, 0.6);
    expect(applyLightingSpec('off', dim, cam)!.enabled, isFalse);
    expect(applyLightingSpec('{"preset": "不存在"}', dim, cam), isNull);
    expect(applyLightingSpec('不是 JSON', dim, cam), isNull);
  });

  test('光影预览:朝灯的面比背灯的面亮,背景光照亮背景板', () {
    // 分割光的主光在画面左边(方位 -90、高 10°):朝它的面是 -x 那边。
    final lg = presetLighting('split', null);
    const white = (1.0, 1.0, 1.0);
    final lit = shade((x: -0.985, y: -0.174, z: 0.0), white, lg, null);
    final dark = shade((x: 0.985, y: 0.174, z: 0.0), white, lg, null);
    expect(lit.$1, greaterThan(dark.$1 * 2));
    final withBg = addLight(lg, 'bg', null);
    expect(
      backdropShade(white, withBg, null).$2,
      greaterThan(backdropShade(white, lg, null).$2),
    );
  });

  test('标签:拆出最后一个,半截的不显示;旧回复里换成一句话', () {
    final r = splitLighting('好的。<lighting>{"preset": "noon"}</lighting>');
    expect((r.prose, r.spec), ('好的。', '{"preset": "noon"}'));
    expect(splitLighting('好的。<lighting>{"pre').prose, '好的。');
    expect(splitLighting('好的。<light').prose, '好的。');
    expect(
      forgetLighting('<lighting>{}</lighting>'),
      isNot(contains('<lighting>')),
    );
  });

  test('接到描述后面:英文接英文、中文接中文,接过的不再接;给 Agent 的现状带写法', () {
    final lg = presetLighting('rim', null);
    final en = appendLighting('A girl on a rooftop', lg, null);
    expect(en, 'A girl on a rooftop. ${lightingPhrase(lg, null, zh: false)}');
    expect(appendLighting(en, lg, null), en);
    expect(
      appendLighting('一个女孩站在屋顶', lg, null),
      '一个女孩站在屋顶。${lightingPhrase(lg, null, zh: true)}',
    );
    expect(appendLighting('A.', lg.patch({'enabled': false}), null), 'A.');
    expect(describeLighting(lg, null), contains('<lighting>'));
    expect(describeLighting(const Lighting(), null), contains('现在关着'));
  });
}
