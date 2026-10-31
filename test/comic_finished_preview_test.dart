import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:penna/core/harness/comic/comic_export_service.dart';
import 'package:penna/ui/features/layout/comic_finished_preview.dart';

class PreviewService extends ComicExportService {
  PreviewService(this.versions, {this.local});
  final List<List<ComicExportVersion>> versions;
  final String? local;
  List<Map<String, Object?>>? exported;
  String? exportedDirection;
  @override
  Future<List<List<ComicExportVersion>>> findPreviewVersions(
    List<Map<String, Object?>> snapshots,
  ) async => versions;
  @override
  Future<List<List<ComicExportVersion>>> findVersions(
    List<Map<String, Object?>> snapshots,
  ) async => [
    for (final v in versions) v.where((i) => i.matchesSource).take(1).toList(),
  ];
  @override
  Future<String?> pickImage() async => local;
  @override
  Future<String?> pickOutputDirectory() async => r'D:\test-export';
  @override
  Future<Map<String, String>> exportComic({
    required List<Map<String, Object?>> pages,
    required String outputDir,
    required String title,
    required List<String> formats,
    required String readingDirection,
    void Function(String)? onProgress,
  }) async {
    exported = pages;
    exportedDirection = readingDirection;
    return {'cbz': r'D:\test-export\comic.cbz'};
  }
}

void main() {
  test('预览可读同一页旧稿，默认优先当前稿，导出严格匹配不受影响', () async {
    final root = Directory.systemTemp.createTempSync('penna-preview-history-');
    addTearDown(() => root.deleteSync(recursive: true));
    const source = {
      'z': 1e-7,
      'a': {'caption': '测试', 'items': []},
    };
    const hash =
        '6ac0d568ba25fc85f93f5966f3ac9c4a72ecc16165901f672bc05c380666b183';
    const context = {'workspace': 'qa', 'series': 1, 'page_number': 2};
    for (final pair in [
      ('current', hash, 2),
      ('previous', 'old-hash', 2),
      ('other', 'old-hash', 3),
    ]) {
      final dir = Directory('${root.path}/${pair.$1}')..createSync();
      File('${dir.path}/page.png').writeAsBytesSync([1]);
      File('${dir.path}/manifest.json')
          .writeAsStringSync(jsonEncode({'status': 'done'}));
      File('${dir.path}/page.json').writeAsStringSync(
        jsonEncode({
          'source_hash': pair.$2,
          'context': {...context, 'page_number': pair.$3},
        }),
      );
    }
    final service = ComicExportService(historyRoot: root.path);
    final snapshots = <Map<String, Object?>>[
      {'source': source, 'context': context},
    ];
    final preview = await service.findPreviewVersions(snapshots);
    expect(preview.single.length, 2);
    expect(preview.single.first.image, contains('current'));
    expect(preview.single.first.matchesSource, isTrue);
    expect(preview.single.last.matchesSource, isFalse);
    expect((await service.findVersions(snapshots)).single.length, 1);
  });

  late Directory images;
  late List<String> paths;
  final snapshots = <Map<String, Object?>>[
    for (var n = 1; n <= 3; n++)
      {
        'title': '测试$n',
        'page_number': n,
        'page_index': n + 8,
        'source': {'page': n},
        'context': {'page_number': n},
      },
  ];
  setUp(() {
    images = Directory.systemTemp.createTempSync('penna-preview-images-');
    final bytes = img.encodePng(
      img.Image(width: 16, height: 24)..clear(img.ColorRgb8(255, 255, 255)),
    );
    paths = [for (var n = 0; n < 4; n++) '${images.path}/$n.png'];
    for (final path in paths) {
      File(path).writeAsBytesSync(bytes);
    }
  });
  tearDown(() => images.deleteSync(recursive: true));

  Future<void> open(
    WidgetTester tester,
    PreviewService service, {
    ValueChanged<int>? edit,
    ValueChanged<int>? render,
    Size size = const Size(1400, 950),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showComicFinishedPreview(
                context,
                snapshots: snapshots,
                title: '日常漫画',
                service: service,
                onEditPage: edit,
                onRenderPage: render,
              ),
              child: const Text('打开预览'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开预览'));
    await tester.pumpAndSettle();
  }

  PreviewService service() => PreviewService([
    [
      ComicExportVersion(image: paths[0], label: '当前版本'),
      ComicExportVersion(image: paths[1], label: '旧版', matchesSource: false),
    ],
    [ComicExportVersion(image: paths[2], label: '第二页')],
    [],
  ], local: paths[3]);

  testWidgets('缩略图和键盘可翻页，双页同时显示两张成品', (tester) async {
    await open(tester, service());
    expect(find.byKey(ValueKey('page-${paths[0]}')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('page-${paths[2]}')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('finished-thumb-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('双页'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('page-${paths[0]}')), findsOneWidget);
    expect(find.byKey(ValueKey('page-${paths[2]}')), findsOneWidget);
    await tester.tap(find.byTooltip('放大'));
    await tester.pumpAndSettle();
    expect(find.text('125%'), findsOneWidget);
  });

  testWidgets('预览选择旧版和补图后，导出保持看到的三张图及页序', (tester) async {
    final fake = service();
    await open(tester, fake);
    await tester.tap(find.byKey(const ValueKey('finished-version-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旧稿 · 旧版').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('正在查看旧稿成品'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('finished-thumb-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择本地 PNG'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('阅读方向'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<bool>, '从左向右'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuButton<bool>>(find.byType(PopupMenuButton<bool>))
          .initialValue,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('finished-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('comic-export-directory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('comic-export-start')));
    await tester.pumpAndSettle();
    expect(fake.exported!.map((p) => p['image']), [
      paths[1],
      paths[2],
      paths[3],
    ]);
    expect(fake.exported!.map((p) => p['page_number']), [1, 2, 3]);
    expect(fake.exportedDirection, 'ltr');
  });

  testWidgets('修改和重做返回对应全局页签，不自动发生成请求', (tester) async {
    int? edited, rendered;
    await open(
      tester,
      service(),
      edit: (i) => edited = i,
      render: (i) => rendered = i,
    );
    await tester.tap(find.byKey(const ValueKey('finished-thumb-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('finished-render')));
    await tester.pumpAndSettle();
    expect(rendered, 10);
    expect(edited, isNull);
    expect(find.text('打开预览'), findsOneWidget);
    await tester.tap(find.text('打开预览'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('finished-thumb-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('finished-edit')));
    await tester.pumpAndSettle();
    expect(edited, 11);
  });

  testWidgets('窄窗口缺图仍可预览，不伪造成已生成，也不会布局溢出', (tester) async {
    await open(
      tester,
      PreviewService([[], [], []]),
      size: const Size(720, 720),
    );
    expect(find.text('第 1 页还没有成品'), findsOneWidget);
    expect(find.textContaining('0 / 3 页已有图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
