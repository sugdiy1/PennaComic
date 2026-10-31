import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/layout/layout_bodies.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/layout/layout_camera.dart';
import 'package:penna/ui/features/layout/layout_canvas.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

String _draft(String caption) =>
    '{"width": 832, "height": 1216, "summary": {"caption": "$caption"}, '
    '"items": [{"name": "人", "label": "character", "caption": "a girl", '
    '"bbox": [200, 300, 600, 1100]}], '
    '"bbox_coord_space": "abs", "bbox_format": "xyxy"}';

void main() {
  test('Agent 写 <lighting>:画板换上灯光,交出去的 caption 接上光影;再换布局灯光照旧', () async {
    final board = LayoutBoard();
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final seen = <LlmRequest>[];
    final replies = [
      '<layout>${_draft('A girl in a studio')}</layout>'
          '<lighting>{"preset": "rembrandt"}</lighting>打好光了。',
      '<layout>${_draft('A girl by the window')}</layout>换了个场景。',
    ];
    final chat = StudioViewModel(
      config: service,
      layout: board,
      layoutOnly: true,
      streamChat: (r) {
        seen.add(r);
        return Stream.value(replies[seen.length - 1]);
      },
    );
    chat.send('排一张,用伦勃朗光');
    await pumpEventQueue();
    expect(board.layout.lighting.preset, 'rembrandt');
    expect(chat.messages.last.toolSummary, contains('已调整灯光'));
    final caption =
        (jsonDecode(board.json) as Map)['summary']['caption'] as String;
    expect(caption, startsWith('A girl in a studio. Lighting: '));
    expect(
      caption,
      endsWith(lightingPhrase(board.layout.lighting, null, zh: false)),
    );
    expect(caption, contains('Rembrandt lighting'));

    chat.send('换到窗边');
    await pumpEventQueue();
    expect(board.layout.caption, 'A girl by the window');
    expect(board.layout.lighting.preset, 'rembrandt');
    // 发给模型的系统提示里有灯光现状;上一条回复里的灯光标签换成了一句话。
    final sent = seen.last.messages;
    expect(sent.first['content'], contains('【灯光】开着'));
    expect(
      sent.where((m) => m['role'] == 'assistant').single['content'],
      allOf(isNot(contains('<lighting>')), contains('调过一次灯光')),
    );
  });

  testWidgets('光影预览:3D 视图里开着灯光时画布底色按灯光变暗,关掉预览就恢复', (tester) async {
    final board = LayoutBoard()
      ..addBox(const LayoutBox(left: 200, top: 300, right: 600, bottom: 1100))
      ..setThreeD(true);
    board.setLighting(presetLighting('low_key', null));
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 416,
            height: 608,
            child: LayoutCanvas(board: board),
          ),
        ),
      ),
    );
    final backdrop = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == litBackdrop(board.layout),
    );
    expect(backdrop, findsOneWidget);
    // 低调光:画布底色明显比白纸暗。
    expect(litBackdrop(board.layout).computeLuminance(), lessThan(0.5));
    board.shadePreview.value = false;
    await tester.pump();
    expect(backdrop, findsNothing);
  });

  Future<LayoutBoard> panel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final board = LayoutBoard()..setThreeD(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 2400,
              child: ListenableBuilder(
                listenable: board,
                builder: (context, _) => CameraPanel(board: board),
              ),
            ),
          ),
        ),
      ),
    );
    return board;
  }

  testWidgets('部件窗口:点图标换窗口、再点收起,摄像机和灯光各是各的', (tester) async {
    await panel(tester);
    // 默认展开摄像机窗口,里面没有灯光;内容从窗口顶上排(不是摆在正中)。
    expect(find.text('自由镜头'), findsOneWidget);
    expect(tester.getTopLeft(find.text('摄像机')).dy, lessThan(40));
    expect(find.byType(Switch), findsNothing);
    await tester.tap(find.byTooltip('灯光'));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('自由镜头'), findsNothing);
    final open = tester.getSize(find.byType(CameraPanel)).width;
    await tester.tap(find.byTooltip('灯光'));
    await tester.pumpAndSettle();
    // 收起后只剩图标栏。
    expect(tester.getSize(find.byType(CameraPanel)).width, lessThan(open / 4));
  });

  testWidgets('灯光窗口里展开预设格子,点一个就套用并收起', (tester) async {
    final board = await panel(tester);
    await tester.tap(find.byTooltip('灯光'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('打光预设'));
    await tester.pumpAndSettle();
    expect(find.text('人像'), findsOneWidget);
    await tester.tap(find.text('霓虹'));
    await tester.pumpAndSettle();
    expect(board.layout.lighting.preset, 'neon');
    expect(find.text('人像'), findsNothing);
  });

  testWidgets('灯光窗口里打开灯光、拖灯光球上的手柄,灯换方向,下面的提示词跟着变', (tester) async {
    final board = await panel(tester);
    await tester.tap(find.byTooltip('灯光'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final lg = board.layout.lighting;
    expect((lg.enabled, lg.preset), (true, 'natural'));
    expect(find.textContaining('Lighting: Natural daylight'), findsOneWidget);

    // 灯光球 180 宽、半径 89;自然光的主光在左上。
    final ball = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_LightBall',
    );
    final c = tester.getCenter(ball);
    final key = relDir(lg.lights.first, lg, board.layout.camera);
    final from = c + Offset(key.side, -key.up) * 89;
    final g = await tester.startGesture(from);
    await g.moveTo(from + const Offset(20, 10));
    await g.moveTo(c + const Offset(60, 0));
    await g.up();
    await tester.pumpAndSettle();
    final moved = board.layout.lighting;
    expect(moved.preset, '');
    expect(
      relDir(moved.lights.first, moved, board.layout.camera).side,
      greaterThan(0.5),
    );
    expect(find.textContaining('from the front right'), findsOneWidget);
  });
}
