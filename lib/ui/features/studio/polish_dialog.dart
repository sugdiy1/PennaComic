import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/settings_llm_section.dart';
import 'studio_view_model.dart';
import '../../../l10n/l10n.dart';

/// 问用户要怎么改、用哪个模型。点「开始」返回要求(可为空串),取消返回 null。
Future<String?> showPolishDialog(BuildContext context, StudioViewModel vm) {
  final (start, end) = vm.polishRange;
  final whole = start == 0 && end == vm.body.length;
  var instruction = '';
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('润色'), style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              whole ? tr('范围:全文') : tr('范围:{0} 个字符', [end - start]),
              style: TextStyle(fontSize: 12, color: PennaColors.slate500),
            ),
            const SizedBox(height: 12),
            PennaField(
              label: tr('要求'),
              hint: tr('留空则直接润色'),
              maxLines: 3,
              value: '',
              onChanged: (v) => instruction = v,
            ),
            const SizedBox(height: 12),
            // 选的模型会记进设置,下次沿用。
            ListenableBuilder(
              listenable: vm.config,
              builder: (context, _) => LlmRolePicker(
                title: tr('模型'),
                service: vm.config,
                pinnedId: vm.config.config.polishLlmId,
                onPick: (id) =>
                    vm.config.config.copyWith(polishLlmId: () => id),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, instruction),
          child: Text(tr('开始')),
        ),
      ],
    ),
  );
}
