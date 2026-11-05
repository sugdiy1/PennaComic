part of 'studio_view_model.dart';

extension StudioMetrics on StudioViewModel {
  /// 与实际请求有关的配置；同一个模型 ID 改地址/名称也会改变此值。
  String get contextConfigurationKey => jsonEncode({
    'chain': [for (final p in config.config.agentChain) p.toJson()],
    'preset': config.config.activePreset.toJson(),
    'reasoning': config.config.reasoningEffort,
    'disabledSkills': config.config.disabledSkills.toList()..sort(),
    'piercing': config.config.piercingText,
    'layoutQuality': config.config.layoutQuality,
  });

  String _sourceFor(LlmRequest request) =>
      jsonEncode([request.protocol, request.baseUrl, request.model]);
  void _activateContextSource(LlmRequest request) {
    final source = _sourceFor(request);
    if (source == _contextSource) return;
    _contextSource = source;
    _contextStatus = const ContextSnapshot();
  }

  /// 换聊天/页后立即作废旧统计；稍后由输入栏重新测量保留下来的固定资料。
  void _resetContext() {
    _contextRun++;
    _usageEpoch++;
    _measuringContext = false;
    _isThinking = false;
    _lastActualContext = null;
    _lastActualSource = null;
    _contextStatus = ContextSnapshot(capacity: _contextStatus.capacity);
  }

  Future<void> refreshContext({
    String draft = '',
    List<Attachment> attachments = const [],
    List<String> skillIds = const [],
  }) async {
    if (_disposed || isStreaming) return;
    final run = ++_contextRun, chatStamp = _chatId;
    final cfg = config.config, chain = _usable(config.config.agentChain);
    final configuration = contextConfigurationKey;
    if (_contextConfigurationStamp != configuration) {
      _lastActualContext = null;
      _lastActualSource = null;
      _contextConfigurationStamp = configuration;
    }
    if (chain.isEmpty) {
      _contextStatus = const ContextSnapshot();
      _measuringContext = false;
      _notify();
      return;
    }
    final history = <ChatMessage>[
      ..._messages,
      ChatMessage(
        fromUser: true,
        text: draft,
        time: DateTime.now(),
        attachments: attachments,
        skillIds: skillIds,
        quote: _quote,
      ),
    ];
    final pending =
        draft.trim().isNotEmpty ||
        attachments.isNotEmpty ||
        skillIds.isNotEmpty ||
        (_quote?.isNotEmpty ?? false);
    final requests = _preparedChatRequests(history, cfg, chain);
    // 备用模型刚完成时，空草稿仍显示该实际来源；下一份草稿才按首选模型估算。
    final actualRequest = !pending && _lastActualContext != null
        ? requests
              .map((r) => r.$2)
              .where((r) => _sourceFor(r) == _lastActualSource)
              .firstOrNull
        : null;
    final request = actualRequest ?? requests.first.$2;
    _activateContextSource(request);
    if (!isLocalBonsai(request.baseUrl, request.model)) {
      _contextStatus = const ContextSnapshot();
      _measuringContext = false;
      _notify();
      return;
    }
    _measuringContext = true;
    _notify();
    final result = await _contextService.measure(request);
    if (_disposed || run != _contextRun) return;
    if (chatStamp != _chatId ||
        isStreaming ||
        configuration != contextConfigurationKey) {
      // 这期间换了对话或开始生成:结果作废,但要把“正在测量”收掉,
      // 否则圆环会一直转。
      _measuringContext = false;
      _notify();
      return;
    }
    // 没有待发内容时保留上次请求的实测用量；刷新仅补容量。
    // 新草稿/引用/附件才显示估算，删除草稿后能切回实测快照。
    final actual = _lastActualContext;
    _contextStatus = ContextSnapshot(
      usedTokens: !pending && actual != null
          ? actual.usedTokens
          : result.usedTokens,
      capacity: result.capacity ?? _contextStatus.capacity,
      estimated: pending || actual == null,
    );
    if (!_contextStatus.estimated) _lastActualContext = _contextStatus;
    _measuringContext = false;
    _notify();
  }

  List<(String, LlmRequest)> _preparedChatRequests(
    List<ChatMessage> history,
    AppConfig cfg,
    List<LlmProfile> chain,
  ) {
    final preset = cfg.activePreset;
    // 出错的、被停在开头的空回复不算历史,有的接口会拒收空内容。
    final sent = [
      for (final m in history)
        if (m.fromUser || !m.failed && m.text.isNotEmpty) m,
    ];
    return _requests(
      cfg,
      chain,
      preset,
      [
        {
          'role': 'system',
          'content': layoutOnly
              ? _layoutSystemPrompt(cfg, preset)
              : _systemPrompt(cfg, preset),
        },
        for (final (i, m) in sent.indexed)
          {
            'role': m.fromUser ? 'user' : 'assistant',
            'content': switch (_withReferences(m, {
              for (final s in skills?.all ?? const <UserSkill>[])
                if (!cfg.disabledSkills.contains(s.id)) s.id,
            })) {
              // 自己以前写的布局、透视、灯光不重发:画板可能已被用户改过。
              // 后面紧跟着工具结果的是查资料的那条,里面的布局没放上画板。
              final text when !m.fromUser => forgetLighting(
                forgetPerspectives(
                  forgetLayers(
                    forgetLayouts(
                      text,
                      placed: i + 1 >= sent.length || !sent[i + 1].tool,
                    ),
                  ),
                ),
              ),
              // 布局页里刚发的这条带着参考图:就在这里提醒画布多大,
              // 模型看了图常照图的比例写宽高(系统提示里说了也会忘)。
              final text
                  when layoutOnly &&
                      i == sent.length - 1 &&
                      m.attachments.any((a) => a.isImage) =>
                '$text${_canvasReminder()}',
              final text => text,
            },
          },
      ],
      latestUserText: history
          .where((m) => m.fromUser && !m.tool)
          .lastOrNull
          ?.text,
      // 下标 +1:前面还有一条系统提示。
      images: {
        for (final (i, m) in sent.indexed)
          if (m.attachments.any((a) => a.isImage))
            i + 1: [
              for (final a in m.attachments)
                if (a.isImage) (mime: a.mime!, bytes: a.bytes!),
            ],
      },
    );
  }
}
