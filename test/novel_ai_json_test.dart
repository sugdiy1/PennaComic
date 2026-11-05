import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comic/novel_ai_designer.dart';
import 'package:penna/data/models/novel_comic.dart';

import 'novel_ai_designer_test.dart' show aiConfig, aiResult, assetResult;

void main() {
  test('资产JSON尾逗号可恢复，不改写字符串内的逗号和引号', () async {
    final payload = assetResult();
    payload['visual_notes'] = r'对白原样：,} 和 ,] 以及 \"引号\"';
    var calls = 0;
    final ai = NovelAiDesigner(
      config: aiConfig,
      streamChat: (_) async* {
        calls++;
        final text = jsonEncode(payload);
        yield '```json\n${text.substring(0, text.length - 1)},}\n```';
      },
    );
    final result = await ai.prepareAssets(
      options: const ComicOptions(),
      sourceText: '小蓝穿蓝色工作夹克',
      knownNames: [],
    );
    expect(result['visual_notes'], payload['visual_notes']);
    expect(calls, 1);
  });
  test('资产JSON损坏后纠错一次，原文仍包含在请求中', () async {
    var calls = 0;
    final ai = NovelAiDesigner(
      config: aiConfig,
      streamChat: (request) async* {
        calls++;
        expect(
          request.messages.any((m) => m['content']!.contains('测试原文')),
          isTrue,
        );
        yield calls == 1 ? '{"characters": [}' : jsonEncode(assetResult());
      },
    );
    final result = await ai.prepareAssets(
      options: const ComicOptions(),
      sourceText: '测试原文',
      knownNames: [],
    );
    expect(calls, 2);
    expect(result['characters'], hasLength(1));
  });
  test('分镜JSON损坏后纠错一次并继续严格校验布局', () async {
    var calls = 0;
    final ai = NovelAiDesigner(
      config: aiConfig,
      streamChat: (_) async* {
        yield ++calls == 1 ? '{"panels": [}' : jsonEncode(aiResult('L034'));
      },
    );
    final result = await ai.design(
      options: const ComicOptions(),
      sourceText: '测试原文',
      pageNumber: 1,
      pageTotal: 1,
      memories: [],
      cast: {},
    );
    expect(calls, 2);
    expect(result['layout_id'], 'L034');
  });
  test('持续错误只重试一次，不能静默补造剧情', () async {
    var calls = 0;
    final ai = NovelAiDesigner(
      config: aiConfig,
      streamChat: (_) async* {
        calls++;
        yield '{"characters": [}';
      },
    );
    await expectLater(
      ai.prepareAssets(
        options: const ComicOptions(),
        sourceText: '测试原文',
        knownNames: [],
      ),
      throwsFormatException,
    );
    expect(calls, 2);
  });
}
