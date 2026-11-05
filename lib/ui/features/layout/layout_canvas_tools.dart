import 'package:flutter/material.dart';

import '../../../core/harness/layout.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import 'layout_board.dart';

/// 画框用的形状工具,像 PS 的形状工具:在空白处拖出来的框默认是什么形状。
/// 钢笔是一下一下点出顶点,点回起点(或回车)封口。交出去的都还是外框那个方框。
enum ShapeTool { rect, ellipse, polygon, pen }

typedef ShapeToolState = ({ShapeTool tool, int sides});

final _tools = Expando<ValueNotifier<ShapeToolState>>();

extension LayoutShapeTool on LayoutBoard {
  /// 眼下的形状工具(跟着画板走,不存盘;默认方框)。
  ValueNotifier<ShapeToolState> get shapeTool =>
      _tools[this] ??= ValueNotifier((tool: ShapeTool.rect, sides: 5));
}

/// 新拖出来的框按工具给的形状;方框和钢笔(钢笔另走一套)是 null。
LayoutShape? shapeFor(ShapeToolState s) => switch (s.tool) {
  ShapeTool.ellipse => const LayoutShape.ellipse(),
  ShapeTool.polygon => LayoutShape.regular(s.sides),
  _ => null,
};

/// 画布区上面那一行:左边是形状工具和「交给 Agent」(唯一一个交给 Agent 写描述的按钮:
/// 形状、视角、灯光、体块都设好之后点它),右边是自由摄像机(3D 视图)和全屏。
class CanvasTools extends StatelessWidget {
  const CanvasTools({
    super.key,
    required this.board,
    required this.scene,
    required this.onScene,
    required this.onFullscreen,
    required this.onHandOver,
  });

  final LayoutBoard board;

  /// 自由摄像机开着没有。
  final bool scene;
  final VoidCallback onScene, onFullscreen, onHandOver;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ShapeToolbar(board: board),
        const SizedBox(width: 8),
        Tooltip(
          message: handOverRequest(board),
          child: FilledButton.icon(
            onPressed: board.layout.isEmpty ? null : onHandOver,
            icon: const Icon(Icons.auto_awesome_outlined, size: 15),
            label: Text(tr('交给 Agent'), style: const TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: PennaColors.primary,
            ),
          ),
        ),
        const Spacer(),
        if (board.threeD)
          IconButton(
            tooltip: tr('自由摄像机'),
            iconSize: 18,
            isSelected: scene,
            color: scene ? PennaColors.primary : null,
            icon: const Icon(Icons.videocam_outlined),
            onPressed: onScene,
          ),
        // 全屏摆放:画布铺满整个软件窗口,方便转镜头、挪框。
        IconButton(
          tooltip: tr('全屏摆放'),
          iconSize: 18,
          icon: const Icon(Icons.fullscreen),
          onPressed: onFullscreen,
        ),
      ],
    );
  }
}

/// 一排形状工具;多边形选中时旁边能调边数。
class _ShapeToolbar extends StatelessWidget {
  const _ShapeToolbar({required this.board});

  final LayoutBoard board;

  @override
  Widget build(BuildContext context) {
    final tools = [
      (ShapeTool.rect, Icons.crop_square, tr('方框')),
      (ShapeTool.ellipse, Icons.circle_outlined, tr('椭圆')),
      (ShapeTool.polygon, Icons.hexagon_outlined, tr('多边形')),
      (ShapeTool.pen, Icons.draw_outlined, tr('钢笔:点出顶点,点回起点或回车封口,Esc 取消')),
    ];
    return ValueListenableBuilder(
      valueListenable: board.shapeTool,
      builder: (context, s, _) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: PennaColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: PennaColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (tool, icon, tip) in tools)
              Tooltip(
                message: tip,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () =>
                      board.shapeTool.value = (tool: tool, sides: s.sides),
                  child: AnimatedContainer(
                    duration: Motion.of(context, Motion.base),
                    curve: Motion.swift,
                    width: 28,
                    height: 26,
                    decoration: BoxDecoration(
                      color: s.tool == tool ? PennaColors.primaryBg : null,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      icon,
                      size: 16,
                      color: s.tool == tool
                          ? PennaColors.primary
                          : PennaColors.slate500,
                    ),
                  ),
                ),
              ),
            // 多边形:调边数,只在选中它时露出来。
            AnimatedSize(
              duration: Motion.of(context, Motion.base),
              curve: Motion.expand,
              child: s.tool != ShapeTool.polygon
                  ? const SizedBox(height: 26)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _step(Icons.remove, tr('少一个顶点'), () {
                          if (s.sides > minShapePoints) {
                            board.shapeTool.value = (
                              tool: s.tool,
                              sides: s.sides - 1,
                            );
                          }
                        }),
                        SizedBox(
                          width: 18,
                          child: Text(
                            '${s.sides}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        _step(Icons.add, tr('多一个顶点'), () {
                          if (s.sides < maxShapePoints) {
                            board.shapeTool.value = (
                              tool: s.tool,
                              sides: s.sides + 1,
                            );
                          }
                        }),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(IconData icon, String tip, VoidCallback onTap) => Tooltip(
    message: tip,
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: SizedBox(
        width: 22,
        height: 26,
        child: Icon(icon, size: 14, color: PennaColors.slate500),
      ),
    ),
  );
}
