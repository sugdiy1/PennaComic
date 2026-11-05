part of 'studio_view_model.dart';

extension StudioLayoutTask on StudioViewModel {
  LayoutPageTask? get layoutPageTask =>
      _layoutPageTask?.series == series ? _layoutPageTask : null;
  String? get _taskTarget {
    final task = layoutPageTask;
    if (task == null || !task.active) return null;
    if (task.rangeStart case final start?) {
      final number = start + task.completed;
      return number <= seriesLength ? '$number' : 'new';
    }
    return task.completed == 0 ? task.firstTarget : 'new';
  }

  String get _taskContext {
    final task = layoutPageTask;
    if (task == null || !task.active) return '';
    return '\n【程序自动多页任务】\n'
        '用户只发起一次完整任务，程序会自动执行全部 ${task.total} 页；当前只生成任务第 ${task.completed + 1}/${task.total} 页。'
        '本次目标 $_taskTarget。只返回这一页的完整布局，不抢做其他页，也不要要求用户发送“下一页”。'
        '独立漫画格对象框命名“第1格、第2格…”并写各自场景，人物/物体/台词另设框。'
        '不要擅自固定每页格数；承接已经完成的剧情，不重复开场，最后一页收束。'
        '\n【整批原始要求，跨页持续保留】${task.instruction}'
        '\n【已完成页的剧情记忆】${task.summaries.join('\n')}';
  }

  void _prepareLayoutPageTask(QueuedMessage m) {
    if (!layoutOnly || layout == null) return;
    final count = requestedLayoutPageCount(m.text);
    if (count != null) {
      _layoutPageTask = LayoutPageTask(
        instruction: _withReferences(
          ChatMessage(
            fromUser: true,
            text: m.text,
            time: DateTime.now(),
            skillIds: m.skillIds,
            attachments: m.attachments,
            quote: m.quote,
          ),
          {},
        ),
        sourceText: m.text,
        total: count,
        series: series,
        firstTarget: RegExp(r'新系列|另起系列').hasMatch(m.text)
            ? '新系列'
            : layout!.layout.isEmpty
            ? 'current'
            : 'new',
        rangeStart: requestedLayoutRangeStart(m.text),
      );
    } else if (layoutPageTask case final task?
        when !task.complete && !task.active) {
      if (RegExp(
        r'^\s*(?:继续|接着|完成剩下|继续完成|恢复任务|resume)',
        caseSensitive: false,
      ).hasMatch(m.text)) {
        task.active = true;
        task.error = null;
      }
    }
  }

  String? resumeLayoutPageTask() {
    final task = layoutPageTask;
    if (task == null || task.complete) return '没有待继续的多页任务。';
    if (isStreaming) return '当前仍在生成。';
    return send('继续完成剩下的漫画页，不重做已经完成的页。');
  }

  void _pauseLayoutPageTask(String reason) {
    final task = layoutPageTask;
    if (task == null || !task.active) return;
    task.active = false;
    task.error = reason;
    _saveTimer?.cancel();
    _saveNow();
  }

  bool _continueLayoutPageTask() {
    final task = layoutPageTask;
    if (task == null || !task.active) return false;
    if (_messages.last.failed || !_layoutTaskPageApplied) {
      _pauseLayoutPageTask('本页没有成功写入有效分镜。');
      _updateReply(
        (m) => m.copyWith(
          toolSummary:
              '多页任务已暂停：完成 ${task.completed}/${task.total} 页，点继续可重试剩余页。',
        ),
      );
      return false;
    }
    task.completed++;
    final l = layout!.layout;
    final summary = '第${pageNumber(_page)}页 ${pages[_page].name}: ${l.caption}';
    task.summaries.add(
      summary.length > 420 ? '${summary.substring(0, 420)}…' : summary,
    );
    task.series = series;
    if (task.complete) task.active = false;
    _updateReply(
      (m) => m.copyWith(
        toolSummary: task.complete
            ? '自动分镜全部完成：${task.total}/${task.total} 页。'
            : '自动分镜已完成 ${task.completed}/${task.total} 页，正在继续。',
      ),
    );
    _saveTimer?.cancel();
    _saveNow();
    if (task.complete) return false;
    _layoutRepairAttempts = 0;
    final problem = _startReply([
      ..._messages,
      ChatMessage(
        fromUser: true,
        tool: true,
        time: DateTime.now(),
        text: '程序自动续页：继续任务第 ${task.completed + 1}/${task.total} 页。已完成页不要重做。',
      ),
    ], DateTime.now());
    if (problem != null) {
      _pauseLayoutPageTask(problem);
      return false;
    }
    return true;
  }
}
