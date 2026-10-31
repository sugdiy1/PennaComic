part of 'layout_canvas.dart';

/// 鼠标拖镜头时每移动一个屏幕像素转多少度。
const _orbitPerPx = 0.4, _pitchPerPx = 0.3;

/// 自由镜头里拖动转头时每个屏幕像素转多少度(比环绕慢,好瞄准)。
const _lookPerPx = 0.15;

/// 自由镜头每秒走多远(按镜头离目标点的距离算);按着 Shift 快三倍。
const _walkSpeed = 0.8, _walkFast = 3.0;

/// 小键盘一下转多少度。
const _step = 15.0;

/// 拖镜头的几种:转(中键、右键)、平移(加 Shift)、推拉(加 Ctrl)。
enum _CamDrag { orbit, pan, dolly }

final _walkKeys = {
  LogicalKeyboardKey.keyW,
  LogicalKeyboardKey.keyA,
  LogicalKeyboardKey.keyS,
  LogicalKeyboardKey.keyD,
  LogicalKeyboardKey.keyQ,
  LogicalKeyboardKey.keyE,
};

/// 3D 视图里的操作,照 Blender 的习惯:中键拖转、Shift+中键平移、Ctrl+中键或滚轮推拉
/// (右键也能拖,给没有中键的鼠标);小键盘 1 / 3 / 7 正面、右侧、顶视(加 Ctrl 反过来),
/// 2 4 6 8 一下转 15°,9 转到背面,`.` 绕着选中的块转,Home 复位;
/// Shift+` 开自由镜头:左键拖动转头,WASD 走、QE 降升,Esc 退出。
extension _Navigation on _LayoutCanvasState {
  void _cameraDown(PointerDownEvent e) {
    if (!_board.threeD) return;
    final right = e.buttons & kSecondaryMouseButton != 0;
    final middle = e.buttons & kTertiaryButton != 0;
    if (!right && !middle) return;
    final keys = HardwareKeyboard.instance;
    _camDrag = keys.isShiftPressed
        ? _CamDrag.pan
        : keys.isControlPressed
        ? _CamDrag.dolly
        : _CamDrag.orbit;
    _camFrom = e.localPosition;
    _camStart = _board.layout.camera;
    _board.mark(switch (_camDrag) {
      _CamDrag.pan => tr('平移镜头'),
      _CamDrag.dolly => tr('推拉镜头'),
      _CamDrag.orbit => tr('转动镜头'),
    });
  }

  void _cameraMove(PointerMoveEvent e, double scale) {
    final from = _camFrom, c = _camStart;
    if (from == null || c == null) return;
    final d = e.localPosition - from;
    final l = _board.layout;
    _board.setCamera(switch (_camDrag) {
      _CamDrag.pan => panned(c, d.dx / scale, d.dy / scale, l.width, l.height),
      _CamDrag.dolly => c.copyWith(distance: c.distance * math.exp(d.dy / 200)),
      _CamDrag.orbit => c.copyWith(
        orbit: c.orbit + d.dx * _orbitPerPx,
        pitch: c.pitch + d.dy * _pitchPerPx,
      ),
    });
  }

  void _cameraUp() {
    if (_camFrom == null) return;
    _camFrom = null;
    _camStart = null;
    _board.mark(null);
  }

  /// 滚轮推拉镜头(不记进操作记录,滚一下就是一步太碎)。
  void _zoom(PointerSignalEvent e) {
    if (!_board.threeD || e is! PointerScrollEvent) return;
    final c = _board.layout.camera;
    final next = c.copyWith(
      distance: c.distance * math.exp(e.scrollDelta.dy / 600),
    );
    _board.freeCam ? _board.moveFree(next) : _board.setCamera(next);
  }

  /// 自由镜头里左键拖动:原地转头。
  void _look(Offset from, Offset to, Camera start) => _board.moveFree(
    lookAround(
      start,
      (to.dx - from.dx) * _lookPerPx,
      (to.dy - from.dy) * _lookPerPx,
    ),
  );

