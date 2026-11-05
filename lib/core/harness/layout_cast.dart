part of 'layout.dart';

// 本系列角色卡(用户反馈:三页漫画里十四行诗被画成了维尔汀的银发)。Agent 每格自己
// 描述角色时常漏掉发色瞳色、一格塞两三个人,出图模型只好猜,特征就串到别人身上。
// 所以角色卡由程序记在系列上,交出去时原样接在每个人物块的描述前面。

/// 人物块名字里的角色卡名:「凛·2」是「凛」;没有「·」的就是整个名字。
String castKeyOf(String name) => name.split(RegExp('[·・•]')).first.trim();

/// [b] 对上的角色卡;不是人物块、或没对上返回 null。
String? castCardFor(Layout l, LayoutBox b) =>
    b.label == 'character' ? l.cast[castKeyOf(b.name)] : null;

/// 有角色卡时,对不上任何一张的人物块(多半是一块装了几个人)。
List<LayoutBox> castMisses(Layout l) => [
  if (l.cast.isNotEmpty)
    for (final b in l.boxes)
      if (b.label == 'character' && !b.offscreen && castCardFor(l, b) == null)
        b,
];

/// 读 summary.cast:{名字: 英文角色卡},空的不要。
Map<String, String> parseCast(Object? v) => Map.unmodifiable({
  if (v is Map)
    for (final MapEntry(:key, :value) in v.entries)
      if (key is String &&
          value is String &&
          key.trim().isNotEmpty &&
          value.trim().isNotEmpty)
        key.trim(): value.trim(),
});

/// 属性栏里一行一个:「名字: 角色卡」。
String castText(Map<String, String> cast) =>
    cast.entries.map((e) => '${e.key}: ${e.value}').join('\n');

/// [castText] 反过来;冒号全角半角都认,没写冒号或冒号后面是空的那行不要。
Map<String, String> parseCastText(String text) => parseCast({
  for (final line in text.split('\n'))
    if (RegExp('^([^::]+)[::](.*)\$').firstMatch(line) case final m?)
      m[1]!: m[2]!,
});

String _sentence(String s) =>
    s.isEmpty || RegExp(r'[.!?。!?]$').hasMatch(s) ? s : '$s.';

/// 交出去的人物块描述:角色卡在前;导入过交出去的 JSON 时已经带着,不再加。
String _castCaption(Layout l, LayoutBox b) {
  final caption = b.caption.trim();
  final card = castCardFor(l, b);
  if (card == null || caption.contains(card)) return caption;
  return [_sentence(card), caption].where((s) => s.isNotEmpty).join(' ');
}

/// 交出去的整体描述末尾那句:这页出现的角色各一张卡,按出场先后。
String _castLine(Layout l) {
  final cards = <String>{
    for (final b in l.boxes)
      if (!b.offscreen) ?castCardFor(l, b),
  };
  if (cards.isEmpty) return '';
  final strip = RegExp(r'[.。]+$');
  return 'Characters: ${cards.map((c) => c.replaceAll(strip, '')).join('; ')}.';
}
