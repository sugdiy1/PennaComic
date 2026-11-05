part of 'novel_comic_model.dart';

extension NovelComicAssets on NovelComicModel {
  Future<void> prepareAssetsCurrent() async {
    final project = current, ai = designer;
    if (busy || project == null || ai == null) return;
    busy = true;
    error = null;
    _stopRequested = false;
    progress = '正在读取小说，准备文字资产…';
    _notify();
    try {
      options.validate();
      ai.profile(options);
      final hash = sha256
          .convert(await File(project.inputPath).readAsBytes())
          .toString();
      final book = await readBook(project.inputPath, options);
      if (_disposed || _stopRequested) return;
      await _prepareBookAssets(project, book, hash);
      if (!_disposed && !_stopRequested) progress = '文字资产准备完成，可检查角色卡后开始AI排版。';
    } on Object catch (e) {
      if (!_disposed && !_stopRequested) error = '资产准备已暂停：$e';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<ComicProject> _prepareBookAssets(
    ComicProject project,
    Map<String, dynamic> book,
    String hash,
  ) async {
    if (project.assets['signature'] == hash &&
        project.assets['status'] == 'done') {
      return project;
    }
    final chunks = <Map<String, dynamic>>[];
    for (final raw in book['chapters'] as List) {
      final chapter = raw as Map;
      final text = chapter['text'] as String;
      final count = (text.runes.length / 12000).ceil().clamp(1, 100000);
      for (final part in _sourceChunks(text, count)) {
        chunks.add({
          'text': part,
          'chapter': chapter['title'],
          'volume': chapter['volume'],
        });
      }
    }
    if (chunks.isEmpty) throw const FormatException('小说没有可用于准备资产的正文。');
    var assets = project.assets['signature'] == hash
        ? Map<String, dynamic>.from(project.assets)
        : <String, dynamic>{
            'signature': hash,
            'characters': [],
            'locations': [],
            'props': [],
            'completed_chunks': 0,
          };
    final start = (assets['completed_chunks'] as int? ?? 0).clamp(
      0,
      chunks.length,
    );
    for (var index = start; index < chunks.length; index++) {
      if (_disposed || _stopRequested) break;
      progress =
          '前期文字资产 ${index + 1}/${chunks.length} · ${chunks[index]['chapter']}';
      _notify();
      final extracted = await designer!.prepareAssets(
        options: options,
        sourceText: chunks[index]['text'] as String,
        knownNames: [
          for (final card in assets['characters'] as List? ?? [])
            '${card['name']}',
        ],
      );
      if (_disposed || _stopRequested) break;
      for (final kind in ['characters', 'locations', 'props']) {
        final incoming = [
          for (final raw in extracted[kind] as List)
            {
              ...Map<String, dynamic>.from(raw as Map),
              'source': {
                'chapter': chunks[index]['chapter'],
                'volume': chunks[index]['volume'],
              },
            },
        ];
        assets[kind] = _mergeAssetCards(
          (assets[kind] as List? ?? []).cast<Map>(),
          incoming,
        );
      }
      assets = {
        ...assets,
        'signature': hash,
        'completed_chunks': index + 1,
        'total_chunks': chunks.length,
        'status': index + 1 == chunks.length ? 'done' : 'preparing',
        'visual_notes': extracted['visual_notes'],
        'story_segments': [
          ...assets['story_segments'] as List? ?? [],
          {
            'chapter': chunks[index]['chapter'],
            'volume': chunks[index]['volume'],
            'summary': '${extracted['story_summary'] ?? ''}'.substring(
              0,
              '${extracted['story_summary'] ?? ''}'.length.clamp(0, 1000),
            ),
          },
        ],
      };
      project = project.copyWith(name: '${book['book']}', assets: assets);
      _replaceProject(project);
      _write(File('${project.outputPath}/assets.json'), assets);
      _save();
      _notify();
    }
    return project;
  }

  void editAsset(String kind, String name, String field, String value) {
    final project = current;
    if (project == null ||
        busy ||
        !['characters', 'locations', 'props'].contains(kind)) {
      return;
    }
    if (![
          'identity',
          'appearance',
          'outfit',
          'personality',
          'visual_design',
          'description',
        ].contains(field) ||
        value.length > 1600) {
      throw const FormatException('资产字段或长度不正确。');
    }
    final assets = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(project.assets)) as Map,
    );
    final cards = assets[kind] as List? ?? [];
    final card = cards.where((c) => c['name'] == name).firstOrNull;
    if (card == null) return;
    card[field] = value;
    card['manual_locked'] = true;
    final next = project.copyWith(assets: assets);
    try {
      _write(File('${project.outputPath}/assets.json'), assets);
      _replaceProject(next);
      _save();
      error = null;
      if (page?['layout'] is Map) {
        (page!['layout'] as Map)['cast'] = {
          ...Map<String, dynamic>.from(
            (page!['layout'] as Map)['cast'] as Map? ?? {},
          ),
          ..._assetCast(assets),
        };
      }
    } on Object catch (e) {
      error = '资产卡保存失败：$e';
    }
    _notify();
  }
}

List<Map<String, dynamic>> _mergeAssetCards(
  List<Map> existing,
  List<Map<String, dynamic>> incoming,
) {
  final result = [for (final card in existing) Map<String, dynamic>.from(card)];
  for (final next in incoming) {
    final names = {
      '${next['name']}',
      ...(next['aliases'] as List? ?? []).cast<String>(),
    };
    final old = result
        .where(
          (c) =>
              names.contains(c['name']) ||
              (c['aliases'] as List? ?? []).any(names.contains),
        )
        .firstOrNull;
    if (old == null) {
      result.add(Map<String, dynamic>.from(next));
      continue;
    }
    old['aliases'] = {
      ...(old['aliases'] as List? ?? []).cast<String>(),
      ...(next['aliases'] as List? ?? []).cast<String>(),
      if (old['name'] != next['name']) '${next['name']}',
    }.toList();
    if (old['manual_locked'] == true) continue;
    for (final entry in next.entries) {
      if (['name', 'aliases'].contains(entry.key)) continue;
      if (old[entry.key] == null ||
          old[entry.key] == '' ||
          old[entry.key] == '未明确' ||
          old[entry.key] == '未说明') {
        old[entry.key] = entry.value;
      }
    }
  }
  return result;
}

Map<String, dynamic> _assetCast(Map<String, dynamic> assets) => {
  for (final card in assets['characters'] as List? ?? [])
    '${card['name']}':
        '原文身份：${card['identity'] ?? '待核对'}；原文外貌：${card['appearance'] ?? '未明确'}；基础服装：${card['outfit'] ?? '未明确'}；'
        '别名：${(card['aliases'] as List? ?? []).join('、')}；视觉补设（非原文事实）：${card['visual_design'] ?? '未设定'}',
};

Map<String, dynamic> _canonicalCast(
  Map<String, dynamic> values,
  Map<String, dynamic> assets,
) {
  final baseline = _assetCast(assets);
  final cards = assets['characters'] as List? ?? [];
  final result = <String, dynamic>{};
  for (final entry in values.entries) {
    final card = cards
        .where(
          (c) =>
              c['name'] == entry.key ||
              (c['aliases'] as List? ?? []).contains(entry.key),
        )
        .firstOrNull;
    final name = card == null ? entry.key : '${card['name']}';
    result[name] = baseline[name] ?? entry.value;
  }
  return {...result, ...baseline};
}
