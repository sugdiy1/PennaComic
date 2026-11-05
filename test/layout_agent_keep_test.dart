import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/core/harness/layout_3d.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/layout/layout_canvas.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

String _draft(String items, {int w = 100, int h = 200}) =>
    '{"width": $w, "height": $h, "summary": {"caption": "new scene"}, '
    '"items": [$items], "bbox_coord_space": "abs", "bbox_format": "xyxy"}';

LayoutBoard _two() => LayoutBoard()
  ..setSize(100, 200)
  ..addBox(const LayoutBox(left: 0, top: 0, right: 40, bottom: 40, name: 'A'))
  ..addBox(
    const LayoutBox(left: 50, top: 100, right: 90, bottom: 190, name: 'B'),
  );

void main() {
  testWidgets('拖到一半 Agent 放上了新布局:这次拖动作废,不去改别的块', (tester) async {
    final board = _two();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 400,
            child: LayoutCanvas(board: board),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(LayoutCanvas));
    // A 在画布 (0,0)–(40,40),屏幕上是它的两倍。
    final g = await tester.startGesture(origin + const Offset(40, 40));
    await g.moveBy(const Offset(20, 0));
    await tester.pump();
    await g.moveBy(const Offset(20, 0));
    await tester.pump();
    // 新布局里先后换了(B 在前),位置也都不一样。
    board.apply(
      _draft(
        '{"name": "B", "bbox": [10, 120, 30, 180]}, '
        '{"name": "A", "bbox": [60, 10, 90, 40]}',
      ),
    );
    final placed = [for (final b in board.layout.boxes) (b.name, b.left)];
    await g.moveBy(const Offset(40, 40));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect([for (final b in board.layout.boxes) (b.name, b.left)], placed);
  });

  test('交给 Agent:只收描述和程序猜的体块,框、图层、名字和用户调过的体块照旧', () {
    final board = _two()..setThreeD(true);
    // B 的体块是用户在摄像机栏里调过的,不再算猜的。
    final iB = board.layout.boxes.indexWhere((b) => b.name == 'B');
    board.setBody(iB, board.layout.boxes[iB].body!.copyWith(z: 1.4));
    final before = board.layout.boxes;
    final bodyB = before.firstWhere((b) => b.name == 'B').body;
    final request = handOverRequest(board);
    expect(request, contains('程序猜的体块'));
    expect(
      board.apply(
        _draft(
          '{"name": "B", "caption": "B from the side", "bbox": [0, 0, 10, 10], '
          '"body": {"distance": 3, "depth": 1, "yaw": 40}}, '
          '{"name": "A", "caption": "A seen from above", "bbox": [0, 0, 10, 10], '
          '"body": {"distance": 3, "depth": 1, "yaw": 40}}',
        ),
        keep: layoutKeepFor(request),
      ),
      isTrue,
    );
    final after = board.layout.boxes;
    expect([for (final b in after) b.name], [for (final b in before) b.name]);
    expect(
      [for (final b in after) (b.left, b.top, b.right, b.bottom)],
      [for (final b in before) (b.left, b.top, b.right, b.bottom)],
    );
    final a = after.firstWhere((b) => b.name == 'A');
    expect(a.caption, 'A seen from above');
    expect(a.body!.guessed, isFalse);
    final b = after.firstWhere((b) => b.name == 'B');
    expect(b.caption, 'B from the side');
    expect(b.body, bodyB);
    expect(board.layout.caption, 'new scene');
    expect(layoutKeepFor('随便说的话'), LayoutKeep.none);
  });

  test('3D 里同一条回复有透视和布局:先转镜头再立体块,写着正对镜头的人还是正对着', () async {
    final board = LayoutBoard()..setSize(1216, 832);
    board.setThreeD(true);
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final chat = StudioViewModel(
      config: service,
      layout: board,
      layoutOnly: true,
      streamChat: (_) => Stream.value(
        '<perspective>{"vanishing": [[-600, 280], [1800, 280]]}</perspective>'
        '<layout>${_draft('{"name": "人", "label": "character", '
        '"body": {"distance": 1, "depth": 0.5, "yaw": 0}, '
        '"bbox": [400, 200, 600, 800]}', w: 1216, h: 832)}</layout>',
      ),
    );
    chat.send('照这张图排');
    await pumpEventQueue();
    final l = board.layout;
    expect(l.camera.orbit, isNot(0));
    final person = l.boxes.single;
    expect((person.left - 400).abs(), lessThan(20));
    expect((person.right - 600).abs(), lessThan(20));
    final view = CameraView(l.camera, l.width, l.height);
    expect(facingOf(person.body!, view), startsWith('面朝镜头'));
    expect(describeCamera(l, threeD: true), contains('【朝向】'));
    expect(describeCamera(l, threeD: true), contains('不是人物的朝向'));
  });
}
