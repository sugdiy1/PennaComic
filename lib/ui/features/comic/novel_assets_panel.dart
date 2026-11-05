import 'package:flutter/material.dart';

import '../../core/widgets.dart';
import 'novel_comic_model.dart';

class NovelAssetsPanel extends StatelessWidget {
  const NovelAssetsPanel({
    super.key,
    required this.model,
    required this.onBack,
    required this.onPlan,
  });
  final NovelComicModel model;
  final VoidCallback onBack, onPlan;
  @override
  Widget build(BuildContext context) {
    final assets = model.current!.assets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回页面'),
              ),
              const Text(
                '前期文字资产',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(assets['status'] == 'done' ? '原文扫描已完成' : '原文扫描未完成，可继续准备'),
              FilledButton(
                onPressed: model.busy ? null : onPlan,
                child: const Text('使用资产开始AI排版'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '先锁定文字约定，不代表锁脸。原文事实与视觉补设分开；编辑后自动保存并保留手工设定。无有效原文证据的卡需要核对。',
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final entry in [
                ('characters', '角色卡'),
                ('locations', '场景卡'),
                ('props', '道具卡'),
              ]) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '${entry.$2} · ${(assets[entry.$1] as List? ?? []).length}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                for (final raw in assets[entry.$1] as List? ?? [])
                  _card(entry.$1, Map<String, dynamic>.from(raw as Map)),
              ],
              if (assets['visual_notes'] is String)
                Text('视觉约定与待核对项：${assets['visual_notes']}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(String kind, Map<String, dynamic> card) {
    final name = card['name'] as String;
    final fields = kind == 'characters'
        ? [
            ('identity', '原文身份/年龄'),
            ('appearance', '原文明示外貌'),
            ('outfit', '基础服装'),
            ('personality', '原文明示性格'),
            ('visual_design', '视觉补设（非原文事实）'),
          ]
        : [('description', '原文要素')];
    return Card(
      child: ExpansionTile(
        key: ValueKey('asset-$kind-$name'),
        title: Text(name),
        subtitle: Text(
          '${card['manual_locked'] == true ? '手工设定已保留 · ' : ''}${card['evidence_verified'] == true ? '有可匹配原文证据' : '原文证据待核对'}${kind == 'characters' ? ' · 别名：${(card['aliases'] as List? ?? []).join('、')}' : ''}',
        ),
        childrenPadding: const EdgeInsets.all(16),
        children: [
          for (final field in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PennaField(
                key: ValueKey('asset-field-$kind-$name-${field.$1}'),
                label: field.$2,
                value: '${card[field.$1] ?? ''}',
                maxLines: 3,
                onChanged: (value) =>
                    model.editAsset(kind, name, field.$1, value),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText('原文证据：${card['evidence'] ?? '无'}'),
          ),
        ],
      ),
    );
  }
}
