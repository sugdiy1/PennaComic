import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comic/novel_ai_designer.dart';
import 'package:penna/data/models/novel_comic.dart';
import 'package:penna/ui/features/comic/novel_comic_model.dart';

import 'novel_ai_designer_test.dart' show aiConfig, aiResult, assetResult;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('novel-ai-'));
  tearDown(() => dir.deleteSync(recursive: true));
  test('第二页失败保留第一页，重启后续做只调用剩余页，支持单页改稿与接力', () async {
    var calls = 0, fail = true;
    final requests = <String>[];
    NovelAiDesigner designer() => NovelAiDesigner(
      config: aiConfig,
      streamChat: (r) async* {
        if (jsonDecode(r.messages.last['content']!)['task'] ==
            'prepare_assets') {
          yield jsonEncode(assetResult());
          return;
        }
        calls++;
        requests.add(r.messages.last['content']!);
        if (calls == 2 && fail) throw const FormatException('模拟模型失败');
        final answer = aiResult(calls == 1 ? 'L001' : 'L034');
        if (calls > 1) answer['cast'] = {'蓝姐': '错误的新设定：白发红衣'};
        yield jsonEncode(answer);
      },
    );
    final input = File('${dir.path}/story.txt')
      ..writeAsStringSync('成年快递员在站台接住箱子。');
    Future<Map<String, dynamic>> book(
      String path,
      ComicOptions options,
    ) async => {
      'book': '站台',
      'chapters': [
        {
          'index': 1,
          'title': '第一章',
          'volume': '第一卷',
          'text': '箱子倾倒。\n\n三位成年快递员接住箱子。',
        },
      ],
    };
    final model = NovelComicModel(
      dir: dir,
      designer: designer(),
      readBook: book,
    );
    model.setOptions(model.options.copyWith(pagesPerChapter: 2));
    await model.importNovel(input.path);
    await model.planCurrent();
    expect(model.current!.pages, hasLength(1));
    expect(model.current!.assets['status'], 'done');
    expect(model.current!.assets['characters'], hasLength(1));
    expect(model.error, contains('模拟模型失败'));
    final first = model.current!.pages.first.pageJson;
    model.dispose();
    fail = false;
    final restored = NovelComicModel(
      dir: dir,
      designer: designer(),
      readBook: book,
    );
    await restored.load();
    await restored.planCurrent();
    expect(restored.current!.pages, hasLength(2));
    expect(restored.current!.assets['characters'], hasLength(1));
    expect(calls, 3);
    expect(restored.current!.pages.first.pageJson, first);
    expect(requests.last, contains('已接住箱子'));
    expect(restored.current!.aiState['cast']['小蓝'], contains('蓝色工作夹克'));
    await restored.selectPage(restored.current!.pages.last.id);
    restored.editAsset('characters', '小蓝', 'visual_design', '用户指定：黑色短发');
    expect(restored.current!.assets['characters'][0]['manual_locked'], isTrue);
    restored.editItem('pn_1', 'desc', '修正后的独立画格');
    final snapshot = await restored.relaySnapshot();
    expect(jsonEncode(snapshot['source']), contains('修正后的独立画格'));
    expect(jsonEncode(snapshot['source']), contains('黑色短发'));
    expect(jsonEncode(snapshot['source']), isNot(contains('错误的新设定')));
    expect(snapshot['series_pages'], hasLength(2));
    expect(jsonEncode(snapshot), isNot(contains('No lettering')));
    restored.dispose();
  });
}
