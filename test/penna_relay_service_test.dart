import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/integration_settings.dart';
import 'package:penna/core/harness/comic/penna_relay_service.dart';

void main() {
  test('relay passes cancellation marker and accepts cancelled terminal even on nonzero exit', () async {
    final dir = Directory.systemTemp.createTempSync('penna-relay-cancel-');
    final previous = IntegrationSettings.current;
    try {
      final backendDir = Directory('${dir.path}/backend')..createSync();
      File('${backendDir.path}/penna_relay.py').writeAsStringSync('''
import json, sys
assert '--cancel-file' in sys.argv
marker = sys.argv[sys.argv.index('--cancel-file') + 1]
assert marker.endswith('owned-task.json')
print(json.dumps({'stage': 'cancelled', 'message': 'cancelled own job'}), flush=True)
sys.exit(1)
''');
      IntegrationSettings.current =
          IntegrationSettings(home: dir.path, bundleRoot: dir.path)
            ..data = {
              'python': Platform.environment['PENNA_TEST_PYTHON'] ?? 'python',
            };
      final events = await const PennaRelayService().run({
        'pages': <Object>[],
      }, cancelFile: '${dir.path}/control/cancel/owned-task.json').toList();
      expect(events.single.stage, 'cancelled');
    } finally {
      IntegrationSettings.current = previous;
      dir.deleteSync(recursive: true);
    }
  });
}
