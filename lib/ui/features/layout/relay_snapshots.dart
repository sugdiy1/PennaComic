import 'dart:convert';

import '../../../core/harness/layout.dart';
import '../studio/studio_view_model.dart';
import 'layout_board.dart';

/// 只自动挑选命名为漫画格的对象背景；不把人物、台词或同格细节框当作格子。
Set<int> autoPanelFrameIndices(Map<String, Object?> snapshot) {
  final source = snapshot['source'];
  final boxes = source is Map ? source['boxes'] : null;
  if (boxes is! List) return {};
  final groups = <String, (num, int)>{};
  final name = RegExp(
    r'^(第[\d一二三四五六七八九十]+格|panel\s*\d+)(?:$|[\s·:：-])',
    caseSensitive: false,
  );
  for (final (index, box) in boxes.indexed) {
    if (box is! Map || ['text', 'character'].contains(box['label'])) continue;
    final match = name.firstMatch('${box['name'] ?? ''}');
    final rect = box['box'];
    if (match == null ||
        rect is! List ||
        rect.length != 4 ||
        rect.any((n) => n is! num)) {
      continue;
    }
    final area =
        ((rect[2] as num) - (rect[0] as num)) *
        ((rect[3] as num) - (rect[1] as num));
    final key = match.group(1)!.toLowerCase();
    if (area > (groups[key]?.$1 ?? -1)) groups[key] = (area, index);
  }
  return groups.values.map((v) => v.$2).toSet();
}

/// 在启动时冻结整个系列；后端不再读取会继续变化的画板。
/// 空页和损坏的页保留页码并标明原因，不能静默少出一页。
List<Map<String, Object?>> relaySnapshots(
  StudioViewModel vm,
  LayoutBoard board, {
  required String workspace,
}) {
  return [
    for (final (index, page) in vm.pages.indexed)
      if (page.series == vm.series)
        _snapshot(vm, board, index, page, workspace),
  ];
}

Map<String, Object?> _snapshot(
  StudioViewModel vm,
  LayoutBoard board,
  int index,
  DraftPage page,
  String workspace,
) {
  final number = vm.pageNumber(index);
  final context = <String, Object?>{
    'workspace': workspace,
    'series': vm.series,
    'page_number': number,
  };
  final header = <String, Object?>{
    'title': page.name.isEmpty ? '第 $number 页' : page.name,
    'page_number': number,
    'page_index': index,
    'context': context,
  };
  try {
    final layout = index == vm.pageIndex
        ? board.layout
        : Layout.fromJson(
            jsonDecode(page.blocks.map((b) => b.text).join())
                as Map<String, dynamic>,
          );
    if (layout.isEmpty) return {...header, 'unavailable': '空白页，请先完成分镜'};
    return {
      ...header,
      'width': layout.width,
      'height': layout.height,
      'source': layout.toJson(),
      'layout': jsonDecode(
        mossLayoutJson(layout, quality: board.quality?.call() ?? ''),
      ),
    };
  } on Object {
    return {...header, 'unavailable': '这页分镜无法读取，请先修复'};
  }
}
