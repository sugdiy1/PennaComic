import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comic/moss_workflow_defaults.dart';
import 'package:penna/core/harness/comic/penna_relay_service.dart';
import 'package:penna/core/integration_settings.dart';

void main() {
  test('绑定按文件指纹保存，内容变化后不复用旧绑定', () async {
    final dir = await Directory.systemTemp.createTemp('penna-bindings-');
    final before = IntegrationSettings.current;
    IntegrationSettings.current = IntegrationSettings(
      home: dir.path,
      bundleRoot: Directory.current.path,
    );
    addTearDown(() async {
      IntegrationSettings.current = before;
      await dir.delete(recursive: true);
    });
    final graph = jsonDecode(
      await File('workflows/moss-official-api.json').readAsString(),
    ) as Map;
    graph['second'] = {
      'class_type': 'SaveImage',
      'inputs': {
        'images': ['9', 0],
        'filename_prefix': 'second',
      },
    };
    final file = File('${dir.path}/工作流.json');
    await file.writeAsString(jsonEncode(graph));
    final service = PennaRelayService(
      inspectorPython: Platform.environment['PENNA_TEST_PYTHON'],
      inspectorPath: File('backend/workflow_inspect.py').absolute.path,
    );
    final first = await service.inspectWorkflow(file.path);
    expect((first['inspection'] as Map)['status'], 'needs_binding');
    final chosen = await service.inspectWorkflow(
      file.path,
      selection: {'output': 'second'},
    );
    await service.saveWorkflowBinding(file.path, chosen);
    final restored = await service.readWorkflowSettings(file.path);
    expect((restored['inspection'] as Map)['bindings']['output'], 'second');
    graph['8']['inputs']['cfg'] = 3;
    await file.writeAsString(jsonEncode(graph));
    final changed = await service.readWorkflowSettings(file.path);
    expect((changed['inspection'] as Map)['status'], 'needs_binding');
  });
  test('中文路径和BOM工作流可读取，文件修改后指纹改变', () async {
    final dir = await Directory.systemTemp.createTemp('penna-workflow-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/漫画工作流.json');
    final graph = jsonDecode(
      await File('workflows/moss-8step-12steps-cfg2-api.json').readAsString(),
    ) as Map<String, dynamic>;
    await file.writeAsString('\uFEFF${jsonEncode(graph)}');
    final service = PennaRelayService(
      inspectorPython: Platform.environment['PENNA_TEST_PYTHON'],
      inspectorPath: File('backend/workflow_inspect.py').absolute.path,
    );
    final before = await service.readWorkflowSettings(file.path);
    expect((before['defaults'] as Map)['cfg'], 2);
    graph['8']['inputs']['cfg'] = 3;
    await file.writeAsString(jsonEncode(graph));
    final after = await service.readWorkflowSettings(file.path);
    expect(after['hash'], isNot(before['hash']));
    expect((after['defaults'] as Map)['cfg'], 3);
  });
  test('用户API工作流的加速LoRA、画风LoRA和12步CFG2被正确读取', () {
    final graph = jsonDecode(
      File('workflows/moss-api.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    graph['12']['inputs'] = {
      'model': ['1', 0],
      'lora_name': 'muqiu_moss.safetensors',
      'strength_model': .75,
    };
    graph['13'] = {
      'class_type': 'LoraLoaderModelOnly',
      'inputs': {
        'model': ['12', 0],
        'lora_name': 'moss_sft_8step_dmd_latest.safetensors',
        'strength_model': .7,
      },
    };
    graph['2']['inputs']['model'] = ['13', 0];
    graph['8']['inputs'].addAll({'steps': 12, 'cfg': 2, 'seed': 42});
    final settings = mossWorkflowDefaults(graph);
    expect(settings['loras'], [
      {'name': 'muqiu_moss.safetensors', 'strength': .75},
      {'name': 'moss_sft_8step_dmd_latest.safetensors', 'strength': .7},
    ]);
    expect(settings['steps'], 12);
    expect(settings['cfg'], 2);
  });
}
