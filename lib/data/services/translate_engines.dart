import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../l10n/l10n.dart';

/// 一个机翻引擎:用 [client] 把 [text] 从 [from] 译到 [to]。
/// 语言用 'en'、'zh'(简体)、'zh-Hant'、'ja';各引擎自己换成它认的代码。
typedef Translator = Future<String> Function(
  HttpClient client,
  String text,
  String from,
  String to,
);

/// 给用户看的翻译错误;不含密钥。
class TranslateException implements Exception {
  const TranslateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 引擎没配好(缺凭据):重试没有意义,直接换下一个。
class TranslateConfigException extends TranslateException {
  const TranslateConfigException(super.message);
}

class TranslateResult {
  const TranslateResult(this.text, this.engineId, this.failures);

  final String text;
  final String engineId;

  /// 成功之前失败过的尝试,按时间顺序。
  final List<String> failures;
}

/// 按 [chain] 的顺序翻译:每个引擎最多试 [attempts] 次,单次超过 [timeout] 算失败,
/// 都不行就换下一个;全部失败才抛错。
Future<TranslateResult> translateWithFailover({
  required List<(String id, Translator run)> chain,
  required String text,
  required String from,
  required String to,
  required int attempts,
  required Duration timeout,
}) async {
  if (chain.isEmpty) throw TranslateException(tr('没有启用翻译引擎'));
  final failures = <String>[];
  for (final (id, run) in chain) {
    for (var attempt = 1; attempt <= attempts; attempt++) {
      final client = HttpClient()..connectionTimeout = timeout;
      try {
        final out = await run(client, text, from, to).timeout(timeout);
        if (out.trim().isEmpty) throw TranslateException(tr('返回为空'));
        return TranslateResult(out, id, List.unmodifiable(failures));
      } on TranslateConfigException catch (e) {
        failures.add('$id:${e.message}');
        break;
      } on Object catch (e) {
        failures.add(tr('{0} 第 {1} 次:{2}', [id, attempt, _brief(e)]));
      } finally {
        // 超时后请求还挂着,强制关掉免得占着连接。
        client.close(force: true);
      }
    }
  }
  throw TranslateException(tr('翻译失败\n{0}', [failures.join('\n')]));
}

/// 认不出的异常只报类型:原始文本可能带着 URL 里的 Key。
String _brief(Object e) => switch (e) {
  TranslateException() => e.message,
  TimeoutException() => tr('超时'),
  SocketException() => tr('连不上'),
  HandshakeException() => tr('HTTPS 握手失败'),
  _ => '${e.runtimeType}',
};

/// 服务端的报错原文可能很长(阿里签名错误会把整段原文回显),只留开头。
String _clip(String s) => s.length > 80 ? '${s.substring(0, 80)}…' : s;

/// Google 和 MyMemory 认的语言代码。
String _google(String lang) =>
    const {'zh': 'zh-CN', 'zh-Hant': 'zh-TW'}[lang] ?? lang;

/// 百度认的语言代码。
String _baidu(String lang) =>
    const {'zh-Hant': 'cht', 'ja': 'jp'}[lang] ?? lang;

/// 阿里认的语言代码。
String _ali(String lang) => const {'zh-Hant': 'zh-tw'}[lang] ?? lang;

/// 译成中文、日文时各小段之间不加空格。
bool _cjk(String lang) => lang != 'en';

Future<Object?> _send(HttpClientRequest request, [String? body]) async {
  if (body != null) request.add(utf8.encode(body));
  final response = await request.close();
  final text = await utf8.decodeStream(response);
  if (response.statusCode != HttpStatus.ok) {
    throw TranslateException('HTTP ${response.statusCode}');
  }
  try {
    return jsonDecode(text);
  } on FormatException {
    throw TranslateException(tr('返回的不是 JSON'));
  }
}

Future<Object?> _postForm(
  HttpClient client,
  Uri uri,
  Map<String, String> fields,
) async {
  final request = await client.postUrl(uri);
  request.headers.contentType = ContentType(
    'application',
    'x-www-form-urlencoded',
    charset: 'utf-8',
  );
  return _send(request, Uri(queryParameters: fields).query);
}

/// Google 网页版用的免费接口,无需 Key(非官方,可能限流)。
Future<String> googleFree(
  HttpClient client,
  String text,
  String from,
  String to,
) async {
  final json = await _postForm(
    client,
    Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'dt': 't',
      'sl': _google(from),
      'tl': _google(to),
    }),
    {'q': text},
  );
  final parts = json is List && json.isNotEmpty ? json.first : null;
  if (parts is! List) throw TranslateException(tr('返回格式不认识'));
  return [
    for (final p in parts)
      if (p is List && p.isNotEmpty && p.first is String) p.first as String,
  ].join();
}

