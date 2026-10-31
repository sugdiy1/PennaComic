import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/agent_control/control_runtime.dart';
import 'package:penna/core/agent_control/penna_tools.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
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
