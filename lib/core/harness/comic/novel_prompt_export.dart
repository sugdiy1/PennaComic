import 'dart:convert';
import 'dart:math' as math;

import '../layout.dart';

String compileNovelMoss(Layout layout) {
  final compiled = jsonDecode(mossLayoutJson(layout)) as Map<String, dynamic>;
  if (layout.cast.isNotEmpty) {
    final scene =
        '${layout.caption}\n${layout.boxes.map((b) => b.caption).join('\n')}';
    final visible = layout.cast.entries
        .where((e) => scene.contains(e.key))
        .toList();
    final cards = visible.isEmpty ? layout.cast.entries.take(12) : visible;
    final references = {for (final e in cards) e.key: e.value};
    final summary = compiled['summary'] as Map;
    summary['caption'] =
        '${summary['caption']}\nCharacter text references (only draw characters explicitly present in the scene; do not add off-screen people): ${jsonEncode(references)}';
  }
  return const JsonEncoder.withIndent('  ').convert(compiled);
}

Map<String, dynamic> buildNovelPromptPackage(
  Map<String, dynamic> page,
  Layout layout,
) {
  final frames = layout.boxes
      .where((b) => b.label == 'object' && RegExp(r'^第\d+格$').hasMatch(b.name))
      .toList();
  if (frames.isEmpty) throw const FormatException('当前页没有可导出的漫画格。');
  num overlap(LayoutBox a, LayoutBox b) =>
      math.max(0, math.min(a.right, b.right) - math.max(a.left, b.left)) *
      math.max(0, math.min(a.bottom, b.bottom) - math.max(a.top, b.top));
  final panels = <Map<String, dynamic>>[];
  for (final (index, frame) in frames.indexed) {
    final width = (math.max(64, frame.width) / 16).ceil() * 16;
    final height = (math.max(64, frame.height) / 16).ceil() * 16;
    final contents = <LayoutBox>[];
    for (final element in layout.boxes) {
      if (frames.contains(element)) continue;
      final areas = frames.map((f) => overlap(element, f)).toList();
      final largest = areas.reduce(math.max);
      if (largest == 0 || areas.indexOf(largest) != index) continue;
      final l = ((element.left - frame.left) * width / frame.width)
          .round()
          .clamp(0, width);
      final t = ((element.top - frame.top) * height / frame.height)
          .round()
          .clamp(0, height);
      final r = ((element.right - frame.left) * width / frame.width)
          .round()
          .clamp(0, width);
      final b = ((element.bottom - frame.top) * height / frame.height)
          .round()
          .clamp(0, height);
      if (r > l && b > t) {
        contents.add(element.copyWith(left: l, top: t, right: r, bottom: b));
      }
    }
    final single = Layout.fromJson({
      'width': width,
      'height': height,
      'canvas': 'single',
      'style': layout.style,
      'caption':
          'ONE standalone manga panel, one camera shot; no additional panels or gutters. ${frame.caption} Keep exact supplied dialogue inside the visible image.',
      'cast': layout.cast,
      'boxes': contents.map((b) => b.toJson()).toList(),
    });
    panels.add({
      'panel_number': index + 1,
      'name': frame.name,
      'width': width,
      'height': height,
      'prompt': compileNovelMoss(single),
      'dialogue': contents
          .where((b) => b.label == 'text' && b.text.isNotEmpty)
          .map((b) => b.text)
          .toList(),
    });
  }
  final whole = compileNovelMoss(layout);
  final markdown = StringBuffer(
    '# ${page['title'] ?? '漫画页'}\n\n画布：${layout.width}×${layout.height}\n\n## 整页提示词\n\n```json\n$whole\n```\n',
  );
  for (final panel in panels) {
    markdown.writeln(
      '\n## 第${panel['panel_number']}格 · ${panel['width']}×${panel['height']}\n\n```json\n${panel['prompt']}\n```\n\n台词：${(panel['dialogue'] as List).join(' / ')}',
    );
  }
  markdown.writeln(
    '\n提示词中的bbox是模型构图提示，手动整页生成不保证精确格形。逐格提示词须搭配对应尺寸；精确蒙版拼接可使用软件工作流模式。台词由图像模型绘制，需检查原文。',
  );
  return {
    'title': page['title'],
    'width': layout.width,
    'height': layout.height,
    'layout_id': page['layout_id'],
    'whole_page_prompt': whole,
    'panels': panels,
    'markdown': markdown.toString(),
  };
}
