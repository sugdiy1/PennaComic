import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comic/comic_layout_catalog.dart';

void main() {
  test('121套布局具有唯一几何、有效边界和可供AI判断的用途', () {
    expect(comicLayouts, hasLength(121));
    expect(comicLayouts.map((l) => l.id).toSet(), hasLength(121));
    expect(
      comicLayouts.map((l) => jsonEncode(l.panels)).toSet(),
      hasLength(121),
    );
    for (final layout in comicLayouts) {
      expect(layout.purpose, isNotEmpty);
      expect(layout.tags, isNotEmpty);
      for (final panel in layout.panels) {
        final b = panel['box'] as List<int>;
        expect(b[0], inInclusiveRange(0, 999));
        expect(b[1], inInclusiveRange(0, 999));
        expect(b[2], inInclusiveRange(b[0] + 1, 1000));
        expect(b[3], inInclusiveRange(b[1] + 1, 1000));
      }
    }
    expect(
      comicLayouts.map((l) => l.panels.length).toSet(),
      containsAll([1, 2, 3, 4, 5, 6]),
    );
  });
  test('AI目录包含全部编号和用途，几何按实际画幅缩放', () {
    for (final layout in comicLayouts) {
      expect(comicLayoutMenu(), contains(layout.id));
      final boxes = layout.pixelPanels(768, 1024);
      expect(boxes, hasLength(layout.panels.length));
      expect(boxes.first['box'], hasLength(4));
    }
  });
}
