import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/agent_control/penna_tools.dart';
import 'package:penna/core/agent_control/control_server.dart';
import 'package:penna/core/harness/comic/penna_relay_service.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

Map<String, dynamic> drawing(String caption) => {
  'width': 832,
  'height': 1216,
  'caption': caption,
  'canvas': 'multi_panel',
  'boxes': [
    {
      'box': [20, 20, 400, 500],
      'label': 'object',
      'name': '第1格',
      'caption': caption,
    },
  ],
};

class FakeRelay extends PennaRelayService {
  final stream = StreamController<RelayEvent>();
  Map<String, Object?>? request;
  String? cancellation;
  Completer<String?>? preflight;
  @override
  Future<List<String>> listLoras() async => ['line.safetensors'];
  @override
  Future<String?> findPendingBatch(Map<String, Object?> request) async =>
      preflight == null ? null : await preflight!.future;
  @override
  Stream<RelayEvent> run(
    Map<String, Object?> snapshot, {
    String? resume,
    String? cancelFile,
  }) {
    request = snapshot;
    cancellation = cancelFile;
    return stream.stream;
  }
}

void main() {
  late StudioViewModel vm;
  late LayoutBoard board;
  late PennaTools api;
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('penna-agent-');
    board = LayoutBoard();
    vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      layoutOnly: true,
      layout: board,
      saveFile: File('${dir.path}/pages.json'),
    );
    api = PennaTools(vm: vm, home: dir);
  });
  tearDown(() {
    vm.dispose();
    board.dispose();
    dir.deleteSync(recursive: true);
  });
  Future<Map<String, Object?>> create(String text) => api.call(
    'penna_create_page',
    {'series': 0, 'name': text, 'layout': drawing(text)},
  );
  test(
    'flush durably saves 51 pages and current manual board changes',
    () async {
      for (var i = 0; i < 50; i++) {
        await create('page $i');
      }
      board.setSummary(caption: 'current manual edit');
      final result = await api.call('penna_flush', {});
      expect(result, containsPair('persisted', true));
      expect(result['page_count'], 51);
      expect(result['save_path'], vm.saveFile!.absolute.path);
      final otherBoard = LayoutBoard();
      final other = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
        layoutOnly: true,
        layout: otherBoard,
        saveFile: vm.saveFile,
      );
      await other.load();
      expect(other.pages.length, 51);
      expect(otherBoard.layout.caption, 'current manual edit');
      expect(other.pages.last.blocks.single.text, contains('page 49'));
      other.dispose();
      otherBoard.dispose();
    },
  );
  test('flush reports write failure instead of claiming persistence', () async {
    final blocker = Directory('${vm.saveFile!.path}.agent.tmp')..createSync();
    try {
      await expectLater(
        api.call('penna_flush', {}),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      blocker.deleteSync();
    }
  });
  test('flush saves board file as well as page archive', () async {
    vm.dispose();
    board.dispose();
    board = LayoutBoard(dir: dir);
    vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      layoutOnly: true,
      layout: board,
      saveFile: File('${dir.path}/layout_chat.json'),
    );
    api = PennaTools(vm: vm, home: dir);
    board.setSummary(caption: 'both files');
    final result = await api.call('penna_flush', {});
    expect(
      result['board_save_path'],
      File('${dir.path}/layout.json').absolute.path,
    );
    expect(
      File(result['board_save_path'] as String).readAsStringSync(),
      contains('both files'),
    );
    expect(
      File(result['save_path'] as String).readAsStringSync(),
      contains('both files'),
    );
    final blocker = Directory('${dir.path}/layout.json.agent.tmp')
      ..createSync();
    try {
      await expectLater(
        api.call('penna_flush', {}),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      blocker.deleteSync();
    }
  });
  test(
    'cancel running relay writes owned marker and waits for backend terminal',
    () async {
      final p = await create('frozen');
      final relay = FakeRelay();
      api = PennaTools(vm: vm, home: dir, relay: relay);
      final job = await api.call('penna_submit_render', {
        'series': 0,
        'page_numbers': [p['page_number']],
        'settings': {
          'render_mode': 'generate_edit',
          'edit_prompt': '只修手部，保留文字。',
          'edit_steps': 25,
        },
      });
      await pumpEventQueue();
      expect(
        (relay.request!['settings'] as Map)['render_mode'],
        'generate_edit',
      );
      expect((relay.request!['settings'] as Map)['edit_prompt'], '只修手部，保留文字。');
      expect(
        relay.cancellation,
        '${dir.absolute.path}/control/cancel/${job['task_id']}.json',
      );
      expect(File(relay.cancellation!).existsSync(), false);
      await expectLater(
        api.call('penna_cancel_render', {'task_id': 'unknown'}),
        throwsA(isA<ControlException>()),
      );
      await api.call('penna_cancel_render', {'task_id': job['task_id']});
      expect(File(relay.cancellation!).existsSync(), true);
      expect(api.busy, true);
      relay.stream.add(
        const RelayEvent(stage: 'cancelled', message: 'stopped'),
      );
      await relay.stream.close();
      await pumpEventQueue();
      expect(
        (await api.call('penna_get_task', {
          'task_id': job['task_id'],
        }))['status'],
        'cancelled',
      );
      expect(api.busy, false);
      expect(
        (await api.call('penna_cancel_render', {
          'task_id': job['task_id'],
        }))['status'],
        'cancelled',
      );
    },
  );
  test(
    'cancel during preflight prevents relay launch and permits a future job',
    () async {
      final p = await create('frozen');
      final relay = FakeRelay()..preflight = Completer<String?>();
      api = PennaTools(vm: vm, home: dir, relay: relay);
      final job = await api.call('penna_submit_render', {
        'series': 0,
        'page_numbers': [p['page_number']],
      });
      final cancelled = await api.call('penna_cancel_render', {
        'task_id': job['task_id'],
      });
      expect(cancelled['status'], 'cancelling');
      expect(api.busy, true);
      relay.preflight!.complete(null);
      await pumpEventQueue();
      expect(relay.request, isNull);
      expect(
        (await api.call('penna_get_task', {
          'task_id': job['task_id'],
        }))['status'],
        'cancelled',
      );
      expect(api.busy, false);
      relay.preflight = null;
      final next = await api.call('penna_submit_render', {
        'series': 0,
        'page_numbers': [p['page_number']],
      });
      await pumpEventQueue();
      expect(next['task_id'], isNot(job['task_id']));
      relay.stream.add(const RelayEvent(stage: 'done', message: 'ok'));
      await relay.stream.close();
      await pumpEventQueue();
    },
  );
  test(
    'edits a specified page, preserves selection and other pages, persists',
    () async {
      final first = await create('one');
      await create('two');
      await create('three');
      final selected = vm.pageIndex;
      final result = await api.call('penna_update_page', {
        'series': 0,
        'page_number': first['page_number'],
        'expected_revision': first['revision'],
        'layout': drawing('updated'),
      });
      expect(vm.pageIndex, selected);
      expect(result['layout'], containsPair('caption', 'updated'));
      expect(
        (await api.call('penna_get_page', {
          'series': 0,
          'page_number': 3,
        }))['layout'],
        containsPair('caption', 'two'),
      );
      final other = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
        layoutOnly: true,
        layout: LayoutBoard(),
        saveFile: vm.saveFile,
      );
      await other.load();
      expect(other.pages.length, 4);
      expect(other.pages[1].blocks.single.text, contains('updated'));
      other.dispose();
      other.layout!.dispose();
    },
  );
  test('a manual board change invalidates previous revision', () async {
    final initial = await create('one');
    vm.openPage(1);
    board.setSummary(caption: 'manual edit');
    await expectLater(
      api.call('penna_update_page', {
        'series': 0,
        'page_number': initial['page_number'],
        'expected_revision': initial['revision'],
        'layout': drawing('overwritten'),
      }),
      throwsA(
        isA<ControlException>().having((e) => e.code, 'code', 'conflict'),
      ),
    );
    expect(board.layout.caption, 'manual edit');
  });
  test('invalid bounds and dimensions leave state untouched', () async {
    final first = await create('one');
    final before = vm.toJson();
    for (final bad in [
      {...drawing('bad'), 'width': 9000},
      {
        ...drawing('bad'),
        'boxes': [
          {
            'box': [-1, 0, 80, 80],
            'caption': 'bad',
          },
        ],
      },
    ]) {
      await expectLater(
        api.call('penna_update_page', {
          'series': 0,
          'page_number': first['page_number'],
          'expected_revision': first['revision'],
          'layout': bad,
        }),
        throwsA(isA<ControlException>()),
      );
      expect(vm.toJson(), before);
    }
  });
  test(
    'render freezes selected pages, returns ID and blocks overlap',
    () async {
      final p = await create('original');
      final relay = FakeRelay();
      api = PennaTools(vm: vm, home: dir, relay: relay);
      final job = await api.call('penna_submit_render', {
        'series': 0,
        'page_numbers': [p['page_number']],
        'settings': {'steps': 1, 'seed': 42, 'loras': []},
      });
      expect(job['task_id'], isA<String>());
      await expectLater(
        api.call('penna_submit_render', {
          'series': 0,
          'page_numbers': [p['page_number']],
        }),
        throwsA(isA<ControlException>().having((e) => e.code, 'code', 'busy')),
      );
      await api.call('penna_update_page', {
        'series': 0,
        'page_number': p['page_number'],
        'expected_revision': p['revision'],
        'layout': drawing('new'),
      });
      await pumpEventQueue();
      expect(
        ((relay.request!['pages'] as List).single as Map)['source'],
        containsPair('caption', 'original'),
      );
      relay.stream.add(const RelayEvent(stage: 'done', message: 'ok'));
      await relay.stream.close();
      await pumpEventQueue();
      expect(
        (await api.call('penna_get_task', {
          'task_id': job['task_id'],
        }))['status'],
        'done',
      );
    },
  );
  test('malformed cast is rejected without changing page revision', () async {
    final original = await create('one');
    for (final cast in [
      <String, Object>{'Alice': 123},
      <Object>[],
    ]) {
      await expectLater(
        api.call('penna_update_page', {
          'series': 0,
          'page_number': original['page_number'],
          'expected_revision': original['revision'],
          'layout': {...drawing('bad'), 'cast': cast},
        }),
        throwsA(isA<ControlException>()),
      );
      expect(
        await api.call('penna_get_page', {
          'series': 0,
          'page_number': original['page_number'],
        }),
        original,
      );
    }
  });
  test('failed persistence restores pending changes and live board', () async {
    await create('one');
    vm.openPage(1);
    const pending = DiffProposal(
      title: 'review',
      segmentIndex: 0,
      removed: 'old',
      added: 'proposed',
    );
    vm = _withPending(vm, board, pending);
    api = PennaTools(vm: vm, home: dir);
    final before = await api.call('penna_get_page', {
      'series': 0,
      'page_number': 1,
    });
    final blocker = Directory('${vm.saveFile!.path}.agent.tmp')..createSync();
    try {
      await expectLater(
        api.call('penna_update_page', {
          'series': 0,
          'page_number': 1,
          'expected_revision': before['revision'],
          'layout': drawing('bad save'),
        }),
        throwsA(isA<FileSystemException>()),
      );
      expect(vm.pending, same(pending));
      expect(board.layout.caption, 'one');
      expect(
        await api.call('penna_get_page', {'series': 0, 'page_number': 1}),
        before,
      );
    } finally {
      blocker.deleteSync();
    }
  });
  test(
    'normalized polygon survives create read update save and reload',
    () async {
      const polygon = [
        [0, 0.15],
        [1, 0],
        [1, 1],
        [0, 1],
      ];
      final layout = drawing('斜切格');
      (layout['boxes'] as List).first['shape'] = polygon;
      final created = await api.call('penna_create_page', {
        'series': 0,
        'layout': layout,
      });
      vm.openPage(1);
      expect(board.layout.boxes.single.shape!.points, [
        (0.0, 0.15),
        (1.0, 0.0),
        (1.0, 1.0),
        (0.0, 1.0),
      ]);
      final read = await api.call('penna_get_page', {
        'series': 0,
        'page_number': created['page_number'],
      });
      final readLayout = Map<String, dynamic>.from(read['layout'] as Map);
      expect(((readLayout['boxes'] as List).first as Map)['shape'], polygon);
      readLayout['caption'] = '修改描述，保留斜切';
      final changed = await api.call('penna_update_page', {
        'series': 0,
        'page_number': created['page_number'],
        'expected_revision': read['revision'],
        'layout': readLayout,
      });
      expect(
        ((changed['layout'] as Map)['boxes'] as List).first,
        containsPair('shape', polygon),
      );
      final other = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
        layoutOnly: true,
        layout: LayoutBoard(),
        saveFile: vm.saveFile,
      );
      await other.load();
      other.openPage(1);
      expect(
        other.layout!.layout.boxes.single.shape!.points,
        board.layout.boxes.single.shape!.points,
      );
      other.dispose();
      other.layout!.dispose();
    },
  );
  test(
    'MCP schema exposes normalized polygon and explains rendering limits',
    () {
      final tool = api.tools.firstWhere(
        (t) => t['name'] == 'penna_update_page',
      );
      final props = ((tool['inputSchema'] as Map)['properties'] as Map);
      final layout = props['layout'] as Map;
      final box =
          (((layout['properties'] as Map)['boxes'] as Map)['items'] as Map);
      expect((box['properties'] as Map), contains('shape'));
      expect(layout['description'], contains('0–1'));
      expect(layout['description'], contains('精确裁切'));
      final render = api.tools.firstWhere(
        (t) => t['name'] == 'penna_submit_render',
      );
      final renderProps = ((render['inputSchema'] as Map)['properties'] as Map);
      final settings = (renderProps['settings'] as Map)['properties'] as Map;
      final lora =
          ((settings['loras'] as Map)['items'] as Map)['properties'] as Map;
      expect(lora, isNot(contains('shape')));
    },
  );
  test('invalid shapes are rejected rather than clamped or dropped', () async {
    final original = await create('one');
    final badShapes = <Object>[
      'triangle',
      [
        [0, 0],
        [1, 1],
      ],
      [
        [0, 0],
        [1, 0],
        [1.5, 1],
      ],
      [
        [0, 0],
        [1, 0],
        ['x', 1],
      ],
      List.generate(17, (i) => [i / 17, 0.5]),
    ];
    for (final shape in badShapes) {
      final layout = drawing('bad shape');
      (layout['boxes'] as List).first['shape'] = shape;
      await expectLater(
        api.call('penna_update_page', {
          'series': 0,
          'page_number': original['page_number'],
          'expected_revision': original['revision'],
          'layout': layout,
        }),
        throwsA(isA<ControlException>()),
      );
      expect(
        await api.call('penna_get_page', {
          'series': 0,
          'page_number': original['page_number'],
        }),
        original,
      );
    }
  });
  test('unknown tool is explicit', () async {
    await expectLater(api.call('shell', {}), throwsA(isA<ControlException>()));
  });
  test(
    'legacy bubble is validated and ignored while MOSS text survives',
    () async {
      final textPage = drawing('with dialogue');
      (textPage['boxes'] as List).add({
        'box': [20, 600, 400, 800],
        'label': 'text',
        'text': '今天也要加油！',
        'caption': 'handwritten dialogue',
      });
      final page = await api.call('penna_create_page', {
        'series': 0,
        'layout': textPage,
      });
      await expectLater(
        api.call('penna_submit_render', {
          'series': 0,
          'page_numbers': [page['page_number']],
          'settings': {'bubble': 'bad'},
        }),
        throwsA(isA<ControlException>()),
      );
      final fake = FakeRelay();
      api = PennaTools(vm: vm, home: dir, relay: fake);
      await api.call('penna_submit_render', {
        'series': 0,
        'page_numbers': [page['page_number']],
        'settings': {'bubble': 'cloud'},
      });
      await pumpEventQueue();
      expect(fake.request!['settings'] as Map, isNot(contains('bubble')));
      final source =
          ((fake.request!['pages'] as List).single as Map)['source'] as Map;
      expect((source['boxes'] as List).last, containsPair('text', '今天也要加油！'));
      final descriptor = api.tools.firstWhere(
        (t) => t['name'] == 'penna_submit_render',
      );
      final settings =
          (((descriptor['inputSchema'] as Map)['properties'] as Map)['settings']
                  as Map)['properties']
              as Map;
      expect(settings, isNot(contains('bubble')));
      fake.stream.add(const RelayEvent(stage: 'done', message: 'ok'));
      await fake.stream.close();
      await pumpEventQueue();
    },
  );
}

StudioViewModel _withPending(
  StudioViewModel previous,
  LayoutBoard board,
  DiffProposal pending,
) {
  final saved = previous.toJson();
  final file = previous.saveFile;
  previous.dispose();
  final next = StudioViewModel(
    config: tempConfig(),
    streamChat: (_) => const Stream.empty(),
    layoutOnly: true,
    layout: board,
    saveFile: file,
  );
  next.restore(saved);
  // Keep test injection at public constructor boundary instead of private fields.
  next.dispose();
  final blocks = next.pages[next.pageIndex].blocks;
  final withPending = StudioViewModel(
    config: tempConfig(),
    streamChat: (_) => const Stream.empty(),
    layoutOnly: true,
    layout: board,
    saveFile: file,
    pending: pending,
    blocks: blocks,
  );
  // Restore clears pending, so build a single current page via constructor.
  return withPending;
}
