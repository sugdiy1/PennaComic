// ignore_for_file: prefer_initializing_formals
import '../../core/integration_settings.dart';

/// 小说漫画工作区独立配置；生成参数先保存，框架阶段不执行生图。
class ComicOptions {
  const ComicOptions({
    String? python,
    String? launcher,
    this.comfyUrl = 'http://127.0.0.1:8188',
    this.style = 'mono',
    this.lora = 'moss_Lineart.safetensors',
    this.loraStrength = .85,
    this.pagesPerChapter = 4,
    this.panelsPerPage = 4,
    this.steps = 50,
    this.seed = 20261029,
    this.cfg = 3,
    this.planner = 'ai',
    this.llmId = '',
    this.creativeBrief = '按剧情设计分镜、留白和人物表演；每页可选择不同布局，不强制固定格数。',
    this.deliveryMode = 'copy',
    this.workflowPath = '',
  }) : _python = python,
       _launcher = launcher;

  final String? _python, _launcher;
  String get python => _python ?? IntegrationSettings.current.python;
  String get launcher => _launcher ?? IntegrationSettings.current.novelLauncher;
  final String comfyUrl, style, lora;
  final String planner, llmId, creativeBrief;
  final String deliveryMode, workflowPath;
  final double loraStrength;
  final double cfg;
  final int pagesPerChapter, panelsPerPage, steps, seed;

  Map<String, dynamic> toJson() => {
    'python': python,
    'launcher': launcher,
    'comfyUrl': comfyUrl,
    'style': style,
    'lora': lora,
    'loraStrength': loraStrength,
    'pagesPerChapter': pagesPerChapter,
    'panelsPerPage': panelsPerPage,
    'steps': steps,
    'seed': seed,
    'cfg': cfg,
    'planner': planner,
    'llmId': llmId,
    'creativeBrief': creativeBrief,
    'deliveryMode': deliveryMode,
    'workflowPath': workflowPath,
  };

  factory ComicOptions.fromJson(Map<String, dynamic> json) {
    const defaults = ComicOptions();
    return ComicOptions(
      python: json['python'] as String? ?? defaults.python,
      launcher: json['launcher'] as String? ?? defaults.launcher,
      comfyUrl: json['comfyUrl'] as String? ?? defaults.comfyUrl,
      style: json['style'] as String? ?? defaults.style,
      lora: json['lora'] as String? ?? defaults.lora,
      loraStrength:
          (json['loraStrength'] as num?)?.toDouble() ?? defaults.loraStrength,
      pagesPerChapter:
          json['pagesPerChapter'] as int? ?? defaults.pagesPerChapter,
      panelsPerPage: json['panelsPerPage'] as int? ?? defaults.panelsPerPage,
      steps: json['steps'] as int? ?? defaults.steps,
      seed: json['seed'] as int? ?? defaults.seed,
      cfg: (json['cfg'] as num?)?.toDouble() ?? defaults.cfg,
      planner: json['planner'] as String? ?? defaults.planner,
      llmId: json['llmId'] as String? ?? defaults.llmId,
      creativeBrief: json['creativeBrief'] as String? ?? defaults.creativeBrief,
      deliveryMode: json['deliveryMode'] as String? ?? defaults.deliveryMode,
      workflowPath: json['workflowPath'] as String? ?? defaults.workflowPath,
    );
  }

  ComicOptions copyWith({
    String? python,
    String? launcher,
    String? comfyUrl,
    String? style,
    String? lora,
    double? loraStrength,
    int? pagesPerChapter,
    int? panelsPerPage,
    int? steps,
    int? seed,
    double? cfg,
    String? planner,
    String? llmId,
    String? creativeBrief,
    String? deliveryMode,
    String? workflowPath,
  }) => ComicOptions(
    python: python ?? this.python,
    launcher: launcher ?? this.launcher,
    comfyUrl: comfyUrl ?? this.comfyUrl,
    style: style ?? this.style,
    lora: lora ?? this.lora,
    loraStrength: loraStrength ?? this.loraStrength,
    pagesPerChapter: pagesPerChapter ?? this.pagesPerChapter,
    panelsPerPage: panelsPerPage ?? this.panelsPerPage,
    steps: steps ?? this.steps,
    seed: seed ?? this.seed,
    cfg: cfg ?? this.cfg,
    planner: planner ?? this.planner,
    llmId: llmId ?? this.llmId,
    creativeBrief: creativeBrief ?? this.creativeBrief,
    deliveryMode: deliveryMode ?? this.deliveryMode,
    workflowPath: workflowPath ?? this.workflowPath,
  );

