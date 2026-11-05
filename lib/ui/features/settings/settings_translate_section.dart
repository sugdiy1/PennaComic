import 'package:flutter/material.dart';

import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'settings_sections.dart';
import '../../../l10n/l10n.dart';

/// 翻译:引擎按顺序使用,失败自动换下一个。
class TranslateSection extends StatelessWidget {
  const TranslateSection({super.key, required this.service});

  final ConfigService service;

  void _reorder(int from, int to) {
    final cfg = service.config;
    final order = [...cfg.mtOrder];
    order.insert(to, order.removeAt(from));
    service.update(cfg.copyWith(mtOrder: order));
  }

  @override
  Widget build(BuildContext context) {
    final cfg = service.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(tr('翻译'), tr('按顺序使用,失败自动换下一个')),
        PennaCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: _NumberStepper(
                  label: tr('每个引擎尝试'),
                  unit: tr('次'),
                  value: cfg.mtAttempts,
                  min: minMtAttempts,
                  max: maxMtAttempts,
                  onChanged: (v) =>
                      service.update(service.config.copyWith(mtAttempts: v)),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _NumberStepper(
                  label: tr('单次超时'),
                  unit: tr('秒'),
                  value: cfg.mtTimeoutSeconds,
                  step: 5,
                  min: minMtTimeoutSeconds,
                  max: maxMtTimeoutSeconds,
                  onChanged: (v) => service.update(
                    service.config.copyWith(mtTimeoutSeconds: v),
                  ),
                ),
              ),
            ],
          ),
        ),
        gap,
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: _reorder,
          proxyDecorator: (child, _, _) =>
              Material(color: Colors.transparent, child: child),
          children: [
            for (final (index, id) in cfg.mtOrder.indexed)
              Padding(
                key: ValueKey(id),
                padding: const EdgeInsets.only(bottom: 8),
                child: _EngineRow(
                  service: service,
                  engine: mtEngines.firstWhere((e) => e.id == id),
                  index: index,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        PennaCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('LLM 意译'), style: titleStyle),
                    SizedBox(height: 2),
                    Text(
                      tr('使用当前模型'),
                      style: TextStyle(
                        fontSize: 12,
                        color: PennaColors.slate500,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: cfg.paraphrase,
                onChanged: (on) => service.update(cfg.copyWith(paraphrase: on)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 列表里的一个引擎:拖动手柄、序号、名字、开关;启用且需要凭据时展开输入框。
class _EngineRow extends StatelessWidget {
  const _EngineRow({
    required this.service,
    required this.engine,
    required this.index,
  });

  final ConfigService service;
  final MtEngine engine;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cfg = service.config;
    final enabled = cfg.mtEnabled.contains(engine.id);
    final free = engine.fields.isEmpty;
    return PennaCard(
      borderColor: enabled ? PennaColors.primaryBorder : PennaColors.border,
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 18,
                      color: PennaColors.slate400,
                    ),
                  ),
                ),
              ),
              Text(
                '${index + 1}',
                style: titleStyle.copyWith(
                  color: enabled ? PennaColors.primary : PennaColors.slate400,
                ),
              ),
              const SizedBox(width: 10),
              Text(tr(engine.label), style: titleStyle),
              const SizedBox(width: 8),
              PennaCard(
                color: free ? PennaColors.diffAdd : PennaColors.slate100,
                borderColor: free ? PennaColors.diffAdd : PennaColors.slate100,
                radius: 99,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                child: Text(
                  free ? tr('免费') : tr('需凭据'),
                  style: TextStyle(
                    fontSize: 11,
                    color: free
                        ? PennaColors.diffAddText
                        : PennaColors.slate500,
                  ),
                ),
              ),
              const Spacer(),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: enabled,
                  onChanged: (on) => service.update(
                    cfg.copyWith(
                      mtEnabled: on
                          ? {...cfg.mtEnabled, engine.id}
                          : ({...cfg.mtEnabled}..remove(engine.id)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (enabled)
            for (final field in engine.fields)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: _MtFieldInput(
                  service: service,
                  engine: engine,
                  field: field,
                ),
              ),
        ],
      ),
    );
  }
}

/// 「标签  [-] 3 次 [+]」形式的整数调节。
class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  final String label;
  final String unit;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, int next) => IconButton(
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon),
      onPressed: next == value ? null : () => onChanged(next),
    );
    return Row(
      children: [
        Expanded(child: Text(label, style: titleStyle)),
        button(Icons.remove, (value - step).clamp(min, max)),
        SizedBox(
          width: 56,
          child: Text(
            '$value $unit',
            textAlign: TextAlign.center,
            style: titleStyle.copyWith(color: PennaColors.primary),
          ),
        ),
        button(Icons.add, (value + step).clamp(min, max)),
      ],
    );
  }
}

class _MtFieldInput extends StatelessWidget {
  const _MtFieldInput({
    required this.service,
    required this.engine,
    required this.field,
  });

  final ConfigService service;
  final MtEngine engine;
  final MtField field;

  @override
  Widget build(BuildContext context) {
    final cfg = service.config;
    final key = engine.keyOf(field);
    return PennaField(
      label: tr(field.label),
      obscure: field.secret,
      value: (field.secret ? cfg.secrets[key] : cfg.fields[key]) ?? '',
      onChanged: (v) => service.update(
        field.secret
            ? service.config.setSecret(key, v)
            : service.config.setField(key, v),
      ),
    );
  }
}
