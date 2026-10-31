part of 'studio_view_model.dart';

/// 外部控制也走工作台的内存状态、撤销记录和原子存盘。
/// 整个提交同步完成，UI 事件不能插到版本核对与写入之间。
extension StudioAgentControl on StudioViewModel {
  /// Explicit durability barrier for the live page and the current board.
  /// Unlike debounced UI saving, filesystem failures propagate to the caller.
  Map<String, Object?> agentFlush() {
    if (isStreaming) throw StateError('内置 Agent 正在回复，请等回复结束');
    if (!layoutOnly || layout == null) throw StateError('需要区域分镜工作台');
    final file = saveFile;
    if (file == null) throw StateError('工作台未配置保存路径');
    _pullBoard();
    _saveTimer?.cancel();
    _saveTimer = null;
    void write(File target, Object data) {
      target.parent.createSync(recursive: true);
      File('${target.path}.agent.tmp')
        ..writeAsStringSync(jsonEncode(data), flush: true)
        ..renameSync(target.path);
    }

    write(file, toJson());
    final board = layout!;
    final boardDir = board.dir;
    final boardFile = boardDir == null
        ? null
        : File('${boardDir.path}/layout.json');
    if (boardFile != null) {
      write(boardFile, {
        'layout': board.layout.toJson(),
        'sizes': [
          for (final size in board.sizes) [size.width, size.height],
        ],
      });
    }
    return {
      'persisted': true,
      'save_path': file.absolute.path,
      if (boardFile != null) 'board_save_path': boardFile.absolute.path,
      'page_count': pages.length,
    };
  }

  T _agentCommit<T>(T Function() change) {
    if (isStreaming) throw StateError('内置 Agent 正在回复，请等回复结束');
    if (!layoutOnly || layout == null) throw StateError('需要区域分镜工作台');
    final before = _snapshot();
    final boardBefore = layout!.layout;
    final textBefore = _boardText;
    final actions = _actions;
    final undo = _undo;
    try {
      final value = change();
      _changed();
      _saveTimer?.cancel();
      _saveTimer = null;
      final file = saveFile;
      if (file != null) {
        file.parent.createSync(recursive: true);
        File('${file.path}.agent.tmp')
          ..writeAsStringSync(jsonEncode(toJson()), flush: true)
          ..renameSync(file.path);
      }
      return value;
    } catch (_) {
      _pages = before.pages;
      _page = before.page;
      _seriesNames = before.seriesNames;
      _seriesChats = before.seriesChats;
      _messages = before.messages;
      _chatId = before.chatId;
      _archive = before.archive;
      _closedTabs = before.closedTabs;
      _blocks = before.pages[_page].blocks;
      _pending = before.pages[_page].pending;
      _queued = before.pages[_page].queued;
      layout!.removeListener(_boardListener);
      try {
        layout!.replace(boardBefore);
      } finally {
        layout!.addListener(_boardListener);
      }
      _boardText = textBefore;
      _notify();
      _actions = actions;
      _undo = undo;
      rethrow;
    }
  }

  void agentReplacePage(int index, Layout value, {String? name}) =>
      _agentCommit(() {
        final current = pages;
        final old = current[index];
        _log('外部 Agent 修改 ${seriesName(old.series)} 第 ${pageNumber(index)} 页');
        final blocks = <Block>[
          (text: jsonEncode(value.toJson()), pinned: false),
        ];
        current[index] = (
          series: old.series,
          name: name ?? old.name,
          blocks: blocks,
          pending: null,
          queued: const [],
        );
        _pages = List.unmodifiable(current);
        if (index == _page) {
          _blocks = List.unmodifiable(blocks);
          _pending = null;
          _queued = const [];
        }
      });

  int agentCreatePage(
    Layout value, {
    required int series,
    String name = '',
    String? seriesName,
  }) => _agentCommit(() {
    final before = _snapshot();
    final at = _insertPage(series);
    if (at == null) throw StateError(StudioPages.fullMessage);
    final current = pages;
    current[at] = _newPage(
      series,
      name: name,
      blocks: [(text: jsonEncode(value.toJson()), pinned: false)],
    );
    _pages = List.unmodifiable(current);
    if (seriesName != null) {
      _seriesNames = Map.unmodifiable({..._seriesNames, series: seriesName});
    }
    _log('外部 Agent 新建第 ${pageNumber(at)} 页', before: before);
    return at;
  });
}
