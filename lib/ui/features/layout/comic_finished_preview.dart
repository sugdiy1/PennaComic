import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/harness/comic/comic_export_service.dart';
import '../../core/theme.dart';
import 'comic_export_dialog.dart';

Future<void> showComicFinishedPreview(
  BuildContext context, {
  required List<Map<String, Object?>> snapshots,
  required String title,
  int initialPage = 0,
  ValueChanged<int>? onEditPage,
  ValueChanged<int>? onRenderPage,
  ComicExportService service = const ComicExportService(),
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => ComicFinishedPreview(
      snapshots: snapshots,
      title: title,
      initialPage: initialPage,
      onEditPage: onEditPage,
      onRenderPage: onRenderPage,
      service: service,
    ),
  ),
);

/// 成品阅读器只读 PNG 和任务元数据，不发模型请求，不改分镜或原图。
class ComicFinishedPreview extends StatefulWidget {
  const ComicFinishedPreview({
    super.key,
    required this.snapshots,
    required this.title,
    this.initialPage = 0,
    this.onEditPage,
    this.onRenderPage,
    this.service = const ComicExportService(),
  });
  final List<Map<String, Object?>> snapshots;
  final String title;
  final int initialPage;
  final ValueChanged<int>? onEditPage, onRenderPage;
  final ComicExportService service;
  @override
  State<ComicFinishedPreview> createState() => _ComicFinishedPreviewState();
}

class _ComicFinishedPreviewState extends State<ComicFinishedPreview> {
  final _transform = TransformationController();
  final _thumbnails = ScrollController();
  List<List<ComicExportVersion>> _versions = [];
  List<String?> _selected = [];
  int _at = 0;
  bool _loading = true, _spread = false, _rtl = true;
  String? _error;
  double _zoom = 1;
  Size _viewport = Size.zero;
  int get _count => widget.snapshots.length;
  Map<String, Object?>? get _page => _count == 0 ? null : widget.snapshots[_at];
  ComicExportVersion? _version(int index) =>
      _versions[index].where((v) => v.image == _selected[index]).firstOrNull;
  bool _old(int index) => _version(index)?.matchesSource == false;
  int get _ready => _selected.whereType<String>().length;
  List<int> get _visible {
    if (_count == 0) return const [];
    final first = _spread ? (_at ~/ 2) * 2 : _at;
    final pages = [first, if (_spread && first + 1 < _count) first + 1];
    return _spread && _rtl ? pages.reversed.toList() : pages;
  }

  @override
  void initState() {
    super.initState();
    _at = _count == 0 ? 0 : widget.initialPage.clamp(0, _count - 1);
    _versions = List.generate(_count, (_) => <ComicExportVersion>[]);
    _selected = List.filled(_count, null);
    _load();
  }

  @override
  void dispose() {
    _transform.dispose();
    _thumbnails.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final found = await widget.service.findPreviewVersions(widget.snapshots);
      if (found.length != _count) throw StateError('页面版本列表不完整，请刷新重试。');
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _count; i++) {
          final previous = _version(i);
          _versions[i] = [...found[i]];
          if (previous != null &&
              previous.jobDir == null &&
              !_versions[i].any((v) => v.image == previous.image)) {
            _versions[i].add(previous);
          }
          // 刷新保留用户的版本选择，不能偷偷换成另一张图。
          if (!_versions[i].any((v) => v.image == _selected[i])) {
            _selected[i] = _versions[i].firstOrNull?.image;
          }
        }
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fit() {
    _transform.value = Matrix4.identity();
    setState(() => _zoom = 1);
  }

  void _setZoom(double value) {
    final scale = value.clamp(1, 5).toDouble();
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        center.dx * (1 - scale),
        center.dy * (1 - scale),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
    setState(() => _zoom = scale);
  }

