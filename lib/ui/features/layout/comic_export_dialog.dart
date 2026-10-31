import 'package:flutter/material.dart';

import '../../../core/harness/comic/comic_export_service.dart';
import '../../core/theme.dart';

Future<void> showComicExport(
  BuildContext context, {
  required List<Map<String, Object?>> snapshots,
  required String title,
  List<String?>? initialImages,
  String initialReadingDirection = 'rtl',
  ComicExportService service = const ComicExportService(),
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ComicExportDialog(
    snapshots: snapshots,
    title: title,
    initialImages: initialImages,
    initialReadingDirection: initialReadingDirection,
    service: service,
  ),
);

class ComicExportDialog extends StatefulWidget {
  const ComicExportDialog({
    super.key,
    required this.snapshots,
    required this.title,
    this.service = const ComicExportService(),
    this.initialImages,
    this.initialReadingDirection = 'rtl',
  });
  final List<Map<String, Object?>> snapshots;
  final String title;
  final ComicExportService service;
  final List<String?>? initialImages;
  final String initialReadingDirection;

  @override
  State<ComicExportDialog> createState() => _ComicExportDialogState();
}

class _ComicExportDialogState extends State<ComicExportDialog> {
  List<List<ComicExportVersion>> _versions = [];
  List<String?> _selected = [];
  bool _loading = true, _busy = false;
  String? _error, _directory;
  String _formats = 'both', _direction = 'rtl', _message = '';
  Map<String, String> _files = {};

  @override
  void initState() {
    super.initState();
    _direction = widget.initialReadingDirection == 'ltr' ? 'ltr' : 'rtl';
    _selected = List.filled(widget.snapshots.length, null);
    _versions = List.generate(widget.snapshots.length, (_) => []);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final versions = await widget.service.findVersions(widget.snapshots);
      if (versions.length != widget.snapshots.length) {
        throw StateError('页面版本列表不完整。');
      }
      if (!mounted) return;
      setState(() {
        _versions = [
          for (final page in versions) [...page],
        ];
        _selected = [
          for (var i = 0; i < versions.length; i++)
            widget.initialImages != null && i < widget.initialImages!.length
                ? widget.initialImages![i]
                : versions[i].firstOrNull?.image,
        ];
        for (var i = 0; i < _selected.length; i++) {
          final path = _selected[i];
          if (path != null && !_versions[i].any((v) => v.image == path)) {
            _versions[i].insert(
              0,
              ComicExportVersion(image: path, label: '预览选定版本'),
            );
          }
        }
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseDirectory() async {
    try {
      final path = await widget.service.pickOutputDirectory();
      if (mounted && path != null) setState(() => _directory = path);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _chooseImage(int index) async {
    try {
      final path = await widget.service.pickImage();
      if (!mounted || path == null) return;
      setState(() {
        if (!_versions[index].any((v) => v.image == path)) {
          _versions[index].add(
            ComicExportVersion(
              image: path,
              label: '本地 PNG · ${path.split(RegExp(r'[/\\]')).last}',
            ),
          );
        }
        _selected[index] = path;
        _files = {};
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _export() async {
    if (_busy ||
        _selected.isEmpty ||
        _selected.any((p) => p == null) ||
        _directory == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _files = {};
    });
    try {
      final pages = <Map<String, Object?>>[
        for (var index = 0; index < widget.snapshots.length; index++)
          {
            ...widget.snapshots[index],
            'image': _selected[index],
            'page_number':
                (widget.snapshots[index]['context'] as Map?)?['page_number'] ??
                index + 1,
          },
      ];
      final files = await widget.service.exportComic(
        pages: pages,
        outputDir: _directory!,
        title: widget.title,
        formats: _formats == 'both' ? ['cbz', 'pdf'] : [_formats],
        readingDirection: _direction,
        onProgress: (message) {
          if (mounted) setState(() => _message = message);
        },
      );
      if (mounted) {
        setState(() {
          _files = files;
          _message = '导出完成：${pages.length} 页';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _message = '';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _page(int index) {
    final snapshot = widget.snapshots[index];
    final options = _versions[index];
    final missing = _selected[index] == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${index + 1}. ${snapshot['title'] ?? '漫画页'}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: options.isEmpty
                    ? Text(
                        '缺少成品图片，请选择本地 PNG',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      )
                    : DropdownButtonFormField<String>(
                        key: ValueKey('comic-export-version-$index'),
                        initialValue: _selected[index],
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final v in options)
                            DropdownMenuItem(
                              value: v.image,
                              child: Text(
                                v.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy || _loading
                            ? null
                            : (value) => setState(() {
                                _selected[index] = value;
                                _files = {};
                              }),
                      ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: ValueKey('comic-export-local-$index'),
                onPressed: _busy || _loading ? null : () => _chooseImage(index),
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('本地 PNG'),
              ),
            ],
          ),
          if (!missing)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _selected[index]!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: PennaColors.slate500),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final missing = _selected.where((path) => path == null).length;
    final canExport =
        !_loading &&
        !_busy &&
        _selected.isNotEmpty &&
        missing == 0 &&
        _directory != null;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 860,
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
                    Icon(Icons.menu_book_outlined, color: PennaColors.primary),
                    const SizedBox(width: 10),
                    const Text(
                      '导出漫画',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.title} · ${widget.snapshots.length} 页，按下列顺序阅读',
                  style: TextStyle(color: PennaColors.slate500),
                ),
                const SizedBox(height: 12),
                if (_loading) const LinearProgressIndicator(),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var i = 0; i < widget.snapshots.length; i++)
                          _page(i),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _formats,
                        decoration: const InputDecoration(
                          labelText: '文件格式',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'both',
                            child: Text('CBZ + PDF'),
                          ),
                          DropdownMenuItem(value: 'cbz', child: Text('CBZ')),
                          DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _formats = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _direction,
                        decoration: const InputDecoration(
                          labelText: '阅读方向',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'rtl', child: Text('从右向左')),
                          DropdownMenuItem(value: 'ltr', child: Text('从左向右')),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _direction = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _directory ?? '请选择成品保存目录',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('comic-export-directory'),
                      onPressed: _busy ? null : _chooseDirectory,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('选择目录'),
                    ),
                  ],
                ),
                if (!_loading && missing > 0)
                  Text(
                    '还有 $missing 页未选择图片，补齐后可导出。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SelectableText(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                if (_message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_message),
                  ),
                for (final file in _files.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SelectableText(
                      '${file.key.toUpperCase()}：${file.value}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('关闭'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('comic-export-start'),
                      onPressed: canExport ? _export : null,
                      child: Text(_busy ? '正在导出…' : '导出成品'),
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