  void validate() {
    if (python.trim().isEmpty || launcher.trim().isEmpty) {
      throw const FormatException('请填写 Python 和后端入口路径。');
    }
    if (!['copy', 'workflow'].contains(deliveryMode) ||
        workflowPath.length > 4096 ||
        !['ai', 'rules'].contains(planner) ||
        creativeBrief.length > 12000 ||
        !['mono', 'color', 'sketch'].contains(style) ||
        ![4, 5, 6].contains(panelsPerPage) ||
        pagesPerChapter < 1 ||
        steps < 1 ||
        seed < 0 ||
        !cfg.isFinite ||
        cfg < 0 ||
        cfg > 20 ||
        !loraStrength.isFinite ||
        loraStrength < 0 ||
        loraStrength > 2) {
      throw const FormatException('请检查画风、格数、页数、步数、种子和 LoRA 强度。');
    }
    final uri = Uri.tryParse(comfyUrl);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('ComfyUI 地址需要完整的 http:// 或 https:// URL。');
    }
  }
}

class ComicPageRef {
  const ComicPageRef({
    required this.id,
    required this.title,
    required this.volume,
    required this.chapter,
    required this.pageJson,
    this.status = 'planned',
  });
  final String id, title, volume, chapter, pageJson, status;

  factory ComicPageRef.fromJson(Map<String, dynamic> json) => ComicPageRef(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    volume: json['volume'] as String? ?? '',
    chapter: json['chapter'] as String? ?? '',
    pageJson: json['page_json'] as String,
    status: json['status'] as String? ?? 'planned',
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'volume': volume,
    'chapter': chapter,
    'page_json': pageJson,
    'status': status,
  };
}

class ComicProject {
  const ComicProject({
    required this.id,
    required this.name,
    required this.inputPath,
    required this.outputPath,
    this.status = 'imported',
    this.pages = const [],
    this.warnings = const [],
    this.aiState = const {},
    this.assets = const {},
  });
  final String id, name, inputPath, outputPath, status;
  final List<ComicPageRef> pages;
  final List<String> warnings;
  final Map<String, dynamic> aiState;
  final Map<String, dynamic> assets;

  factory ComicProject.fromJson(Map<String, dynamic> json) => ComicProject(
    id: json['id'] as String,
    name: json['name'] as String,
    inputPath: json['inputPath'] as String,
    outputPath: json['outputPath'] as String,
    status: json['status'] as String? ?? 'imported',
    pages: [
      for (final p in (json['pages'] as List? ?? const []))
        ComicPageRef.fromJson(Map<String, dynamic>.from(p as Map)),
    ],
    warnings: (json['warnings'] as List? ?? const []).cast<String>(),
    aiState: Map<String, dynamic>.from(json['aiState'] as Map? ?? {}),
    assets: Map<String, dynamic>.from(json['assets'] as Map? ?? {}),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'inputPath': inputPath,
    'outputPath': outputPath,
    'status': status,
    'pages': [for (final p in pages) p.toJson()],
    'warnings': warnings,
    'aiState': aiState,
    'assets': assets,
  };
  ComicProject copyWith({
    String? name,
    String? status,
    List<ComicPageRef>? pages,
    List<String>? warnings,
    Map<String, dynamic>? aiState,
    Map<String, dynamic>? assets,
  }) => ComicProject(
    id: id,
    name: name ?? this.name,
    inputPath: inputPath,
    outputPath: outputPath,
    status: status ?? this.status,
    pages: pages ?? this.pages,
    warnings: warnings ?? this.warnings,
    aiState: aiState ?? this.aiState,
    assets: assets ?? this.assets,
  );
}
