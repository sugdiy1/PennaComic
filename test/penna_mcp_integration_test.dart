import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/agent_control/control_server.dart';
import 'package:penna/core/agent_control/penna_tools.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
  test('real MCP process edits live Penna via authenticated HTTP and reports conflicts', () async {
    final dir = Directory.systemTemp.createTempSync('penna-mcp-e2e-');
    final board = LayoutBoard();
    final vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      layoutOnly: true,
      layout: board,
      saveFile: File('${dir.path}/layout_chat.json'),
    );
    final tools = PennaTools(vm: vm, home: dir);
    final server = ControlServer(
      home: dir,
      listTools: () => tools.tools,
      callTool: tools.call,
    );
    Process? process;
    try {
      await server.start();
      final python = Platform.environment['PENNA_TEST_PYTHON'] ?? 'python';
      process = await Process.start(
        python,
        [File('backend/penna_mcp.py').absolute.path, '--home', dir.path],
        environment: {'PYTHONIOENCODING': 'utf-8'},
      );
      final stderr = process.stderr.transform(utf8.decoder).join();
      final replies = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      var id = 0;
      Future<Map<String, dynamic>> rpc(
        String method,
        Map<String, Object?> params,
      ) async {
        process!.stdin.writeln(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': ++id,
            'method': method,
            'params': params,
          }),
        );
        expect(
          await replies.moveNext().timeout(const Duration(seconds: 15)),
          true,
        );
        final reply = jsonDecode(replies.current) as Map<String, dynamic>;
        expect(reply['id'], id);
        expect(reply['error'], isNull);
        return reply['result'] as Map<String, dynamic>;
      }

      Future<Map<String, dynamic>> call(
        String name,
        Map<String, Object?> arguments,
      ) => rpc('tools/call', {'name': name, 'arguments': arguments});
      Map<String, dynamic> content(Map<String, dynamic> value) =>
          jsonDecode((value['content'] as List).single['text'])
              as Map<String, dynamic>;
      final init = await rpc('initialize', {
        'protocolVersion': '2025-03-26',
        'capabilities': {},
        'clientInfo': {'name': 'test', 'version': '1'},
      });
      expect(init['protocolVersion'], '2025-03-26');
      final listing = await rpc('tools/list', {});
      expect(listing['tools'], hasLength(10));
      final created = content(
        await call('penna_create_page', {
          'series': 0,
          'name': '快递员',
          'layout': {
            'width': 832,
            'height': 1216,
            'caption': 'An adult courier in the rain',
            'boxes': [
              {
                'box': [20, 20, 400, 500],
                'label': 'character',
                'name': '快递员',
                'caption': 'Adult courier holding a parcel',
              },
            ],
          },
        }),
      );
      expect(vm.pages.length, 2);
      expect(vm.pageIndex, 0);
      final changed = await call('penna_update_page', {
        'series': 0,
        'page_number': created['page_number'],
        'expected_revision': created['revision'],
        'layout': {
          ...(created['layout'] as Map<String, dynamic>),
          'caption': 'Courier arrives at the station',
        },
      });
      expect(changed['isError'], isNot(true));
      final conflict = await call('penna_update_page', {
        'series': 0,
        'page_number': created['page_number'],
        'expected_revision': created['revision'],
        'layout': created['layout'],
      });
      expect(conflict['isError'], true);
      expect(content(conflict)['error'], containsPair('code', 'conflict'));
      final read = content(
        await call('penna_get_page', {
          'series': 0,
          'page_number': created['page_number'],
        }),
      );
      expect(
        read['layout'],
        containsPair('caption', 'Courier arrives at the station'),
      );
      final saved = jsonDecode(vm.saveFile!.readAsStringSync()) as Map;
      expect(saved['pages'], hasLength(2));
      await process.stdin.close();
      expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
      expect(await stderr, isEmpty);
      await replies.cancel();
      await server.stop();
      expect(File(server.discoveryPath).existsSync(), false);
    } finally {
      process?.kill();
      await server.stop();
      vm.dispose();
      board.dispose();
      dir.deleteSync(recursive: true);
    }
  });
}
