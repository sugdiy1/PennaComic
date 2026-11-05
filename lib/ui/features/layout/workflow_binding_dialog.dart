import 'package:flutter/material.dart';

/// 候选来自真实连接关系，用户只在有歧义时选择，不编辑工作流原文件。
class WorkflowBindingDialog extends StatefulWidget {
  const WorkflowBindingDialog({
    super.key,
    required this.initial,
    required this.inspect,
  });
  final Map<String, dynamic> initial;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) inspect;
  @override
  State<WorkflowBindingDialog> createState() => _WorkflowBindingDialogState();
}

class _WorkflowBindingDialogState extends State<WorkflowBindingDialog> {
  late Map<String, dynamic> report = widget.initial;
  bool busy = false;
  String? error;
  Map get analysis => report['inspection'] as Map;
  Future<void> choose(String field, Object value) async {
    final selection = Map<String, dynamic>.from(analysis['bindings'] as Map)
      ..[field] = value;
    // 上游选择改变时，下游候选必须按新链路重新计算。
    if (field == 'output') {
      selection.remove('sampler');
      selection.remove('positive');
    }
    if (field == 'sampler') selection.remove('positive');
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = await widget.inspect(selection);
      if (mounted) setState(() => report = next);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bindings = analysis['bindings'] as Map;
    Widget picker(String label, String field, String choices) {
      final options = analysis[choices] as List? ?? [];
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$field-${bindings[field]}-${options.length}'),
          initialValue: options.any((v) => v['id'] == bindings[field])
              ? bindings[field] as String?
              : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final raw in options)
              DropdownMenuItem(
                value: raw['id'] as String,
                child: Text('${raw['label']}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: busy
              ? null
              : (v) {
                  if (v != null) choose(field, v);
                },
        ),
      );
    }

    return AlertDialog(
      title: const Text('工作流识别与绑定'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('按出图连接反查正面入口。编号或节点改名不影响识别；修改工作流后会重新检查。'),
              picker('最终出图节点', 'output', 'outputs'),
              picker('MOSS 采样器', 'sampler', 'samplers'),
              picker('正面提示词入口', 'positive', 'positives'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('由 Penna 管理 LoRA'),
                subtitle: const Text('关闭后保留原工作流 LoRA，面板多选不替换它们。'),
                value: bindings['manage_loras'] != false,
                onChanged: busy ? null : (v) => choose('manage_loras', v),
              ),
              const Text(
                '识别到的 LoRA',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              if ((analysis['loras'] as List? ?? []).isEmpty)
                const Text('没有检测到固定 LoRA；不会默认勾选额外画风。'),
              for (final entry in analysis['loras'] as List? ?? [])
                Text(
                  '${entry['enabled'] == true ? '启用' : '关闭'} · ${entry['name']} · 模型 ${entry['strength']}${entry.containsKey('clip_strength') ? ' / CLIP ${entry['clip_strength']}' : ''}',
                ),
              for (final message in [
                ...analysis['warnings'] as List? ?? [],
                ...analysis['errors'] as List? ?? [],
              ])
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('$message'),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: busy || analysis['status'] != 'ready'
              ? null
              : () => Navigator.pop(context, report),
          child: const Text('保存绑定并导入参数'),
        ),
      ],
    );
  }
}
