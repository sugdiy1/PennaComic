import 'dart:convert';
import 'dart:io';

import '../providers/llm_http.dart';

/// Bonsai's template accepts low, medium and xhigh reasoning efforts.
class BonsaiReasoningPlan {
  const BonsaiReasoningPlan({
    required this.enabled,
    required this.effort,
    required this.budgetTokens,
    required this.maxOutputTokens,
  });

  final bool enabled;
  final String? effort;
  final int budgetTokens;
  final int maxOutputTokens;
}

/// Reserve the normal response allowance in addition to the thinking budget.
BonsaiReasoningPlan bonsaiReasoningPlan(String level) {
  final (effort, budget) = switch (level.trim().toLowerCase()) {
    'none' => (null, 0),
    'low' => ('low', 1024),
    'high' => ('xhigh', 8192),
    'xhigh' => ('xhigh', 16384),
    _ => ('medium', 4096),
  };
  return BonsaiReasoningPlan(
    enabled: budget > 0,
    effort: effort,
    budgetTokens: budget,
    maxOutputTokens: 16384 + budget,
  );
}

class ContextSnapshot {
  const ContextSnapshot({
    this.usedTokens,
    this.capacity,
    this.estimated = true,
  });

  final int? usedTokens;

  /// The server's active n_ctx, when available; never the training limit.
  final int? capacity;

  /// False means text was counted with the server template and tokenizer.
  /// Actual generation prefill can still differ by a few special tokens.
  final bool estimated;
}

/// Read-only llama.cpp context measurements for loopback servers.
///
/// This service only calls props, apply-template and tokenize. It never starts
/// inference, changes server settings or persists prompts.
class LocalContextService {
  static const _timeout = Duration(seconds: 3);
  static const _capacityTtl = Duration(seconds: 30);
  final _capacities = <String, ({int value, DateTime fetchedAt})>{};

  Future<ContextSnapshot> measure(LlmRequest request) async {
    final estimate = _estimateTokens(request.messages);
    final root = _localRoot(request.baseUrl);
    if (root == null) return ContextSnapshot(usedTokens: estimate);

    final key = root.toString();
    final cached = _capacities[key];
    int? capacity = cached?.value;
    final client = HttpClient()
      ..connectionTimeout = _timeout
      ..findProxy = (_) => 'DIRECT';
    try {
      if (cached == null ||
          DateTime.now().difference(cached.fetchedAt) >= _capacityTtl) {
        try {
          final props = await _json(client, root, 'props', request.apiKey);
          final settings = props is Map
              ? props['default_generation_settings']
              : null;
          final value = settings is Map ? settings['n_ctx'] : null;
          if (value is int && value > 0) {
            capacity = value;
            _capacities[key] = (value: value, fetchedAt: DateTime.now());
          }
        } on Object {
          // Keep any previously measured capacity if the server is unavailable.
        }
      }

      final template = await _json(
        client,
        root,
        'apply-template',
        request.apiKey,
        body: {
          'messages': request.messages,
          'chat_template_kwargs': {
            if (request.enableThinking != null)
              'enable_thinking': request.enableThinking,
            if (request.reasoningEffort != null)
              'reasoning_effort': request.reasoningEffort,
          },
        },
      );
      final prompt = template is Map ? template['prompt'] : template;
      if (prompt is! String) throw const FormatException('Missing prompt');
      final tokenized = await _json(
        client,
        root,
        'tokenize',
        request.apiKey,
        body: {'content': prompt, 'add_special': false, 'parse_special': true},
      );
      final tokens = tokenized is Map ? tokenized['tokens'] : null;
      if (tokens is! List) throw const FormatException('Missing tokens');
      return ContextSnapshot(
        usedTokens: tokens.length,
        capacity: capacity,
        estimated: request.images.values.any((images) => images.isNotEmpty),
      );
    } on Object {
      return ContextSnapshot(usedTokens: estimate, capacity: capacity);
    } finally {
      client.close(force: true);
    }
  }

  Future<Object?> _json(
    HttpClient client,
    Uri root,
    String endpoint,
    String apiKey, {
    Map<String, Object?>? body,
  }) => (() async {
    final uri = root.replace(path: '${root.path}$endpoint');
    final outgoing = await client.openUrl(body == null ? 'GET' : 'POST', uri);
    // A loopback endpoint must not redirect this request to another host.
    outgoing.followRedirects = false;
    if (apiKey.isNotEmpty) {
      outgoing.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    }
    if (body != null) {
      outgoing.headers.contentType = ContentType.json;
      outgoing.add(utf8.encode(jsonEncode(body)));
    }
    final response = await outgoing.close();
    if (response.statusCode != HttpStatus.ok) {
      throw const HttpException('Context endpoint unavailable');
    }
    return jsonDecode(await utf8.decodeStream(response));
  })().timeout(_timeout);

  static Uri? _localRoot(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final host = uri.host.toLowerCase();
    if (!{'localhost', '127.0.0.1', '::1', '[::1]'}.contains(host)) {
      return null;
    }
    var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.endsWith('/v1')) path = path.substring(0, path.length - 3);
    return uri.replace(path: '$path/', query: '', fragment: '');
  }

  static int _estimateTokens(List<Map<String, String>> messages) {
    // Chat templates add delimiters even for empty messages. CJK characters
    // generally require more tokens per character than ordinary English text.
    var count = 4;
    for (final message in messages) {
      var cjk = 0;
      var ascii = 0;
      var other = 0;
      for (final rune in (message['content'] ?? '').runes) {
        if ((rune >= 0x2e80 && rune <= 0x9fff) ||
            (rune >= 0xac00 && rune <= 0xd7af) ||
            (rune >= 0xf900 && rune <= 0xfaff) ||
            (rune >= 0x20000 && rune <= 0x323af)) {
          cjk++;
        } else if (rune < 128) {
          ascii++;
        } else {
          other++;
        }
      }
      count += 8 + cjk + (ascii / 4).ceil() + (other / 2).ceil();
    }
    return count;
  }
}
