import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets.dart';
import 'novel_comic_model.dart';

class NovelPromptOutput extends StatefulWidget {
  const NovelPromptOutput({super.key, required this.model});
  final NovelComicModel model;
  @override
  State<NovelPromptOutput> createState() => _NovelPromptOutputState();
}

class _NovelPromptOutputState extends State<NovelPromptOutput> {
  String selected = 'page';
  String? exported;
  @override
  Widget build(BuildContext context) {
    final pack = widget.model.currentPromptPackage();
    final panels = (pack['panels'] as List).cast<Map<String, dynamic>>();
    final choices = <String, String>{
      'page': '整页MOSS提示词 · ${pack['width']}×${pack['height']}',
      for (final (i, p) in panels.indexed)
        'p$i': '第${i + 1}格 · ${p['width']}×${p['height']}',
      'dialogue': '台词清单',
    };
    final key = choices.containsKey(selected) ? selected : 'page';
    final text = key == 'page'
        ? pack['whole_page_prompt'] as String
        : key == 'dialogue'
        ? panels
              .map(
                (p) =>
                    '第${p['panel_number']}格：${(p['dialogue'] as List).join(' / ')}',
              )
              .join('\n')
        : panels[int.parse(key.substring(1))]['prompt'] as String;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '自行复制提示词',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('直接复制到支持MOSS的工作流正面提示词节点。逐格使用时请同步设置对应尺寸。此模式不调用ComfyUI。'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: key,
                  items: [
                    for (final e in choices.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => selected = v!),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: const ValueKey('copy-novel-prompt'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) showToast(context, '已复制提示词');
                },
                icon: const Icon(Icons.copy),
                label: const Text('复制'),
              ),
              TextButton(
                onPressed: () async {
                  final folder = await getDirectoryPath(
                    confirmButtonText: '导出全部提示词',
                  );
                  if (folder == null) return;
                  try {
                    final path = await widget.model.exportAllPrompts(folder);
                    if (mounted) setState(() => exported = path);
                  } on Object catch (e) {
                    if (context.mounted) {
                      showToast(context, '导出失败：$e', warn: true);
                    }
                  }
                },
                child: const Text('导出全部提示词'),
              ),
            ],
          ),
          if (exported != null) SelectableText('已导出：$exported'),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                key: const ValueKey('novel-prompt-text'),
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
