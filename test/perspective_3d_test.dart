import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/core/harness/layout_3d.dart';
import 'package:penna/ui/features/layout/layout_board.dart';

const _w = 832, _h = 1216;

void main() {
  test('三点透视:镜头算出透视线,再照透视线算回镜头,俯仰、环绕、视角、移轴都对得上', () {
    for (final c in const [
      Camera(orbit: 25, pitch: 15),
      Camera(orbit: -40, pitch: -20, fov: 35),
      Camera(orbit: 150, pitch: 30, shift: 0.1),
    ]) {
      final p = perspectiveFromCamera(c, _w, _h, 3);
      final back = cameraFromPerspective(
        p,
        c.copyWith(orbit: c.orbit + 5),
        _w,
        _h,
      );
      expect(back.orbit, closeTo(c.orbit, 0.5), reason: '$c');
      expect(back.pitch, closeTo(c.pitch, 0.5), reason: '$c');
      expect(back.fov, closeTo(c.fov, 0.5), reason: '$c');
      expect(back.shift, closeTo(c.shift, 0.005), reason: '$c');
    }
  });

  test('三点透视里一个点在正中、竖直的点在它正下方(正对前方低头):照样算出俯仰', () {
    for (final c in const [Camera(pitch: 25), Camera(pitch: -30)]) {
      final p = perspectiveFromCamera(c, _w, _h, 3);
      final back = cameraFromPerspective(p, const Camera(), _w, _h);
      expect(back.pitch, closeTo(c.pitch, 0.5), reason: '$c');
      expect(back.orbit, closeTo(0, 0.5), reason: '$c');
      // 算回去的透视线和原来的对得上。
      final again = perspectiveFromCamera(back, _w, _h, 3);
      expect((again.horizon - p.horizon).abs(), lessThanOrEqualTo(2));
      expect((again.third!.y - p.third!.y).abs(), lessThanOrEqualTo(3));
    }
  });

  test('两点透视:镜头保持水平,用移轴把地平线放到画的位置,竖线不收拢', () {
    const c = Camera(orbit: 30, shift: -0.2, fov: 60);
    final p = perspectiveFromCamera(c, _w, _h, 2);
    final back = cameraFromPerspective(p, const Camera(orbit: 20), _w, _h);
    expect(back.pitch, 0);
    expect(back.orbit, closeTo(30, 0.5));
    expect(back.fov, closeTo(60, 0.5));
    expect(back.shift, closeTo(-0.2, 0.005));
    // 竖直方向的消失点在无穷远:竖线平行。
    expect(
      perspectiveFromCamera(back, _w, _h, 3).third!.y.abs(),
      greaterThan(_h * 10),
    );
  });

  test('正面平视是一点透视:消失点在正中,地平线在中间;俯视地平线往上走', () {
    final p = perspectiveFromCamera(const Camera(), _w, _h, 1);
    expect(p.xs.single, _w ~/ 2);
    expect(p.horizon, _h ~/ 2);
    final down = perspectiveFromCamera(const Camera(pitch: 20), _w, _h, 3);
    expect(down.horizon, lessThan(_h ~/ 2));
    // 俯视时竖直方向的消失点在画面下方。
    expect(down.third!.y, greaterThan(_h));
  });

  test('一点透视的消失点往左拖,镜头往反方向转;三点透视把竖直的点拖到下面是俯视', () {
    final p = perspectiveFromCamera(const Camera(), _w, _h, 1);
    final turned = cameraFromPerspective(
      p.copyWith(xs: [p.xs.single - 200]),
      const Camera(),
      _w,
      _h,
    );
    expect(turned.orbit, greaterThan(0));
    final three = perspectiveFromCamera(
      const Camera(orbit: 30, pitch: 5),
      _w,
      _h,
      3,
    );
    final down = cameraFromPerspective(
      three.copyWith(third: (x: three.third!.x, y: _h * 2)),
      const Camera(orbit: 30, pitch: 5),
      _w,
      _h,
    );
    expect(down.pitch, greaterThan(5));
  });

  test('开着透视时,站在地上的东西底边越低越近', () {
    final l = Layout(
      width: _w,
      height: _h,
      perspective: Perspective.preset(1, _w, _h),
    );
    LayoutBox at(int bottom) => liftBox(
      LayoutBox(left: 300, top: bottom - 300, right: 500, bottom: bottom),
      l,
    );
    final near = at(_h), far = at(_h ~/ 2 + 120);
    final view = CameraView(l.camera, _w, _h);
    expect(
      view.toCamera(near.body!.center).z,
      lessThan(view.toCamera(far.body!.center).z),
    );
    expect(horizonOf(l), _h ~/ 2);
  });

  test('开着两点透视切到 3D:镜头水平、移轴对上地平线,框不动,不算转过镜头', () {
    final board = LayoutBoard()
      ..replace(
        const Layout(
          width: _w,
          height: _h,
          boxes: [LayoutBox(left: 200, top: 400, right: 500, bottom: 1100)],
          perspective: Perspective(horizon: 300, xs: [-500, 1400]),
        ),
      );
    final before = board.layout.boxes.single;
    board.setThreeD(true);
    final l = board.layout;
    expect(l.camera.pitch, 0);
    expect(l.camera.shift, lessThan(0)); // 地平线在上面:底片往上挪
    expect(board.cameraMoved, isFalse);
    final after = l.boxes.single;
    expect((after.left - before.left).abs(), lessThanOrEqualTo(2));
    expect((after.bottom - before.bottom).abs(), lessThanOrEqualTo(2));
    expect((l.perspective!.horizon - 300).abs(), lessThanOrEqualTo(2));
  });

  test('3D 视图里拖消失点就是转镜头,透视线跟着镜头走', () {
    final board = LayoutBoard()
      ..replace(const Layout(width: _w, height: _h))
      ..setThreeD(true)
      ..setPerspective(1);
    expect(board.layout.perspective!.xs.single, _w ~/ 2);
    board.moveVanishing(0, _w / 2 - 300, _h / 2 - 200);
    final l = board.layout;
    expect(l.camera.orbit, greaterThan(0));
    expect(l.camera.shift, lessThan(0));
    expect(
      (l.perspective!.xs.single - (_w ~/ 2 - 300)).abs(),
      lessThanOrEqualTo(2),
    );
    expect(
      (l.perspective!.horizon - (_h ~/ 2 - 200)).abs(),
      lessThanOrEqualTo(2),
    );
  });
}
