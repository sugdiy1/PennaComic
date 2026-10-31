part of 'studio_view_model.dart';

/// 外部控制也走工作台的内存状态、撤销记录和原子存盘。
/// 整个提交同步完成，UI 事件不能插到版本核对与写入之间。
extension StudioAgentControl on StudioViewModel {
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
