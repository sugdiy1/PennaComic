import 'dart:convert';
import 'dart:io';

import 'llm_http.dart';
import '../../../l10n/l10n.dart';
import '../comic/layout_context_policy.dart';

export 'llm_http.dart';

/// 取出一行 SSE 里的增量文本;不是内容行(注释、心跳、空行)返回 null。
String? parseSseLine(String line) {
  final json = sseJson(line);
  if (json is! Map) return null;
  final error = json['error'];
  if (error != null) {
    throw LlmException(
      tr('模型返回错误:{0}', [error is Map ? error['message'] : error]),
    );
  }
  final choices = json['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  final delta = first is Map ? first['delta'] : null;
  final content = delta is Map ? delta['content'] : null;
  return content is String ? content : null;
}

/// `/models` 响应里的模型名;有的兼容接口不包 `data`,直接回一个数组。
List<String> parseOpenAiModels(Object? json) {
  final data = json is Map ? json['data'] : json;
  return [
    if (data is List)
      for (final m in data)
        if (m is Map && m['id'] is String) m['id'] as String,
  ];
}

/// 问 OpenAI 兼容接口有哪些模型。
Future<List<String>> listOpenAiModels(String baseUrl, String apiKey) async {
  final key = apiKey.trim();
  return parseOpenAiModels(
    await getJson(llmEndpoint(baseUrl, '/models'), {
      if (key.isNotEmpty) HttpHeaders.authorizationHeader: 'Bearer $key',
    }),
  );
}

/// 请求里的消息;带图片的那条把 content 换成「文字 + 图片」的分段格式。
List<Map<String, Object?>> openAiMessages(LlmRequest req) => [
  for (final (i, m) in req.messages.indexed)
    if ((req.images[i] ?? const []).isEmpty)
      m
    else
      {
        'role': m['role'],
        'content': [
          if ((m['content'] ?? '').isNotEmpty)
            {'type': 'text', 'text': m['content']},
          for (final image in req.images[i]!)
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:${image.mime};base64,${base64Encode(image.bytes)}',
              },
            },
        ],
      },
];

/// 调用 OpenAI 兼容的 `/chat/completions`,逐段吐出回复文本。
Stream<String> streamOpenAiChat(LlmRequest req) =>
    runLlmStream((client) => _chat(client, req));

Stream<String> _chat(HttpClient client, LlmRequest req) async* {
  final apiKey = req.apiKey.trim();
  final lines = postForLines(
    client,
    llmEndpoint(req.baseUrl, '/chat/completions'),
    {if (apiKey.isNotEmpty) HttpHeaders.authorizationHeader: 'Bearer $apiKey'},
    {
      'model': req.model,
      'messages': openAiMessages(req),
      'temperature': req.temperature,
      if (req.topP < 1) 'top_p': req.topP,
      'stream': true,
      if (req.maxOutputTokens != null) 'max_tokens': req.maxOutputTokens,
      if (req.reasoningEffort != null) 'reasoning_effort': req.reasoningEffort,
      if (req.enableThinking != null) ...{
        'chat_template_kwargs': {'enable_thinking': req.enableThinking},
        'reasoning_format': 'deepseek',
      },
      if (req.reasoningBudgetTokens != null)
        'reasoning_budget_tokens': req.reasoningBudgetTokens,
      if (req.onUsage != null) 'stream_options': {'include_usage': true},
      if (req.layoutSchema != null)
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'comic_layout',
            'strict': true,
            'schema': req.layoutSchema,
          },
        },
    },
  );

  var yielded = false;
  final plain = StringBuffer();
  final structured = StringBuffer();
  bool thoughtSeen = false, answerSeen = false;
  String? finishReason;
  await for (final line in lines) {
    if (!line.startsWith('data:')) {
      plain.writeln(line);
      continue;
    }
    if (line.substring(5).trim() == '[DONE]') break;
    final packet = sseJson(line);
    if (packet is Map) {
      final usage = LlmUsage.fromJson(packet['usage']);
      if (usage != null) req.onUsage?.call(usage);
      final choices = packet['choices'];
      if (choices is List && choices.isNotEmpty && choices.first is Map) {
        final choice = choices.first as Map;
        finishReason = choice['finish_reason'] as String? ?? finishReason;
        final data = choice['delta'];
        if (!thoughtSeen &&
            data is Map &&
            (data['reasoning_content'] ?? '').toString().isNotEmpty) {
          thoughtSeen = true;
          req.onReasoning?.call();
        }
      }
    }
    final delta = parseSseLine(line);
    if (delta != null && delta.isNotEmpty) {
      if (!answerSeen) {
        answerSeen = true;
        req.onAnswer?.call();
      }
      yielded = true;
      if (req.layoutSchema != null) {
        structured.write(delta);
      } else {
        yield delta;
      }
    }
  }
  if (yielded) {
    if (req.layoutSchema != null && finishReason == 'length') {
      throw const LlmException('输出达到上限，分镜未完成，原稿已保留。可降低思考程度后重试。');
    }
    if (req.layoutSchema != null) {
      yield layoutEnvelopeToTags(
        structured.toString(),
        forcedTarget: req.layoutTarget,
      );
    }
    return;
  }
  // 有的接口无视 stream:true,直接回一整个 JSON。
  if (thoughtSeen) {
    throw const LlmException('模型只返回思考，没有正文。请降低思考程度后重试。');
  }
  try {
    final response = jsonDecode(plain.toString());
    if (response is Map) {
      final usage = LlmUsage.fromJson(response['usage']);
      if (usage != null) req.onUsage?.call(usage);
    }
  } on FormatException {
    /* 交给下方已有的错误处理。 */
  }
  final whole = _wholeReply(plain.toString());
  if (whole == null) throw LlmException(tr('模型没有返回可识别的内容'));
  yield req.layoutSchema == null
      ? whole
      : layoutEnvelopeToTags(whole, forcedTarget: req.layoutTarget);
}

String? _wholeReply(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (json is! Map) return null;
  final choices = json['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  final message = first is Map ? first['message'] : null;
  final content = message is Map ? message['content'] : null;
  return content is String && content.isNotEmpty ? content : null;
}
