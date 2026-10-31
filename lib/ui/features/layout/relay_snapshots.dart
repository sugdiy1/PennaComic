import 'dart:convert';

import '../../../core/harness/layout.dart';
import '../studio/studio_view_model.dart';
import 'layout_board.dart';

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
