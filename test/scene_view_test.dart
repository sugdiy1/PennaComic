import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/layout/layout_scene_view.dart';

LayoutBoard _board() {
  final board = LayoutBoard()..setSize(1216, 832);
  board
    ..addBox(
      const LayoutBox(
        left: 100,
        top: 200,
        right: 400,
        bottom: 800,
        label: 'character',
        name: '人',
      ),
    )
    ..addBox(
      const LayoutBox(left: 700, top: 300, right: 1100, bottom: 700, name: '桌'),
    );
  board.setThreeD(true);
  return board;
}

void main() {
  test('横画布在宽的地方上下摆,竖画布左右摆', () {
    expect(sceneStacked(1216 / 832, const Size(800, 900)), isTrue);
    expect(sceneStacked(832 / 1216, const Size(800, 900)), isFalse);
    expect(sceneStacked(1, const Size(1600, 600)), isFalse);
  });

  test('视线和地面求交:往下看能落地,往上看落不了', () {
    final view = CameraView(const Camera(pitch: 30), 100, 100);
    final hit = hitGround(view, 50, 50, 0.5)!;
    expect(hit.y, 0.5);
    expect(hit.z, greaterThan(view.eye.z));
    expect(
      hitGround(CameraView(const Camera(pitch: -30), 100, 100), 50, 50, 0.5),
      isNull,
    );
  });

  test('视口镜头框得住所有体块和主镜头', () {
    final l = _board().layout;
    final view = CameraView(fitSceneCamera(l), 400, 300);
    final pts = [
      CameraView(l.camera, l.width, l.height).eye,
      for (final b in l.boxes) ...b.body!.corners,
    ];
    for (final p in pts) {
      final q = view.project(p)!;
      expect(q.u, inInclusiveRange(0, 400));
      expect(q.v, inInclusiveRange(0, 300));
    }
  });

  testWidgets('在自由视图里拖体块:它在地面上挪,别的块不动,主画布的框跟着变', (tester) async {
    final board = _board();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: SceneView(board: board),
          ),
        ),
      ),
    );
    final i = board.layout.boxes.indexWhere((b) => b.name == '桌');
    final body = board.layout.boxes[i].body!;
    final view = CameraView(fitSceneCamera(board.layout), 400, 300);
    final c = view.project(body.center)!;
    final other = board.layout.boxes.firstWhere((b) => b.name == '人');
    final before = board.layout.boxes[i];
    final origin = tester.getTopLeft(find.byType(SceneView));
    final g = await tester.startGesture(origin + Offset(c.u, c.v));
    await g.moveBy(const Offset(10, 0));
    await g.moveBy(const Offset(30, 0));
    await g.up();
    await tester.pump();
    final moved = board.layout.boxes.firstWhere((b) => b.name == '桌');
    expect(moved.body!.y, closeTo(body.y, 1e-9));
    expect(
      (moved.body!.x - body.x).abs() + (moved.body!.z - body.z).abs(),
      greaterThan(0.01),
    );
    expect(moved.left, isNot(before.left));
    final still = board.layout.boxes.firstWhere((b) => b.name == '人');
    expect(still.body, other.body);
    expect(still.left, other.left);
  });

  testWidgets('体块拖到主镜头外面后,视口里照样画着、还能拖回来', (tester) async {
    final board = _board();
    final i = board.layout.boxes.indexWhere((b) => b.name == '桌');
    final body = board.layout.boxes[i].body!;
    board.setBody(i, body.copyWith(x: body.x - 3));
    final gone = board.layout.boxes.firstWhere((b) => b.name == '桌');
    expect(gone.offscreen, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: SceneView(board: board),
          ),
        ),
      ),
    );
    final view = CameraView(fitSceneCamera(board.layout), 400, 300);
    final c = view.project(gone.body!.center)!;
    final origin = tester.getTopLeft(find.byType(SceneView));
    final g = await tester.startGesture(origin + Offset(c.u, c.v));
    await g.moveBy(const Offset(10, 0));
    await g.moveBy(const Offset(30, 0));
    await g.up();
    await tester.pump();
    final back = board.layout.boxes.firstWhere((b) => b.name == '桌');
    expect(back.body!.x, isNot(gone.body!.x));
  });
}
