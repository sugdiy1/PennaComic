import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comic/comic_export_service.dart';
import 'package:penna/ui/features/layout/comic_export_dialog.dart';

class FakeComicExportService extends ComicExportService {
  FakeComicExportService(this.versions);
  final List<List<ComicExportVersion>> versions;
  List<Map<String, Object?>>? capturedPages;
  List<String>? capturedFormats;
  String? capturedDirection;
  Completer<Map<String, String>>? pending;

  @override
  Future<List<List<ComicExportVersion>>> findVersions(
    List<Map<String, Object?>> snapshots,
  ) async => versions;

  @override
  Future<String?> pickOutputDirectory() async => r'E:\exports';

  @override
  Future<String?> pickImage() async => r'E:\local-page.png';

  @override
  Future<Map<String, String>> exportComic({
    required List<Map<String, Object?>> pages,
    required String outputDir,
    required String title,
    required List<String> formats,
    required String readingDirection,
    void Function(String)? onProgress,
  }) async {
    capturedPages = pages;
    capturedFormats = formats;
    capturedDirection = readingDirection;
    onProgress?.call('正在打包…');
    if (pending != null) return pending!.future;
    return {'cbz': r'E:\exports\test.cbz', 'pdf': r'E:\exports\test.pdf'};
  }
}

final snapshots = <Map<String, Object?>>[
  {
    'title': '先读这一页',
    'source': {'summary': 'Synthetic page A'},
    'context': {'workspace': 'test', 'series': 'sample', 'page_number': 12},
  },
  {
    'title': '再读这一页',
    'source': {'summary': 'Synthetic page B'},
    'context': {'workspace': 'test', 'series': 'sample', 'page_number': 2},
  },
];

void main() {
  test('历史匹配遵循Python中文浮点哈希和页面身份，只接受已完成版本', () async {
    final root = await Directory.systemTemp.createTemp(
      'penna-export-discovery-',
    );
    addTearDown(() => root.delete(recursive: true));
    const hash =
        '6ac0d568ba25fc85f93f5966f3ac9c4a72ecc16165901f672bc05c380666b183';
    final context = {
      'workspace': 'test',
      'series': 'sample',
      'page_number': 12,
    };
    Future<void> fixture(
      String name, {
      String status = 'done',
      int pageNumber = 12,
      String sourceHash = hash,
    }) async {
      final job = await Directory('${root.path}/$name').create();
      await File('${job.path}/page.png').writeAsBytes([1]);
      await File('${job.path}/manifest.json')
          .writeAsString(jsonEncode({'status': status}));
      await File('${job.path}/page.json').writeAsString(
        jsonEncode({
          'source_hash': sourceHash,
          'context': {...context, 'page_number': pageNumber},
        }),
        encoding: utf8,
      );
    }

    await fixture('valid');
    await fixture('unfinished', status: 'rendering');
    await fixture('wrong-page', pageNumber: 2);
    await fixture('wrong-source', sourceHash: 'different');
    final service = ComicExportService(historyRoot: root.path);
    final result = await service.findVersions([
      {
        'source': {
          'z': 1e-7,
          'a': {'caption': '测试', 'items': []},
        },
        'context': context,
      },
      {
        'source': {
          'z': 1e-7,
          'a': {'caption': '测试', 'items': []},
        },
        'context': {...context, 'page_number': 99},
      },
    ]);
    expect(result.map((p) => p.length), [1, 0]);
    expect(
      result.first.single.jobDir,
      '${root.path}${Platform.pathSeparator}valid',
    );
  });

  Future<void> show(WidgetTester tester, ComicExportService service) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ComicExportDialog(
            snapshots: snapshots,
            title: '测试漫画',
            service: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('comic-export-directory')));
    await tester.pumpAndSettle();
  }

  testWidgets('缺页时禁用导出并明确指出缺图页，本地PNG可以补齐', (tester) async {
    final fake = FakeComicExportService([
      [const ComicExportVersion(image: r'E:\first.png', label: '版本一')],
      [],
    ]);
    await show(tester, fake);
    expect(find.textContaining('缺少成品图片'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('comic-export-start')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('comic-export-local-1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('comic-export-start')),
          )
          .onPressed,
      isNotNull,
    );
    expect(fake.capturedPages, isNull);
  });

  testWidgets('导出按传入页序提交选定旧版本和格式，不按页码重排', (tester) async {
    final fake = FakeComicExportService([
      [
        const ComicExportVersion(image: r'E:\new.png', label: '新版本'),
        const ComicExportVersion(image: r'E:\old.png', label: '旧版本'),
      ],
      [const ComicExportVersion(image: r'E:\second.png', label: '第二页版本')],
    ]);
    await show(tester, fake);
    await tester.tap(find.byKey(const ValueKey('comic-export-version-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旧版本').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('comic-export-start')));
    await tester.pumpAndSettle();
    expect(fake.capturedPages!.map((p) => p['image']), [
      r'E:\old.png',
      r'E:\second.png',
    ]);
    expect(fake.capturedPages!.map((p) => p['page_number']), [12, 2]);
    expect(fake.capturedFormats, ['cbz', 'pdf']);
    expect(fake.capturedDirection, 'rtl');
    expect(find.text('导出完成：2 页'), findsOneWidget);
  });

  testWidgets('导出期间锁定按钮，失败后显示原因并允许重试', (tester) async {
    final fake = FakeComicExportService([
      [const ComicExportVersion(image: r'E:\first.png', label: '第一页版本')],
      [const ComicExportVersion(image: r'E:\second.png', label: '第二页版本')],
    ])..pending = Completer<Map<String, String>>();
    await show(tester, fake);
    await tester.tap(find.byKey(const ValueKey('comic-export-start')));
    await tester.pump();
    expect(find.text('正在打包…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('comic-export-start')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '关闭'))
          .onPressed,
      isNull,
    );
    fake.pending!.completeError(StateError('第2页图片损坏'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第2页图片损坏'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('comic-export-start')),
          )
          .onPressed,
      isNotNull,
    );
  });
}
