import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comic/novel_ai_designer.dart';
import 'package:penna/core/harness/comic/novel_prompt_export.dart';
import 'package:penna/core/harness/layout.dart';

import 'novel_ai_designer_test.dart' show aiResult;

void main() {
  test('手动复制包保留整页、逐格、角色文字设定和台词，不调用任何服务', () {
    final page = decodeNovelAiPage(
      jsonEncode(aiResult('L034')),
      sourceText: '她喊道：“接住！”',
      seed: 42,
      style: 'color',
    );
    final layout = Layout.fromJson(
      Map<String, dynamic>.from(page['layout'] as Map),
    );
    final pack = buildNovelPromptPackage(page, layout);
    expect(pack['panels'], hasLength(3));
    expect(pack['whole_page_prompt'], contains('蓝色工作夹克'));
    expect(pack['markdown'], contains('接住！'));
    for (final panel in pack['panels'] as List) {
      final prompt = jsonDecode(panel['prompt'] as String) as Map;
      expect(prompt['summary']['canvas'], 'single');
      expect(panel['prompt'], isNot(contains('No lettering')));
    }
    final first = (pack['panels'] as List).first;
    expect(
      jsonDecode(first['prompt'])['items'].where((i) => i['label'] == 'text'),
      hasLength(1),
    );
  });
}
