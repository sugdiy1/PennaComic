import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'studio_view_model.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';

const _closedWidth = 30.0;
const _openWidth = 210.0;

String _clock(DateTime t) =>
    [t.hour, t.minute, t.second].map((n) => '$n'.padLeft(2, '0')).join(':');

/// 工作台最左边的操作记录:平时是一条窄边,点开是一列流水账(新的在上)。
class ActivityBar extends StatefulWidget {
  const ActivityBar({super.key, required this.vm});

  final StudioViewModel vm;

  /// 收起、展开时各占多宽;外面排版要用。
  static double widthOf({required bool open}) =>
      open ? _openWidth : _closedWidth;

  @override
  State<ActivityBar> createState() => _ActivityBarState();
}

class _ActivityBarState extends State<ActivityBar> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final actions = widget.vm.actions;
    return AnimatedContainer(
      duration: Motion.base,
      curve: Motion.swift,
      width: ActivityBar.widthOf(open: _open),
      decoration: BoxDecoration(
        color: PennaColors.slate50,
        border: Border(right: BorderSide(color: PennaColors.border)),
        // 区域控制页里它展开时盖在属性栏上,带一点影子看得出浮在上面。
        boxShadow: _open
            ? const [BoxShadow(color: Color(0x22000000), blurRadius: 14)]
            : null,
      ),
      // 宽度变化的过程中里面的东西不换行、不报溢出,多出来的裁掉。
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: ActivityBar.widthOf(open: _open),
          maxWidth: ActivityBar.widthOf(open: _open),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Tooltip(
                message: _open ? tr('收起操作记录') : tr('操作记录'),
                child: InkWell(
                  onTap: () => setState(() => _open = !_open),
                  child: SizedBox(
                    height: 38,
                    child: Row(
                      children: [
                        const SizedBox(width: 7),
                        Icon(
                          Icons.history,
                          size: 16,
                          color: PennaColors.slate500,
                        ),
                        if (_open) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tr('操作记录'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_left,
                            size: 16,
                            color: PennaColors.slate400,
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (_open) const Divider(height: 1),
              if (_open)
                Expanded(
                  child: actions.isEmpty
                      ? Center(
                          child: Text(
                            tr('还没有操作'),
                            style: TextStyle(
                              fontSize: 12,
                              color: PennaColors.slate400,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(10),
                          itemCount: actions.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _clock(actions[i].time),
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: PennaColors.slate400,
                                      ),
                                    ),
                                  ),
                                  Tooltip(
                                    message: tr('回滚到这一步之前'),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(4),
                                      onTap: () {
                                        final problem = widget.vm.rollback(i);
                                        if (problem != null) {
                                          showToast(
                                            context,
                                            problem,
                                            warn: true,
                                          );
                                        }
                                      },
                                      child: Padding(
                                        padding: EdgeInsets.all(2),
                                        child: Icon(
                                          Icons.undo,
                                          size: 13,
                                          color: PennaColors.slate500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                actions[i].text,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: PennaColors.slate700,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
