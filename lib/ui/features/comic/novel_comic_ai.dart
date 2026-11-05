part of 'novel_comic_model.dart';

extension NovelComicAi on NovelComicModel {
  void pauseAi() {
    _stopRequested = true;
    designer?.cancel();
    progress = '正在暂停，已完成页会保留。';
    _notify();
  }

  void _replaceProject(ComicProject project) {
    _projects = [for (final p in _projects) p.id == project.id ? project : p];
  }

  Future<void> planAi({bool restart = false}) async {
    final selectedProject = current;
    if (busy || selectedProject == null) return;
    ComicProject project = selectedProject;
    final ai = designer;
    if (ai == null) {
      error = '小说漫画尚未配置AI连接。';
      _notify();
      return;
    }
    busy = true;
    error = null;
    _stopRequested = false;
    progress = '正在读取小说卷章…';
    _notify();
    try {
      options.validate();
      ai.profile(options);
      final input = File(project.inputPath);
      final hash = sha256.convert(await input.readAsBytes()).toString();
      final signature = sha256
          .convert(
            utf8.encode(
              jsonEncode({
                'source': hash,
                'pages': options.pagesPerChapter,
                'style': options.style,
                'brief': options.creativeBrief,
              }),
            ),
          )
          .toString();
      final book = await readBook(project.inputPath, options);
      if (_disposed || _stopRequested) return;
      project = await _prepareBookAssets(project, book, hash);
      if (_disposed || _stopRequested) return;
      final tasks = <Map<String, dynamic>>[];
      for (final raw in book['chapters'] as List) {
        final chapter = Map<String, dynamic>.from(raw as Map);
        final chunks = _sourceChunks(
          chapter['text'] as String,
          options.pagesPerChapter,
        );
        for (final (i, chunk) in chunks.indexed) {
          if (chunk.length > 24000) {
            throw const FormatException('单页原文超过24000字符，请增加每章页数后重试；原文没有被截断。');
          }
          tasks.add({
            'volume': chapter['volume'],
            'chapter': chapter['title'],
            'chapter_index': chapter['index'],
            'chapter_page': i + 1,
            'text': chunk,
          });
        }
      }
      if (tasks.isEmpty) throw const FormatException('小说没有可用于分镜的正文。');
      var state = Map<String, dynamic>.from(project.aiState);
      if (restart || state['signature'] == null || state['run'] == null) {
        state = {
          'signature': signature,
          'run': '${DateTime.now().microsecondsSinceEpoch}',
          'total': tasks.length,
          'memories': <String>[],
          'cast': _assetCast(project.assets),
          'status': 'running',
        };
        project = project.copyWith(
          name: '${book['book']}',
          pages: [],
          aiState: state,
          warnings: [],
          status: 'planning',
        );
        _replaceProject(project);
        _pageId = null;
        page = null;
        _save();
      } else if (state['signature'] != signature) {
        throw const FormatException('原文或创作设置发生变化。请使用“重新规划”创建新一轮，旧页面文件会保留。');
      }
      var memories = (state['memories'] as List? ?? []).cast<String>().toList();
      var cast = {
        ...Map<String, dynamic>.from(state['cast'] as Map? ?? {}),
        ..._assetCast(project.assets),
      };
      for (var index = project.pages.length; index < tasks.length; index++) {
        if (_disposed || _stopRequested) break;
        progress =
            'AI正在设计第 ${index + 1}/${tasks.length} 页 · ${tasks[index]['chapter']}';
        _notify();
        final result = await ai.design(
          options: options,
          sourceText: tasks[index]['text'] as String,
          pageNumber: index + 1,
          pageTotal: tasks.length,
          memories: memories.length > 8
              ? [memories.first, ...memories.sublist(memories.length - 7)]
              : memories,
          cast: cast,
          assets: {
            ...project.assets,
            'chapter_memory': (project.assets['story_segments'] as List? ?? [])
                .where(
                  (s) =>
                      s['chapter'] == tasks[index]['chapter'] &&
                      s['volume'] == tasks[index]['volume'],
                )
                .take(8)
                .map((s) => s['summary'])
                .join('\n'),
          },
        );
        if (_disposed || _stopRequested) break;
        final id = 'ai-${state['run']}-${index + 1}';
        final relative =
            'ai/${state['run']}/p${(index + 1).toString().padLeft(5, '0')}/page.json';
        // Existing baseline identity wins; per-scene wardrobe/action belongs in
        // the panel description and continuity memory, not an accidental rename.
        cast = _canonicalCast({
          ...Map<String, dynamic>.from(result['cast'] as Map),
          ...cast,
        }, project.assets);
        // Missed characters can be registered during storyboard design too,
        // but remain explicitly unverified until the user checks their card.
        final cards = (project.assets['characters'] as List? ?? []).cast<Map>();
        final names = {for (final card in cards) card['name']};
        final newlyFound = [
          for (final entry in cast.entries)
            if (!names.contains(entry.key))
              {
                'name': entry.key,
                'aliases': <String>[],
                'identity': '待核对',
                'appearance': '未明确',
                'outfit': '未明确',
                'personality': '未明确',
                'evidence': '',
                'evidence_verified': false,
                'visual_design': '分镜阶段发现，待核对：${entry.value}',
              },
        ];
        if (newlyFound.isNotEmpty) {
          final assets = {
            ...project.assets,
            'characters': _mergeAssetCards(cards, newlyFound),
          };
          project = project.copyWith(assets: assets);
          _write(File('${project.outputPath}/assets.json'), assets);
        }
        result['cast'] = cast;
        (result['layout'] as Map)['cast'] = cast;
        result.addAll({
          'id': id,
          'source': tasks[index],
          'page_number': index + 1,
          'ai_model': ai.profile(options).models.first,
        });
        final target = resolveComicArtifact(project.outputPath, relative);
        _write(target, result);
        _write(File('${target.parent.path}/manifest.json'), {
          'page_id': id,
          'status': 'planned',
          'layout_id': result['layout_id'],
          'visual_review': 'not_performed',
        });
        final memory = '第${index + 1}页：${result['continuity']}';
        memories = [
          ...memories,
          memory.length > 600 ? memory.substring(0, 600) : memory,
        ];
        state = {
          ...state,
          'memories': memories,
          'cast': cast,
          'status': 'running',
        };
        final ref = ComicPageRef(
          id: id,
          title: '${index + 1} · ${result['title']}',
          volume: '${tasks[index]['volume']}',
          chapter: '${tasks[index]['chapter']}',
          pageJson: relative,
        );
        project = project.copyWith(
          pages: [...project.pages, ref],
          aiState: state,
          status: 'planning',
        );
        _replaceProject(project);
        await _readPage(id);
        _save();
        _notify();
      }
      if (!_disposed) {
        final complete = project.pages.length == tasks.length;
        project = project.copyWith(
          status: complete ? 'planned' : 'paused',
          aiState: {...state, 'status': complete ? 'done' : 'paused'},
        );
        _replaceProject(project);
        _save();
        progress = complete
            ? 'AI排版完成：${project.pages.length}页。尚未生成成品图片。'
            : '已暂停，完成${project.pages.length}/${tasks.length}页。';
      }
    } on Object catch (e) {
      if (!_disposed) {
        error = _stopRequested ? null : 'AI分镜已暂停：$e';
        final now = current!;
        _replaceProject(
          now.copyWith(
            status: 'paused',
            aiState: {...now.aiState, 'status': 'paused'},
          ),
        );
        progress = '已保留${now.pages.length}页，可继续剩余页。';
        _save();
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> redesignCurrentPage(String instruction) async {
    final project = current, ref = currentPage, old = page, ai = designer;
    if (busy || project == null || ref == null || old == null || ai == null) {
      return;
    }
    if (old['layout'] == null) {
      error = '此页为旧规则分镜，请先使用AI重新规划。';
      _notify();
      return;
    }
    busy = true;
    _stopRequested = false;
    error = null;
    progress = 'AI正在重设计当前页，其他页保留。';
    _notify();
    try {
      final index = project.pages.indexOf(ref);
      final result = await ai.design(
        options: options,
        sourceText: '${old['source_text'] ?? ''}',
        pageNumber: index + 1,
        pageTotal: project.pages.length,
        memories: (project.aiState['memories'] as List? ?? [])
            .take(index)
            .cast<String>()
            .toList(),
        cast: Map<String, dynamic>.from(old['cast'] as Map? ?? {}),
        revisionInstruction: instruction,
        previous: old,
        assets: project.assets,
      );
      if (_disposed || _stopRequested) return;
      final baseline = _canonicalCast({
        ...Map<String, dynamic>.from(result['cast'] as Map),
        ...Map<String, dynamic>.from(old['cast'] as Map? ?? {}),
      }, project.assets);
      result['cast'] = baseline;
      (result['layout'] as Map)['cast'] = baseline;
      final target = resolveComicArtifact(project.outputPath, ref.pageJson);
      // Archive before replacing only this selected page.
      target.copySync(
        '${target.path}.revision-${DateTime.now().microsecondsSinceEpoch}',
      );
      result.addAll({
        'id': old['id'],
        'source': old['source'],
        'page_number': index + 1,
        'manual_revision': (old['manual_revision'] as int? ?? 0) + 1,
      });
      _write(target, result);
      page = result;
      final memories = (project.aiState['memories'] as List? ?? [])
          .cast<String>()
          .toList();
      if (index < memories.length) {
        memories[index] = '第${index + 1}页：${result['continuity']}';
      }
      _replaceProject(
        project.copyWith(
          aiState: {...project.aiState, 'memories': memories},
          warnings: ['当前页已重设计，请检查后续页的剧情与人物连续性。'],
        ),
      );
      _save();
      progress = '当前页已更新，其他页未重做。';
    } on Object catch (e) {
      if (!_disposed) error = _stopRequested ? null : '单页修改失败：$e';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<Map<String, Object?>> relaySnapshot() async {
    final project = current, ref = currentPage;
    if (project == null || ref == null || page?['layout'] == null) {
      throw const FormatException('请先完成AI排版，再启动接力。');
    }
    final snapshots = <Map<String, Object?>>[];
    for (final (index, entry) in project.pages.indexed) {
      final context = <String, Object?>{
        'workspace': project.outputPath,
        'series': 0,
        'page_number': index + 1,
      };
      final header = <String, Object?>{
        'title': entry.title,
        'page_index': index,
        'page_number': index + 1,
        'context': context,
      };
      try {
        final data = jsonDecode(
          await resolveComicArtifact(
            project.outputPath,
            entry.pageJson,
          ).readAsString(),
        ) as Map;
        final rawLayout = Map<String, dynamic>.from(data['layout'] as Map);
        rawLayout['cast'] = {
          ...Map<String, dynamic>.from(rawLayout['cast'] as Map? ?? {}),
          ..._assetCast(project.assets),
        };
        final layout = Layout.fromJson(rawLayout);
        snapshots.add({
          ...header,
          'width': layout.width,
          'height': layout.height,
          'source': layout.toJson(),
          'layout': jsonDecode(compileNovelMoss(layout)),
        });
      } on Object {
        snapshots.add({...header, 'unavailable': '此页布局无法读取，请修复后出图。'});
      }
    }
    final index = project.pages.indexOf(ref);
    final selected = snapshots[index];
    if (selected.containsKey('unavailable')) {
      throw const FormatException('当前页布局无法读取。');
    }
    return {
      ...selected,
      'series_title': project.name,
      'series_pages': snapshots,
      'relay_defaults': {
        if (options.workflowPath.isEmpty) ...{
          'steps': options.steps,
          'seed': options.seed,
          'cfg': options.cfg,
          'loras': [
            {'name': options.lora, 'strength': options.loraStrength},
          ],
        } else
          'inherit_workflow': true,
        'render_mode': 'panels',
        'workflow_path': options.workflowPath.isEmpty
            ? IntegrationSettings.current.workflow
            : options.workflowPath,
      },
    };
  }

  Map<String, dynamic> currentPromptPackage() {
    final data = page, project = current;
    if (data == null || project == null || data['layout'] is! Map) {
      throw const FormatException('请先完成AI分镜。');
    }
    final raw = Map<String, dynamic>.from(data['layout'] as Map);
    raw['cast'] = {
      ...Map<String, dynamic>.from(raw['cast'] as Map? ?? {}),
      ..._assetCast(project.assets),
    };
    return buildNovelPromptPackage(data, Layout.fromJson(raw));
  }

  Future<String> exportAllPrompts(String directory) async {
    final project = current;
    if (project == null || project.pages.isEmpty) {
      throw const FormatException('没有可导出的分镜页。');
    }
    final folder = Directory(
      '$directory/novel-prompts-${DateTime.now().microsecondsSinceEpoch}',
    );
    await folder.create(recursive: true);
    final index = StringBuffer(
      '# ${project.name}\n\n整页/逐格提示词与台词。未调用ComfyUI。\n',
    );
    for (final (i, ref) in project.pages.indexed) {
      final data = Map<String, dynamic>.from(
        jsonDecode(
          await resolveComicArtifact(
            project.outputPath,
            ref.pageJson,
          ).readAsString(),
        ) as Map,
      );
      if (data['layout'] is! Map) {
        throw FormatException('第${i + 1}页不是AI布局，未导出该页。');
      }
      final raw = Map<String, dynamic>.from(data['layout'] as Map);
      raw['cast'] = {
        ...Map<String, dynamic>.from(raw['cast'] as Map? ?? {}),
        ..._assetCast(project.assets),
      };
      final pack = buildNovelPromptPackage(data, Layout.fromJson(raw));
      final name = 'p${(i + 1).toString().padLeft(4, '0')}';
      _write(File('${folder.path}/$name.json'), pack);
      await File('${folder.path}/$name.md')
          .writeAsString(pack['markdown'] as String, encoding: utf8);
      index.writeln('- [$name · ${ref.title}]($name.md)');
    }
    await File('${folder.path}/README.md')
        .writeAsString(index.toString(), encoding: utf8);
    return folder.path;
  }
}

List<String> _sourceChunks(String text, int count) {
  final chars = text.runes.toList();
  if (chars.isEmpty) return [];
  final n = count.clamp(1, chars.length);
  final chunks = <String>[];
  var start = 0;
  for (var i = 0; i < n; i++) {
    var end = i == n - 1 ? chars.length : ((i + 1) * chars.length / n).round();
    if (i < n - 1) {
      // Prefer a nearby sentence/paragraph boundary; never drop or repeat text.
      final low = (end - 200).clamp(start + 1, chars.length - (n - i - 1));
      final high = (end + 200).clamp(low, chars.length - (n - i - 1));
      final candidates = [
        for (var j = low; j < high; j++)
          if (const [10, 0x3002, 0xff01, 0xff1f].contains(chars[j - 1])) j,
      ];
      if (candidates.isNotEmpty) {
        candidates.sort((a, b) => (a - end).abs().compareTo((b - end).abs()));
        end = candidates.first;
      }
      end = end.clamp(start + 1, chars.length - (n - i - 1));
    }
    chunks.add(String.fromCharCodes(chars.sublist(start, end)));
    start = end;
  }
  return chunks;
}
