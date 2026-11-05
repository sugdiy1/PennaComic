import 'package:flutter/widgets.dart';

/// 动效令牌:时长四档、曲线三种,都是快起慢收。各处的动画只用这里的,
/// 不再各写各的毫秒数(参考 open-claude-ui 的拆解:克制靠的是一套统一的约束)。
abstract final class Motion {
  /// 按下、焦点环。
  static const fast = Duration(milliseconds: 60);

  /// 分段按钮、标签切换、小的颜色变化。
  static const snap = Duration(milliseconds: 120);

  /// 悬停、菜单、折叠展开、卡片变化。
  static const base = Duration(milliseconds: 200);

  /// 侧栏、面板、新出现的块。
  static const sheet = Duration(milliseconds: 300);

  /// 悬停、阴影、颜色:一下就到位,尾巴拖得很轻。
  static const swift = Cubic(0.16, 1, 0.3, 1);

  /// 折叠展开、尺寸变化。
  static const expand = Cubic(0.19, 1, 0.22, 1);

  /// 新块入场。
  static const enter = Cubic(0.22, 1, 0.36, 1);

  /// 系统设置了「减少动画」时动画直接跳到结尾。
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;
}
