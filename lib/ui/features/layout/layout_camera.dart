import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/harness/layout.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../../l10n/l10n.dart';
import 'layout_bodies.dart';
import 'layout_board.dart';
import 'layout_canvas.dart';

part 'layout_light_ball.dart';
part 'layout_lighting.dart';

const _panelWidth = 232.0;
const _railWidth = 40.0;
const _sceneHeight = 150.0;

/// 拖小场景时每移动一个屏幕像素转多少度。
const _orbitPerPx = 0.6, _pitchPerPx = 0.4;

/// 3D 视图里画布右边的部件窗口(不盖住画布):最右一条图标栏一直在,摄像机、灯光
/// 各一个窗口,点图标展开、再点收起、点另一个就换过去(宽度和内容都有过渡),
/// 下面是自由镜头和复位。摄像机窗口:自由镜头的开关、小场景(拖着转镜头、滚轮推拉)、
/// 一行一个参数(箭头一步一步调,按住中间左右拖着调)、选中块的体块。交给 Agent 写描述
/// 只在画布上面那一个「交给 Agent」(用户要求统一成一个按钮)。灯光窗口见 [_LightingSection]。
class CameraPanel extends StatefulWidget {
  const CameraPanel({super.key, required this.board});

  final LayoutBoard board;

  @override
  State<CameraPanel> createState() => _CameraPanelState();
}

/// 部件窗口:摄像机、灯光。
enum _Tab { camera, lighting }

class _CameraPanelState extends State<CameraPanel> {
  /// 展开着的窗口;null 是收起。
  _Tab? _tab = _Tab.camera;

  /// 窗口里画的是哪个:收起的过渡里还画着刚才那个。
  _Tab _shown = _Tab.camera;

  void _toggle(_Tab tab) => setState(() {
    _tab = _tab == tab ? null : tab;
    _shown = tab;
  });

  Camera? _dragFrom;
  Offset _dragStart = Offset.zero;

  LayoutBoard get board => widget.board;

