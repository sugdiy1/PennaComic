// ignore_for_file: prefer_initializing_formals
import '../../integration_settings.dart';

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'penna_relay_service.dart';

class ComicExportVersion {
  const ComicExportVersion({
    required this.image,
    required this.label,
    this.jobDir,
    this.modifiedAt,
    this.matchesSource = true,
  });
  final String image, label;
  final String? jobDir;
  final DateTime? modifiedAt;

  /// false 表示同一页的旧分镜成品，可预览，但不能冒充当前稿已经出图。
  final bool matchesSource;
}

/// Reads saved metadata only; image generation and GPU state are never touched.
class ComicExportService {
  const ComicExportService({
    String? historyRoot,
    String? python,
    String? backend,
  }) : _historyRoot = historyRoot,
       _python = python,
       _backend = backend;
  final String? _historyRoot, _python, _backend;
  String get historyRoot => _historyRoot ?? PennaRelayService.output;
  String get python => _python ?? PennaRelayService.python;
  String get backend => _backend ?? IntegrationSettings.current.exporter;

  Future<List<String>> _sourceHashes(
    List<Map<String, Object?>> snapshots,
  ) async {
    // Use the producer's JSON encoder: Python and Dart format small floats
    // differently, so a Dart-only hash can reject an otherwise identical page.
    const script =
        'import hashlib,json,sys; '
        'values=json.load(sys.stdin); '
        'print(json.dumps([hashlib.sha256(json.dumps(v,ensure_ascii=False,'
        'sort_keys=True,separators=(",",":")).encode("utf-8")).hexdigest() '
        'for v in values]))';
    final payload = utf8.encode(
      jsonEncode(snapshots.map((s) => s['source']).toList()),
    );
    final process = await Process.start(
      python,
      ['-c', script],
      environment: IntegrationSettings.current.environment,
      runInShell: false,
    );
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdin.add(payload);
    await process.stdin.close();
    final exit = await process.exitCode;
    final output = await stdout;
    final error = await stderr;
    if (exit != 0) throw StateError('无法核对页面版本：${error.trim()}');
    return List<String>.from(jsonDecode(output) as List);
  }

  Future<List<List<ComicExportVersion>>> findVersions(
    List<Map<String, Object?>> snapshots,
  ) => _findVersions(snapshots, includePreviousSources: false);

  /// 预览也展示改稿之前的图片；导出的默认匹配仍只接受当前稿。
  Future<List<List<ComicExportVersion>>> findPreviewVersions(
    List<Map<String, Object?>> snapshots,
  ) => _findVersions(snapshots, includePreviousSources: true);

  Future<List<List<ComicExportVersion>>> _findVersions(
    List<Map<String, Object?>> snapshots, {
    required bool includePreviousSources,
  }) async {
    final versions = List.generate(
      snapshots.length,
      (_) => <ComicExportVersion>[],
    );
    if (snapshots.isEmpty) return versions;
    final root = Directory(historyRoot);
    if (!await root.exists()) return versions;
    final hashes = await _sourceHashes(snapshots);
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is! File || entry.uri.pathSegments.last != 'page.json') {
        continue;
      }
      final job = entry.parent;
      final image = File('${job.path}${Platform.pathSeparator}page.png');
      final manifest = File(
        '${job.path}${Platform.pathSeparator}manifest.json',
      );
      if (!await image.exists() || !await manifest.exists()) continue;
      try {
        final state =
            jsonDecode(await manifest.readAsString(encoding: utf8)) as Map;
        if (state['status'] != 'done') continue;
        final page =
            jsonDecode(await entry.readAsString(encoding: utf8)) as Map;
        if (page['source_hash'] is! String) continue;
        final context = page['context'];
        for (var index = 0; index < snapshots.length; index++) {
          final matches = page['source_hash'] == hashes[index];
          if (!matches && !includePreviousSources) continue;
          final expected = snapshots[index]['context'];
          // Legacy pages without identity require an explicit local PNG choice.
          if (context is! Map || expected is! Map) continue;
          if (!['workspace', 'series', 'page_number'].every(
            (key) => expected[key] != null && context[key] == expected[key],
          )) {
            continue;
          }
          final modified = (await image.stat()).modified;
          final stamp = modified
              .toLocal()
              .toIso8601String()
              .replaceFirst('T', ' ')
              .split('.')
              .first;
          final jobName = job.uri.pathSegments.where((s) => s.isNotEmpty).last;
          versions[index].add(
            ComicExportVersion(
              image: image.absolute.path,
              jobDir: job.absolute.path,
              modifiedAt: modified,
              label: '$stamp · $jobName',
              matchesSource: matches,
            ),
          );
        }
      } on FormatException {
        // An interrupted/unrelated job is not an export candidate.
      } on FileSystemException {
        // Other completed jobs remain available; missing pages stay visible.
      } on TypeError {
        // Malformed metadata cannot establish a page's identity.
      }
    }
    for (final page in versions) {
      page.sort(
        (a, b) => a.matchesSource != b.matchesSource
            ? (a.matchesSource ? -1 : 1)
            : b.modifiedAt!.compareTo(a.modifiedAt!),
      );
    }
    return versions;
  }

  Future<String?> pickImage() async => (await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(label: 'PNG 图片', extensions: ['png']),
    ],
  ))?.path;

  Future<String?> pickOutputDirectory() => getDirectoryPath();

  Future<Map<String, String>> exportComic({
    required List<Map<String, Object?>> pages,
    required String outputDir,
    required String title,
    required List<String> formats,
    required String readingDirection,
    void Function(String)? onProgress,
  }) async {
    if (pages.isEmpty ||
        pages.any(
          (p) => p['image'] is! String || (p['image'] as String).isEmpty,
        )) {
      throw StateError('每页都需要成品图片，不能漏页导出。');
    }
    final temporary = await Directory.systemTemp.createTemp(
      'penna-comic-export-',
    );
    try {
      onProgress?.call('正在保存导出清单…');
      final request = File(
        '${temporary.path}${Platform.pathSeparator}request.json',
      );
      await request.writeAsString(
        jsonEncode({
          'pages': pages,
          'output_dir': outputDir,
          'title': title,
          'formats': formats,
          'reading_direction': readingDirection,
        }),
        encoding: utf8,
        flush: true,
      );
      onProgress?.call('正在验证并打包 ${pages.length} 页…');
      final result = await Process.run(
        python,
        [backend, '--request', request.path],
        environment: IntegrationSettings.current.environment,
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        final raw = '${result.stderr}'.trim();
        String message = raw;
        try {
          message = '${(jsonDecode(raw) as Map)['error'] ?? raw}';
        } on FormatException {
          /* Preserve a non-JSON Python error. */
        }
        throw StateError(
          message.isEmpty ? '导出失败（${result.exitCode}）。' : message,
        );
      }
      final response = jsonDecode('${result.stdout}') as Map;
      return Map<String, String>.from(response['files'] as Map);
    } finally {
      await temporary.delete(recursive: true);
    }
  }
}
