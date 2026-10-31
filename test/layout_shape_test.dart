import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:flutter/services.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/layout/layout_canvas.dart';
import 'package:penna/ui/features/layout/layout_canvas_tools.dart';

const _tri = LayoutBox(left: 100, top: 100, right: 300, bottom: 300);

/// 一块 400×400 的画布,屏幕上一比一,返回它左上角在屏幕上的位置。
Future<Offset> _canvas(WidgetTester tester, LayoutBoard board) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 400,
            child: LayoutCanvas(board: board),
          ),
        ),
      ),
    ),
  );
  return tester.getTopLeft(find.byType(LayoutCanvas));
}

void main() {
  testWidgets('形状工具:选椭圆、多边形后在空白处拖出来的就是那个形状,框是外框', (tester) async {
    final board = LayoutBoard()..setSize(400, 400);
    final o = await _canvas(tester, board);
    Future<void> drag(Offset a, Offset b) async {
      final g = await tester.startGesture(o + a);
      await g.moveTo(o + (a + b) / 2);
      await g.moveTo(o + b);
      await g.up();
      await tester.pump();
    }

    board.shapeTool.value = (tool: ShapeTool.ellipse, sides: 5);
    await drag(const Offset(20, 20), const Offset(120, 100));
    final oval = board.layout.boxes.single;
    expect(oval.shape!.isEllipse, isTrue);
    expect((oval.left, oval.top, oval.right, oval.bottom), (20, 20, 120, 100));

    board.shapeTool.value = (tool: ShapeTool.polygon, sides: 6);
    await drag(const Offset(200, 200), const Offset(380, 380));
    expect(
      board.layout.boxes.where((b) => b.shape == LayoutShape.regular(6)),
      hasLength(1),
    );
  });

  testWidgets('钢笔:点出顶点,点回起点封口成一块;回车也能封口,Esc 取消', (tester) async {
    final board = LayoutBoard()..setSize(400, 400);
    final o = await _canvas(tester, board);
    board.shapeTool.value = (tool: ShapeTool.pen, sides: 5);
    await tester.pump();
    for (final p in const [
      Offset(50, 300),
      Offset(150, 100),
      Offset(250, 300),
    ]) {
      await tester.tapAt(o + p);
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(board.layout.boxes, isEmpty);
    // 点回起点:封口。
    await tester.tapAt(o + const Offset(52, 298));
    await tester.pump();
    final tri = board.layout.boxes.single;
    expect((tri.left, tri.top, tri.right, tri.bottom), (50, 100, 250, 300));
    expect(tri.shape!.points, hasLength(3));
    expect(tri.shapePoints[1], (150.0, 100.0));

    // 回车封口;退格删掉多点的那个。
    for (final p in const [
      Offset(300, 20),
      Offset(390, 20),
      Offset(390, 90),
      Offset(10, 10),
    ]) {
      await tester.tapAt(o + p);
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(board.layout.boxes, hasLength(2));
    expect(
      board.layout.boxes.where((b) => b.left == 300 && b.right == 390),
      hasLength(1),
    );

    // Esc 取消,什么都不加。
    await tester.tapAt(o + const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tapAt(o + const Offset(220, 220));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(o + const Offset(240, 200));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(board.layout.boxes, hasLength(2));
  });

  testWidgets('3D 视图里异形挤成柱体画,框只是外框:转着镜头、开着光影预览也画得出,按框点得中', (tester) async {
    final board = LayoutBoard()
      ..setSize(400, 400)
      ..addBox(
        const LayoutBox(
          left: 40,
          top: 40,
          right: 180,
          bottom: 180,
          shape: LayoutShape.ellipse(),
        ),
      )
      ..addBox(_tri.copyWith(shape: () => LayoutShape.regular(5)))
      ..setThreeD(true);
    board.setLighting(presetLighting('rembrandt', null));
    board.setCamera(const Camera(orbit: 40, pitch: 15));
    final o = await _canvas(tester, board);
    expect(tester.takeException(), isNull);
    // 椭圆框的左上角(椭圆外面):3D 里按框点,也选得中它。
    final oval = board.layout.boxes.indexWhere((b) => b.shape!.isEllipse);
    final b = board.layout.boxes[oval];
    board.select(null);
    await tester.tapAt(o + Offset(b.left + 3.0, b.top + 3.0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(board.selected, oval);
  });

  test('交给 Agent:系统提示里有【形状】,按形状改描述只收描述', () {
    final board = LayoutBoard()
      ..setSize(400, 400)
      ..addBox(_tri.copyWith(name: '山', shape: () => LayoutShape.regular(3)))
      ..addBox(const LayoutBox(left: 0, top: 0, right: 50, bottom: 50));
    expect(board.prompt, contains('【形状】'));
    expect(board.prompt, contains('山:三角形'));
    expect(describeShapes(const Layout()), isEmpty);
    // 有异形时,「交给 Agent」那句话点名要它照【形状】写;回复只收描述。
    final request = handOverRequest(board);
    expect(request, contains('【形状】'));
    expect(layoutKeepFor(request), LayoutKeep.describe);
    expect(boxFromPolygon(const [(0, 0), (10, 0), (20, 0)]), isNull);
  });

  test('正多边形撑满框;椭圆和多边形按形状判断点在不在里面', () {
    final s = LayoutShape.regular(3);
    expect(s.points, hasLength(3));
    expect(s.points.map((p) => p.$1).reduce((a, b) => a < b ? a : b), 0);
    expect(s.points.map((p) => p.$2).reduce((a, b) => a > b ? a : b), 1);
    expect(LayoutShape.regular(40).points, hasLength(maxShapePoints));

    final tri = _tri.copyWith(shape: () => s);
    expect(tri.covers(200, 250), isTrue);
    expect(tri.covers(110, 110), isFalse); // 框里、三角形外
    final oval = _tri.copyWith(shape: () => const LayoutShape.ellipse());
    expect(oval.covers(200, 200), isTrue);
    expect(oval.covers(105, 105), isFalse);
    expect(_tri.covers(105, 105), isTrue);
  });

  test('拖一个顶点:框换成新的外框,别的顶点在画布上不动', () {
    final tri = _tri.copyWith(shape: () => LayoutShape.regular(3));
    final moved = tri.withVertex(0, 200, 40);
    expect(
      (moved.left, moved.top, moved.right, moved.bottom),
      (100, 40, 300, 300),
    );
    expect(moved.shapePoints.skip(1), [(300.0, 300.0), (100.0, 300.0)]);
    // 挤成一条线的不收。
    final flat = moved.withVertex(0, 200, 300);
    expect(flat, same(moved));
  });

  test('存盘读回形状一样;交出去的 JSON 只有方框,给 Agent 的带形状', () {
    final l = Layout(
      width: 400,
      height: 400,
      boxes: [
        _tri.copyWith(shape: () => LayoutShape.regular(3)),
        _tri.copyWith(shape: () => const LayoutShape.ellipse()),
      ],
    );
    final back = Layout.fromJson(
      jsonDecode(jsonEncode(l.toJson())) as Map<String, dynamic>,
    );
    expect(back.boxes[0].shape, LayoutShape.regular(3));
    expect(back.boxes[1].shape!.isEllipse, isTrue);

    final out = jsonDecode(mossLayoutJson(l)) as Map;
    final item = (out['items'] as List).first as Map;
    expect(item.containsKey('shape'), isFalse);
    expect(item['bbox'], [-100, -100, 100, 100]);

    final draft = jsonDecode(mossLayoutJson(l, draft: true)) as Map;
    final items = draft['items'] as List;
    expect((items[0] as Map)['shape'], [
      [200, 100],
      [300, 300],
      [100, 300],
    ]);
    expect((items[1] as Map)['shape'], 'ellipse');
  });

  test('读 Agent 写的形状:没写 bbox 拿顶点外框;写了 bbox 形状拉伸进去', () {
    final read = parseMossLayout(
      jsonEncode({
        'summary': {'caption': ''},
        'items': [
          {
            'caption': '山',
            'shape': [
              [200, 100],
              [300, 300],
              [100, 300],
            ],
          },
          {
            'caption': '挪过的山',
            'bbox': [0, 0, 100, 100],
            'shape': [
              [200, 100],
              [300, 300],
              [100, 300],
            ],
          },
          {
            'caption': '脸',
            'bbox': [10, 10, 50, 50],
            'shape': 'ellipse',
          },
        ],
        'bbox_coord_space': 'abs',
        'bbox_format': 'xyxy',
      }),
      width: 400,
      height: 400,
    )!;
    final [mountain, movedMountain, face] = read.boxes;
    expect(
      (mountain.left, mountain.top, mountain.right, mountain.bottom),
      (100, 100, 300, 300),
    );
    expect(mountain.shape, LayoutShape.regular(3));
    expect(movedMountain.right, 100);
    expect(movedMountain.shapePoints.first, (50.0, 0.0));
    expect(face.shape!.isEllipse, isTrue);
  });

  test('Agent 重写布局时没写形状的接原来的,写 rect 的换回方框', () {
    final old = [
      _tri.copyWith(name: '山', shape: () => LayoutShape.regular(3)),
      _tri.copyWith(name: '脸', shape: () => const LayoutShape.ellipse()),
    ];
    final fresh = [
      _tri.copyWith(name: '山'),
      _tri.copyWith(name: '脸', shape: () => LayoutShape.box),
    ];
    final got = inheritNames(old, fresh, keepLayers: true);
    expect(got[0].shape, LayoutShape.regular(3));
    expect(got[1].shape, isNull);
  });

  testWidgets('画布上:点三角形外的空角不选中它,拖顶点改形状', (tester) async {
    final board = LayoutBoard()
      ..setSize(400, 400)
      ..addBox(_tri);
    board.updateBox(
      0,
      board.layout.boxes[0].copyWith(shape: () => LayoutShape.regular(3)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 400,
              child: LayoutCanvas(board: board),
            ),
          ),
        ),
      ),
    );
    final o = tester.getTopLeft(find.byType(LayoutCanvas));
    board.select(null);
    await tester.tapAt(o + const Offset(110, 110));
    await tester.pump(const Duration(milliseconds: 400));
    expect(board.selected, isNull);
    await tester.tapAt(o + const Offset(200, 250));
    await tester.pump(const Duration(milliseconds: 400));
    expect(board.selected, 0);

    final g = await tester.startGesture(o + const Offset(200, 100));
    await g.moveBy(const Offset(0, -20));
    await g.moveBy(const Offset(0, -40));
    await g.up();
    await tester.pump();
    final b = board.layout.boxes.single;
    expect(b.top, 40);
    expect((b.left, b.right, b.bottom), (100, 300, 300));
    expect(b.shapePoints.first, (200.0, 40.0));
  });
}
