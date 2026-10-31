import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/core/harness/comic/layout_context_policy.dart';
import 'package:penna/core/harness/providers/llm_http.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
  test('新建与单页修改锁定目标，误放在画格中的台词转独立文本框', () {
    expect(layoutTargetFor('新建第4页，不改旧页', currentPage: 3, pageCount: 3), 'new');
    expect(
      layoutTargetFor('只修改当前第2页，不要新建', currentPage: 2, pageCount: 5),
      'current',
    );
    expect(layoutTargetFor('修改第2页', currentPage: 4, pageCount: 5), '2');
    final tags = layoutEnvelopeToTags(
      jsonEncode({
        'pages': [
          {
            'target': 'new',
            'name': '页"<>名',
            'layout': {
              'items': [
                {
                  'name': '第1格',
                  'label': 'object',
                  'caption': 'A panel',
                  'bbox': [0, 0, 832, 600],
                  'text': '已经到了。',
                },
              ],
            },
          },
        ],
      }),
      forcedTarget: 'current',
    );
    expect(tags, isNot(contains('page="新"')));
    expect(tags, contains('"label":"text"'));
    expect(tags, contains('已经到了。'));
    final schema = layoutSchemaFor('new');
    final pages = (schema['properties'] as Map)['pages'] as Map;
    expect(pages['maxItems'], 1);
    expect(((pages['items'] as Map)['properties'] as Map)['target']['enum'], [
      'new',
    ]);
  });
  test('本地助手对仅说完成的输出自动修复一次，失败不改画板', () async {
    final cfg = tempConfig();
    cfg.update(
      cfg.config.copyWith(
        llms: [
          const LlmProfile(
            id: 'bonsai',
            name: 'Bonsai',
            baseUrl: 'http://127.0.0.1:8090/v1',
            model: 'ternary-bonsai-27b',
          ),
        ],
        activeLlmId: () => 'bonsai',
      ),
    );
    final board = LayoutBoard();
    final seen = <LlmRequest>[];
    final vm = StudioViewModel(
      config: cfg,
      layout: board,
      layoutOnly: true,
      streamChat: (r) async* {
        seen.add(r);
        yield '已经排好了。';
      },
    );
    await vm.sendAndWait('请画第三页漫画：成年快递员在雨中找到遗失包裹。');
    expect(seen.length, 2);
    expect(vm.messages.last.failed, isTrue);
    expect(board.layout.isEmpty, isTrue);
    expect(seen.first.messages.first['content'], contains('【用户当前的 Preset】'));
    vm.dispose();
    board.dispose();
    await cfg.flushed();
    cfg.dispose();
  });
  test('本地精简协议保留坐标台词和角色，长度不随历史页面叠加', () {
    final layout = Layout(
      width: 832,
      height: 1216,
      caption: '雨夜车站',
      boxes: [
        const LayoutBox(
          left: 50,
          top: 50,
          right: 700,
          bottom: 800,
          name: '林舟·1',
          label: 'character',
          caption: 'Adult man holding an umbrella',
        ),
        const LayoutBox(
          left: 500,
          top: 80,
          right: 760,
          bottom: 240,
          name: '台词',
          label: 'text',
          text: '等到你了。',
        ),
      ],
    );
    final system = localLayoutSystem(
      layout: layout,
      series: '雨夜',
      page: 4,
      style: 'Monochrome manga',
      cast: {'林舟': 'Adult man, 30 years old, black hair, blue raincoat.'},
      siblings: List.generate(100, (i) => '第$i页：车站'),
    );
    expect(system.length, lessThan(8000));
    expect(system, contains('等到你了。'));
    expect(system, contains('Adult man, 30 years old'));
    final json = RegExp(r'<current-layout>([\s\S]*?)</current-layout>')
        .firstMatch(system)!
        .group(1)!;
    expect((jsonDecode(json)['items'] as List).first['bbox'], [
      50,
      50,
      700,
      800,
    ]);
    expect(system, isNot(contains('第99页')));
  });
  test('长历史不会越积越大，原始列表不被修改，图片索引跟随消息', () {
    final original = <Map<String, String>>[
      {'role': 'system', 'content': 'old rules'},
      for (var i = 0; i < 30; i++)
        {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '第$i条 ${'长说明' * 1000}',
        },
      {'role': 'user', 'content': '只修改当前页的雨伞为红色，其他元素不动。'},
    ];
    final copied = jsonEncode(original);
    final result = compactLayoutMessages(original, {
      31: [
        (mime: 'image/png', bytes: Uint8List.fromList([1, 2])),
      ],
    }, 'short rules');
    expect(result.messages.length, lessThanOrEqualTo(9));
    expect(result.messages.last['content'], contains('雨伞为红色'));
    expect(result.images.keys.single, result.messages.length - 1);
    expect(jsonEncode(original), copied);
    expect(
      result.messages.fold<int>(0, (n, m) => n + m['content']!.length),
      lessThan(15000),
    );
  });
  test('画板成功必须有可解析布局，不能只回答已经完成', () {
    expect(requestsLayoutAction('请生成第三页漫画'), isTrue);
    expect(requestsLayoutAction('你好'), isFalse);
    expect(requestsLayoutAction('画风是什么？只解释，不修改画板。'), isFalse);
    expect(
      hasValidLayoutAction('已经给你排好四格了。', width: 832, height: 1216),
      isFalse,
    );
    expect(
      hasValidLayoutAction(
        '<layout>{坏的 JSON}</layout>',
        width: 832,
        height: 1216,
      ),
      isFalse,
    );
    expect(
      hasValidLayoutAction(
        '<layout>{"summary":{"caption":"A station"},"items":[{"name":"第1格","label":"object","caption":"A panel.","bbox":[0,0,400,500]}],"bbox_coord_space":"abs","bbox_format":"xyxy"}</layout>',
        width: 832,
        height: 1216,
      ),
      isTrue,
    );
  });
}
