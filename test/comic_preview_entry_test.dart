import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/services/archive_store.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/layout/layout_page.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
  testWidgets('区域工作台直接提供成品预览入口', (tester) async {
    final cfg = tempConfig();
    await tester.runAsync(() async {
      cfg.update(
        cfg.config.copyWith(
          llms: [
            const LlmProfile(
              id: 'test',
              name: '本机',
              baseUrl: 'http://127.0.0.1:1/v1',
              model: 'test',
            ),
          ],
          activeLlmId: () => 'test',
        ),
      );
      await cfg.flushed();
    });
    final board = LayoutBoard();
    final vm = StudioViewModel(
      config: cfg,
      layout: board,
      streamChat: (_) => const Stream.empty(),
    );
    final chat = StudioViewModel(
      config: cfg,
      layout: board,
      layoutOnly: true,
      streamChat: (_) => const Stream.empty(),
    );
    final archive = ArchiveStore(File('${cfg.dir.path}/archive.json'));
    addTearDown(() {
      vm.dispose();
      chat.dispose();
      board.dispose();
      cfg.dispose();
    });
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutPage(
            board: board,
            vm: vm,
            chat: chat,
            config: cfg,
            archive: archive,
            onOpenStudio: () {},
            onOpenSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('成品预览'), findsOneWidget);
  });
}
