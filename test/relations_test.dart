import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/core/harness/layout_3d.dart';
import 'package:penna/core/harness/layout_relations.dart';
import 'package:penna/ui/features/layout/layout_board.dart';

LayoutBox _b(
  String name,
  int l,
  int t,
  int r,
  int b, {
  String layer = 'middle',
}) => LayoutBox(left: l, top: t, right: r, bottom: b, name: name, layer: layer);

void main() {
  // 前后照 boxes 的先后:标题最前,人物其次,大字最后。
  final layout = Layout(
    width: 832,
    height: 1216,
    caption: 'poster',
    boxes: [
      _b('标题', 0, 0, 500, 300, layer: 'front'),
      _b('小杯子', 300, 500, 400, 600, layer: 'front'),
      _b('人物', 200, 200, 650, 1216),
      _b('大字', 0, 400, 832, 800, layer: 'back'),
    ],
  );
  final text = layoutRelations(layout);

  test('每块在画面哪里、占多大、贴着哪条边', () {
    expect(text, contains('「标题」:画面左上'));
    expect(text, contains('贴着画面上边、左边'));
    expect(text, contains('「大字」:画面正中'));
    expect(text, contains('横贯整个宽度'));
    expect(text, contains('「人物」'));
    expect(text, contains('贴着画面下边'));
  });

  test('重叠时说谁在前、挡住后面那块的哪部分、挡多少;整个落在里面的单说', () {
    expect(text, contains('「标题」在「人物」前面,挡住「人物」的上部'));
    expect(text, contains('「人物」在「大字」前面,挡住「大字」的中间'));
    expect(text, contains('「小杯子」整个落在「人物」的范围里、在它前面'));
    // 不重叠的两块不提。
    expect(text, isNot(contains('「标题」在「小杯子」')));
  });

  test('人物块按占画面多高说景别:框小的是全景、贴边又高的是近景', () {
    String shotOf(int top, int bottom) => layoutRelations(
      Layout(
        width: 832,
        height: 1216,
        caption: '',
        boxes: [
          LayoutBox(
            left: 200,
            top: top,
            right: 600,
            bottom: bottom,
            name: '她',
            label: 'character',
          ),
        ],
      ),
    );
    expect(shotOf(550, 1050), contains('高约画面的 41%,全景'));
    expect(shotOf(900, 1100), contains('远景'));
    expect(shotOf(300, 1216), contains('近景'));
    expect(shotOf(550, 1050), contains('不要写成特写'));
    // 不是人物的块不说景别。
    expect(text, isNot(contains('高约画面')));
  });

  test('发给 Agent 的画板现状里带着位置关系,空画板不带', () {
    final board = LayoutBoard()..replace(layout);
    expect(board.prompt, contains('【位置关系】'));
    board.clear();
    expect(board.prompt, isNot(contains('【位置关系】')));
  });

  group('3D 视图开着时按 3D 场景算', () {
    // 正面看:小红在前(近),背景板在后(远),小红挡住背景板的一部分。
    Layout scene(Camera camera) {
      const flat = Layout();
      final base = Layout(
        boxes: [
          liftBox(_b('小红', 300, 300, 550, 1000, layer: 'front'), flat, (
            distance: 0.8,
            depth: 0.5,
            yaw: 0,
          )),
          liftBox(_b('背景板', 100, 200, 732, 900, layer: 'back'), flat, (
            distance: 2.5,
            depth: 0.1,
            yaw: 0,
          )),
          const LayoutBox(
            left: 100,
            top: 50,
            right: 732,
            bottom: 250,
            label: 'text',
            text: 'TITLE',
            name: '标题',
          ),
        ],
      );
      final l = base.copyWith(camera: camera);
      return l.copyWith(boxes: [for (final m in reprojectBoxes(l)) m.$2]);
    }

    test('正面:近的挡远的,看得到正面;文字压在什么上面', () {
      final text = sceneRelations(scene(const Camera()));
      expect(text, contains('3D 构图'));
      expect(text, contains('「小红」:离镜头第 1 近'));
      expect(text, contains('「小红」离镜头更近,挡住「背景板」的'));
      expect(text, contains('看得到它的正面'));
      expect(text, contains('「标题」压在「背景板」的'));
    });

    test('绕到背后:前后对调,看得到背面;俯视看得到顶面', () {
      final behind = sceneRelations(
        scene(const Camera(orbit: 180, distance: 4)),
      );
      expect(behind, contains('「背景板」:离镜头第 1 近'));
      expect(behind, contains('「背景板」离镜头更近,挡住「小红」的'));
      expect(behind, contains('背面'));
      final above = sceneRelations(scene(const Camera(pitch: 60)));
      expect(above, contains('顶面'));
    });

    test('3D 视图开着时发给 Agent 的是 3D 的关系', () {
      final board = LayoutBoard()..replace(scene(const Camera()));
      expect(board.prompt, contains('【位置关系】程序按框算'));
      board.setThreeD(true);
      expect(board.prompt, contains('【位置关系 · 3D 构图】'));
      expect(board.prompt, isNot(contains('【位置关系】程序按框算')));
    });
  });
}
