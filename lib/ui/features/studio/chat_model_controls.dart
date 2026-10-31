import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../core/theme.dart';

/// 仅选择思考预算；不读取或展示模型的推理内容。
class ReasoningSelector extends StatelessWidget {
  const ReasoningSelector({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.busy = false,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final bool busy;

  static const _values = ['none', 'low', 'medium', 'high', 'xhigh'];

  String _label(String value) => switch (value) {
    'none' => tr('思考：关闭'),
    'low' => tr('思考：低'),
    'high' => tr('思考：高'),
    'xhigh' => tr('思考：极高'),
    _ => tr('思考：中'),
  };

  @override
  Widget build(BuildContext context) {
    final canSelect = enabled && !busy;
    final hint = !enabled
        ? tr('思考程度仅适用于本地 Bonsai')
        : busy
        ? tr('正在生成，结束后可调整思考程度')
        : tr('调整思考程度');
    return SizedBox(
      width: 104,
      height: 32,
      child: Tooltip(
        message: hint,
        child: PopupMenuButton<String>(
          enabled: canSelect,
          tooltip: '',
          initialValue: _values.contains(value) ? value : 'medium',
          position: PopupMenuPosition.over,
          constraints: const BoxConstraints(minWidth: 144, maxWidth: 220),
          // 再检查一次状态，避免菜单打开后开始生成仍能修改。
          onSelected: (selection) {
            if (enabled && !busy) onChanged(selection);
          },
          itemBuilder: (_) => [
            for (final option in _values)
              CheckedPopupMenuItem<String>(
                value: option,
                checked: option == value,
                height: 36,
                child: Text(
                  _label(option),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: canSelect ? PennaColors.primaryBg : PennaColors.slate50,
              border: Border.all(color: PennaColors.border),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _label(value),
                      style: TextStyle(
                        fontSize: 11,
                        color: canSelect
                            ? PennaColors.primary
                            : PennaColors.slate400,
                      ),
                    ),
                  ),
                ),
                Icon(Icons.expand_more, size: 13, color: PennaColors.slate400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 所有用量由调用方提供；本控件不读取历史、不计算 token，也不清空数据。
class ContextUsageRing extends StatefulWidget {
  const ContextUsageRing({
    super.key,
    this.usedTokens,
    this.capacity,
    this.estimated = true,
    this.loading = false,
    this.onNewChat,
    this.onRefresh,
  });

  final int? usedTokens;
  final int? capacity;
  final bool estimated;
  final bool loading;
  final VoidCallback? onNewChat;
  final VoidCallback? onRefresh;

  int? get _used => usedTokens != null && usedTokens! >= 0 ? usedTokens : null;
  int? get _capacity => capacity != null && capacity! > 0 ? capacity : null;
  double? get _ratio =>
      _used != null && _capacity != null ? _used! / _capacity! : null;
  String get _kind => estimated ? tr('用量估算') : tr('实际用量');
  String get _usedLabel =>
      _used == null ? tr('已用：未知') : tr('已用：{0} tokens', [_number(_used!)]);
  String get _capacityLabel => _capacity == null
      ? tr('总容量：未知')
      : tr('总容量：{0} tokens', [_number(_capacity!)]);
  String get _remainingLabel => _ratio == null
      ? tr('剩余：未知')
      : tr('剩余：{0} tokens', [
          _number((_capacity! - _used!).clamp(0, _capacity!)),
        ]);

  static String _number(int value) =>
      '$value'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  State<ContextUsageRing> createState() => _ContextUsageRingState();
}

class _ContextUsageRingState extends State<ContextUsageRing> {
  // 详情打开时，刷新结果或外部更新也能立即显示。
  late final _current = ValueNotifier<ContextUsageRing>(widget);

  @override
  void didUpdateWidget(covariant ContextUsageRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 弹窗属于另一条路由，等当前构建结束再通知它重建。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _current.value = widget;
    });
  }

  @override
  void dispose() {
    _current.dispose();
    super.dispose();
  }

  void _showDetails() {
    _current.value = widget;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<ContextUsageRing>(
        valueListenable: _current,
        builder: (_, data, _) => AlertDialog(
          backgroundColor: PennaColors.card,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          scrollable: true,
          title: Row(
            children: [
              Expanded(
                child: Text(tr('上下文占用'), style: const TextStyle(fontSize: 16)),
              ),
              IconButton(
                tooltip: tr('刷新上下文用量'),
                iconSize: 18,
                color: PennaColors.primary,
                onPressed: data.loading ? null : data.onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data._kind,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: PennaColors.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(data._usedLabel),
                Text(data._capacityLabel),
                Text(data._remainingLabel),
                const SizedBox(height: 12),
                if (data.loading) Text(tr('正在刷新用量…')),
                Text(
                  data.estimated
                      ? tr('按当前消息估算，实际用量可能不同。')
                      : tr('显示上次请求的实际用量；输入新内容后显示估算。'),
                  style: TextStyle(fontSize: 12, color: PennaColors.slate500),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('新对话保留画板和角色信息，上下文占用不一定归零。'),
                  style: TextStyle(fontSize: 12, color: PennaColors.slate500),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(tr('关闭')),
            ),
            TextButton(
              onPressed: data.onNewChat == null
                  ? null
                  : () {
                      Navigator.of(dialogContext).pop();
                      data.onNewChat!();
                    },
              child: Text(tr('新对话继续')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget._ratio;
    final percent = ratio == null ? '—' : '${(ratio * 100).round()}%';
    final color = ratio == null
        ? PennaColors.slate400
        : ratio >= .95
        ? PennaColors.diffDelText
        : ratio >= .8
        ? PennaColors.amber
        : PennaColors.primary;
    final tooltip = [
      tr('上下文占用'),
      widget._kind,
      widget._usedLabel,
      widget._capacityLabel,
      widget._remainingLabel,
      if (widget.loading) tr('正在刷新用量…'),
    ].join('\n');
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: SizedBox.square(
          dimension: 32,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _showDetails,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CircularProgressIndicator(
                        value: widget.loading ? null : (ratio ?? 0).clamp(0, 1),
                        strokeWidth: 2.5,
                        backgroundColor: PennaColors.border,
                        color: color,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(3),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          percent,
                          style: TextStyle(fontSize: 9, color: color),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
