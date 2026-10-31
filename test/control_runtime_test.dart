import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/agent_control/control_runtime.dart';
import 'package:penna/core/agent_control/penna_tools.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
  test('storage failure shows actual directory and allows retry without stale disabled state', () async {
    final dir = Directory.systemTemp.createTempSync('runtime-failure');
    final blocked = File('${dir.path}/blocked')
      ..writeAsStringSync('not a directory');
    final board = LayoutBoard();
    final vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      layoutOnly: true,
      layout: board,
    );
    final runtime = ControlRuntime();
    runtime.attach(PennaTools(vm: vm, home: Directory('${blocked.path}/home')));
    await runtime.setEnabled(true);
    expect(runtime.changing, false);
    expect(runtime.running, false);
    expect(runtime.error, contains('文件系统'));
    expect(runtime.error, contains('blocked'));
    expect(runtime.error, isNot(contains('另一个实例')));
    blocked.deleteSync();
    Directory(blocked.path).createSync();
    await runtime.setEnabled(true);
    expect(runtime.running, true);
    expect(runtime.error, isNull);
    await runtime.stop();
    runtime.dispose();
    vm.dispose();
    board.dispose();
    dir.deleteSync(recursive: true);
  });

  test(
    'control is off by default; explicit enable and disable manage discovery',
    () async {
      final dir = Directory.systemTemp.createTempSync('penna-runtime');
      final board = LayoutBoard();
      final vm = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
        layoutOnly: true,
        layout: board,
      );
      final runtime = ControlRuntime();
      runtime.attach(PennaTools(vm: vm, home: dir));
      expect(runtime.running, false);
      expect(File('${dir.path}/control/connection.json').existsSync(), false);
      await runtime.setEnabled(true);
      expect(runtime.running, true);
      expect(runtime.url, startsWith('http://127.0.0.1:'));
      expect(File('${dir.path}/control/connection.json').existsSync(), true);
      await runtime.setEnabled(false);
      expect(runtime.running, false);
      expect(File('${dir.path}/control/connection.json').existsSync(), false);
      runtime.dispose();
      vm.dispose();
      board.dispose();
      dir.deleteSync(recursive: true);
    },
  );
}