  void _select(int index) {
    if (index < 0 || index >= _count) return;
    setState(() => _at = index);
    _fit();
    if (_thumbnails.hasClients) {
      final offset = (index * 212.0)
          .clamp(0.0, _thumbnails.position.maxScrollExtent)
          .toDouble();
      _thumbnails.animateTo(
        offset,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
  }

  int _destination(int direction) =>
      (_spread ? (_at ~/ 2) * 2 : _at) + direction * (_spread ? 2 : 1);
  bool _canTurn(int direction) =>
      _count > 0 &&
      _destination(direction) >= 0 &&
      _destination(direction) < _count;
  void _turn(int direction) {
    if (_canTurn(direction)) _select(_destination(direction));
  }

  Future<void> _pick() async {
    if (_count == 0) return;
    final index = _at;
    try {
      final path = await widget.service.pickImage();
      if (path == null || !mounted) return;
      setState(() {
        if (!_versions[index].any((v) => v.image == path)) {
          _versions[index].add(
            ComicExportVersion(image: path, label: '手动选择的 PNG'),
          );
        }
        _selected[index] = path;
        _error = null;
      });
      _fit();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _leaveFor(ValueChanged<int>? action) {
    final index = _page?['page_index'];
    if (action == null || index is! int) return;
    Navigator.of(context).pop();
    action(index);
  }

  Future<void> _export() => showComicExport(
    context,
    snapshots: widget.snapshots,
    title: widget.title,
    initialImages: List.of(_selected),
    initialReadingDirection: _rtl ? 'rtl' : 'ltr',
    service: widget.service,
  );

  KeyEventResult _keys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _turn(_rtl ? 1 : -1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _turn(_rtl ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      _select(0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      _select(_count - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _image(String path, {bool thumb = false}) => Image.file(
    File(path),
    key: ValueKey('${thumb ? 'thumb' : 'page'}-$path'),
    fit: BoxFit.contain,
    cacheWidth: thumb ? 200 : null,
    errorBuilder: (_, error, stack) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: PennaColors.slate400,
            size: thumb ? 24 : 42,
          ),
          if (!thumb) ...[
            const SizedBox(height: 12),
            const Text('图片无法读取，请重新选择 PNG。'),
          ],
        ],
      ),
    ),
  );

  Widget _thumb(int index) {
    final selected = _at == index;
    final path = _selected[index];
    final page = widget.snapshots[index];
    return SizedBox(
      height: 212,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
        child: InkWell(
          key: ValueKey('finished-thumb-$index'),
          onTap: () => _select(index),
          borderRadius: BorderRadius.circular(5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: PennaColors.card,
                    border: Border.all(
                      color: selected
                          ? PennaColors.primary
                          : PennaColors.border,
                      width: selected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: path == null
                      ? Center(
                          child: Icon(
                            Icons.image_outlined,
                            color: PennaColors.slate400,
                          ),
                        )
                      : _image(path, thumb: true),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '第 ${page['page_number'] ?? index + 1} 页',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? PennaColors.primary : PennaColors.text,
                ),
              ),
              Text(
                path == null
                    ? '尚未出图'
                    : _old(index)
                    ? '旧稿成品'
                    : '${page['title'] ?? '成品'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: _old(index) ? PennaColors.amber : PennaColors.slate500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyPage(int index) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 48,
            color: PennaColors.slate400,
          ),
          const SizedBox(height: 18),
          Text(
            '第 ${widget.snapshots[index]['page_number'] ?? index + 1} 页还没有成品',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '先生成这一页，或选择已有 PNG 查看。',
            style: TextStyle(color: PennaColors.slate500),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () {
              _select(index);
              _pick();
            },
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('选择 PNG'),
          ),
        ],
      ),
    ),
  );

  Widget _header(bool narrow) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: PennaColors.card,
      border: Border(bottom: BorderSide(color: PennaColors.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '返回画板',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '成品预览',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${widget.title} · $_ready / $_count 页已有图片',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: PennaColors.slate500),
                  ),
                ],
              ),
            ),
            if (!narrow) _actions(),
          ],
        ),
        if (narrow)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _actions(),
          ),
      ],
    ),
  );

  Widget _actions() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: '刷新成品',
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
      ),
      TextButton.icon(
        key: const ValueKey('finished-edit'),
        onPressed: widget.onEditPage == null || _page?['page_index'] is! int
            ? null
            : () => _leaveFor(widget.onEditPage),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('修改分镜'),
      ),
      TextButton.icon(
        key: const ValueKey('finished-render'),
        onPressed: widget.onRenderPage == null || _page?['page_index'] is! int
            ? null
            : () => _leaveFor(widget.onRenderPage),
        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
        label: Text(_count > 0 && _selected[_at] != null ? '重做此页' : '生成此页'),
      ),
      const SizedBox(width: 8),
      FilledButton.icon(
        key: const ValueKey('finished-export'),
        onPressed: _loading || _count == 0 ? null : _export,
        icon: const Icon(Icons.menu_book_outlined, size: 18),
        label: const Text('导出成品'),
      ),
    ],
  );

  Widget _versionBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    color: PennaColors.card,
    child: Row(
      children: [
        Expanded(
          child: Text(
            _page == null
                ? '还没有漫画页'
                : '第 ${_page!['page_number'] ?? _at + 1} 页 · ${_page!['title'] ?? '漫画页'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        if (_count > 0 && _versions[_at].isNotEmpty)
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: DropdownButtonFormField<String>(
                key: ValueKey('finished-version-$_at'),
                initialValue: _selected[_at],
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '图片版本',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final v in _versions[_at])
                    DropdownMenuItem(
                      value: v.image,
                      child: Text(
                        '${v.matchesSource ? '' : '旧稿 · '}${v.label}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
                onChanged: (value) {
                  setState(() => _selected[_at] = value);
                  _fit();
                },
              ),
            ),
          ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '选择本地 PNG',
          onPressed: _count == 0 ? null : _pick,
          icon: const Icon(Icons.add_photo_alternate_outlined),
        ),
      ],
    ),
  );

  Widget _reader() => LayoutBuilder(
    builder: (context, constraints) {
      _viewport = constraints.biggest;
      if (_count == 0) {
        return const Center(child: Text('当前系列还没有漫画页，返回画板添加分镜后再预览。'));
      }
      return InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 5,
        boundaryMargin: const EdgeInsets.all(240),
        onInteractionUpdate: (_) =>
            setState(() => _zoom = _transform.value.getMaxScaleOnAxis()),
        child: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (position, index) in _visible.indexed) ...[
                  if (position > 0) const SizedBox(width: 12),
                  Expanded(
                    child: _selected[index] == null
                        ? _emptyPage(index)
                        : _image(_selected[index]!),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _footer() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    color: PennaColors.card,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('finished-previous'),
            tooltip: '上一页',
            onPressed: _canTurn(-1) ? () => _turn(-1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            _count == 0 ? '0 / 0' : '${_at + 1} / $_count',
            style: const TextStyle(fontSize: 12),
          ),
          IconButton(
            key: const ValueKey('finished-next'),
            tooltip: '下一页',
            onPressed: _canTurn(1) ? () => _turn(1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
          const SizedBox(width: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('单页')),
              ButtonSegment(value: true, label: Text('双页')),
            ],
            selected: {_spread},
            onSelectionChanged: (v) {
              setState(() => _spread = v.single);
              _fit();
            },
          ),
          const SizedBox(width: 12),
          PopupMenuButton<bool>(
            tooltip: '阅读方向',
            initialValue: _rtl,
            onSelected: (v) {
              setState(() => _rtl = v);
              _fit();
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: true,
                checked: _rtl,
                child: const Text('从右向左'),
              ),
              CheckedPopupMenuItem(
                value: false,
                checked: !_rtl,
                child: const Text('从左向右'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _rtl ? '从右向左' : '从左向右',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            tooltip: '缩小',
            onPressed: _zoom <= 1 ? null : () => _setZoom(_zoom / 1.25),
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${(_zoom * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: '放大',
            onPressed: _zoom >= 5 ? null : () => _setZoom(_zoom * 1.25),
            icon: const Icon(Icons.add),
          ),
          TextButton(onPressed: _fit, child: const Text('适合窗口')),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: PennaColors.slate100,
    body: Focus(
      autofocus: true,
      onKeyEvent: _keys,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            _header(constraints.maxWidth < 1000),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: constraints.maxWidth < 800 ? 112 : 170,
                    decoration: BoxDecoration(
                      color: PennaColors.bg,
                      border: Border(
                        right: BorderSide(color: PennaColors.border),
                      ),
                    ),
                    child: ListView.builder(
                      controller: _thumbnails,
                      itemExtent: 212,
                      itemCount: _count,
                      itemBuilder: (_, i) => _thumb(i),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _versionBar(),
                        if (_count > 0 && _old(_at))
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 9,
                            ),
                            color: PennaColors.lock,
                            child: Text(
                              _versions[_at].any((v) => v.matchesSource)
                                  ? '正在查看旧稿成品，可在图片版本中切回当前稿。'
                                  : '正在查看旧稿成品：本页分镜已经修改，尚未生成对应图片。',
                              style: TextStyle(
                                fontSize: 12,
                                color: PennaColors.lockText,
                              ),
                            ),
                          ),
                        Expanded(child: _reader()),
                        _footer(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
