import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comic/comic_layout_catalog.dart';
import 'package:penna/core/harness/comic/novel_ai_designer.dart';
import 'package:penna/core/harness/providers/llm_http.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/models/novel_comic.dart';
import 'package:penna/ui/features/comic/comic_preview.dart';

Map<String, dynamic> aiResult(String id) => {
  'template_id': id,
  'title': '箱子落下',
  'intent': '危险逼近，随后放松',
  'choice_reason': '让动作占据首格，后两格承接手部和反应。',
  'alternatives': ['先给空站台建立空间', '先给手部突出危险'],
  'continuity': '三名成年快递员已接住箱子，仍在站台。',
  'cast': {'小蓝': '成年女性，蓝色工作夹克，深色马尾'},
  'panels': [
    for (var i = 0; i < comicLayoutById(id).panels.length; i++)
      {
        'desc': '第${i + 1}个独立动作瞬间',
        'camera': 'close',
        'dialogue': i == 0 ? ['接住！'] : [],
      },
  ],
};
AppConfig aiConfig() => const AppConfig(
  llms: [
    LlmProfile(
      id: 'local',
      name: '本机',
      baseUrl: 'http://127.0.0.1:8090/v1',
      model: 'bonsai',
    ),
  ],
  activeLlmId: 'local',
);

Map<String, dynamic> assetResult() => {
  'characters': [
    {
      'name': '小蓝',
      'aliases': ['蓝姐'],
      'identity': '成年女性',
      'appearance': '深色马尾',
      'outfit': '蓝色工作夹克',
      'personality': '未明确',
      'evidence': '三位成年快递员接住箱子',
      'visual_design': '无',
    },
  ],
  'locations': [],
  'props': [],
  'visual_notes': '漫画风格随作品设置。',
};

void main() {
  test('前期资产明确区分原文信息和视觉补设，并保留证据核对结果', () async {
    final ai = NovelAiDesigner(
      config: aiConfig,
      streamChat: (r) async* {
        yield jsonEncode({
          'characters': [
            {
              'name': '小蓝',
              'aliases': [],
              'identity': '成年快递员',
              'appearance': '未明确',
              'outfit': '蓝色工作夹克',
              'personality': '未明确',
              'evidence': '小蓝穿蓝色工作夹克',
              'visual_design': '补设：深色马尾',
            },
          ],
          'locations': [],
          'props': [],
          'visual_notes': '彩色漫画',
        });
      },
    );
    final assets = await ai.prepareAssets(
      options: const ComicOptions(),
      sourceText: '成年快递员小蓝穿蓝色工作夹克站在站台。',
      knownNames: [],
    );
    expect(assets['characters'], hasLength(1));
    expect(assets['characters'][0]['evidence_verified'], isTrue);
    expect(assets['characters'][0]['visual_design'], contains('补设'));
  });
  testWidgets('Luna实际创作的两页可转换为不同版面，排版预览可绘制', (tester) async {
    await tester.runAsync(() async {
      final loader = FontLoader('LXGW 975 Yuan SC')
        ..addFont(rootBundle.load('font/LXGW975YuanSC-500W.ttf'));
      await loader.load();
    });
    tester.view.physicalSize = const Size(1100, 1650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final samples = jsonDecode(
      File('test/fixtures/novel_luna_response.json').readAsStringSync(),
    ) as List;
    final geometry = <String>[];
    for (final (index, sample) in samples.indexed) {
      final page = decodeNovelAiPage(
        jsonEncode(sample),
        sourceText: '自写的成年快递员站台图书故事',
        seed: 20261102,
        style: 'color',
      );
      geometry.add(
        jsonEncode(
          (page['items'] as List)
              .where((p) => p['type'] == 'panel')
              .map((p) => p['bbox'])
              .toList(),
        ),
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 1024,
                  height: 1536,
                  child: ComicPreview(
                    page: page,
                    selected: null,
                    onSelect: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final output = Platform.environment['PENNA_LUNA_PREVIEW_OUT'];
      if (output != null) {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$output/layout-page-${index + 1}.png');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    expect(geometry.toSet(), hasLength(2));
  });
  test('AI选择真实三格几何，台词进入Layout，不加no text负面约束', () async {
    LlmRequest? sent;
    final ai = NovelAiDesigner(
      config: aiConfig,
      streamChat: (r) async* {
        sent = r;
        yield jsonEncode(aiResult('L034'));
      },
    );
    final page = await ai.design(
      options: const ComicOptions(),
      sourceText: '她喊道：“接住！”',
      pageNumber: 2,
      pageTotal: 3,
      memories: ['上一页箱子倾倒。'],
      cast: {},
    );
    expect(sent!.messages.last['content'], contains('上一页箱子倾倒'));
    expect(sent!.messages.first['content'], contains('L121'));
    expect(page['layout_id'], 'L034');
    expect(
      (page['items'] as List).where((i) => i['type'] == 'panel'),
      hasLength(3),
    );
    expect(jsonEncode(page['layout']), contains('接住！'));
    expect(jsonEncode(page), isNot(contains('No lettering')));
    expect(page['visual_review'], 'not_performed');
  });
  test('未知模板或格数不匹配必须失败，不退回固定四格', () async {
    for (final bad in [
      {'template_id': 'fake'},
      {...aiResult('L034'), 'panels': []},
    ]) {
      final ai = NovelAiDesigner(
        config: aiConfig,
        streamChat: (r) async* {
          yield jsonEncode(bad);
        },
      );
      await expectLater(
        ai.design(
          options: const ComicOptions(),
          sourceText: '原文',
          pageNumber: 1,
          pageTotal: 1,
          memories: [],
          cast: {},
        ),
        throwsFormatException,
      );
    }
  });
}
