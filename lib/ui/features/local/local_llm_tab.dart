part of 'local_page.dart';

// 「LLM 反推」:从「API 管理」里启用的模型中挑一到两个,同时看图写提示词,结果并排显示。
// 写法跟着当前 Preset 走。

class _LlmTab extends StatelessWidget {
  const _LlmTab({
    required this.model,
    required this.config,
    required this.vm,
    required this.onToDraft,
    required this.onSend,
  });

  final LocalModel model;
  final ConfigService config;
  final StudioViewModel vm;
  final ValueChanged<String> onToDraft;
  final ValueChanged<String> onSend;

  /// 启用的接口,和它们各自的模型。
  List<LlmProfile> get _llms => [
    for (final l in config.config.llms)
      if (l.enabled && l.models.isNotEmpty) l,
  ];

  String _name(LlmPick pick) {
    final llm = config.config.llms.where((l) => l.id == pick.llm).firstOrNull;
    return '${llm?.name ?? pick.llm} · ${pick.model}';
  }

  Future<String> _ask(LlmPick pick, Attachment image) {
    final cfg = config.config;
    final llm = cfg.llms.where((l) => l.id == pick.llm).firstOrNull;
    if (llm == null) throw LlmException(tr('这个模型已经不在了'));
    return vm.askModel(
      llm,
      pick.model,
      llmReverseMessages(cfg.activePreset.systemPrompt),
      images: {
        1: [(mime: image.mime!, bytes: image.bytes!)],
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: config,
      builder: (context, _) {
        final llms = _llms;
        // 选过、但后来停用或删掉的不算。
        final picks = [
          for (final p in model.llmPicks)
            if (llms.any((l) => l.id == p.llm && l.models.contains(p.model))) p,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_models(llms), _results(context, picks)],
        );
      },
    );
  }

  Widget _models(List<LlmProfile> llms) {
    return _Block(
      title: tr('模型'),
      trailing: Text(
        tr('最多选 {0} 个', [maxLlmPicks]),
        style: TextStyle(fontSize: 11, color: PennaColors.slate400),
      ),
      child: llms.isEmpty
          ? Text(
              tr('「API 管理」里还没有启用的模型'),
              style: TextStyle(fontSize: 12, color: PennaColors.slate500),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final llm in llms)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              llm.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final m in llm.models)
                                PennaChip(
                                  label: m,
                                  selected: model.llmPicks.contains((
                                    llm: llm.id,
                                    model: m,
                                  )),
                                  onTap: () =>
                                      model.toggleLlm((llm: llm.id, model: m)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _results(BuildContext context, List<LlmPick> picks) {
    final busy = model.llmBusy;
    return _Block(
      title: tr('反推结果'),
      trailing: PennaButton(
        label: busy ? tr('反推中…') : tr('反推'),
        icon: Icons.image_search,
        background: PennaColors.primary,
        foreground: Colors.white,
        onPressed: picks.isEmpty || model.image == null || busy
            ? null
            : () => _run(context, () => model.runLlm(picks, _ask)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, p) in picks.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _result(p)),
          ],
        ],
      ),
    );
  }

  /// 一个模型的结果:名字,下面是转圈、出错原因或它写的提示词。
  Widget _result(LlmPick pick) {
    final r = model.llmResultOf(pick);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _name(pick),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: PennaColors.slate700,
          ),
        ),
        const SizedBox(height: 6),
        PennaCard(
          color: PennaColors.slate50,
          radius: 4,
          child: switch (r) {
            (busy: true, text: _, error: _) => const Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            (error: final String error, text: _, busy: _) => Text(
              error,
              style: TextStyle(fontSize: 12, color: PennaColors.diffDelText),
            ),
            (text: final text, error: _, busy: _) => SelectableText(
              contextMenuBuilder: pennaTextMenu,
              text,
              style: monoStyle.copyWith(fontSize: 11.5),
            ),
            null => Text(
              tr('暂无内容'),
              style: TextStyle(fontSize: 12, color: PennaColors.slate400),
            ),
          },
        ),
        if (r case (busy: false, error: null, text: final text)) ...[
          const SizedBox(height: 8),
          _ResultActions(text: text, onToDraft: onToDraft, onSend: onSend),
        ],
      ],
    );
  }
}
