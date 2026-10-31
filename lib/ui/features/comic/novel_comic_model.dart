import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../../data/models/novel_comic.dart';
import '../../../core/harness/comic/novel_comic_backend.dart';

/// 与既有提示词/布局存档分开；导入、分镜、选页和逐格编辑的状态。
class NovelComicModel extends ChangeNotifier {
  NovelComicModel({required this.dir, NovelComicBackend? backend})
    : backend = backend ?? const PythonComicBackend();

  final Directory dir;
  final NovelComicBackend backend;
  List<ComicProject> _projects = [];
  List<ComicProject> get projects => List.unmodifiable(_projects);
  ComicOptions options = const ComicOptions();
  String? _projectId, _pageId;
  Map<String,dynamic>? page;
  bool busy = false;
  String? error;
  bool _disposed = false;
  int _selection = 0;

  File get file => File('${dir.path}/workspace.json');
  ComicProject? get current => _projects.where((p)=>p.id==_projectId).firstOrNull;
  ComicPageRef? get currentPage => current?.pages.where((p)=>p.id==_pageId).firstOrNull;

  void _notify() { if (!_disposed) notifyListeners(); }

  void _write(File target, Object data) {
    target.parent.createSync(recursive:true);
    final temp=File('${target.path}.tmp');
    temp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data), encoding:utf8, flush:true);
    temp.renameSync(target.path);
  }

  void _save() {
    _write(file, {'version':1, 'options':options.toJson(), 'selectedProject':_projectId,
      'selectedPage':_pageId, 'projects':[for(final p in _projects)p.toJson()]});
  }

  Future<void> load() async {
    if (!file.existsSync()) return;
    try {
      final json=Map<String,dynamic>.from(jsonDecode(await file.readAsString()) as Map);
      options=ComicOptions.fromJson(Map<String,dynamic>.from(json['options'] as Map? ?? {}));
      _projects=[for(final p in (json['projects'] as List? ?? []))
        ComicProject.fromJson(Map<String,dynamic>.from(p as Map))];
      _projectId=json['selectedProject'] as String? ?? _projects.firstOrNull?.id;
      if (current==null) _projectId=_projects.firstOrNull?.id;
      await _readPage(json['selectedPage'] as String? ?? current?.pages.firstOrNull?.id);
    } on Object catch(e) {
      error='小说漫画工作区读取失败：$e';
      // Preserve the original file before a later import could save new state.
      try { file.renameSync('${file.path}.bad-${DateTime.now().millisecondsSinceEpoch}'); }
      on FileSystemException { /* Keep original if a backup cannot be created. */ }
    }
    _notify();
  }

  Future<void> importNovel(String input) async {
    if (busy) return;
    final source=File(input).absolute;
    if (!source.existsSync() || !RegExp(r'\.(txt|epub)$',caseSensitive:false).hasMatch(source.path)) {
      throw const FormatException('请选择已有的 TXT 或 EPUB 小说。');
    }
    final existing=_projects.where((p)=>p.inputPath==source.path).firstOrNull;
    if (existing!=null) { await selectProject(existing.id); return; }
    final id='novel-${DateTime.now().microsecondsSinceEpoch}';
    final name=source.uri.pathSegments.last.replaceFirst(RegExp(r'\.[^.]+$'),'');
    _projects=[..._projects,ComicProject(id:id,name:name,inputPath:source.path,
      outputPath:Directory('${dir.path}/projects/$id').absolute.path)];
    _projectId=id;
    _pageId=null;
    page=null;
    error=null;
    _save();
    _notify();
  }

  Future<void> selectProject(String id) async {
    if (busy) return;
    _projectId=id;
    await _readPage(current?.pages.firstOrNull?.id);
    _save();
    _notify();
  }

  Future<void> selectPage(String id) async {
    await _readPage(id);
    _save();
    _notify();
  }

  Future<void> _readPage(String? id) async {
    final token=++_selection;
    _pageId=id;
    page=null;
    final project=current;
    final ref=currentPage;
    if (project==null || ref==null) return;
    try {
      final data=jsonDecode(await resolveComicArtifact(project.outputPath,ref.pageJson).readAsString());
      if (token==_selection) page=Map<String,dynamic>.from(data as Map);
    } on Object catch(e) { if(token==_selection) error='页面读取失败：$e'; }
  }

  Future<void> planCurrent() async {
    final project=current;
    if (busy || project==null) return;
    busy=true;
    error=null;
    _notify();
    try {
      final result=await backend.plan(input:project.inputPath,output:project.outputPath,options:options);
      final next=project.copyWith(name:result['book'] as String, status:'planned',
        pages:[for(final p in result['pages'] as List)
          ComicPageRef.fromJson(Map<String,dynamic>.from(p as Map))],
        warnings:(result['warnings'] as List? ?? []).cast<String>());
      _projects=[for(final p in _projects) p.id==next.id ? next : p];
      await _readPage(next.pages.firstOrNull?.id);
      _save();
    } on Object catch(e) { error='分镜生成失败：$e'; }
    finally { busy=false; _notify(); }
  }

  void setOptions(ComicOptions next) {
    next.validate();
    options=next;
    _save();
    _notify();
  }

  /// 保存用户自己的分镜改稿，不触发重新规划或 GPU 任务。
  void editItem(String id,String field,Object value) {
    final draft=page;
    final project=current;
    final ref=currentPage;
    if (draft==null || project==null || ref==null || busy) return;
    if (!{'desc','camera','text','kind','note'}.contains(field)) {
      throw const FormatException('不支持编辑该分镜字段。');
    }
    final copy=Map<String,dynamic>.from(jsonDecode(jsonEncode(draft)) as Map);
    final items=(copy['items'] as List).cast<Map<String,dynamic>>();
    final item=items.where((i)=>i['id']==id).firstOrNull;
    if(item==null) return;
    item[field]=value;
    if(field=='desc' && item['type']=='panel') {
      item['prompt']='${item['desc']} No lettering, no captions, no speech bubbles, no text.';
    }
    if(field=='desc') {
      final oldScene=copy['scene'] as String? ?? '';
      final prefix=oldScene.split('<|layout|>').first;
      copy['scene']='$prefix<|layout|>LAYOUT AND STORY: '
        '${items.where((i)=>i['type']=='panel').map((i)=>i['desc']).join(' ')}<|/layout|>';
    }
    copy['manual_revision']=(copy['manual_revision'] as int? ?? 0)+1;
    try {
      _write(resolveComicArtifact(project.outputPath,ref.pageJson),copy);
      page=copy;
      final record=File('${resolveComicArtifact(project.outputPath,ref.pageJson).parent.path}/manifest.json');
      if(record.existsSync()) {
        final manifest=Map<String,dynamic>.from(jsonDecode(record.readAsStringSync()) as Map);
        manifest['manual_revision']=copy['manual_revision'];
        for(final raw in manifest['panels'] as List? ?? []) {
          final panel=items.where((i)=>i['id']==raw['id']).firstOrNull;
          if(panel!=null) raw['prompt']=panel['prompt'];
        }
        _write(record,manifest);
      }
      error=null;
    } on Object catch(e) { error='分镜没有保存成功：$e'; }
    _notify();
  }

  @override
  void dispose() { _disposed=true; super.dispose(); }
}