/// MyMemory 单次最多 500 字节,留点余量。
const myMemoryChunkBytes = 450;

/// MyMemory 免费接口,无需 Key;长文本分段翻译。
Future<String> myMemory(
  HttpClient client,
  String text,
  String from,
  String to,
) async {
  final out = <String>[];
  for (final chunk in splitByBytes(text, myMemoryChunkBytes)) {
    final request = await client.getUrl(
      Uri.https('api.mymemory.translated.net', '/get', {
        'q': chunk,
        'langpair': '${_google(from)}|${_google(to)}',
      }),
    );
    final json = await _send(request);
    if (json is! Map || json['responseStatus'] != 200) {
      final detail = json is Map ? json['responseDetails'] : null;
      throw TranslateException(detail is String ? detail : tr('返回格式不认识'));
    }
    final data = json['responseData'];
    final piece = data is Map ? data['translatedText'] : null;
    if (piece is! String) throw TranslateException(tr('返回格式不认识'));
    // 额度用完时它照样回 200,只是把提示塞在译文里。
    if (piece.startsWith('MYMEMORY WARNING')) {
      throw TranslateException(tr('今日免费额度已用完'));
    }
    out.add(piece);
  }
  return out.join(_cjk(to) ? '' : ' ');
}

/// 把 [text] 切成每段不超过 [maxBytes](UTF-8)的小段,尽量在标点或空格处断开。
List<String> splitByBytes(String text, int maxBytes) {
  final chunks = <String>[];
  var current = StringBuffer();
  var size = 0;
  void flush() {
    final s = current.toString().trim();
    if (s.isNotEmpty) chunks.add(s);
    current = StringBuffer();
    size = 0;
  }

  // 先按标点切句;句子本身太长再按空格切词;词还太长就按字符硬切。
  final pieces = text
      .split(RegExp(r'(?<=[.,;!?。，；！？\n])'))
      .expand(
        (p) => utf8.encode(p).length <= maxBytes
            ? [p]
            : p.split(RegExp(r'(?<= )')),
      )
      .expand(
        (p) => utf8.encode(p).length <= maxBytes
            ? [p]
            : p.runes.map(String.fromCharCode),
      );
  for (final piece in pieces) {
    final bytes = utf8.encode(piece).length;
    if (size + bytes > maxBytes) flush();
    current.write(piece);
    size += bytes;
  }
  flush();
  return chunks;
}

/// Google Cloud Translation v2(官方,需要 API Key)。
Translator googleCloud(String apiKey) => (client, text, from, to) async {
  if (apiKey.trim().isEmpty) {
    throw TranslateConfigException(tr('没填 API Key'));
  }
  final json = await _postForm(
    client,
    Uri.https('translation.googleapis.com', '/language/translate/v2', {
      'key': apiKey.trim(),
    }),
    {
      'q': text,
      'source': _google(from),
      'target': _google(to),
      'format': 'text',
    },
  );
  final data = json is Map ? json['data'] : null;
  final list = data is Map ? data['translations'] : null;
  final first = list is List && list.isNotEmpty ? list.first : null;
  final out = first is Map ? first['translatedText'] : null;
  if (out is! String) throw TranslateException(tr('返回格式不认识'));
  return out;
};

