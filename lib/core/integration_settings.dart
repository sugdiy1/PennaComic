import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 安装目录只放程序；所有个人配置与任务使用独立目录。
class IntegrationSettings {
  IntegrationSettings({required this.home, required this.bundleRoot});
  static IntegrationSettings current = IntegrationSettings(
    home:
        Platform.environment['PENNA_HOME'] ??
        p.join(
          Platform.environment['APPDATA'] ?? Directory.systemTemp.path,
          'PennaComic',
        ),
    bundleRoot:
        Platform.environment['PENNA_BUNDLE_ROOT'] ??
        File(Platform.resolvedExecutable).parent.path,
  );
  final String home, bundleRoot;
  Map<String, dynamic> data = {};
  String get configPath => p.join(home, 'integration.json');
  String _path(String key, String fallback) {
    final raw = (data[key] as String?)?.trim();
    final value = raw == null || raw.isEmpty ? fallback : raw;
    return p.normalize(p.isAbsolute(value) ? value : p.join(home, value));
  }

  String get python =>
      _path('python', p.join(bundleRoot, 'runtime', 'python.exe'));
  String get workflow =>
      _path('workflow', p.join(bundleRoot, 'workflows', 'moss-api.json'));
  String get output => _path('output', p.join(home, 'renders'));
  String get backend =>
      p.normalize(p.join(bundleRoot, 'backend', 'penna_relay.py'));
  String get controller =>
      p.normalize(p.join(bundleRoot, 'backend', 'gpu_mode.py'));
  String get exporter =>
      p.normalize(p.join(bundleRoot, 'backend', 'comic_export.py'));
  String get novelLauncher =>
      p.normalize(p.join(bundleRoot, 'backend', 'novel_launcher.py'));
  String get comfyUrl =>
      (data['comfy_url'] as String? ?? 'http://127.0.0.1:8188').replaceAll(
        RegExp(r'/+$'),
        '',
      );
  Map<String, String> get environment => {
    'PYTHONIOENCODING': 'utf-8',
    'PENNA_HOME': home,
    'PENNA_INTEGRATION': configPath,
    'PENNA_BUNDLE_ROOT': bundleRoot,
  };
  void _validate(Map<String, dynamic> value) {
    for (final key in ['comfy_url', 'llm_url']) {
      final raw = value[key];
      if (raw == null) continue;
      final u = raw is String ? Uri.tryParse(raw) : null;
      if (u == null ||
          !['http', 'https'].contains(u.scheme) ||
          u.host.isEmpty ||
          u.userInfo.isNotEmpty ||
          u.hasQuery ||
          u.hasFragment) {
        throw FormatException('$key 需要有效的 HTTP(S) 地址');
      }
    }
    if (!['external', 'managed'].contains(value['mode'] ?? 'external')) {
      throw const FormatException('无效的服务模式');
    }
    for (final key in ['python', 'workflow', 'output']) {
      if (value[key] != null && value[key] is! String) {
        throw FormatException('$key 需要路径字符串');
      }
    }
  }

  void load() {
    final file = File(configPath);
    final next = file.existsSync()
        ? Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map)
        : <String, dynamic>{};
    _validate(next);
    data = next;
  }

  Future<void> save(Map<String, dynamic> changes) async {
    final next = <String, dynamic>{'mode': 'external', ...data, ...changes};
    _validate(next);
    await Directory(home).create(recursive: true);
    final temp = File('$configPath.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(next),
      flush: true,
    );
    await temp.rename(configPath);
    data = next;
  }
}
