part of 'local_model.dart';

// 「LLM 反推」:用「API 管理」里启用的模型看图写提示词,可以同时选两个,结果并排比较。

/// LLM 反推选的一个模型:哪个接口([llm] 是它的 id)的哪个模型。
typedef LlmPick = ({String llm, String model});

/// 一个模型的反推结果:说的话、出错时给用户看的原因、是不是还在等。
typedef LlmResult = ({String text, String? error, bool busy});

/// 最多同时用几个模型反推。
const maxLlmPicks = 2;

const _llmReversePrompt =
    '你是图像反推助手。看这张图,写出能让文生图模型画出同样画面的英文正面提示词:'
    '主体、场景、构图、光影、色彩、画风与媒介都要写到。'
    '只输出提示词本身,不要解释,不要负面词,不要任何标签或分段标注。'
    '写法(句子还是标签、偏什么风格)照下面用户当前 Preset 的要求来;它没有要求时写成一段英文。';

/// 发给模型的话:反推要求 + 用户当前 Preset 的系统提示。图片挂在下标 1 那条上。
List<Map<String, String>> llmReverseMessages(String presetPrompt) => [
  {
    'role': 'system',
    'content': '$_llmReversePrompt\n\n【用户当前的 Preset】\n$presetPrompt',
  },
  {'role': 'user', 'content': '反推这张图'},
];

extension LocalLlm on LocalModel {
  LlmResult? llmResultOf(LlmPick pick) => _llmResults[pick];

  bool get llmBusy => _llmResults.values.any((r) => r.busy);

  /// 勾上或去掉一个模型;已经选满时挤掉最早选的那个。
  void toggleLlm(LlmPick pick) {
    final next = llmPicks.contains(pick)
        ? llmPicks.where((p) => p != pick).toList()
        : [...llmPicks, pick];
    update(
      () => llmPicks = List.unmodifiable(
        next.skip(next.length > maxLlmPicks ? next.length - maxLlmPicks : 0),
      ),
    );
  }

  /// 用 [picks] 里的几个模型同时反推当前这张图,各自的结果分开放。
  /// [ask] 问一个模型、返回它说的话(失败抛 [LlmException])。
  /// 没法开始时返回给用户看的原因;各模型自己的错误记在它的结果里。
  Future<String?> runLlm(
    List<LlmPick> picks,
    Future<String> Function(LlmPick pick, Attachment image) ask,
  ) async {
    final image = _image;
    if (image == null) return tr('先放一张图');
    if (picks.isEmpty) return tr('先选模型');
    if (llmBusy) return tr('正在反推');
    final round = _llmRound;
    _llmResults = Map.unmodifiable({
      for (final p in picks) p: (text: '', error: null, busy: true),
    });
    _changed();
    await Future.wait([for (final p in picks) _askOne(p, image, round, ask)]);
    return null;
  }

  Future<void> _askOne(
    LlmPick pick,
    Attachment image,
    int round,
    Future<String> Function(LlmPick pick, Attachment image) ask,
  ) async {
    var text = '';
    String? error;
    try {
      text = (await ask(pick, image)).trim();
      if (text.isEmpty) error = tr('模型没有返回内容');
    } on LlmException catch (e) {
      error = e.message;
    } on Object catch (e) {
      // 只报类型,原文可能带着 Key。
      error = tr('反推失败({0})', [e.runtimeType]);
    }
    // 等结果的时候图换了:这次的结果不要了。
    if (round != _llmRound) return;
    _llmResults = Map.unmodifiable({
      ..._llmResults,
      pick: (text: text, error: error, busy: false),
    });
    _changed();
  }
}
