import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../../../core/harness/comic/penna_relay_service.dart';
import '../../../core/harness/comic/comic_export_service.dart';
import '../../../core/integration_settings.dart';
import '../../core/theme.dart';
import '../../../l10n/l10n.dart';
import 'relay_lora_picker.dart';
import 'comic_finished_preview.dart';
import 'relay_snapshots.dart';
import 'workflow_binding_dialog.dart';

/// 当前页在打开面板时拍下快照。接力期间不再读画板，保证图片和存档一致。
Future<void> showPennaRelay(
  BuildContext context, {
  required Map<String, Object?> snapshot,
  VoidCallback? onArchive,
  ValueChanged<int>? onEditPage,
  ValueChanged<int>? onRenderPage,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => PennaRelayDialog(
    snapshot: snapshot,
    onArchive: onArchive,
    onEditPage: onEditPage,
    onRenderPage: onRenderPage,
  ),
);

class PennaRelayDialog extends StatefulWidget {
  const PennaRelayDialog({
    super.key,
    required this.snapshot,
    this.service = const PennaRelayService(),
    this.onArchive,
    this.onEditPage,
    this.onRenderPage,
    this.previewService = const ComicExportService(),
  });
  final Map<String, Object?> snapshot;
  final PennaRelayService service;
  final VoidCallback? onArchive;
  final ValueChanged<int>? onEditPage;
  final ValueChanged<int>? onRenderPage;
  final ComicExportService previewService;
  @override
  State<PennaRelayDialog> createState() => _PennaRelayDialogState();
}

class _PennaRelayDialogState extends State<PennaRelayDialog> {
  final _steps = TextEditingController(text: '50');
  final _cfg = TextEditingController(text: '3');
  final _workflow = TextEditingController(
    text: IntegrationSettings.current.workflow,
  );
  final _seed = TextEditingController(text: '42');
  final _editSteps = TextEditingController(text: '25');
  final _editPrompt = TextEditingController(
    text:
        '只修正漫画中不自然的手指、手臂连接和肢体遮挡。保留人物身份、服装、动作、分格、气泡位置及全部原有中文台词，不增删或改写文字，保持原画风。',
  );
  final _reference = TextEditingController();
  String _renderMode = 'generate';
  bool _panelEdit = false;
  int _panelResolution = 768;
  final _panelIndices = <int>{};
  final _panelSeeds = <int, int>{};
  bool get _usesQwen =>
      _renderMode == 'generate_edit' ||
      _renderMode == 'edit_only' ||
      (_renderMode == 'panels' && _panelEdit);
  List<Map<String, Object?>> get _boxes {
    final source = widget.snapshot['source'];
    final boxes = source is Map ? source['boxes'] : null;
    return boxes is List
        ? [for (final box in boxes) Map<String, Object?>.from(box as Map)]
        : [];
  }

  List<String> _loras = [];
  Set<String> _selected = {'moss_Lineart.safetensors'};
  final _weights = <String, String>{};
  final _clipWeights = <String, String>{};
  bool _loadingLoras = true, _loadedPreferences = false;
  String? _loraError, _lastSettings;
  String? _workflowHash;
  String? _inspectedPath;
  Map<String, dynamic>? _workflowReport;
  Map<String, dynamic> _workflowBindings = {};
  bool _inspecting = false;
  bool _busy = false, _archived = false;
  bool _renderActive = false;
  bool _cancelRequested = false;
  File? _cancelFile;
  String? _jobDir, _image;
  String? _batchDir;
  bool _multi = false;
  final _pickedPages = <int>{};
  List<Map<String, dynamic>> _results = [];
  int? _previewPage;
  List<Map<String, Object?>> get _pages => [
    for (final p in widget.snapshot['series_pages'] as List? ?? const [])
      Map<String, Object?>.from(p as Map),
  ];
  String _stage = 'idle', _message = '先保存当前分镜，再切换显存出图。完成后自动恢复对话。';
  final _log = <String>[];
  static const _stages = [
    ('saved', '保存分镜'),
    ('switching', '释放显存'),
    ('rendering', '生成画面'),
    ('composing', '保存成品'),
    ('restoring', '恢复对话'),
  ];

  @override
  void initState() {
    super.initState();
    _panelIndices.addAll(autoPanelFrameIndices(widget.snapshot));
    _pickedPages.addAll(
      _pages
          .where((p) => p['unavailable'] == null)
          .map((p) => p['page_number'] as int),
    );
    _loadLoras();
  }

  Future<void> _loadLoras() async {
    setState(() => _loadingLoras = true);
    try {
      final names = await widget.service.listLoras();
      Map<String, dynamic> prefs = {};
      if (!_loadedPreferences) {
        try {
          prefs = await widget.service.readSettings();
        } on Object {
          prefs = {};
        }
        {
          final defaults = widget.snapshot['relay_defaults'] is Map
              ? Map<String, dynamic>.from(
                  widget.snapshot['relay_defaults'] as Map,
                )
              : <String, dynamic>{};
          final candidate =
              defaults['workflow_path'] ??
              prefs['workflow_path'] ??
              _workflow.text;
          if (candidate is String && File(candidate).existsSync()) {
            final loaded = await widget.service.readWorkflowSettings(candidate);
            final actualHash = loaded['hash'] as String;
            _workflowHash = actualHash;
            _inspectedPath = candidate;
            _workflowReport = loaded;
            final analysis = loaded['inspection'];
            if (analysis is Map) {
              _workflowBindings = Map<String, dynamic>.from(
                analysis['bindings'] as Map,
              );
            }
            final workflowDefaults = _resolveLoraNames(
              Map<String, dynamic>.from(loaded['defaults'] as Map),
              names,
            );
            if (candidate != prefs['workflow_path'] ||
                actualHash != prefs['workflow_sha256']) {
              prefs = {...prefs, ...workflowDefaults};
            }
            prefs['workflow_path'] = candidate;
            final missing = [
              for (final raw in prefs['loras'] as List? ?? [])
                if (raw is Map &&
                    raw['name'] is String &&
                    !names.contains(raw['name']))
                  raw['name'],
            ];
            if (missing.isNotEmpty) {
              throw FormatException(
                '选中工作流的LoRA缺失：${missing.join('、')}。请先准备模型，不会自动移除加速LoRA。',
              );
            }
          }
          prefs = {...prefs, ...defaults};
        }
      }
      if (!mounted) return;
      setState(() {
        _loras = names;
        _loraError = null;
        if (!_loadedPreferences) {
          final saved = prefs['loras'];
          if (saved is List) {
            _selected = {};
            for (final item in saved) {
              if (item is Map && names.contains(item['name'])) {
                final name = item['name'] as String;
                _selected.add(name);
                _weights[name] = '${item['strength'] ?? .85}';
                if (item['clip_strength'] is num) {
                  _clipWeights[name] = '${item['clip_strength']}';
                }
              }
            }
          } else {
            _selected = names
                .where(
                  (n) =>
                      n.replaceAll('\\', '/').split('/').last ==
                      'moss_Lineart.safetensors',
                )
                .toSet();
          }
          if (prefs['steps'] is int) _steps.text = '${prefs['steps']}';
          if (prefs['cfg'] is num) _cfg.text = '${prefs['cfg']}';
          if (prefs['workflow_path'] is String &&
              (prefs['workflow_path'] as String).isNotEmpty) {
            _workflow.text = prefs['workflow_path'] as String;
          }
          if (prefs['seed'] is int) _seed.text = '${prefs['seed']}';
          if ([
            'generate',
            'generate_edit',
            'edit_only',
            'panels',
          ].contains(prefs['render_mode'])) {
            _renderMode = prefs['render_mode'] as String;
          }
          if (prefs['edit_prompt'] is String) {
            _editPrompt.text = prefs['edit_prompt'] as String;
          }
          if (prefs['edit_steps'] is int) {
            _editSteps.text = '${prefs['edit_steps']}';
          }
          if (prefs['reference_image'] is String) {
            _reference.text = prefs['reference_image'] as String;
          }
          if (prefs['panel_edit'] is bool) {
            _panelEdit = prefs['panel_edit'] as bool;
          }
          if ([512, 768, 1024].contains(prefs['panel_resolution'])) {
            _panelResolution = prefs['panel_resolution'] as int;
          }
          _loadedPreferences = true;
        }
      });
    } on Object catch (e) {
      if (mounted) setState(() => _loraError = '$e');
    } finally {
      if (mounted) setState(() => _loadingLoras = false);
    }
  }

  @override
  void dispose() {
    _steps.dispose();
    _cfg.dispose();
    _workflow.dispose();
    _seed.dispose();
    _editSteps.dispose();
    _editPrompt.dispose();
    _reference.dispose();
    super.dispose();
  }

  Map<String, dynamic> _resolveLoraNames(
    Map<String, dynamic> defaults,
    List<String> names,
  ) {
    if (defaults['loras'] is! List) return defaults;
    return {
      ...defaults,
      'loras': [
        for (final raw in defaults['loras'] as List)
          (() {
            final item = Map<String, dynamic>.from(raw as Map);
            final name = '${item['name']}'.replaceAll('\\', '/');
            final matches = names.where((n) {
              final value = n.replaceAll('\\', '/');
              return value == name || value == '$name.safetensors';
            }).toList();
            if (matches.length == 1) item['name'] = matches.single;
            return item;
          })(),
      ],
    };
  }

  Future<bool> _bindWorkflow({bool pickFile = false}) async {
    if (_busy || _inspecting) return false;
    if (pickFile) {
      final chosen = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'ComfyUI API JSON', extensions: ['json']),
        ],
      );
      if (chosen == null || !mounted) return false;
      _workflow.text = chosen.path;
    }
    setState(() => _inspecting = true);
    try {
      final path = _workflow.text.trim();
      final initial = await widget.service.readWorkflowSettings(path);
      if (!mounted) return false;
      final result = initial['inspection'] is Map
          ? await showDialog<Map<String, dynamic>>(
              context: context,
              builder: (_) => WorkflowBindingDialog(
                initial: initial,
                inspect: (selection) =>
                    widget.service.inspectWorkflow(path, selection: selection),
              ),
            )
          : initial;
      if (result == null || !mounted) return false;
      if (result['inspection'] is Map) {
        await widget.service.saveWorkflowBinding(path, result);
      }
      if (!mounted) return false;
      final defaults = _resolveLoraNames(
        Map<String, dynamic>.from(result['defaults'] as Map),
        _loras,
      );
      setState(() {
        _workflowReport = result;
        _workflowHash = result['hash'] as String;
        _inspectedPath = path;
        final analysis = result['inspection'];
        _workflowBindings = analysis is Map
            ? Map<String, dynamic>.from(analysis['bindings'] as Map)
            : {};
        for (final pair in [
          ('steps', _steps),
          ('cfg', _cfg),
          ('seed', _seed),
        ]) {
          if (defaults[pair.$1] is num) pair.$2.text = '${defaults[pair.$1]}';
        }
        if (defaults['loras'] is List) {
          _selected = {};
          _weights.clear();
          _clipWeights.clear();
          for (final raw in defaults['loras'] as List) {
            final name = '${raw['name']}';
            _selected.add(name);
            _weights[name] = '${raw['strength']}';
            if (raw['clip_strength'] is num) {
              _clipWeights[name] = '${raw['clip_strength']}';
            }
          }
        }
        final missing = _selected
            .where((name) => !_loras.contains(name))
            .toList();
        _loraError = missing.isEmpty
            ? null
            : '工作流 LoRA 未安装：${missing.join('、')}';
      });
      return _loraError == null;
    } catch (e) {
      if (mounted) setState(() => _message = '工作流识别失败：$e');
      return false;
    } finally {
      if (mounted) setState(() => _inspecting = false);
    }
  }

  Future<void> _start() async {
    if (_busy) return;
    if (_renderMode != 'edit_only' &&
        (_inspectedPath != _workflow.text.trim() ||
            (_workflowReport?['inspection'] as Map?)?['status'] ==
                'needs_binding') &&
        File(_workflow.text.trim()).existsSync()) {
      if (!await _bindWorkflow()) return;
    }
    if (_usesQwen &&
        (_editPrompt.text.trim().isEmpty ||
            _editPrompt.text.length > 12000 ||
            (int.tryParse(_editSteps.text) ?? 0) < 1 ||
            (int.tryParse(_editSteps.text) ?? 101) > 100 ||
            (_renderMode == 'edit_only' && _reference.text.trim().isEmpty))) {
      setState(() {
        _stage = 'error';
        _message = '请填写修改要求、1–100 的修改步数；修改已有图片时请选择参考 PNG。';
      });
      return;
    }
    if (_renderMode == 'panels' &&
        !_multi &&
        (_panelIndices.isEmpty || _panelIndices.length > 32)) {
      setState(() {
        _stage = 'error';
        _message = '请勾选 1–32 个作为漫画格的框；人物框、台词框不用勾选。';
      });
      return;
    }
    final steps = _renderMode == 'edit_only' ? 50 : int.tryParse(_steps.text);
    final seed = int.tryParse(_seed.text);
    final cfg = double.tryParse(_cfg.text);
    if (_loadingLoras || _loraError != null) return;
    if (steps == null ||
        steps < 1 ||
        steps > 100 ||
        seed == null ||
        seed < 0 ||
        seed >= 9007199254740992 ||
        cfg == null ||
        !cfg.isFinite ||
        cfg < 0 ||
        cfg > 20) {
      setState(() {
        _stage = 'error';
        _message = '请填写有效参数：步数 1–100，CFG 0–20，非负整数种子，LoRA 强度 0–2。';
      });
      return;
    }
    final selected = <Map<String, Object>>[];
    for (final name in _loras.where(
      (name) =>
          _renderMode != 'edit_only' &&
          _workflowBindings['manage_loras'] != false &&
          _selected.contains(name),
    )) {
      final weight = double.tryParse(_weights[name] ?? '0.85');
      if (weight == null || !weight.isFinite || weight < 0 || weight > 2) {
        setState(() {
          _stage = 'error';
          _message = '$name 的强度应为 0–2。';
        });
        return;
      }
      final clip = _clipWeights.containsKey(name)
          ? double.tryParse(_clipWeights[name]!)
          : null;
      if (_clipWeights.containsKey(name) &&
          (clip == null || !clip.isFinite || clip < -2 || clip > 2)) {
        setState(() => _message = '$name 的 CLIP 强度应为 -2–2。');
        return;
      }
      selected.add({'name': name, 'strength': weight, 'clip_strength': ?clip});
    }
    final settings = <String, Object>{
      'steps': steps,
      'seed': seed,
      'loras': selected,
      'cfg': cfg,
      'workflow_path': _workflow.text.trim(),
      'workflow_sha256': ?_workflowHash,
      if (_workflowBindings.isNotEmpty) 'workflow_bindings': _workflowBindings,
      'render_mode': _renderMode,
      'edit_prompt': _editPrompt.text,
      'edit_steps': int.tryParse(_editSteps.text) ?? 25,
      if (_renderMode == 'edit_only') 'reference_image': _reference.text.trim(),
      if (_renderMode == 'panels') ...{
        'panel_edit': _panelEdit,
        'panel_resolution': _panelResolution,
        if (!_multi) 'panel_indices': (_panelIndices.toList()..sort()),
        if (!_multi)
          'panel_seeds': {
            for (final entry in _panelSeeds.entries)
              if (_panelIndices.contains(entry.key))
                '${entry.key}': entry.value,
          },
      },
    };
    final chosen = _pages
        .where(
          (p) =>
              _pickedPages.contains(p['page_number']) &&
              p['unavailable'] == null,
        )
        .toList();
    if (_multi && chosen.isEmpty) {
      setState(() {
        _stage = 'error';
        _message = '请至少选择一页已完成的分镜。';
      });
      return;
    }
    final snapshot = <String, Object?>{
      if (_multi) ...{
        'title': widget.snapshot['series_title'] ?? '漫画批次',
        'pages': chosen,
        'skip_completed': true,
      } else ...{
        for (final e in widget.snapshot.entries)
          if (!['series_pages', 'series_title', 'current_page'].contains(e.key))
            e.key: e.value,
      },
      'settings': settings,
    };
    final settingsKey = jsonEncode(snapshot);
    var resume =
        _stage == 'error' &&
            _lastSettings == settingsKey &&
            (_multi
                ? _batchDir != null
                : _jobDir != null &&
                      File('$_jobDir${Platform.pathSeparator}manifest.json')
                          .existsSync())
        ? (_multi ? _batchDir : _jobDir)
        : null;
    setState(() {
      _busy = true;
      _renderActive = true;
      _cancelRequested = false;
      _cancelFile = File(
        '${IntegrationSettings.current.home}/control/cancel/ui-relay-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      _lastSettings = settingsKey;
      _jobDir = resume;
      _batchDir = _multi ? resume : null;
      _stage = 'saved';
      _image = null;
      _results = [];
      _previewPage = null;
      _log.clear();
      _message = '正在保存当前分镜…';
    });
    try {
      if (_multi && resume == null) {
        resume = await widget.service.findPendingBatch(snapshot);
      }
      if (_cancelRequested) {
        if (mounted) {
          setState(() {
            _stage = 'cancelled';
            _message = '任务已终止，未继续提交页面。';
          });
        }
        return;
      }
      if (!_archived) {
        widget.onArchive?.call();
        _archived = true;
      }
      await for (final event in widget.service.run(
        snapshot,
        resume: resume,
        cancelFile: _cancelFile!.path,
      )) {
        if (!mounted) continue;
        setState(() {
          _stage = event.stage;
          _message = event.message;
          if (event.jobDir != null) _jobDir = event.jobDir;
          if (event.image != null) _image = event.image;
          if (event.batchDir != null) _batchDir = event.batchDir;
          if (event.pages.isNotEmpty) {
            _results = event.pages;
            final images = event.pages.where((p) => p['image'] is String);
            if (images.isNotEmpty) {
              final selected =
                  images
                      .where((p) => p['number'] == _previewPage)
                      .firstOrNull ??
                  images.last;
              _image = selected['image'] as String;
              _previewPage = selected['number'] as int;
            }
          }
          if (_log.isEmpty || _log.last != event.message) {
            _log.add(event.message);
          }
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _stage = 'error';
          _message = '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _renderActive = false;
        });
      }
    }
  }

  void _cancel() {
    final marker = _cancelFile;
    if (!_busy || !_renderActive || _cancelRequested || marker == null) return;
    try {
      marker.parent.createSync(recursive: true);
      File('${marker.path}.tmp')
        ..writeAsStringSync(
          jsonEncode({
            'cancel_requested_at': DateTime.now().toUtc().toIso8601String(),
          }),
          flush: true,
        )
        ..renameSync(marker.path);
      setState(() {
        _cancelRequested = true;
        _message = '正在终止任务，请等待当前任务停止。';
      });
    } on FileSystemException catch (_) {
      setState(() => _message = '未能写入终止请求，请检查数据目录后重试。');
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await widget.service.restoreChat();
      if (mounted) setState(() => _message = '对话服务已恢复，分镜和任务记录已保留。');
    } on Object catch (e) {
      if (mounted) setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController value, {
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: value,
      enabled: !_busy,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        labelText: tr(label),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  void _editPreview() {
    if (_busy || widget.onEditPage == null) return;
    final result = _results
        .where((p) => p['number'] == _previewPage)
        .firstOrNull;
    final number = result == null
        ? widget.snapshot['page_number']
        : (result['context'] as Map?)?['page_number'];
    final page =
        _pages.where((p) => p['page_number'] == number).firstOrNull ??
        widget.snapshot;
    final index = page['page_index'];
    if (index is! int) return;
    Navigator.of(context).pop();
    widget.onEditPage!(index);
  }

  void _openFinishedPreview() {
    final pages = _pages.isEmpty ? [widget.snapshot] : _pages;
    final result = _results
        .where((p) => p['number'] == _previewPage)
        .firstOrNull;
    final number =
        (result?['context'] as Map?)?['page_number'] ??
        widget.snapshot['page_number'];
    showComicFinishedPreview(
      context,
      snapshots: pages,
      service: widget.previewService,
      title:
          '${widget.snapshot['series_title'] ?? widget.snapshot['title'] ?? '漫画'}',
      initialPage: pages.indexWhere((p) => p['page_number'] == number),
      onEditPage: widget.onEditPage == null
          ? null
          : (index) {
              Navigator.of(context).pop();
              widget.onEditPage!(index);
            },
      onRenderPage: widget.onRenderPage == null
          ? null
          : (index) {
              Navigator.of(context).pop();
              widget.onRenderPage!(index);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = _stage == 'done'
        ? _stages.length
        : _stages.indexWhere((s) => s.$1 == _stage);
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 980,
            maxHeight: MediaQuery.sizeOf(context).height * .86,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.play_circle_outline, color: PennaColors.primary),
                    const SizedBox(width: 10),
                    Text(
                      tr('一键接力'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${widget.snapshot['width']} × ${widget.snapshot['height']}',
                      style: TextStyle(
                        color: PennaColors.slate500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.snapshot['title'] ?? '当前页'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: PennaColors.slate500),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('当前单页'),
                          icon: Icon(Icons.insert_drive_file_outlined),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('多页批量'),
                          icon: Icon(Icons.collections_bookmark_outlined),
                        ),
                      ],
                      selected: {_multi},
                      onSelectionChanged: _busy || _renderMode == 'edit_only'
                          ? null
                          : (v) => setState(() => _multi = v.single),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _multi
                            ? '勾选本系列页面，按页序逐张生成；已完成页可断点续跑。'
                            : '只重做当前页，其他页成品保留。',
                        style: TextStyle(
                          fontSize: 12,
                          color: PennaColors.slate500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 350,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                tr(_multi ? '批量页面与共用参数' : '当前页生成参数'),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 18),
                              InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: '出图模式',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    key: const ValueKey('relay-render-mode'),
                                    value: _renderMode,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'generate',
                                        child: Text('MOSS 生成'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'generate_edit',
                                        child: Text('MOSS 生成后由 Qwen 修改'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'edit_only',
                                        child: Text('只修改已有图片（Qwen）'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'panels',
                                        child: Text('逐格生成并蒙版拼接'),
                                      ),
                                    ],
                                    onChanged: _busy
                                        ? null
                                        : (value) => setState(() {
                                            _renderMode = value!;
                                            if (_renderMode == 'edit_only') {
                                              _multi = false;
                                            }
                                          }),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              if (_renderMode == 'panels') ...[
                                const Text(
                                  '漫画格方框＝真实蒙版；模型只生成格内画面，台词仍由模型绘制。',
                                  style: TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<int>(
                                  initialValue: _panelResolution,
                                  decoration: const InputDecoration(
                                    labelText: '单格出图长边',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: [
                                    for (final n in [512, 768, 1024])
                                      DropdownMenuItem(
                                        value: n,
                                        child: Text('$n 像素'),
                                      ),
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (v) => setState(
                                          () => _panelResolution = v!,
                                        ),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    '每格再用 Qwen 修改',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  value: _panelEdit,
                                  onChanged: _busy
                                      ? null
                                      : (v) => setState(() => _panelEdit = v),
                                ),
                                if (_multi)
                                  const Text(
                                    '批量逐页识别“第1格、第2格…”对象框；同名格的最大框作为蒙版。',
                                    style: TextStyle(fontSize: 12),
                                  )
                                else ...[
                                  const Text(
                                    '勾选作为漫画格的框（人物／台词框通常不选）',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  for (final (i, box) in _boxes.indexed)
                                    if (box['label'] != 'text')
                                      CheckboxListTile(
                                        key: ValueKey('panel-mask-$i'),
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                        title: Text(
                                          '${box['name'] ?? '方框 ${i + 1}'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          '${box['box']}  ${box['shape'] == 'ellipse'
                                              ? '椭圆'
                                              : box['shape'] is List
                                              ? '多边形'
                                              : '矩形'}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        value: _panelIndices.contains(i),
                                        secondary: IconButton(
                                          key: ValueKey('panel-redo-$i'),
                                          tooltip: '只重绘这一格（换种子后开始接力）',
                                          onPressed:
                                              _busy ||
                                                  !_panelIndices.contains(i)
                                              ? null
                                              : () => setState(
                                                  () => _panelSeeds[i] =
                                                      DateTime.now()
                                                          .microsecondsSinceEpoch,
                                                ),
                                          icon: Icon(
                                            _panelSeeds.containsKey(i)
                                                ? Icons.refresh
                                                : Icons.casino_outlined,
                                          ),
                                        ),
                                        onChanged: _busy
                                            ? null
                                            : (v) => setState(() {
                                                if (v == true) {
                                                  _panelIndices.add(i);
                                                } else {
                                                  _panelIndices.remove(i);
                                                }
                                              }),
                                      ),
                                ],
                                const Text(
                                  '改描述或点格子右侧骰子，再开始接力；仅改变的格子重绘，其他格复用缓存。',
                                  style: TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 18),
                              ],
                              if (_usesQwen) ...[
                                TextField(
                                  key: const ValueKey('relay-edit-prompt'),
                                  controller: _editPrompt,
                                  enabled: !_busy,
                                  minLines: 3,
                                  maxLines: 5,
                                  decoration: const InputDecoration(
                                    labelText: '修改要求',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (_renderMode == 'generate_edit' ||
                                    _renderMode == 'panels')
                                  _field('修改步数', _editSteps, numeric: true),
                                if (_renderMode == 'edit_only') ...[
                                  _field('参考 PNG 路径（尺寸须与当前画布一致）', _reference),
                                  OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            final image = await widget
                                                .previewService
                                                .pickImage();
                                            if (image != null && mounted) {
                                              setState(
                                                () => _reference.text = image,
                                              );
                                            }
                                          },
                                    icon: const Icon(Icons.image_outlined),
                                    label: const Text('选择漫画 PNG'),
                                  ),
                                ],
                                const Text(
                                  '原稿与修改稿分别保存；模型可能改字，请对照检查。',
                                  style: TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 18),
                              ],
                              if (_multi) ...[
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => setState(
                                              () => _pickedPages.addAll(
                                                _pages
                                                    .where(
                                                      (p) =>
                                                          p['unavailable'] ==
                                                          null,
                                                    )
                                                    .map(
                                                      (p) =>
                                                          p['page_number']
                                                              as int,
                                                    ),
                                              ),
                                            ),
                                      child: const Text('全选'),
                                    ),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => setState(_pickedPages.clear),
                                      child: const Text('清空选择'),
                                    ),
                                    Text(
                                      '已选 ${_pickedPages.length} 页',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                                for (final page in _pages)
                                  CheckboxListTile(
                                    key: ValueKey(
                                      'relay-page-${page['page_number']}',
                                    ),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    value: _pickedPages.contains(
                                      page['page_number'],
                                    ),
                                    title: Text(
                                      '第 ${page['page_number']} 页 · ${page['title']}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    subtitle: page['unavailable'] == null
                                        ? null
                                        : Text(
                                            '${page['unavailable']}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                    onChanged:
                                        _busy || page['unavailable'] != null
                                        ? null
                                        : (v) => setState(
                                            () => v!
                                                ? _pickedPages.add(
                                                    page['page_number'] as int,
                                                  )
                                                : _pickedPages.remove(
                                                    page['page_number'],
                                                  ),
                                          ),
                                  ),
                                if (_pages.isEmpty)
                                  const Text('本系列还没有可批量生成的分镜。'),
                                const Divider(),
                              ] else if (widget.snapshot['unavailable'] != null)
                                Text(
                                  '${widget.snapshot['unavailable']}',
                                  style: TextStyle(color: PennaColors.amber),
                                ),
                              if (_renderMode != 'edit_only')
                                RelayLoraPicker(
                                  names: _loras,
                                  selected: _selected,
                                  weights: _weights,
                                  clipWeights: _clipWeights,
                                  busy:
                                      _busy ||
                                      _workflowBindings['manage_loras'] ==
                                          false,
                                  loading: _loadingLoras,
                                  error: _loraError,
                                  onSelect: (name, on) => setState(
                                    () => on
                                        ? _selected.add(name)
                                        : _selected.remove(name),
                                  ),
                                  onWeight: (name, value) =>
                                      _weights[name] = value,
                                  onClipWeight: (name, value) =>
                                      _clipWeights[name] = value,
                                  onRefresh: _loadLoras,
                                  onClear: () => setState(() => _selected = {}),
                                ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: _field(
                                      _renderMode == 'edit_only'
                                          ? '修改步数'
                                          : '采样步数',
                                      _renderMode == 'edit_only'
                                          ? _editSteps
                                          : _steps,
                                      numeric: true,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _field('随机种子', _seed, numeric: true),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_renderMode != 'edit_only') ...[
                                _field('工作流（ComfyUI API JSON）', _workflow),
                                if (_renderMode != 'edit_only') ...[
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: _busy || _inspecting
                                            ? null
                                            : () =>
                                                  _bindWorkflow(pickFile: true),
                                        icon: const Icon(
                                          Icons.file_open_outlined,
                                          size: 16,
                                        ),
                                        label: const Text('导入 API 工作流'),
                                      ),
                                      TextButton(
                                        onPressed: _busy || _inspecting
                                            ? null
                                            : () => _bindWorkflow(),
                                        child: Text(
                                          _inspecting ? '正在识别…' : '识别 / 修改绑定',
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_workflowReport?['inspection'] is Map)
                                    Text(
                                      '正面：${_workflowBindings['positive'] ?? '待选择'} · 采样：${_workflowBindings['sampler'] ?? '待选择'} · LoRA：${_workflowBindings['manage_loras'] == false ? '保留原工作流' : 'Penna 管理'}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                ],
                                TextField(
                                  key: const ValueKey('relay-cfg'),
                                  controller: _cfg,
                                  enabled: !_busy,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'MOSS CFG',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              Text(
                                tr('生成期间请等待接力完成，再发送新的 Agent 消息或其他出图任务。'),
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.6,
                                  color: PennaColors.slate500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 320),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: PennaColors.editorBg,
                            border: Border.all(color: PennaColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _image != null
                              ? Image.file(
                                  File(_image!),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, error, stack) =>
                                      SelectableText('预览读取失败：$error'),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _stage == 'error'
                                          ? Icons.info_outline
                                          : Icons.auto_awesome_outlined,
                                      size: 40,
                                      color: _stage == 'error'
                                          ? PennaColors.amber
                                          : PennaColors.primary,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _busy
                                          ? tr(_multi ? '正在逐页制作' : '正在制作当前页')
                                          : tr('成品会显示在这里'),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    for (final (i, s) in _stages.indexed)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 5,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              i < index
                                                  ? Icons.check_circle_outline
                                                  : Icons
                                                        .radio_button_unchecked,
                                              size: 16,
                                              color: i < index
                                                  ? PennaColors.accent
                                                  : PennaColors.slate400,
                                            ),
                                            const SizedBox(width: 10),
                                            SizedBox(
                                              width: 100,
                                              child: Text(
                                                tr(s.$2),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_results.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final page in _results)
                          ChoiceChip(
                            label: Text(
                              '第 ${(page['context'] as Map?)?['page_number'] ?? page['number']} 页 · ${switch (page['status']) {
                                'done' => '完成',
                                'error' => '失败',
                                'rendering' => '生成中',
                                _ => '等待',
                              }}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected: _previewPage == page['number'],
                            onSelected: page['image'] is! String
                                ? null
                                : (_) => setState(() {
                                    _previewPage = page['number'] as int;
                                    _image = page['image'] as String;
                                  }),
                          ),
                      ],
                    ),
                  ),
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 10),
                ],
                SelectableText(
                  _message,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: _stage == 'error'
                        ? PennaColors.amber
                        : PennaColors.slate700,
                  ),
                ),
                if (_jobDir != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _jobDir!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: PennaColors.slate500,
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_busy && _renderActive)
                      TextButton(
                        onPressed: _cancelRequested ? null : _cancel,
                        child: Text(_cancelRequested ? '终止中…' : '终止任务'),
                      ),
                    if (_image != null && !_busy)
                      TextButton.icon(
                        onPressed: _openFinishedPreview,
                        icon: const Icon(Icons.auto_stories_outlined, size: 16),
                        label: const Text('成品预览'),
                      ),
                    if (widget.onEditPage != null && !_busy)
                      TextButton.icon(
                        onPressed: _editPreview,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('修改此页分镜'),
                      ),
                    if (_stage == 'error')
                      TextButton(
                        onPressed: _busy ? null : _restore,
                        child: Text(tr('恢复对话')),
                      ),
                    if (_jobDir != null)
                      TextButton(
                        onPressed: () => Process.start('explorer.exe', [
                          _batchDir ?? _jobDir!,
                        ], runInShell: false),
                        child: Text(tr('打开输出目录')),
                      ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(tr('关闭')),
                    ),
                    FilledButton.icon(
                      onPressed:
                          _busy ||
                              _loadingLoras ||
                              _loraError != null ||
                              (_multi
                                  ? _pickedPages.isEmpty
                                  : widget.snapshot['unavailable'] != null)
                          ? null
                          : _start,
                      icon: Icon(
                        _busy ? Icons.hourglass_top : Icons.play_arrow,
                        size: 18,
                      ),
                      label: Text(
                        tr(
                          _busy
                              ? '正在接力…'
                              : _stage == 'error'
                              ? '重试接力'
                              : _stage == 'done'
                              ? '重新生成'
                              : '开始接力',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
