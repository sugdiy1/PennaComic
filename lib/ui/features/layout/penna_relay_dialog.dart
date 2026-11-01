import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/harness/comic/penna_relay_service.dart';
import '../../../core/harness/comic/comic_export_service.dart';
import '../../../core/integration_settings.dart';
import '../../core/theme.dart';
import '../../../l10n/l10n.dart';
import 'relay_lora_picker.dart';
import 'comic_finished_preview.dart';

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
  final _seed = TextEditingController(text: '42');
  final _editSteps = TextEditingController(text: '25');
  final _editPrompt = TextEditingController(
    text:
        '只修正漫画中不自然的手指、手臂连接和肢体遮挡。保留人物身份、服装、动作、分格、气泡位置及全部原有中文台词，不增删或改写文字，保持原画风。',
  );
  final _reference = TextEditingController();
  String _renderMode = 'generate';
  List<String> _loras = [];
  Set<String> _selected = {'moss_Lineart.safetensors'};
  final _weights = <String, String>{};
  bool _loadingLoras = true, _loadedPreferences = false;
  String? _loraError, _lastSettings;
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
          if (prefs['seed'] is int) _seed.text = '${prefs['seed']}';
          if ([
            'generate',
            'generate_edit',
            'edit_only',
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
    _seed.dispose();
    _editSteps.dispose();
    _editPrompt.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;
    if (_renderMode != 'generate' &&
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
    final steps = _renderMode == 'edit_only' ? 50 : int.tryParse(_steps.text);
    final seed = int.tryParse(_seed.text);
    if (_loadingLoras || _loraError != null) return;
    if (steps == null ||
        steps < 1 ||
        steps > 100 ||
        seed == null ||
        seed < 0 ||
        seed >= 9007199254740992) {
      setState(() {
        _stage = 'error';
        _message = '请填写有效参数：步数 1–100，非负整数种子，LoRA 强度 0–2。';
      });
      return;
    }
    final selected = <Map<String, Object>>[];
    for (final name in _loras.where(
      (name) => _renderMode != 'edit_only' && _selected.contains(name),
    )) {
      final weight = double.tryParse(_weights[name] ?? '0.85');
      if (weight == null || !weight.isFinite || weight < 0 || weight > 2) {
        setState(() {
          _stage = 'error';
          _message = '$name 的强度应为 0–2。';
        });
        return;
      }
      selected.add({'name': name, 'strength': weight});
    }
    final settings = <String, Object>{
      'steps': steps,
      'seed': seed,
      'loras': selected,
      'cfg': 3,
      'render_mode': _renderMode,
      'edit_prompt': _editPrompt.text,
      'edit_steps': int.tryParse(_editSteps.text) ?? 25,
      if (_renderMode == 'edit_only') 'reference_image': _reference.text.trim(),
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
                              if (_renderMode != 'generate') ...[
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
                                if (_renderMode == 'generate_edit')
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
                                  busy: _busy,
                                  loading: _loadingLoras,
                                  error: _loraError,
                                  onSelect: (name, on) => setState(
                                    () => on
                                        ? _selected.add(name)
                                        : _selected.remove(name),
                                  ),
                                  onWeight: (name, value) =>
                                      _weights[name] = value,
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
