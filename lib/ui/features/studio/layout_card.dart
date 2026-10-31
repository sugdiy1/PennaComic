import 'package:flutter/material.dart';

import '../../../core/harness/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../../l10n/l10n.dart';

/// 回复里 Agent 写的一份布局(`<layout>`)。说完时已经自动放到区域控制工作台;
/// 用户之后又改了画板,点这里能再放一次。
class LayoutCard extends StatelessWidget {
  const LayoutCard({
    super.key,
    required this.json,
    required this.complete,
    required this.writing,
    this.onAdopt,
    this.onOpen,
  });

  final String json;
  final bool complete;
  final bool writing;
  final VoidCallback? onAdopt;

  /// 切到区域控制工作台去看;只在主工作区的对话里有。
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    // 这里只看读不读得了、有几个框。画布给得足够大:按真画布算时框不会被截掉,
    // 小了反而会把靠边的框截成零面积、少算几个。
    final parsed = writing || !complete
        ? null
        : parseMossLayout(json, width: _anyCanvas, height: _anyCanvas);
    final broken = complete && !writing && parsed == null;
    final color = broken ? PennaColors.diffDelText : PennaColors.primary;
    return PennaCard(
      radius: 12,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            broken ? Icons.error_outline : Icons.crop_free,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            // parsed 为 null 又不是读不了的,是被打断、没写完的。
            child: Text(
              writing
                  ? tr('正在写区域')
                  : broken
                  ? tr('布局读不了')
                  : parsed == null
                  ? tr('区域控制')
                  : tr('区域控制 · {0} 个框', [parsed.boxes.length]),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          if (onOpen != null && complete && !writing && !broken)
            PennaButton(
              label: tr('去区域控制工作台'),
              icon: Icons.open_in_new,
              onPressed: onOpen,
            ),
          PennaButton(
            label: writing || complete ? tr('放到区域控制工作台') : tr('不完整'),
            icon: Icons.keyboard_double_arrow_left,
            onPressed: writing || !complete || broken ? null : onAdopt,
          ),
        ],
      ),
    );
  }
}

/// 只为数框时用的画布边长:比哪种画布都大。
const _anyCanvas = 1 << 20;