  @override
  Widget build(BuildContext context) {
    final cam = board.layout.camera;
    final dials =
        <
          ({
            String label,
            String unit,
            double value,
            double step,
            double perPx,
            Camera Function(double) apply,
          })
        >[
          (
            label: tr('环绕'),
            unit: '°',
            value: cam.orbit,
            step: 15,
            perPx: 0.5,
            apply: (v) => cam.copyWith(orbit: v),
          ),
          (
            label: tr('俯仰'),
            unit: '°',
            value: cam.pitch,
            step: 5,
            perPx: 0.3,
            apply: (v) => cam.copyWith(pitch: v),
          ),
          (
            label: tr('滚转'),
            unit: '°',
            value: cam.roll,
            step: 5,
            perPx: 0.3,
            apply: (v) => cam.copyWith(roll: v),
          ),
          (
            label: tr('距离'),
            unit: '',
            value: cam.distance,
            step: 0.1,
            perPx: 0.01,
            apply: (v) => cam.copyWith(distance: v),
          ),
          (
            label: tr('视角'),
            unit: '°',
            value: cam.fov,
            step: 5,
            perPx: 0.2,
            apply: (v) => cam.copyWith(fov: v),
          ),
          (
            label: tr('平移 X'),
            unit: '',
            value: cam.panX,
            step: 0.1,
            perPx: 0.005,
            apply: (v) => cam.copyWith(panX: v),
          ),
          (
            label: tr('平移 Y'),
            unit: '',
            value: cam.panY,
            step: 0.1,
            perPx: 0.005,
            apply: (v) => cam.copyWith(panY: v),
          ),
          (
            label: tr('平移 Z'),
            unit: '',
            value: cam.panZ,
            step: 0.1,
            perPx: 0.005,
            apply: (v) => cam.copyWith(panZ: v),
          ),
          (
            label: tr('移轴'),
            unit: '',
            value: cam.shift,
            step: 0.05,
            perPx: 0.003,
            apply: (v) => cam.copyWith(shift: v),
          ),
        ];
    final decoration = BoxDecoration(
      color: PennaColors.card,
      border: Border(left: BorderSide(color: PennaColors.border)),
    );
    final lit = board.layout.lighting.enabled;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 窗口:宽度过渡着展开 / 收起,内容按满宽排好、靠右贴着图标栏,露出多少画多少。
        AnimatedContainer(
          duration: Motion.of(context, Motion.sheet),
          curve: Motion.expand,
          width: _tab == null ? 0 : _panelWidth,
          decoration: decoration,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerRight,
              minWidth: _panelWidth,
              maxWidth: _panelWidth,
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.base),
                switchInCurve: Motion.swift,
                // 默认把内容摆在正中、按内容高度:窗口要撑满整栏、从顶上排。
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: KeyedSubtree(
                  key: ValueKey(_shown),
                  child: _shown == _Tab.camera
                      ? _cameraWindow(cam, dials)
                      : SingleChildScrollView(
                          child: _LightingSection(board: board),
                        ),
                ),
              ),
            ),
          ),
        ),
        Container(
          width: _railWidth,
          decoration: decoration,
          child: Column(
            spacing: 4,
            children: [
              const SizedBox(height: 2),
              _railButton(
                _Tab.camera,
                Icons.videocam_outlined,
                tr('摄像机'),
                PennaColors.primary,
              ),
              _railButton(
                _Tab.lighting,
                lit ? Icons.wb_sunny : Icons.wb_sunny_outlined,
                tr('灯光'),
                PennaColors.amber,
              ),
              const Divider(height: 9, indent: 8, endIndent: 8),
              _freeCamIcon(),
              _resetButton(cam),
            ],
          ),
        ),
      ],
    );
  }

  /// 图标栏上的一个窗口按钮:展开着时底色填上那个窗口的颜色。
  Widget _railButton(_Tab tab, IconData icon, String tip, Color color) {
    final on = _tab == tab;
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _toggle(tab),
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.base),
          curve: Motion.swift,
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: on ? color.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 17, color: on ? color : PennaColors.slate500),
        ),
      ),
    );
  }

  Widget _cameraWindow(
    Camera cam,
    List<
      ({
        String label,
        String unit,
        double value,
        double step,
        double perPx,
        Camera Function(double) apply,
      })
    >
    dials,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(cam),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: _FreeCamButton(
              on: board.freeCam,
              onTap: () => board.setFreeCam(!board.freeCam),
            ),
          ),
          const Divider(height: 1),
          _scene(),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final d in dials)
                  _Dial(
                    label: d.label,
                    value: d.value,
                    unit: d.unit,
                    step: d.step,
                    perPx: d.perPx,
                    onStart: () => board.mark(tr('调整镜头的{0}', [d.label])),
                    onEnd: () => board.mark(null),
                    onChanged: (v, {required bool step}) => board.setCamera(
                      d.apply(v),
                      action: step ? tr('调整镜头的{0}', [d.label]) : null,
                    ),
                  ),
              ],
            ),
          ),
          ?_bodySection(),
        ],
      ),
    );
  }

  /// 选中的那一块的体块:位置、宽高厚、朝向一行一个,改了框马上照它重新投出来。
  /// 斜着看时靠拖框去改体块不好控制,这里直接改数。没选中、文字块没有体块时不显示。
  Widget? _bodySection() {
    final i = board.selected;
    final box = i == null ? null : board.layout.boxes[i];
    final b = box?.body;
    if (i == null || box == null || b == null) return null;
    final name = boxName(box, i);
    double size(double v) => v < 0.01 ? 0.01 : v;
    // 世界坐标的 y 向下,这里换成向上为正,和"往上挪"对得上。
    final rows =
        <
          ({
            String label,
            String unit,
            double value,
            double step,
            double perPx,
            Body Function(double) apply,
          })
        >[
          (
            label: tr('位置 X'),
            unit: '',
            value: b.x,
            step: 0.05,
            perPx: 0.004,
            apply: (v) => b.copyWith(x: v),
          ),
          (
            label: tr('位置 Y'),
            unit: '',
            value: -b.y,
            step: 0.05,
            perPx: 0.004,
            apply: (v) => b.copyWith(y: -v),
          ),
          (
            label: tr('位置 Z'),
            unit: '',
            value: b.z,
            step: 0.05,
            perPx: 0.004,
            apply: (v) => b.copyWith(z: v),
          ),
          (
            label: tr('宽'),
            unit: '',
            value: b.w,
            step: 0.05,
            perPx: 0.003,
            apply: (v) => b.copyWith(w: size(v)),
          ),
          (
            label: tr('高'),
            unit: '',
            value: b.h,
            step: 0.05,
            perPx: 0.003,
            apply: (v) => b.copyWith(h: size(v)),
          ),
          (
            label: tr('厚'),
            unit: '',
            value: b.d,
            step: 0.05,
            perPx: 0.003,
            apply: (v) => b.copyWith(d: size(v)),
          ),
          (
            label: tr('朝向'),
            unit: '°',
            value: b.yaw,
            step: 15,
            perPx: 0.5,
            apply: (v) => b.copyWith(yaw: wrapDegrees(v)),
          ),
        ];
    String what(String label) => tr('调整「{0}」的{1}', [name, label]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
          child: Row(
            children: [
              Icon(
                Icons.view_in_ar_outlined,
                size: 14,
                color: layoutBoxColor(i),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr('体块 · {0}', [name]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Column(
            children: [
              for (final r in rows)
                _Dial(
                  label: r.label,
                  value: r.value,
                  unit: r.unit,
                  step: r.step,
                  perPx: r.perPx,
                  onStart: () => board.mark(what(r.label)),
                  onEnd: () => board.mark(null),
                  onChanged: (v, {required bool step}) => board.setBody(
                    i,
                    r.apply(v),
                    action: step ? what(r.label) : null,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resetButton(Camera cam) => IconButton(
    tooltip: tr('镜头复位'),
    iconSize: 15,
    visualDensity: VisualDensity.compact,
    icon: const Icon(Icons.restart_alt),
    onPressed: cam.isDefault
        ? null
        : () => board.setCamera(const Camera(), action: tr('镜头复位')),
  );

  /// 收起时那条窄边上的自由镜头开关:开着时填满主色,一眼看得出。
  Widget _freeCamIcon() => Tooltip(
    message: board.freeCam ? tr('退出自由镜头') : tr('自由镜头'),
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => board.setFreeCam(!board.freeCam),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: board.freeCam ? PennaColors.primary : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          Icons.open_with,
          size: 16,
          color: board.freeCam ? Colors.white : PennaColors.slate500,
        ),
      ),
    ),
  );

  Widget _header(Camera cam) => SizedBox(
    height: 34,
    child: Row(
      children: [
        const SizedBox(width: 10),
        Icon(Icons.videocam_outlined, size: 15, color: PennaColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            tr('摄像机'),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
        Tooltip(
          richMessage: TextSpan(
            children: [
              for (final (i, (keys, what)) in layoutNavigationTips.indexed)
                TextSpan(
                  children: [
                    if (i > 0) const TextSpan(text: '\n'),
                    TextSpan(
                      text: keys,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: '  $what'),
                  ],
                ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              Icons.keyboard_outlined,
              size: 16,
              color: PennaColors.slate500,
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    ),
  );

  /// 小场景:左右拖是水平环绕,上下拖是俯仰,滚轮推拉镜头。
  Widget _scene() => Listener(
    onPointerSignal: (e) {
      if (e is! PointerScrollEvent) return;
      final c = board.layout.camera;
      board.setCamera(
        c.copyWith(distance: c.distance * math.exp(e.scrollDelta.dy / 600)),
      );
    },
    child: MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        onPanStart: (d) {
          _dragFrom = board.layout.camera;
          _dragStart = d.localPosition;
          board.mark(tr('转动镜头'));
        },
        onPanUpdate: (d) {
          final from = _dragFrom;
          if (from == null) return;
          final m = d.localPosition - _dragStart;
          board.setCamera(
            from.copyWith(
              orbit: from.orbit + m.dx * _orbitPerPx,
              pitch: from.pitch + m.dy * _pitchPerPx,
            ),
          );
        },
        onPanEnd: (_) => _endDrag(),
        onPanCancel: _endDrag,
        child: SizedBox(
          height: _sceneHeight,
          child: CustomPaint(
            painter: OrbitPainter(
              board.layout,
              layoutBodyColor,
              grid: PennaColors.slate400,
            ),
          ),
        ),
      ),
    ),
  );

  void _endDrag() {
    _dragFrom = null;
    board.mark(null);
  }
}

/// 一行参数:◀ 名字 数值 ▶。点箭头走一步,按住中间左右拖着调。
class _Dial extends StatefulWidget {
  const _Dial({
    required this.label,
    required this.value,
    required this.unit,
    required this.step,
    required this.perPx,
    required this.onStart,
    required this.onEnd,
    required this.onChanged,
  });

  final String label, unit;
  final double value, step, perPx;
  final VoidCallback onStart, onEnd;
  final void Function(double value, {required bool step}) onChanged;

  @override
  State<_Dial> createState() => _DialState();
}

class _DialState extends State<_Dial> {
  double _from = 0, _dx = 0;

  String get _text => widget.unit == '°' || widget.unit == 'K'
      ? '${widget.value.round()}${widget.unit}'
      : widget.value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, double sign) => InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () =>
          widget.onChanged(widget.value + sign * widget.step, step: true),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Icon(icon, size: 14, color: PennaColors.slate500),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Container(
        height: 24,
        decoration: BoxDecoration(
          color: PennaColors.slate50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: PennaColors.border),
        ),
        child: Row(
          children: [
            arrow(Icons.chevron_left, -1),
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {
                    _from = widget.value;
                    _dx = 0;
                    widget.onStart();
                  },
                  onHorizontalDragUpdate: (d) {
                    _dx += d.delta.dx;
                    widget.onChanged(_from + _dx * widget.perPx, step: false);
                  },
                  onHorizontalDragEnd: (_) => widget.onEnd(),
                  onHorizontalDragCancel: widget.onEnd,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: PennaColors.slate700,
                          ),
                        ),
                      ),
                      Text(
                        _text,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: PennaColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            arrow(Icons.chevron_right, 1),
          ],
        ),
      ),
    );
  }
}

/// 自由镜头的开关,放在「摄像机」标题下面:开着时填满主色、写着怎么退出。
class _FreeCamButton extends StatelessWidget {
  const _FreeCamButton({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = on ? Colors.white : PennaColors.slate700;
    return Material(
      color: on ? PennaColors.primary : PennaColors.slate50,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: on ? PennaColors.primary : PennaColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.open_with, size: 15, color: fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  on ? tr('自由镜头中') : tr('自由镜头'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              Text(
                on ? 'Esc' : 'Shift+`',
                style: TextStyle(
                  fontSize: 11,
                  color: fg.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
