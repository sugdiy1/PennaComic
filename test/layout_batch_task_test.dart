import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comic/layout_page_task.dart';
import 'package:penna/core/harness/providers/llm_http.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

String result(int n) =>
    '<layout page="current" name="页$n">${jsonEncode({
      'summary': {
        'caption': 'UNIQUE_SCENE_$n',
        'style': 'color manga',
        'cast': {'小蓝': 'An adult courier in a blue jacket.'},
      },
      'items': [
        {
          'name': '第1格',
          'label': 'object',
          'caption': 'Adult courier scene $n',
          'bbox': [16, 16, 800, 1180],
        },
      ],
      'bbox_coord_space': 'abs',
      'bbox_format': 'xyxy',
    })}</layout>';

void main() {
  test('15页是数量而非第15页，中文数与页码范围可识别', () {
    expect(requestedLayoutPageCount('画15页漫画。'), 15);
    expect(requestedLayoutPageCount('请做十五页漫画。'), 15);
    expect(requestedLayoutPageCount('生成第1到15页分镜。'), 15);
    expect(requestedLayoutPageCount('只修改第15页的手。'), isNull);
    expect(requestedLayoutPageCount('解释第15页为什么错误'), isNull);
  });
  test('一次请求自动完成15页，忽略模型错误的current目标且每次保留原始故事', () async {
    final cfg = tempConfig();
    cfg.update(
      cfg.config.copyWith(
        llms: [
          const LlmProfile(
            id: 'test',
            name: 'test',
            baseUrl: 'http://127.0.0.1:8189/v1',
            model: 'deepseek-flash',
          ),
        ],
        activeLlmId: () => 'test',
      ),
    );
    final board = LayoutBoard();
    final requests = <LlmRequest>[];
    final vm = StudioViewModel(
      config: cfg,
      layout: board,
      layoutOnly: true,
      streamChat: (r) async* {
        requests.add(r);
        yield result(requests.length);
      },
    );
    addTearDown(() async {
      vm.dispose();
      board.dispose();
      await cfg.flushed();
      cfg.dispose();
    });
    await vm.sendAndWait('画15页漫画，故事锚点 ORIGINAL_STORY_BLUE_COURIER，不要重复开场。');
    expect(requests, hasLength(15));
    expect(vm.seriesLength, 15);
    expect(vm.layoutPageTask!.completed, 15);
    expect(vm.layoutPageTask!.active, isFalse);
    expect(
      requests.every(
        (r) => r.messages.any(
          (m) => m['content']!.contains('ORIGINAL_STORY_BLUE_COURIER'),
        ),
      ),
      isTrue,
    );
    expect(
      vm.pages.map((p) => p.blocks.map((b) => b.text).join()).toSet(),
      hasLength(15),
    );
  });
  test('第二页失败后暂停；存档重载可继续剩余页而不重做第一页', () async {
    final cfg = tempConfig();
    cfg.update(
      cfg.config.copyWith(
        llms: [
          const LlmProfile(
            id: 'test',
            name: 'test',
            baseUrl: 'https://example.invalid/v1',
            model: 'test',
          ),
        ],
        activeLlmId: () => 'test',
      ),
    );
    final board = LayoutBoard();
    var calls = 0;
    final vm = StudioViewModel(
      config: cfg,
      layout: board,
      layoutOnly: true,
      streamChat: (r) async* {
        calls++;
        if (calls == 2) throw Exception('synthetic failure');
        yield result(calls);
      },
    );
    await vm.sendAndWait('画3页成年快递员漫画。');
    expect(vm.layoutPageTask!.completed, 1);
    expect(vm.layoutPageTask!.active, isFalse);
    expect(vm.seriesLength, 1);
    final saved = vm.toJson();
    vm.dispose();
    board.dispose();
    final board2 = LayoutBoard();
    var resumed = 0;
    final vm2 = StudioViewModel(
      config: cfg,
      layout: board2,
      layoutOnly: true,
      streamChat: (r) async* {
        resumed++;
        yield result(resumed + 1);
      },
    );
    vm2.restore(saved);
    expect(vm2.newChat(), isTrue);
    addTearDown(() async {
      vm2.dispose();
      board2.dispose();
      await cfg.flushed();
      cfg.dispose();
    });
    expect(vm2.resumeLayoutPageTask(), isNull);
    for (var i = 0; i < 100 && vm2.layoutPageTask!.completed < 3; i++) {
      await pumpEventQueue();
    }
    expect(resumed, 2);
    expect(vm2.seriesLength, 3);
    expect(vm2.layoutPageTask!.completed, 3);
  });
}
