part of 'layout_board.dart';

/// 打光辅助:灯光存在 [Layout.lighting] 里,跟着这一页走;框和体块不动。
extension LayoutLighting on LayoutBoard {
  /// 换成 [lighting](摄像机栏里的灯光面板)。拖灯时只有第一帧带 [action]。
  void setLighting(Lighting lighting, {String? action}) {
    if (lighting == _layout.lighting) return;
    _set(_layout.copyWith(lighting: lighting), action: action);
  }

  /// 照 Agent 写的 `<lighting>` 改灯光(见 [applyLightingSpec]);读不了返回 false,画板不动。
  bool applyLighting(String spec) {
    final l = _layout;
    final next = applyLightingSpec(spec, l.lighting, l.camera);
    if (next == null) return false;
    _set(l.copyWith(lighting: next), action: tr('Agent 调整灯光'));
    return true;
  }
}
