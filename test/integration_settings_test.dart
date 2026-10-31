import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/integration_settings.dart';

void main() {
  test('独立用户配置的相对路径可用于中文空格目录，保存后重新载入', () async {
    final dir = Directory.systemTemp.createTempSync('漫画 space ');
    addTearDown(() => dir.deleteSync(recursive: true));
    final settings = IntegrationSettings(
      home: dir.path,
      bundleRoot: '${dir.path}/app',
    );
    await settings.save({
      'python': 'python/python.exe',
      'output': '作品',
      'comfy_url': 'http://localhost:9999/',
    });
    final loaded = IntegrationSettings(
      home: dir.path,
      bundleRoot: '${dir.path}/app',
    )..load();
    expect(
      loaded.python,
      '${dir.path}${Platform.pathSeparator}python${Platform.pathSeparator}python.exe',
    );
    expect(loaded.output, '${dir.path}${Platform.pathSeparator}作品');
    expect(loaded.comfyUrl, 'http://localhost:9999');
    expect(
      loaded.backend,
      '${dir.path}${Platform.pathSeparator}app${Platform.pathSeparator}backend${Platform.pathSeparator}penna_relay.py',
    );
    expect(loaded.data['mode'], 'external');
  });
  test(
    'desktop --home overrides environment and resolves absolute runtime path',
    () {
      final c = IntegrationSettings.fromStartup(
        arguments: ['--home', '漫画 home'],
        environment: {'PENNA_HOME': 'ignored', 'APPDATA': 'ignored'},
        executable: File('app/penna.exe').absolute.path,
      );
      expect(c.home, Directory('漫画 home').absolute.path);
      expect(c.homeSource, '--home');
      final equals = IntegrationSettings.fromStartup(
        arguments: ['--home=漫画 home'],
        environment: {},
        executable: File('app/penna.exe').absolute.path,
      );
      expect(equals.home, c.home);
      final env = IntegrationSettings.fromStartup(
        arguments: [],
        environment: {'PENNA_HOME': Directory('env-home').absolute.path},
        executable: File('app/penna.exe').absolute.path,
      );
      expect(env.homeSource, 'PENNA_HOME');
      expect(env.home, Directory('env-home').absolute.path);
      expect(
        () => IntegrationSettings.fromStartup(
          arguments: ['--home'],
          environment: {},
        ),
        throwsFormatException,
      );
      expect(
        () => IntegrationSettings.fromStartup(
          arguments: ['--home', 'a', '--home', 'b'],
          environment: {},
        ),
        throwsFormatException,
      );
    },
  );
  test('无效网址不能覆盖已有配置', () async {
    final dir = Directory.systemTemp.createTempSync('integration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = IntegrationSettings(home: dir.path, bundleRoot: dir.path);
    await c.save({'comfy_url': 'http://localhost:8188'});
    await expectLater(
      c.save({'comfy_url': 'file:///tmp'}),
      throwsFormatException,
    );
    expect(c.comfyUrl, 'http://localhost:8188');
  });
}
