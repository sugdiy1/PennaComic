import '../models/app_config.dart';
import 'translate_engines.dart';
import '../../l10n/l10n.dart';

typedef ConfigTranslator = Future<TranslateResult> Function(
  AppConfig config,
  String text,
);

String mtLabel(String id) => mtEngines.firstWhere((e) => e.id == id).label;

// ponytail: 原文固定当英文(成稿是英文,译文给人核对);要自动识别原文语言时再加参数。
/// 按设置里的引擎顺序、尝试次数和超时翻译 [text],译成界面语言对应的对照语言
/// (`AppConfig.glossLanguage`;英文界面不用对照,真调到了就按简体中文)。
Future<TranslateResult> translateWithConfig(AppConfig config, String text) {
  return translateWithFailover(
    chain: [for (final id in config.mtChain) (id, _engine(config, id))],
    text: text,
    from: 'en',
    to: config.glossLanguage ?? 'zh',
    attempts: config.mtAttempts,
    timeout: Duration(seconds: config.mtTimeoutSeconds),
  );
}

Translator _engine(AppConfig config, String id) {
  String value(String field) {
    final key = 'mt.$id.$field';
    return config.secrets[key] ?? config.fields[key] ?? '';
  }

  return switch (id) {
    'google_free' => googleFree,
    'mymemory' => myMemory,
    'google' => googleCloud(value('key')),
    'ali' => ali(value('id'), value('secret')),
    'baidu' => baidu(value('appid'), value('secret')),
    _ => throw StateError(tr('未知翻译引擎:{0}', [id])),
  };
}
