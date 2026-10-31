import '../../integration_settings.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../data/models/novel_comic.dart';

/// 保留后端边界，未来可加入 LLM 分镜和生产队列；本轮只有离线计划。
abstract interface class NovelComicBackend {
  Future<Map<String, dynamic>> plan({
    required String input,
    required String output,
    required ComicOptions options,
  });
}

class PythonComicBackend implements NovelComicBackend {
  const PythonComicBackend();

  @override
  Future<Map<String, dynamic>> plan({
    required String input,
    required String output,
    required ComicOptions options,
  }) async {
    options.validate();
    if (!File(options.python).existsSync()) {
      throw const FileSystemException('Python 不存在，请在小说漫画设置中修改路径。');
    }
    if (!File(options.launcher).existsSync()) {
      throw const FileSystemException(
        'novel2comic 后端入口不存在，请检查 launcher.py 路径。',
      );
    }
    final process = await Process.start(
      options.python,
      [
        options.launcher,
        'run',
        '--input',
        input,
        '--out',
        output,
        '--plan-only',
        '--json',
        '--style',
        options.style,
        '--lora',
        options.lora,
        '--lora-strength',
        '${options.loraStrength}',
        '--pages-per-chapter',
        '${options.pagesPerChapter}',
        '--panels-per-page',
        '${options.panelsPerPage}',
        '--steps',
        '${options.steps}',
        '--seed',
        '${options.seed}',
        '--comfy-url',
        options.comfyUrl,
      ],
      environment: IntegrationSettings.current.environment,
      runInShell: false,
    );
    final outputText = process.stdout.transform(utf8.decoder).join();
    final errorText = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        process.kill();
        throw TimeoutException('小说解析超过两分钟，已停止本次后端进程。');
      },
    );
    final stdout = await outputText;
    final stderr = await errorText;
    if (exitCode != 0) {
      throw ProcessException(
        options.python,
        [options.launcher],
        stderr.trim().isEmpty ? '分镜规划失败（退出码 $exitCode）。' : stderr.trim(),
        exitCode,
      );
    }
    final result = Map<String, dynamic>.from(jsonDecode(stdout) as Map);
    if (result['stage'] != 'planned' || result['pages'] is! List) {
      throw const FormatException('后端返回的数据不是分镜计划。');
    }
    return result;
  }
}

/// 页索引只能引用当前作品的相对文件，不能读写目录外的文件。
File resolveComicArtifact(String root, String relative) {
  final normal = relative.replaceAll('\\', '/');
  final uri = Uri.tryParse(normal);
  if (uri == null ||
      uri.isAbsolute ||
      normal.startsWith('/') ||
      normal.split('/').contains('..') ||
      normal.contains(':')) {
    throw const FormatException('作品文件路径超出了输出目录。');
  }
  return File(
    '${Directory(root).absolute.path}${Platform.pathSeparator}'
    '${normal.split('/').join(Platform.pathSeparator)}',
  );
}
