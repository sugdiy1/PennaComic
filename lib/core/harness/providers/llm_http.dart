import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../l10n/l10n.dart';

/// 随某条消息发出的一张图片。
typedef LlmImage = ({String mime, Uint8List bytes});

@immutable
class LlmRequest {
  const LlmRequest({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.messages,
    this.images = const {},
    this.temperature = 0.7,
    this.topP = 1,
    this.protocol = 'openai',
    this.maxOutputTokens,
    this.reasoningEffort,
    this.layoutSchema,
    this.layoutTarget,
    this.enableThinking,
    this.reasoningBudgetTokens,
    this.onUsage,
    this.onReasoning,
    this.onAnswer,
  });

  /// 带图片的消息:[messages] 里的下标 → 那条消息的图片。
  final Map<int, List<LlmImage>> images;

  final String baseUrl;
  final String model;

  /// 可为空(本地模型常常不需要 Key)。
  final String apiKey;

  /// 统一用 OpenAI 的消息格式:`{'role': 'system'|'user'|'assistant', 'content': '...'}`;
  /// 其他协议各自转换。
  final List<Map<String, String>> messages;
  final double temperature;

  /// 小于 1 才发给模型:有的接口不让它和温度一起给。
  final double topP;

  /// 'openai' 或 'google'。
  final String protocol;
  final int? maxOutputTokens;
  final String? reasoningEffort;
  final Map<String, Object?>? layoutSchema;
  final String? layoutTarget;
  final bool? enableThinking;
  final int? reasoningBudgetTokens;
  final void Function(LlmUsage usage)? onUsage;
  final void Function()? onReasoning, onAnswer;
}

/// 服务端上报的用量。缓存 token 已包含在 prompt 中，不能重复相加。
class LlmUsage {
  const LlmUsage({
    required this.promptTokens,
    required this.completionTokens,
    this.cachedTokens = 0,
  });
  final int promptTokens, completionTokens, cachedTokens;
  int get totalTokens => promptTokens + completionTokens;
  static LlmUsage? fromJson(Object? value) {
    if (value is! Map ||
        value['prompt_tokens'] is! num ||
        value['completion_tokens'] is! num) {
      return null;
    }
    return LlmUsage(
      promptTokens: (value['prompt_tokens'] as num).toInt(),
      completionTokens: (value['completion_tokens'] as num).toInt(),
      cachedTokens:
          ((value['prompt_tokens_details'] as Map?)?['cached_tokens'] as num? ??
                  0)
              .toInt(),
    );
  }
}

/// 给用户看的模型调用错误;不含 Key。
class LlmException implements Exception {
  const LlmException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef ChatStreamer = Stream<String> Function(LlmRequest request);

const _maxErrorBody = 300;

/// 跑一次流式对话:[chat] 用给它的连接发请求并逐段吐字。
/// 取消订阅会立刻掐断连接,不用等下一段回复。
Stream<String> runLlmStream(Stream<String> Function(HttpClient client) chat) {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  var cancelled = false;
  late final StreamController<String> out;
  out = StreamController<String>(
    onListen: () async {
      try {
        await for (final delta in chat(client)) {
          if (cancelled) break;
          out.add(delta);
        }
      } on Object catch (e) {
        if (!cancelled) out.addError(_friendly(e));
      } finally {
        client.close(force: true);
        if (!cancelled) await out.close();
      }
    },
    onCancel: () {
      cancelled = true;
      client.close(force: true);
    },
  );
  return out.stream;
}

/// 把底层异常换成给用户看的话。原始异常文本可能带着请求头(也就是 Key),
/// 所以认不出的异常只报类型,不原样转述。
LlmException _friendly(Object e) => switch (e) {
  LlmException() => e,
  TimeoutException() => LlmException(tr('模型接口超时')),
  SocketException() => LlmException(tr('连不上模型接口:{0}', [e.message])),
  HandshakeException() => LlmException(tr('HTTPS 握手失败:{0}', [e.message])),
  HttpException() => LlmException(tr('网络请求中断:{0}', [e.message])),
  FormatException() => LlmException(tr('请求发不出去:API Key 或接口地址里有非法字符')),
  _ => LlmException(tr('调用模型失败({0})', [e.runtimeType])),
};

/// 拼出接口地址;[baseUrl] 不是 http(s) 地址时报错。
Uri llmEndpoint(String baseUrl, String path) {
  final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.tryParse('$base$path');
  if (uri == null || !uri.isScheme('http') && !uri.isScheme('https')) {
    throw LlmException(tr('Base URL 无效:要以 http:// 或 https:// 开头'));
  }
  return uri;
}

/// POST 一段 JSON,把成功响应按行吐出来;非 200 时抛出带状态码的错误。
Stream<String> postForLines(
  HttpClient client,
  Uri uri,
  Map<String, String> headers,
  Map<String, Object?> body,
) async* {
  final request = await client.postUrl(uri);
  request.headers.contentType = ContentType.json;
  request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
  headers.forEach(request.headers.set);
  request.add(utf8.encode(jsonEncode(body)));
  // 模型卡住不说话时不能一直等:超时算失败,还没出字就会换下一个模型。
  final response = await request.close().timeout(llmStallTimeout);
  if (response.statusCode != HttpStatus.ok) {
    throw _statusError(response.statusCode, await utf8.decodeStream(response));
  }
  yield* response
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      // 推理模型思考时也一直在发数据,隔这么久一行都没有才算卡住。
      .timeout(llmStallTimeout);
}

/// 等模型回话最多等多久(从发出请求到收到回应,或两段数据之间)。
const llmStallTimeout = Duration(seconds: 60);

LlmException _statusError(int status, String body) {
  // 回来的是一张网页:多半是地址填错了,打到了网站而不是接口上。
  if (body.trimLeft().startsWith('<')) {
    return LlmException(tr('模型接口返回 {0}:地址不对,返回的是网页。请检查 Base URL', [status]));
  }
  // 多数接口把原因放在 error.message 里;取得到就只显示这一句,不显示整坨 JSON。
  var reason = body;
  try {
    final decoded = jsonDecode(body);
    final json = decoded is List && decoded.isNotEmpty
        ? decoded.first
        : decoded;
    final error = json is Map ? json['error'] ?? json : null;
    final message = error is Map ? error['message'] : error;
    if (message is String && message.trim().isNotEmpty) reason = message.trim();
  } on FormatException {
    // 不是 JSON,原样显示。
  }
  final shown = reason.length > _maxErrorBody
      ? reason.substring(0, _maxErrorBody)
      : reason;
  return LlmException(tr('模型接口返回 {0}:{1}', [status, shown]));
}

const _getTimeout = Duration(seconds: 30);

/// GET 一个 JSON 接口(拉取模型列表用);出错时和对话一样换成给用户看的话。
Future<Object?> getJson(Uri uri, Map<String, String> headers) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final String text;
  try {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(_getTimeout);
    text = await utf8.decodeStream(response).timeout(_getTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw _statusError(response.statusCode, text);
    }
  } on TimeoutException {
    throw LlmException(tr('模型接口超时'));
  } on Object catch (e) {
    throw _friendly(e);
  } finally {
    client.close(force: true);
  }
  try {
    return jsonDecode(text);
  } on FormatException {
    throw LlmException(tr('接口返回的不是模型列表'));
  }
}

/// 一行 SSE 的 JSON 内容;不是数据行、是结束标记或解析不了时返回 null。
Object? sseJson(String line) {
  if (!line.startsWith('data:')) return null;
  try {
    return jsonDecode(line.substring(5).trim());
  } on FormatException {
    return null;
  }
}
