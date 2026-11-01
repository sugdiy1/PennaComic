import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../ui/features/studio/studio_view_model.dart';
import '../harness/layout.dart';
import '../harness/comic/penna_relay_service.dart';
import '../harness/comic/comic_export_service.dart';
import '../integration_settings.dart';
import 'control_server.dart';
import 'penna_tool_schema.dart';

/// 外部 Agent 的业务入口，绝不调用内置聊天模型。
class PennaTools {
  PennaTools({
    required this.vm,
    required this.home,
    this.relay = const PennaRelayService(),
    this.exporter = const ComicExportService(),
  }) {
    try {
      final saved = jsonDecode(_taskFile.readAsStringSync()) as Map;
      for (final e in saved.entries) {
        final value = Map<String, Object?>.from(e.value as Map);
        if (value['status'] == 'running' || value['status'] == 'cancelling') {
          value['status'] = 'interrupted';
          value['message'] = '程序已重启；按原参数再次提交可续跑已保存批次';
        }
        _tasks[e.key as String] = value;
      }
    } on Object {
      /* 无历史任务，首次启动 */
    }
  }
  final StudioViewModel vm;
  final Directory home;
  final PennaRelayService relay;
  final ComicExportService exporter;
  final Map<String, Map<String, Object?>> _tasks = {};
  bool _rendering = false;
  String? _activeTask;
  File _cancelFile(String id) =>
      File('${home.absolute.path}/control/cancel/$id.json');
  List<Map<String, Object?>> get tools => pennaToolSchema();
  bool get busy => _rendering;
  File get _taskFile => File('${home.path}/control/tasks.json');
  Never _bad(String message) =>
      throw ControlException('invalid_arguments', message);
  int _int(Map<String, dynamic> a, String k, {int? fallback}) {
    final x = a[k] ?? fallback;
    if (x is! int) _bad('$k 必须是整数');
    return x;
  }

  String _text(Map<String, dynamic> a, String k, {String? fallback}) {
    final x = a[k] ?? fallback;
    if (x is! String || x.length > 200000) _bad('$k 必须是文本，且不能过长');
    return x;
  }

  int _index(Map<String, dynamic> a) {
    final series = _int(a, 'series'), number = _int(a, 'page_number');
    for (final (i, p) in vm.pages.indexed) {
      if (p.series == series && vm.pageNumber(i) == number) return i;
    }
    throw const ControlException('not_found', '指定分镜页不存在，请重新列出页面');
  }

