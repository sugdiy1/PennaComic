import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comic/layout_context_policy.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/core/harness/providers/llm_http.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
  test('本地分镜恢复原有系统提示且不强制每页格数或台词数', () async {
    final cfg = tempConfig();
    cfg.update(
      cfg.config.copyWith(
        llms: [
          const LlmProfile(
            id: 'local',
            name: 'local',
            baseUrl: 'http://127.0.0.1:8090/v1',
            model: 'bonsai',
          ),
        ],
        activeLlmId: () => 'local',
      ),
    );
    final board = LayoutBoard();
    LlmRequest? request;
    final vm = StudioViewModel(
      config: cfg,
      layout: board,
      layoutOnly: true,
      streamChat: (r) async* {
        request = r;
        yield '<layout>{"summary":{"caption":"test"},"items":[],"bbox_coord_space":"abs","bbox_format":"xyxy"}</layout>';
      },
    );
    addTearDown(() async {
      vm.dispose();
      board.dispose();
      await cfg.flushed();
      cfg.dispose();
    });
    await vm.sendAndWait('画一页没有对白的单幅大画面。');
    final system = request!.messages.first['content']!;
    expect(system, contains('【用户当前的 Preset】'));
    expect(system, isNot(contains('漫画每页 4–6 格')));
    expect(system, isNot(contains('每页至少4格、2条对白')));
  });
  test('远程主模型成功澄清时不因备用本地模型自动修复', () async {
    final cfg = tempConfig();
    cfg.update(
      cfg.config.copyWith(
        llms: [
          const LlmProfile(
            id: 'remote',
            name: 'remote',
            baseUrl: 'https://example.invalid/v1',
            model: 'remote',
          ),
          const LlmProfile(
            id: 'local',
            name: 'local',
            baseUrl: 'http://127.0.0.1:8090/v1',
            model: 'bonsai',
          ),
        ],
        activeLlmId: () => 'remote',
      ),
    );
    final board = LayoutBoard();
    final requests = <LlmRequest>[];
    final vm = StudioViewModel(
      config: cfg,
      layout: board,
      layoutOnly: true,
      streamChat: (request) async* {
        requests.add(request);
        yield '需要先确认你想使用哪位角色。';
      },
    );
    addTearDown(() async {
      vm.dispose();
      board.dispose();
      await cfg.flushed();
      cfg.dispose();
    });
    await vm.sendAndWait('请画一页漫画。');
    expect(requests, hasLength(1));
    expect(requests.single.model, 'remote');
    expect(requests.single.layoutSchema, isNull);
    expect(vm.messages.last.failed, isFalse);
  });

  test('要求其他页不修改仍保留当前页修改动作', () {
    expect(requestsLayoutAction('请修改当前页，其他页不修改。'), isTrue);
    expect(requestsLayoutAction('只解释这张画，不修改画板。'), isFalse);
    expect(requestsLayoutAction('这是什么画风？'), isFalse);
    expect(requestsLayoutAction('能解释一下这个布局吗？'), isFalse);
  });

  test('当前在第一页时指定修改第二页，请求携带第二页完整布局', () async {
    final cfg = tempConfig();
    cfg.update(
      cfg.config.copyWith(
        llms: [
          const LlmProfile(
            id: 'local',
            name: 'local',
            baseUrl: 'http://127.0.0.1:8090/v1',
            model: 'bonsai',
          ),
        ],
        activeLlmId: () => 'local',
      ),
    );
    final board = LayoutBoard();
    final requests = <LlmRequest>[];
    final vm = StudioViewModel(
      config: cfg,
      layout: board,
      layoutOnly: true,
      streamChat: (request) async* {
        requests.add(request);
        // Synthetic response only: no HTTP, actual model, or GPU calls.
        yield '<layout page="2">{"summary":{"caption":"Edited second page"},'
            '"items":[{"name":"second-panel","label":"object",'
            '"caption":"A synthetic panel","bbox":[0,0,400,400]}],'
            '"bbox_coord_space":"abs","bbox_format":"xyxy"}</layout>';
      },
    );
    addTearDown(() async {
      vm.dispose();
      board.dispose();
      await cfg.flushed();
      cfg.dispose();
    });
    board.replace(
      const Layout(
        caption: 'UNIQUE_FIRST_PAGE',
        boxes: [
          LayoutBox(
            left: 0,
            top: 0,
            right: 400,
            bottom: 400,
            name: 'first-panel',
            label: 'object',
            caption: 'First panel',
          ),
        ],
      ),
    );
    vm.addPage();
    board.replace(
      const Layout(
        caption: 'UNIQUE_SECOND_PAGE',
        boxes: [
          LayoutBox(
            left: 20,
            top: 40,
            right: 600,
            bottom: 800,
            name: 'second-panel',
            label: 'object',
            caption: 'Second panel',
          ),
        ],
      ),
    );
    vm.openPage(0);
    await vm.sendAndWait('只修改第2页的动作，保留该页全部框和其他内容。');

    expect(requests, hasLength(1));
    expect(requests.single.layoutTarget, '2');
    final system = requests.single.messages.first['content']!;
    final current = RegExp(r'<current-layout>([\s\S]*?)</current-layout>')
        .firstMatch(system)![1]!;
    final layout = jsonDecode(current) as Map;
    expect((layout['summary'] as Map)['caption'], 'UNIQUE_SECOND_PAGE');
    expect((layout['items'] as List).single['name'], 'second-panel');
    expect((layout['items'] as List).single['bbox'], [20, 40, 600, 800]);
  });
}
