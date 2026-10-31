import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 列表来自 ComfyUI，不扫描或移动模型。勾选和强度只属于这次 Penna 接力。
class RelayLoraPicker extends StatefulWidget {
  const RelayLoraPicker({
    super.key,
    required this.names,
    required this.selected,
    required this.weights,
    required this.busy,
    required this.loading,
    required this.error,
    required this.onSelect,
    required this.onWeight,
    required this.onRefresh,
    required this.onClear,
  });
  final List<String> names;
  final Set<String> selected;
  final Map<String, String> weights;
  final bool busy, loading;
  final String? error;
  final void Function(String, bool) onSelect;
  final void Function(String, String) onWeight;
  final VoidCallback onRefresh, onClear;
  @override
  State<RelayLoraPicker> createState() => _RelayLoraPickerState();
}

class _RelayLoraPickerState extends State<RelayLoraPicker> {
  bool _mossOnly = true;
  String _search = '';
  String _friendly(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('moss_lineart')) return '黑白线稿';
    if (lower.contains('colorful line art')) return '彩色线稿';
    if (lower.contains('muqiu_moss')) return 'muqiu 画风';
    if (lower.contains('yoneyama')) return '米山舞画风';
    if (lower.contains('handwritten_speech')) return '手绘气泡';
    if (lower.contains('blue-archive-style')) return '碧蓝档案画风';
    if (lower.contains('mossrealistic')) return '写实快照';
    if (lower.contains('meion_moss')) return 'MeIoN 画风';
    return name.replaceFirst(
      RegExp(r'\.safetensors$', caseSensitive: false),
      '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.names
        .where(
          (name) =>
              (!_mossOnly || name.toLowerCase().contains('moss')) &&
              ('$name ${_friendly(name)}').toLowerCase().contains(
                _search.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'LoRA 多选',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              '已选 ${widget.selected.length} 个',
              style: TextStyle(fontSize: 11, color: PennaColors.slate500),
            ),
            IconButton(
              tooltip: '刷新本机 LoRA',
              onPressed: widget.busy || widget.loading
                  ? null
                  : widget.onRefresh,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh, size: 17),
            ),
          ],
        ),
        TextField(
          enabled: !widget.busy,
          onChanged: (v) => setState(() => _search = v),
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            hintText: '搜索名称或画风',
            prefixIcon: Icon(Icons.search, size: 17),
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        Row(
          children: [
            SizedBox(
              width: 26,
              height: 32,
              child: Checkbox(
                value: _mossOnly,
                onChanged: widget.busy
                    ? null
                    : (v) => setState(() => _mossOnly = v!),
              ),
            ),
            const Text('只看 MOSS', style: TextStyle(fontSize: 12)),
            const Spacer(),
            TextButton(
              onPressed: widget.busy ? null : widget.onClear,
              child: const Text('清空选择', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        if (widget.loading)
          const Padding(
            padding: EdgeInsets.all(14),
            child: LinearProgressIndicator(),
          )
        else if (widget.error != null)
          Text(
            '读取失败：${widget.error}\n请确认 ComfyUI 已启动，再点刷新。',
            style: TextStyle(fontSize: 12, color: PennaColors.amber),
          )
        else
          Container(
            height: 220,
            decoration: BoxDecoration(
              border: Border.all(color: PennaColors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: names.isEmpty
                ? const Center(
                    child: Text('没有匹配的 LoRA', style: TextStyle(fontSize: 12)),
                  )
                : ListView.separated(
                    itemCount: names.length,
                    separatorBuilder: (_, i) =>
                        Divider(height: 1, color: PennaColors.border),
                    itemBuilder: (context, i) {
                      final name = names[i],
                          checked = widget.selected.contains(name);
                      return ColoredBox(
                        color: checked
                            ? PennaColors.primaryBg
                            : PennaColors.card,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(2, 6, 8, 6),
                          child: Row(
                            children: [
                              Checkbox(
                                key: ValueKey('lora-check-$name'),
                                value: checked,
                                onChanged: widget.busy
                                    ? null
                                    : (v) => widget.onSelect(name, v!),
                              ),
                              Expanded(
                                child: Tooltip(
                                  message: name,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _friendly(name),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: PennaColors.slate500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 64,
                                child: TextFormField(
                                  key: ValueKey(
                                    'lora-weight-$name-${widget.weights[name]}',
                                  ),
                                  initialValue: widget.weights[name] ?? '0.85',
                                  enabled: checked && !widget.busy,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  style: const TextStyle(fontSize: 12),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: '强度',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    ),
                                  ),
                                  onChanged: (v) => widget.onWeight(name, v),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        const SizedBox(height: 6),
        Text(
          widget.selected.isEmpty
              ? '未选 LoRA，将使用基础模型。'
              : '未勾选的 LoRA 不会加载；强度 0 等同关闭。',
          style: TextStyle(fontSize: 10, color: PennaColors.slate500),
        ),
      ],
    );
  }
}
