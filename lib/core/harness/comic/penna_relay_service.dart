import '../../integration_settings.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 接力任务只用逐行 JSON 通信，普通日志不会被当作完成结果。
class RelayEvent {
  const RelayEvent({
    required this.stage,
    required this.message,
    this.jobDir,
    this.image,
    this.batchDir,
    this.pageIndex,
    this.pageTotal,
    this.pages = const [],
  });
  factory RelayEvent.fromJson(Map<String, dynamic> json) => RelayEvent(
    stage: json['stage'] as String? ?? 'error',
    message: json['message'] as String? ?? '',
    jobDir: json['job_dir'] as String?,
    image: json['image'] as String?,
    batchDir: json['batch_dir'] as String?,
    pageIndex: json['page_index'] as int?,
    pageTotal: json['page_total'] as int?,
    pages: [
      for (final p in json['pages'] as List? ?? const [])
        if (p is Map) Map<String, dynamic>.from(p),
    ],
  );
  final String stage, message;
  final String? jobDir, image;
  final String? batchDir;
  final int? pageIndex, pageTotal;
  final List<Map<String, dynamic>> pages;
}

class PennaRelayService {
  const PennaRelayService();
  static String get python => IntegrationSettings.current.python;
  static String get backend => IntegrationSettings.current.backend;
  static String get controller => IntegrationSettings.current.controller;
  static String get output => IntegrationSettings.current.output;

  Future<List<String>> listLoras() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(
        Uri.parse(
          '${IntegrationSettings.current.comfyUrl}/object_info/LoraLoaderModelOnly',
        ),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != 200) {
        throw HttpException('读取 LoRA 列表失败（${response.statusCode}）。');
      }
      final json = jsonDecode(await response.transform(utf8.decoder).join());
      return List<String>.from(
        json['LoraLoaderModelOnly']['input']['required']['lora_name'][0]
            as List,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> readSettings() async {
    final file = File(
      '${IntegrationSettings.current.home}/relay-settings.json',
    );
    if (!await file.exists()) return {};
    return Map<String, dynamic>.from(
      jsonDecode(await file.readAsString(encoding: utf8)) as Map,
    );
  }

  /// 应用重启后也能找到相同快照和参数的未完成批次；改过页则新建版本。
  Future<String?> findPendingBatch(Map<String, Object?> request) async {
    final dir = Directory('$output${Platform.pathSeparator}batches');
    if (!await dir.exists()) return null;
    Object? stable(Object? value) {
      if (value is Map) {
        final keys = value.keys.map((e) => e.toString()).toList()..sort();
        return {for (final key in keys) key: stable(value[key])};
      }
      if (value is List) return value.map(stable).toList();
      return value;
    }

    final wanted = jsonEncode(stable(request));
    final dirs = await dir
        .list()
        .where((e) => e is Directory)
        .cast<Directory>()
        .toList();
    dirs.sort((a, b) => b.path.compareTo(a.path));
    for (final entry in dirs.take(100)) {
      try {
        final batch = jsonDecode(
          await File('${entry.path}/batch.json').readAsString(),
        );
        if (batch['status'] == 'done') continue;
        final saved = jsonDecode(
          await File('${entry.path}/request.json').readAsString(),
        );
        final pages = batch['pages'] as List;
        if (pages.length != (request['pages'] as List).length) continue;
        if (jsonEncode(stable(saved)) == wanted) return entry.path;
      } on Object {
        continue;
      }
    }
    return null;
  }

  Stream<RelayEvent> run(
    Map<String, Object?> snapshot, {
    String? resume,
    String? cancelFile,
  }) async* {
    if (!File(python).existsSync() || !File(backend).existsSync()) {
      throw const FileSystemException('一键接力后端不存在，请检查本机安装目录。');
    }
    final requests = Directory('$output${Platform.pathSeparator}requests');
    await requests.create(recursive: true);
    final file = File(
      '${requests.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}.json',
    );
    await file.writeAsString(jsonEncode(snapshot), encoding: utf8, flush: true);
    final process = await Process.start(
      python,
      [
        backend,
        if (resume == null) ...[
          snapshot['pages'] is List ? '--batch' : '--snapshot',
          file.path,
        ] else ...[
          File('$resume${Platform.pathSeparator}batch.json').existsSync()
              ? '--resume-batch'
              : '--resume',
          resume,
        ],
        if (cancelFile != null) ...['--cancel-file', cancelFile],
      ],
      environment: IntegrationSettings.current.environment,
      runInShell: false,
    );
    final stderr = process.stderr.transform(utf8.decoder).join();
    var terminal = false;
    await for (final line
        in process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final data = jsonDecode(line);
      if (data is! Map<String, dynamic>) continue;
      final event = RelayEvent.fromJson(data);
      terminal =
          terminal ||
          event.stage == 'done' ||
          event.stage == 'error' ||
          event.stage == 'cancelled';
      yield event;
    }
    final exit = await process.exitCode;
    final error = (await stderr).trim();
    if (exit != 0 && !terminal) {
      throw ProcessException(
        python,
        [backend],
        error.isEmpty ? '接力任务退出（$exit）。' : error,
        exit,
      );
    }
    if (!terminal) throw const FormatException('后端提前结束，未收到任务结果。');
  }

  Future<void> restoreChat() async {
    final result = await Process.run(
      python,
      [controller, 'chat'],
      environment: IntegrationSettings.current.environment,
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) throw StateError('${result.stderr}'.trim());
  }
}
