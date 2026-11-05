import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/integration_settings.dart';
import 'package:penna/ui/features/settings/settings_comic_section.dart';

void main() {
  testWidgets('用户修改ComfyUI地址保存后，后续连接读取新地址', (tester) async {
    final home = Directory.systemTemp.createTempSync('comic-connection');
    final before = IntegrationSettings.current;
    IntegrationSettings.current = IntegrationSettings(
      home: home.path,
      bundleRoot: home.path,
    );
    addTearDown(() async {
      IntegrationSettings.current = before;
      await home.delete(recursive: true);
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ComicConnectionSection()),
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextField).at(1),
      'http://localhost:9001',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('保存配置'));
      for (
        var i = 0;
        i < 50 && !File(IntegrationSettings.current.configPath).existsSync();
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    final loaded = IntegrationSettings(home: home.path, bundleRoot: home.path)
      ..load();
    expect(loaded.comfyUrl, 'http://localhost:9001');
    expect(loaded.data['mode'], 'external');
  });
}
