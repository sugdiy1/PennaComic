import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comic/novel_ai_designer.dart';
import 'package:penna/ui/features/comic/novel_comic_model.dart';
import 'package:penna/ui/features/comic/novel_comic_page.dart';

import 'novel_ai_designer_test.dart' show aiConfig;

void main() {
  testWidgets('小说界面能查看编辑文字资产、选择AI连接和浏览121套布局', (tester) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    tester.view.physicalSize = const Size(1440, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp.createTempSync('novel-ai-ui-');
    final lunaAssets = jsonDecode(
      File('test/fixtures/novel_luna_assets.json').readAsStringSync(),
    );
    final lunaPages = jsonDecode(
      File('test/fixtures/novel_luna_response.json').readAsStringSync(),
    ) as List;
    final ai = NovelAiDesigner(
      config: aiConfig,
      streamChat: (request) async* {
        yield jsonEncode(
          jsonDecode(request.messages.last['content']!)['task'] ==
                  'prepare_assets'
              ? lunaAssets
              : lunaPages.first,
        );
      },
    );
    final model = NovelComicModel(
      dir: dir,
      designer: ai,
      readBook: (path, options) async => {
        'book': '站台',
        'chapters': [
          {'title': '第一章', 'volume': '第一卷', 'index': 1, 'text': '三位成年快递员接住箱子。'},
        ],
      },
    );
    addTearDown(() {
      model.dispose();
      dir.deleteSync(recursive: true);
    });
    await tester.runAsync(() async {
      final file = File('${dir.path}/story.txt')
        ..writeAsStringSync('三位成年快递员接住箱子。');
      model.setOptions(model.options.copyWith(pagesPerChapter: 1));
      await model.importNovel(file.path);
      await model.planCurrent();
    });
    expect(model.error, isNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
          ),
        ),
        home: Scaffold(body: NovelComicPage(model: model)),
      ),
    );
    expect(find.byTooltip('一键接力出图'), findsOneWidget);
    await tester.tap(find.text('查看/复制当前页提示词'));
    await tester.pumpAndSettle();
    expect(find.text('自行复制提示词'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('copy-novel-prompt')));
    await tester.pump();
    expect(copiedText, contains('bbox_coord_space'));
    await tester.tap(find.text('用我的工作流'));
    await tester.pumpAndSettle();
    expect(model.options.deliveryMode, 'workflow');
    expect(find.text('用工作流出图'), findsOneWidget);
    await tester.tap(find.text('文字资产'));
    await tester.pumpAndSettle();
    expect(find.text('前期文字资产'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('asset-characters-小蓝')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-field-characters-小蓝-visual_design')),
      '补设：黑色短发',
    );
    await tester.pump();
    expect(model.current!.assets['characters'][0]['visual_design'], '补设：黑色短发');
    await tester.tap(find.text('返回页面'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('121套布局目录'));
    await tester.pumpAndSettle();
    expect(find.text('121套漫画布局 · AI按故事自动匹配'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '悬念');
    await tester.pumpAndSettle();
    expect(find.textContaining('横向四拍'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