/// 百度翻译开放平台(需要 APP ID 和密钥)。
Translator baidu(String appId, String secret) =>
    (client, text, from, to) async {
      if (appId.trim().isEmpty || secret.trim().isEmpty) {
        throw TranslateConfigException(tr('没填 APP ID 或密钥'));
      }
      final salt = '${Random.secure().nextInt(1 << 32)}';
      final sign = md5
          .convert(utf8.encode('${appId.trim()}$text$salt${secret.trim()}'))
          .toString();
      final json = await _postForm(
        client,
        Uri.https('fanyi-api.baidu.com', '/api/trans/vip/translate'),
        {
          'q': text,
          'from': _baidu(from),
          'to': _baidu(to),
          'appid': appId.trim(),
          'salt': salt,
          'sign': sign,
        },
      );
      if (json is! Map) throw TranslateException(tr('返回格式不认识'));
      if (json['error_code'] != null) {
        throw TranslateException(
          tr('百度报错 {0}:{1}', [
            json['error_code'],
            _clip('${json['error_msg']}'),
          ]),
        );
      }
      final list = json['trans_result'];
      if (list is! List) throw TranslateException(tr('返回格式不认识'));
      return [
        for (final item in list)
          if (item is Map && item['dst'] is String) item['dst'] as String,
      ].join('\n');
    };

/// 阿里云签名用的编码:在 URL 编码基础上,空格是 %20、* 是 %2A、~ 不编码。
String aliPercentEncode(String value) =>
    Uri.encodeQueryComponent(value)
        .replaceAll('+', '%20')
        .replaceAll('*', '%2A')
        .replaceAll('%7E', '~');

/// 阿里云 RPC 接口的签名(HMAC-SHA1)。
String aliSignature(Map<String, String> params, String secret) {
  final keys = params.keys.toList()..sort();
  final canonical = keys
      .map((k) => '${aliPercentEncode(k)}=${aliPercentEncode(params[k]!)}')
      .join('&');
  final toSign = 'POST&%2F&${aliPercentEncode(canonical)}';
  final mac = Hmac(sha1, utf8.encode('$secret&'));
  return base64.encode(mac.convert(utf8.encode(toSign)).bytes);
}

/// 阿里云机器翻译通用版(需要 AccessKey ID 和 Secret)。
Translator ali(String keyId, String secret) => (client, text, from, to) async {
  if (keyId.trim().isEmpty || secret.trim().isEmpty) {
    throw TranslateConfigException(tr('没填 AccessKey'));
  }
  final now = DateTime.now().toUtc();
  final params = {
    'Action': 'TranslateGeneral',
    'Version': '2018-10-12',
    'Format': 'JSON',
    'FormatType': 'text',
    'Scene': 'general',
    'SourceLanguage': _ali(from),
    'TargetLanguage': _ali(to),
    'SourceText': text,
    'AccessKeyId': keyId.trim(),
    'SignatureMethod': 'HMAC-SHA1',
    'SignatureVersion': '1.0',
    'SignatureNonce':
        '${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
    'Timestamp': '${now.toIso8601String().split('.').first}Z',
  };
  final request = await client.postUrl(
    Uri.https('mt.cn-hangzhou.aliyuncs.com', '/'),
  );
  request.headers.contentType = ContentType(
    'application',
    'x-www-form-urlencoded',
    charset: 'utf-8',
  );
  final body = Uri(
    queryParameters: {
      ...params,
      'Signature': aliSignature(params, secret.trim()),
    },
  ).query;
  request.add(utf8.encode(body));
  final response = await request.close();
  final Object? json;
  try {
    json = jsonDecode(await utf8.decodeStream(response));
  } on FormatException {
    throw TranslateException('HTTP ${response.statusCode}');
  }
  final data = json is Map ? json['Data'] : null;
  final out = data is Map ? data['Translated'] : null;
  if (out is String) return out;
  final message = json is Map ? json['Message'] : null;
  throw TranslateException(
    message is String
        ? tr('阿里报错:{0}', [_clip(message)])
        : 'HTTP ${response.statusCode}',
  );
};
