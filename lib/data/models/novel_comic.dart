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
  }) : _python = python,
       _launcher = launcher;

  final String? _python, _launcher;
  String get python => _python ?? IntegrationSettings.current.python;
  String get launcher => _launcher ?? IntegrationSettings.current.novelLauncher;
  final String comfyUrl, style, lora;
  final double loraStrength;
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
  );

  void validate() {
    if (python.trim().isEmpty || launcher.trim().isEmpty) {
      throw const FormatException('请填写 Python 和后端入口路径。');
    }
    if (!['mono', 'color', 'sketch'].contains(style) ||
        ![4, 5, 6].contains(panelsPerPage) ||
        pagesPerChapter < 1 ||
        steps < 1 ||
        seed < 0 ||
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
  });
  final String id, name, inputPath, outputPath, status;
  final List<ComicPageRef> pages;
  final List<String> warnings;

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
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'inputPath': inputPath,
    'outputPath': outputPath,
    'status': status,
    'pages': [for (final p in pages) p.toJson()],
    'warnings': warnings,
  };
  ComicProject copyWith({
    String? name,
    String? status,
    List<ComicPageRef>? pages,
    List<String>? warnings,
  }) => ComicProject(
    id: id,
    name: name ?? this.name,
    inputPath: inputPath,
    outputPath: outputPath,
    status: status ?? this.status,
    pages: pages ?? this.pages,
    warnings: warnings ?? this.warnings,
  );
}