  Layout _pageLayout(int index) {
    if (index == vm.pageIndex) return vm.layout!.layout;
    final text = vm.pages[index].blocks.map((b) => b.text).join();
    if (text.trim().isEmpty) {
      return Layout(
        width: vm.layout!.layout.width,
        height: vm.layout!.layout.height,
      );
    }
    try {
      return Layout.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on Object {
      throw const ControlException('invalid_page', '该页存档损坏，请先修复');
    }
  }

  Map<String, Object?> _page(int index) {
    final p = vm.pages[index];
    final layout = _pageLayout(index).toJson();
    final identity = {
      'series': p.series,
      'page_number': vm.pageNumber(index),
      'name': p.name,
      'layout': layout,
    };
    return {
      ...identity,
      'revision': sha256.convert(utf8.encode(jsonEncode(identity))).toString(),
    };
  }

  Layout _validateLayout(Object? raw) {
    if (raw is! Map<String, dynamic>) _bad('layout 必须是对象');
    final w = raw['width'], h = raw['height'];
    if (w is! int ||
        h is! int ||
        w < 64 ||
        h < 64 ||
        w > maxLayoutSide ||
        h > maxLayoutSide) {
      _bad('画布尺寸必须为64–4096的整数');
    }
    final cast = raw['cast'];
    if (raw.containsKey('cast') &&
        (cast is! Map ||
            cast.entries.any((e) => e.key is! String || e.value is! String))) {
      _bad('cast 必须是角色名到文本描述的对象');
    }
    final boxes = raw['boxes'];
    if (boxes is! List || boxes.length > 500) _bad('boxes 必须是最多500项的列表');
    for (final box in boxes) {
      if (box is! Map) _bad('每个框必须是对象');
      final b = box['box'];
      if (b is! List || b.length != 4 || b.any((x) => x is! int)) {
        _bad('box 必须是四个整数像素坐标');
      }
      if ((b[0] as int) < 0 ||
          (b[1] as int) < 0 ||
          (b[2] as int) > w ||
          (b[3] as int) > h ||
          b[0] >= b[2] ||
          b[1] >= b[3]) {
        _bad('框必须在画布内且有正面积');
      }
      final shape = box['shape'];
      if (shape != null && shape != 'ellipse' && shape != 'rect') {
        if (shape is! List ||
            shape.length < minShapePoints ||
            shape.length > maxShapePoints) {
          _bad('shape 必须为 ellipse、rect/null 或3–16个归一化顶点');
        }
        for (final point in shape) {
          if (point is! List ||
              point.length != 2 ||
              point.any((v) => v is! num || !v.isFinite || v < 0 || v > 1)) {
            _bad('shape 顶点必须是两个0–1之间的有限数值，不是画布像素');
          }
        }
      }
      if (box['label'] != null && !layoutLabels.contains(box['label'])) {
        _bad('未知框类别');
      }
      if (box['layer'] != null && !layoutLayers.contains(box['layer'])) {
        _bad('未知图层');
      }
    }
    if (raw['canvas'] != null && !layoutCanvases.contains(raw['canvas'])) {
      _bad('未知画布类型');
    }
    try {
      final value = Layout.fromJson(raw);
      if (value.boxes.length != boxes.length) _bad('有框无法读取');
      return value;
    } on ControlException {
      rethrow;
    } on Object {
      _bad('layout 字段格式不正确');
    }
  }

  void _editable() {
    if (vm.isStreaming) {
      throw const ControlException('busy', '内置 Agent 正在回复，请稍后修改');
    }
  }

  List<Map<String, Object?>> _snapshots(int series) {
    if (!vm.pages.any((p) => p.series == series)) {
      throw const ControlException('not_found', '系列不存在');
    }
    return [
      for (final (index, page) in vm.pages.indexed)
        if (page.series == series) _snapshot(index, page),
    ];
  }

  Map<String, Object?> _snapshot(int index, DraftPage page) {
    final value = _pageLayout(index);
    final number = vm.pageNumber(index);
    return {
      'title': page.name.isEmpty ? '第 $number 页' : page.name,
      'page_number': number,
      'page_index': index,
      'context': {
        'workspace': vm.saveFile?.path ?? home.path,
        'series': page.series,
        'page_number': number,
      },
      if (value.isEmpty)
        'unavailable': '空白页，请先完成分镜'
      else ...{
        'width': value.width,
        'height': value.height,
        'source': value.toJson(),
        'layout': jsonDecode(
          mossLayoutJson(value, quality: vm.layout!.quality?.call() ?? ''),
        ),
      },
    };
  }

  Future<Map<String, Object?>> call(String name, Map<String, dynamic> a) async {
    final spec = tools.where((t) => t['name'] == name).firstOrNull;
    if (spec == null) throw const ControlException('unknown_tool', '未知工具');
    final schema = spec['inputSchema'] as Map;
    final allowed = (schema['properties'] as Map).keys;
    if (a.keys.any((k) => !allowed.contains(k))) _bad('包含未知参数');
    for (final key in schema['required'] as List) {
      if (!a.containsKey(key)) _bad('缺少参数 $key');
    }
    switch (name) {
      case 'penna_status':
        return {
          'application': 'Penna Comic',
          'protocol': 1,
          'home': home.absolute.path,
          'save_path': vm.saveFile?.absolute.path,
          'current_series': vm.series,
          'current_page': vm.pageNumber(vm.pageIndex),
          'page_count': vm.pages.length,
          'builtin_agent_busy': vm.isStreaming,
          'render_busy': busy,
          'tasks': _tasks.values.toList(),
        };
      case 'penna_list_pages':
        return {
          'pages': [
            for (final (i, p) in vm.pages.indexed)
              if (a['series'] == null || p.series == _int(a, 'series'))
                {..._page(i)},
          ],
        };
      case 'penna_get_page':
        return _page(_index(a));
      case 'penna_flush':
        _editable();
        return vm.agentFlush();
      case 'penna_create_page':
        _editable();
        final layout = _validateLayout(a['layout']);
        if (a['new_series'] != null && a['new_series'] is! bool) {
          _bad('new_series 必须为布尔值');
        }
        if (a['new_series'] == true && a.containsKey('series')) {
          _bad('新建系列时不要同时指定series');
        }
        final series = a['new_series'] == true
            ? vm.pages.map((p) => p.series).reduce((x, y) => x > y ? x : y) + 1
            : _int(a, 'series', fallback: vm.series);
        if (a['new_series'] != true &&
            !vm.pages.any((p) => p.series == series)) {
          _bad('series 不存在；新系列请用 new_series');
        }
        try {
          return _page(
            vm.agentCreatePage(
              layout,
              series: series,
              name: _text(a, 'name', fallback: ''),
              seriesName: a.containsKey('series_name')
                  ? _text(a, 'series_name')
                  : null,
            ),
          );
        } on StateError {
          throw const ControlException('busy', '工作台暂时不能创建页面');
        }
      case 'penna_update_page':
        _editable();
        final index = _index(a);
        final expected = _text(a, 'expected_revision');
        if (_page(index)['revision'] != expected) {
          throw const ControlException('conflict', '页面已变化，请重新 get_page 后修改');
        }
        final value = _validateLayout(a['layout']);
        vm.agentReplacePage(
          index,
          value,
          name: a.containsKey('name') ? _text(a, 'name') : null,
        );
        return _page(index);
      case 'penna_list_loras':
        return {'loras': await relay.listLoras()};
      case 'penna_submit_render':
        return _submit(a);
      case 'penna_get_task':
        final task = _tasks[_text(a, 'task_id')];
        if (task == null) throw const ControlException('not_found', '任务不存在');
        return Map.from(task);
      case 'penna_cancel_render':
        final id = _text(a, 'task_id');
        final task = _tasks[id];
        if (task == null) throw const ControlException('not_found', '任务不存在');
        if ([
          'done',
          'error',
          'cancelled',
          'interrupted',
        ].contains(task['status'])) {
          return Map.from(task);
        }
        if (id != _activeTask || !_rendering) {
          throw const ControlException('not_found', '没有此应用拥有的活动任务');
        }
        final marker = _cancelFile(id);
        marker.parent.createSync(recursive: true);
        marker.writeAsStringSync(
          jsonEncode({
            'task_id': id,
            'cancel_requested_at': DateTime.now().toUtc().toIso8601String(),
          }),
          flush: true,
        );
        task.addAll({'status': 'cancelling', 'message': '已请求取消，等待当前任务停止'});
        _saveTasks();
        return Map.from(task);
      case 'penna_list_results':
        final snapshots = _snapshots(_int(a, 'series'));
        final found = await exporter.findPreviewVersions(snapshots);
        return {
          'pages': [
            for (var i = 0; i < snapshots.length; i++)
              {
                'page_number': snapshots[i]['page_number'],
                'versions': [
                  for (final v in found[i])
                    {
                      'image': v.image,
                      'job_dir': v.jobDir,
                      'matches_source': v.matchesSource,
                      'label': v.label,
                    },
                ],
              },
          ],
        };
      case 'penna_export_comic':
        final snapshots = _snapshots(_int(a, 'series'));
        final versions = await exporter.findVersions(snapshots);
        final title = _text(a, 'title');
        if (title.trim().isEmpty) _bad('title 不能为空');
        final formats = a['formats'] ?? ['cbz', 'pdf'];
        if (formats is! List ||
            formats.isEmpty ||
            formats.any((x) => !['cbz', 'pdf'].contains(x))) {
          _bad('formats 仅支持cbz/pdf');
        }
        final direction = a['reading_direction'] ?? 'rtl';
        if (!['rtl', 'ltr'].contains(direction)) {
          _bad('reading_direction 仅支持rtl/ltr');
        }
        if (versions.any((p) => p.isEmpty)) {
          throw const ControlException(
            'missing_images',
            '还有页面没有与当前分镜匹配的成品，请先完成出图',
          );
        }
        return {
          'files': await exporter.exportComic(
            pages: [
              for (var i = 0; i < snapshots.length; i++)
                {
                  'image': versions[i].first.image,
                  'title': snapshots[i]['title'],
                },
            ],
            outputDir: '${IntegrationSettings.current.output}/exports',
            title: title,
            formats: List<String>.from(formats),
            readingDirection: direction as String,
          ),
        };
    }
    throw const ControlException('unknown_tool', '未知工具');
  }

  Map<String, Object?> _settings(Object? value) {
    if (value != null && value is! Map) _bad('settings 必须是对象');
    final s = <String, Object?>{
      'steps': 50,
      'seed': 42,
      'cfg': 3,
      'loras': [],
      if (value is Map) ...Map<String, Object?>.from(value),
    };
    if (s.keys.any(
      (k) => ![
        'steps',
        'seed',
        'cfg',
        'bubble',
        'loras',
        'render_mode',
        'edit_prompt',
        'edit_steps',
      ].contains(k),
    )) {
      _bad('未知出图设置');
    }
    if (s.containsKey('render_mode') &&
        !['generate', 'generate_edit'].contains(s['render_mode'])) {
      _bad('MCP 支持 generate 或 generate_edit；已有图片修改请使用软件的当前单页面板');
    }
    if (s.containsKey('edit_prompt') &&
        (s['edit_prompt'] is! String ||
            (s['edit_prompt'] as String).trim().isEmpty ||
            (s['edit_prompt'] as String).length > 12000)) {
      _bad('修改要求应为 1–12000 字');
    }
    if (s.containsKey('edit_steps') &&
        (s['edit_steps'] is! int ||
            (s['edit_steps'] as int) < 1 ||
            (s['edit_steps'] as int) > 100)) {
      _bad('修改步数应为 1–100');
    }
    final steps = s['steps'],
        seed = s['seed'],
        cfg = s['cfg'],
        loras = s['loras'];
    if (steps is! int ||
        steps < 1 ||
        steps > 100 ||
        seed is! int ||
        seed < 0 ||
        seed >= 9007199254740992 ||
        cfg is! num ||
        !cfg.isFinite ||
        cfg < 0 ||
        cfg > 20 ||
        (s.containsKey('bubble') &&
            !['oval', 'cloud', 'spiky'].contains(s['bubble']))) {
      _bad('出图参数范围不正确');
    }
    if (loras is! List || loras.length > 30) _bad('loras 必须是列表，最多30项');
    final names = <String>{};
    for (final l in loras) {
      if (l is! Map || l['name'] is! String || l['strength'] is! num) {
        _bad('LoRA 必须包含name和strength');
      }
      final weight = l['strength'] as num;
      if (!weight.isFinite ||
          weight < 0 ||
          weight > 2 ||
          !names.add(l['name'] as String)) {
        _bad('LoRA 强度必须为0–2且名称不能重复');
      }
    }
    s.remove(
      'bubble',
    ); // Accept old clients without requesting program lettering.
    return s;
  }

  Future<Map<String, Object?>> _submit(Map<String, dynamic> a) async {
    if (_rendering) throw const ControlException('busy', '已有出图任务，完成后再提交');
    _editable();
    final settings = _settings(a['settings']);
    final numbers = a['page_numbers'];
    if (numbers is! List ||
        numbers.isEmpty ||
        numbers.any((x) => x is! int || x < 1) ||
        numbers.toSet().length != numbers.length) {
      _bad('page_numbers 必须是非空且无重复的正整数页码');
    }
    final snapshots = _snapshots(_int(a, 'series'));
    final wanted = numbers.toSet();
    final pages = snapshots
        .where((p) => wanted.contains(p['page_number']))
        .toList();
    if (pages.length != numbers.length ||
        pages.any((p) => p.containsKey('unavailable'))) {
      _bad('所选页不存在或尚未完成分镜');
    }
    final id = 'render-${DateTime.now().microsecondsSinceEpoch}';
    final request = Map<String, Object?>.from(
      jsonDecode(
        jsonEncode({
          'title': vm.seriesName(_int(a, 'series')),
          'pages': pages,
          'settings': settings,
          'skip_completed': true,
        }),
      ) as Map,
    );
    _rendering = true;
    _activeTask = id;
    final task = <String, Object?>{
      'task_id': id,
      'home': home.absolute.path,
      'save_path': vm.saveFile?.absolute.path,
      'status': 'running',
      'stage': 'queued',
      'message': '分镜已冻结，等待后端',
      'series': a['series'],
      'page_numbers': numbers,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    _tasks[id] = task;
    try {
      _saveTasks();
    } catch (_) {
      _rendering = false;
      _activeTask = null;
      _tasks.remove(id);
      rethrow;
    }
    unawaited(_render(task, request));
    return Map.from(task);
  }

  void _saveTasks() {
    _taskFile.parent.createSync(recursive: true);
    File('${_taskFile.path}.tmp')
      ..writeAsStringSync(jsonEncode(_tasks), flush: true)
      ..renameSync(_taskFile.path);
  }

  Future<void> _render(
    Map<String, Object?> task,
    Map<String, Object?> request,
  ) async {
    final cancelFile = _cancelFile(task['task_id'] as String);
    bool cancelled() {
      if (!cancelFile.existsSync()) return false;
      task.addAll({
        'status': 'cancelled',
        'stage': 'cancelled',
        'message': '任务已取消，未继续提交页面',
      });
      return true;
    }

    try {
      if (cancelled()) return;
      final selected = (request['settings'] as Map)['loras'] as List;
      if (selected.isNotEmpty) {
        final available = await relay.listLoras();
        if (cancelled()) return;
        if (selected.any((l) => !available.contains((l as Map)['name']))) {
          throw const ControlException('invalid_lora', '选中的LoRA不存在，请重新读取列表');
        }
      }
      final resume = await relay.findPendingBatch(request);
      if (cancelled()) return;
      var terminal = false;
      await for (final event in relay.run(
        request,
        resume: resume,
        cancelFile: cancelFile.path,
      )) {
        task.addAll({
          'stage': event.stage,
          'message': event.message,
          if (event.jobDir != null) 'job_dir': event.jobDir,
          if (event.batchDir != null) 'batch_dir': event.batchDir,
          if (event.image != null) 'image': event.image,
          if (event.pages.isNotEmpty) 'pages': event.pages,
        });
        if (event.stage == 'done' ||
            event.stage == 'error' ||
            event.stage == 'cancelled') {
          terminal = true;
          task['status'] = event.stage;
        }
        try {
          _saveTasks();
        } on FileSystemException {
          task['storage_warning'] = '任务状态暂未保存';
        }
      }
      if (!terminal) throw StateError('后端提前结束，未返回结果');
    } on Object catch (e) {
      task.addAll({
        'status': 'error',
        'stage': 'error',
        'message': e is ControlException ? e.message : '出图失败：$e',
      });
    } finally {
      _rendering = false;
      _activeTask = null;
      task['finished_at'] = DateTime.now().toUtc().toIso8601String();
      try {
        _saveTasks();
      } on FileSystemException {
        task['storage_warning'] = '任务状态暂未保存';
      }
    }
  }
}
