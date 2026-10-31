part of 'layout_board.dart';

/// Agent 这次只该改哪一样:「交给 Agent」时只收描述(和程序猜的体块),
/// 其余(框、形状、图层、名字)由程序守住——模型常顺手把框也重排了。
enum LayoutKeep { none, describe }

/// 「交给 Agent」那句话的开头,[layoutKeepFor] 认它。
String get _handOverHead => tr('照画板现在的样子写好整体描述和每一块的描述');

/// 「交给 Agent」发出去的话(用户要求:设定好形状、视角、灯光、体块之后统一交给 Agent
/// 写成提示词,只留这一个按钮)。按画板现在有什么,点名要它照哪几样写;回复走
/// [LayoutKeep.describe]。
String handOverRequest(LayoutBoard board) {
  final l = board.layout;
  return [
    _handOverHead,
    if (l.boxes.any((b) => b.shape != null && !b.offscreen))
      tr('形状照【形状】写成轮廓和占的位置'),
    if (board.threeD && board.cameraMoved) tr('照现在的视角写朝向、露出哪一面和谁挡着谁'),
    if (l.lighting.enabled) tr('受光面、阴影和投影方向照【灯光】'),
    if (board.threeD && board.guessedBodies) tr('程序猜的体块顺便估好(body)'),
    tr('框、形状和图层都不动'),
  ].join(tr(';'));
}

/// 用户发的这句话要 Agent 只改哪一样。
LayoutKeep layoutKeepFor(String request) =>
    request.startsWith(_handOverHead) ? LayoutKeep.describe : LayoutKeep.none;

/// 用户画了框还没写描述:那是他定好的构图(比如手画的漫画格),点名要 Agent 原样留着。
/// Gemini 曾把用户画的六个斜边格换成五条一样高的横条。
String _drawnNote(Layout l) {
  final blank = [
    for (final (i, b) in l.boxes.indexed)
      if (!b.offscreen && b.caption.trim().isEmpty) '${i + 1}',
  ];
  if (blank.isEmpty) return '';
  return '【画好的框】第 ${blank.join('、')} 块是用户画好、还没写描述的框:'
      '位置、大小、形状都是他定好的构图。照原样保留它们的 bbox 和 shape'
      '(一个数都不改,不删、不合并、不拆),按用户这次的话给它们写描述;'
      '要往里放人物、气泡这些东西,就放进对应的框里面。'
      '用户说的数量(几格、几个人)和画好的框数对不上时,先用 <options> 问一句,不要自己重排。'
      '漫画页照「漫画分格」里"用户画好了格"那一条做。';
}

/// 有角色卡时,对不上任何一张的人物块:点名要 Agent 拆成一人一块、名字用角色卡的。
String _castNote(Layout l) {
  final misses = castMisses(l);
  if (misses.isEmpty) return '';
  return '【角色卡没对上】${misses.map((b) => '「${b.name.isEmpty ? '(没起名)' : b.name}」').join('、')}'
      '是人物块,名字却对不上【本系列角色卡】里的任何一个,程序没法给它接上角色卡,出图时特征会乱。'
      '一个人物块只放一个角色,name 写成「角色卡名字·格号」;几个人同在一格就各画一块。'
      '路人这类不进角色卡的,label 改成 object。';
}
