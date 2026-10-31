/// Agent 要程序替它做的一件本地反推的事:
/// `<reverse-image kind="tag|nl">模型名</reverse-image>` 用本机的模型反推用户的图(模型名可空,空的用当前选中的);
/// `<download-model kind="tag|nl|runtime">模型名</download-model>` 下载一个模型(runtime 是 llama.cpp 运行时,不用写名字)。
typedef LocalToolCall = ({String action, String kind, String model});

/// [LocalToolCall.action] 的两种。
const toolReverse = 'reverse-image', toolDownload = 'download-model';

final _block = RegExp(
  r'<(reverse-image|download-model)\s+kind\s*=\s*"(tag|nl|runtime)"\s*>'
  r'([\s\S]*?)</\1>',
);
const _opens = ['<reverse-image', '<download-model'];

/// 把回复里这两种标签拆出来,按出现的先后。[prose] 是去掉它们之后给人看的话
/// (还没写完的那一个先不显示)。反推不认 runtime。
({String prose, List<LocalToolCall> calls}) splitLocalTools(String reply) {
  final calls = [
    for (final m in _block.allMatches(reply))
      if (m[1] == toolDownload || m[2] != 'runtime')
        (action: m[1]!, kind: m[2]!, model: m[3]!.trim()),
  ];
  var prose = reply.replaceAll(_block, '');
  for (final open in _opens) {
    final half = prose.indexOf(open);
    if (half >= 0) prose = prose.substring(0, half);
  }
  // 开始标签只到了一半(流式生成中)。
  for (var n = _opens.last.length - 1; n > 1; n--) {
    if (_opens.any((o) => n <= o.length && prose.endsWith(o.substring(0, n)))) {
      prose = prose.substring(0, prose.length - n);
      break;
    }
  }
  return (prose: prose.trim(), calls: calls);
}
