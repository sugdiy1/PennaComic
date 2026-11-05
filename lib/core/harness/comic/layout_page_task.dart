/// Persistent multi-page work, independent of any model's chat window.
int? _pageNumber(String text) {
  final direct = int.tryParse(text);
  if (direct != null) return direct;
  const digits = {
    '零': 0,
    '〇': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  if (text == '一百' || text == '百') return 100;
  if (text.contains('十')) {
    final parts = text.split('十');
    if (parts.length != 2) return null;
    return (parts[0].isEmpty ? 1 : digits[parts[0]] ?? 0) * 10 +
        (parts[1].isEmpty ? 0 : digits[parts[1]] ?? 0);
  }
  return digits[text];
}

int? requestedLayoutRangeStart(String text) {
  final m = RegExp(
    r'第\s*([\d一二两三四五六七八九十百]+)\s*(?:页)?\s*(?:到|至|[-—~～])\s*(?:第)?\s*([\d一二两三四五六七八九十百]+)\s*页',
  ).firstMatch(text);
  return m == null ? null : _pageNumber(m[1]!);
}

int? requestedLayoutPageCount(String text) {
  if (RegExp(r'只解释|只回答|不生成|不要生成|不画|不要画').hasMatch(text)) return null;
  if (!RegExp(
    r'画|绘|做|生成|创作|排|分镜|漫画|comic|pages?',
    caseSensitive: false,
  ).hasMatch(text)) {
    return null;
  }
  final range = RegExp(
    r'第\s*([\d一二两三四五六七八九十百]+)\s*(?:页)?\s*(?:到|至|[-—~～])\s*(?:第)?\s*([\d一二两三四五六七八九十百]+)\s*页',
  ).firstMatch(text);
  int? count;
  if (range != null) {
    final a = _pageNumber(range[1]!), b = _pageNumber(range[2]!);
    if (a != null && b != null) count = b - a + 1;
  } else {
    final m = RegExp(r'(?:共|共计|总共|一共|连续)?\s*([\d一二两三四五六七八九十百]+)\s*页')
        .allMatches(text)
        .where(
          (m) =>
              m.start == 0 ||
              !RegExp(r'第\s*$').hasMatch(text.substring(0, m.start)),
        )
        .firstOrNull;
    if (m != null) count = _pageNumber(m[1]!);
  }
  return count != null && count >= 2 && count <= 100 ? count : null;
}

class LayoutPageTask {
  LayoutPageTask({
    required this.instruction,
    required this.total,
    required this.series,
    required this.firstTarget,
    String? sourceText,
    this.rangeStart,
    this.completed = 0,
    List<String>? summaries,
  }) : summaries = summaries ?? [],
       sourceText = sourceText ?? instruction;
  final String instruction, firstTarget, sourceText;
  final int total;
  final int? rangeStart;
  int series, completed;
  bool active = true;
  String? error;
  final List<String> summaries;
  bool get complete => completed >= total;
  Map<String, Object?> toJson() => {
    'instruction': instruction,
    'sourceText': sourceText,
    'total': total,
    'series': series,
    'firstTarget': firstTarget,
    'rangeStart': rangeStart,
    'completed': completed,
    'summaries': summaries,
    'error': error,
  };
  static LayoutPageTask? restore(Object? value) {
    if (value is! Map) return null;
    try {
      final n = value['total'] as int, done = value['completed'] as int;
      if (n < 2 ||
          n > 100 ||
          done < 0 ||
          done > n ||
          value['instruction'] is! String ||
          (value['instruction'] as String).isEmpty) {
        return null;
      }
      return LayoutPageTask(
          instruction: value['instruction'] as String,
          sourceText: value['sourceText'] as String?,
          total: n,
          series: value['series'] as int,
          firstTarget: value['firstTarget'] as String,
          rangeStart: value['rangeStart'] as int?,
          completed: done,
          summaries: List<String>.from(value['summaries'] as List? ?? []),
        )
        ..active = false
        ..error = value['error'] as String?;
    } on Object {
      return null;
    }
  }
}
