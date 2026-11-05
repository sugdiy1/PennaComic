import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

String _layout(String name, {String? style, String page = ''}) =>
    '<layout$page>{"width": 832, "height": 1216, "summary": {"canvas": "single", '
    '${style == null ? '' : '"style": "$style", '}"caption": "Scene."}, '
    '"items": [{"name": "$name", "bbox": [100, 100, 500, 1100]}], '
    '"bbox_coord_space": "abs", "bbox_format": "xyxy"}</layout>';

void main() {
  const l = Layout(caption: 'A girl.', style: 'Flat anime style');

  test('交出去的 caption 依次是质量词、画风、整体描述;草稿只有整体描述', () {
    final out =
        jsonDecode(mossLayoutJson(l, quality: 'best quality, 8k')) as Map;
    expect(
      out['summary']['caption'],
      'best quality, 8k. Flat anime style. A girl.',
    );
    expect(out['summary'].containsKey('style'), isFalse);
    final draft = jsonDecode(mossLayoutJson(l, draft: true)) as Map;
    expect(draft['summary']['caption'], 'A girl.');
    expect(draft['summary'].containsKey('style'), isFalse);
  });

  test('导入交出去的 JSON 再交出去,质量词和画风不重复', () {
    final once = mossLayoutJson(l, quality: 'best quality');
    final back = parseMossLayout(once, width: 832, height: 1216)!;
    expect(mossLayoutJson(back, quality: 'best quality'), once);
  });

  test('读 summary.style;存档读回还在', () {
    final read = parseMossLayout(
      '{"summary": {"style": "Ink wash.", "caption": "x"}, "items": []}',
      width: 832,
      height: 1216,
    )!;
    expect(read.style, 'Ink wash.');
    expect(Layout.fromJson(read.toJson()).style, 'Ink wash.');
  });

  test('Agent 改布局时没写画风就沿用原来的', () {
    final board = LayoutBoard(quality: () => 'hq')
      ..setSummary(style: 'Watercolor.');
    expect(
      board.apply(_layout('A').replaceAll(RegExp('</?layout>'), '')),
      isTrue,
    );
    expect(board.layout.style, 'Watercolor.');
    expect(
      jsonDecode(board.json)['summary']['caption'],
      'hq. Watercolor. Scene.',
    );
    expect(defaultLayoutQuality, startsWith('best quality, highres'));
  });

  test('画风跟着系列:同系列新开一页沿用,另起系列不带过去', () async {
    final board = LayoutBoard();
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final seen = <List<Map<String, String>>>[];
    final replies = [
      _layout('小绿', style: 'Cel shading.', page: ' page="新系列" series="小绿"'),
      _layout('另一版', page: ' page="新"'),
      _layout('小蓝', page: ' page="新系列" series="小蓝"'),
    ];
    final chat = StudioViewModel(
      config: service,
      layout: board,
      layoutOnly: true,
      streamChat: (request) {
        seen.add(request.messages);
        return Stream.value(replies[seen.length - 1]);
      },
    );

    chat.send('画小绿');
    await pumpEventQueue();
    expect(seen.last.first['content'], contains('【本系列画风】还没定'));
    expect(board.layout.style, 'Cel shading.');

    chat.send('再来一版');
    await pumpEventQueue();
    expect(seen.last.first['content'], contains('【本系列画风】已定'));
    expect(seen.last.first['content'], contains('Cel shading.'));
    expect(chat.seriesLength, 2);
    expect(board.layout.boxes.single.name, '另一版');
    expect(board.layout.style, 'Cel shading.');

    chat.send('换成小蓝');
    await pumpEventQueue();
    expect(board.layout.boxes.single.name, '小蓝');
    expect(board.layout.style, isEmpty);
  });
}