  /// 3D 视图里的快捷键;认得的返回 handled。
  KeyEventResult _navKey(KeyEvent e) {
    if (!_board.threeD) return KeyEventResult.ignored;
    final key = e.logicalKey;
    if (_board.freeCam && _walkKeys.contains(key)) {
      if (e is KeyDownEvent && !_walker.isActive) {
        _walkedAt = Duration.zero;
        _walker.start();
      }
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.escape && _board.freeCam) {
      _board.setFreeCam(false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backquote && keys.isShiftPressed ||
        key == LogicalKeyboardKey.tilde) {
      _board.setFreeCam(!_board.freeCam);
      return KeyEventResult.handled;
    }
    final c = _board.layout.camera;
    final flip = keys.isControlPressed;
    bool k(LogicalKeyboardKey pad, [LogicalKeyboardKey? row]) =>
        key == pad || key == row;
    final view = switch (key) {
      _ when k(LogicalKeyboardKey.numpad1, LogicalKeyboardKey.digit1) =>
        c.copyWith(orbit: flip ? 180 : 0, pitch: 0, roll: 0),
      _ when k(LogicalKeyboardKey.numpad3, LogicalKeyboardKey.digit3) =>
        c.copyWith(orbit: flip ? 90 : -90, pitch: 0, roll: 0),
      _ when k(LogicalKeyboardKey.numpad7, LogicalKeyboardKey.digit7) =>
        c.copyWith(pitch: flip ? -89 : 89, roll: 0),
      _ when k(LogicalKeyboardKey.numpad2, LogicalKeyboardKey.digit2) =>
        c.copyWith(pitch: c.pitch - _step),
      _ when k(LogicalKeyboardKey.numpad8, LogicalKeyboardKey.digit8) =>
        c.copyWith(pitch: c.pitch + _step),
      _ when k(LogicalKeyboardKey.numpad4, LogicalKeyboardKey.digit4) =>
        c.copyWith(orbit: c.orbit + _step),
      _ when k(LogicalKeyboardKey.numpad6, LogicalKeyboardKey.digit6) =>
        c.copyWith(orbit: c.orbit - _step),
      _ when k(LogicalKeyboardKey.numpad9, LogicalKeyboardKey.digit9) =>
        c.copyWith(orbit: c.orbit + 180),
      _ when k(LogicalKeyboardKey.numpadDecimal, LogicalKeyboardKey.period) =>
        _focusSelected(c),
      LogicalKeyboardKey.home => const Camera(),
      _ => null,
    };
    if (view != null) {
      _board.setCamera(view, action: tr('切换视角'));
      return KeyEventResult.handled;
    }
    final zoom = switch (key) {
      _ when k(LogicalKeyboardKey.numpadAdd, LogicalKeyboardKey.equal) => 0.9,
      _ when k(LogicalKeyboardKey.numpadSubtract, LogicalKeyboardKey.minus) =>
        1 / 0.9,
      _ => null,
    };
    if (zoom != null) {
      _board.setCamera(c.copyWith(distance: c.distance * zoom));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 小键盘 `.`:目标点挪到选中的那块的体块中心;没选中或没有体块时不动。
  Camera? _focusSelected(Camera c) {
    final i = _board.selected;
    final body = i == null ? null : _board.layout.boxes[i].body;
    return body == null ? null : focusOn(c, body.center);
  }

  /// 自由镜头里按着 WASDQE 时每一帧走一点;都松开就停。
  void _walkTick(Duration now) {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    if (!_board.freeCam || !pressed.any(_walkKeys.contains)) {
      _walker.stop();
      return;
    }
    final dt = (now - _walkedAt).inMicroseconds / 1e6;
    _walkedAt = now;
    if (dt <= 0 || dt > 0.1) return; // 第一帧和卡顿的那一帧不走
    final c = _board.layout.camera;
    final fast = HardwareKeyboard.instance.isShiftPressed ? _walkFast : 1;
    final d = c.distance * _walkSpeed * fast * dt;
    double axis(LogicalKeyboardKey plus, LogicalKeyboardKey minus) =>
        (pressed.contains(plus) ? d : 0) - (pressed.contains(minus) ? d : 0);
    _board.moveFree(
      walk(
        c,
        forward: axis(LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyS),
        right: axis(LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyA),
        up: axis(LogicalKeyboardKey.keyE, LogicalKeyboardKey.keyQ),
      ),
    );
  }
}

/// 3D 导航的快捷键,摄像机面板的问号里列出来:(按键, 做什么)。
List<(String, String)> get layoutNavigationTips => [
  (tr('中键拖动'), tr('转动镜头')),
  ('Shift + ${tr('中键')}', tr('平移镜头')),
  ('Ctrl + ${tr('中键')} / ${tr('滚轮')}', tr('推拉镜头')),
  ('1 / 3 / 7', tr('正面 / 右侧 / 顶视(Ctrl 反向)')),
  ('2 4 6 8 / 9', tr('转 15° / 转到背面')),
  ('.', tr('绕着选中的块转')),
  ('Home', tr('镜头复位')),
  ('Shift + `', tr('自由镜头')),
  ('W A S D / Q E', tr('走动 / 降升')),
  (tr('左键拖动'), tr('自由镜头里转头')),
  ('Esc', tr('退出自由镜头')),
];
