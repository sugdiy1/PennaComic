import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/integration_settings.dart';

class ComicConnectionSection extends StatefulWidget {
  const ComicConnectionSection({super.key});
  @override
  State<ComicConnectionSection> createState() => _ComicConnectionSectionState();
}

class _ComicConnectionSectionState extends State<ComicConnectionSection> {
  final fields = <String, TextEditingController>{};
  String message = '';
  bool checking = false;
  @override
  void initState() {
    super.initState();
    final c = IntegrationSettings.current;
    try {
      c.load();
    } on Object catch (e) {
      message = '配置读取失败：$e';
    }
    for (final entry in {
      'python': c.python,
      'comfy_url': c.comfyUrl,
      'workflow': c.workflow,
      'output': c.output,
    }.entries) {
      fields[entry.key] = TextEditingController(text: entry.value);
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save({bool doctor = false}) async {
    if (checking) return;
    setState(() {
      checking = true;
      message = '';
    });
    try {
      final c = IntegrationSettings.current;
      await c.save({
        for (final e in fields.entries) e.key: e.value.text.trim(),
      });
      if (doctor) {
        if (!File(c.python).existsSync()) {
          throw const FileSystemException('请选择已有的 Python 可执行文件');
        }
        final result = await Process.run(
          c.python,
          ['${c.bundleRoot}/backend/doctor.py'],
          environment: c.environment,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        ).timeout(const Duration(seconds: 30));
        final checks = jsonDecode('${result.stdout}') as List;
        if (mounted) {
          setState(() {
            message = checks
                .map(
                  (x) =>
                      '${x['ok'] == true ? '✓' : '✗'} ${x['check']}：${x['message']}',
                )
                .join('\n');
          });
        }
      } else if (mounted) {
        setState(() => message = '连接配置已保存。新任务立即使用；正在运行的任务沿用原参数。');
      }
    } on Object catch (e) {
      if (mounted) setState(() => message = '检查失败：$e');
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> pick(String key) async {
    final chosen = key == 'output'
        ? await getDirectoryPath()
        : (await openFile())?.path;
    if (chosen != null && mounted) setState(() => fields[key]!.text = chosen);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '漫画连接',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      const Text('连接已安装的 ComfyUI。默认由你启动和管理模型服务；16GB 显卡请先结束或卸载占用显存的本地模型，再开始出图。'),
      for (final e in {
        'python': 'Python 可执行文件',
        'comfy_url': 'ComfyUI 地址',
        'workflow': '漫画 API 工作流',
        'output': '成品与任务目录',
      }.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: fields[e.key],
                  decoration: InputDecoration(
                    labelText: e.value,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              if (e.key != 'comfy_url')
                IconButton(
                  onPressed: checking ? null : () => pick(e.key),
                  icon: const Icon(Icons.folder_open),
                ),
            ],
          ),
        ),
      Wrap(
        spacing: 12,
        children: [
          ElevatedButton(
            onPressed: checking ? null : () => save(),
            child: const Text('保存配置'),
          ),
          OutlinedButton(
            onPressed: checking ? null : () => save(doctor: true),
            child: Text(checking ? '正在检查…' : '检查环境'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SelectableText(message),
      const SizedBox(height: 16),
      SelectableText('独立数据目录：${IntegrationSettings.current.home}'),
    ],
  );
}
