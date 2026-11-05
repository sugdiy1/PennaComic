import 'dart:async';
import 'dart:io';

import 'package:penna/core/integration_settings.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final home = Directory.systemTemp.createTempSync('penna-comic-tests');
  IntegrationSettings.current = IntegrationSettings(
    home: home.path,
    bundleRoot: Directory.current.path,
  );
  final python = Platform.environment['PENNA_TEST_PYTHON'];
  if (python != null) IntegrationSettings.current.data['python'] = python;
  try {
    await testMain();
  } finally {
    await home.delete(recursive: true);
  }
}
