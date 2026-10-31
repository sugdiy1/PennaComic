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
  @override
  Future<List<String>> listLoras() async => ['line.safetensors'];
  @override
  Future<String?> findPendingBatch(Map<String, Object?> request) async => null;
  @override
  Stream<RelayEvent> run(Map<String, Object?> snapshot, {String? resume}) {
    request = snapshot;
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
  test('unknown tool is explicit', () async {
    await expectLater(api.call('shell', {}), throwsA(isA<ControlException>()));
  });
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
