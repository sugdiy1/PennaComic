import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comic/penna_relay_service.dart';
import 'package:penna/core/harness/comic/comic_export_service.dart';
import 'package:penna/ui/features/layout/penna_relay_dialog.dart';

class FakeRelay extends PennaRelayService {
  final events = StreamController<RelayEvent>();
  int calls = 0;
  Map<String, Object?>? captured;
  @override
  Stream<RelayEvent> run(
    Map<String, Object?> snapshot, {
    String? resume,
    String? cancelFile,
  }) {
    calls++;
    captured = snapshot;
    return events.stream;
  }

  @override
  Future<void> restoreChat() async {}
  @override
  Future<List<String>> listLoras() async => [
    'moss_Lineart.safetensors',
    'muqiu_moss.safetensors',
  ];
  @override
  Future<Map<String, dynamic>> readSettings() async => {};
  @override
  Future<String?> findPendingBatch(Map<String, Object?> request) async => null;
}

class EmptyPreviewService extends ComicExportService {
  const EmptyPreviewService();
  @override
  Future<List<List<ComicExportVersion>>> findPreviewVersions(
    List<Map<String, Object?>> snapshots,
  ) async => [for (final _ in snapshots) <ComicExportVersion>[]];
}

void main() {
  testWidgets('接力结果进入成品预览也可重做选定页，关闭两层界面后回调', (tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = FakeRelay();
    int? rendered;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PennaRelayDialog(
                  snapshot: {
                    'title': '测试第2页',
                    'width': 832,
                    'height': 1216,
                    'source': {},
                    'layout': {},
                    'page_number': 2,
                    'page_index': 9,
                  },
                  service: fake,
                  previewService: const EmptyPreviewService(),
                  onRenderPage: (i) => rendered = i,
                ),
              ),
              child: const Text('打开接力'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开接力'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始接力'));
    await tester.pump();
    fake.events.add(
      const RelayEvent(
        stage: 'done',
        message: '完成',
        image: 'missing-test-image.png',
      ),
    );
    await fake.events.close();
    await tester.pumpAndSettle();
    await tester.tap(find.text('成品预览'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('finished-render')));
    await tester.pumpAndSettle();
    expect(rendered, 9);
    expect(find.text('打开接力'), findsOneWidget);
    expect(fake.calls, 1);
  });
  testWidgets('批量只提交勾选页，整批完成后可定位指定页修改', (tester) async {
    final fake = FakeRelay();
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? edited;
    final pages = [
      for (var n = 1; n <= 3; n++)
        <String, Object?>{
          'title': '测试$n',
          'page_number': n,
          'page_index': n + 6,
          'width': 832,
          'height': 1216,
          'source': {'page': n},
          'layout': {},
          'context': {'page_number': n},
        },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PennaRelayDialog(
                  snapshot: {
                    ...pages.first,
                    'series_pages': pages,
                    'series_title': '测试系列',
                  },
                  service: fake,
                  onEditPage: (i) => edited = i,
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多页批量'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('relay-page-2')));
    await tester.pump();
    await tester.tap(find.text('开始接力'));
    await tester.pump();
    expect(fake.calls, 1);
    expect((fake.captured!['pages'] as List).map((p) => p['page_number']), [
      1,
      3,
    ]);
    expect(
      tester
          .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .onSelectionChanged,
      isNull,
    );
    fake.events.add(
      RelayEvent(
        stage: 'page_done',
        message: '第1页完成',
        batchDir: 'batch',
        pages: [
          {
            'number': 1,
            'status': 'done',
            'image': 'first.png',
            'context': {'page_number': 1},
          },
          {
            'number': 2,
            'status': 'saved',
            'context': {'page_number': 3},
          },
        ],
      ),
    );
    await tester.pump();
    expect(find.text('正在接力…'), findsOneWidget);
    fake.events.add(
      RelayEvent(
        stage: 'done',
        message: '整批完成',
        batchDir: 'batch',
        pages: [
          {
            'number': 1,
            'status': 'done',
            'image': 'first.png',
            'context': {'page_number': 1},
          },
          {
            'number': 2,
            'status': 'done',
            'image': 'third.png',
            'context': {'page_number': 3},
          },
        ],
      ),
    );
    await fake.events.close();
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 1 页 · 完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改此页分镜'));
    await tester.pumpAndSettle();
    expect(edited, 7);
  });
  test('逐行进度解析保留中文、任务目录和结果图', () {
    final event = RelayEvent.fromJson({
      'stage': 'done',
      'message': '接力完成',
      'job_dir': r'D:\MMD\茶凉以后',
      'image': r'D:\MMD\茶凉以后\page.png',
    });
    expect(event.stage, 'done');
    expect(event.message, '接力完成');
    expect(event.image, endsWith('page.png'));
  });

  testWidgets('开始接力只提交一次，生成时禁用开始和关闭，参数来自当前页', (tester) async {
    final fake = FakeRelay();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PennaRelayDialog(
            snapshot: {
              'title': '茶凉以后',
              'width': 832,
              'height': 1216,
              'layout': <String, Object?>{},
              'source': <String, Object?>{},
            },
            service: fake,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('lora-check-muqiu_moss.safetensors')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('lora-weight-muqiu_moss.safetensors-null')),
      '0.3',
    );
    await tester.tap(find.text('开始接力'));
    await tester.pump();
    expect(fake.calls, 1);
    expect(fake.captured!['title'], '茶凉以后');
    expect((fake.captured!['settings'] as Map)['loras'], [
      {'name': 'moss_Lineart.safetensors', 'strength': .85},
      {'name': 'muqiu_moss.safetensors', 'strength': .3},
    ]);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '正在接力…'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '关闭'))
          .onPressed,
      isNull,
    );
    fake.events.add(
      RelayEvent.fromJson({'stage': 'error', 'message': 'ComfyUI 暂不可用'}),
    );
    await fake.events.close();
    await tester.pumpAndSettle();
    expect(find.text('ComfyUI 暂不可用'), findsOneWidget);
    expect(find.text('重试接力'), findsOneWidget);
  });
}
