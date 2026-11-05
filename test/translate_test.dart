import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/translate_engines.dart';

Translator _ok(String out) =>
    (_, _, _, _) async => out;

Future<TranslateResult> _run(
  List<(String, Translator)> chain, {
  int attempts = 3,
  Duration timeout = const Duration(seconds: 5),
}) => translateWithFailover(
  chain: chain,
  text: 'hi',
  from: 'en',
  to: 'zh',
  attempts: attempts,
  timeout: timeout,
);

void main() {
  group('按顺序切换引擎', () {
    test('第一个引擎连续失败满次数后才换下一个', () async {
      var calls = 0;
      Future<String> flaky(_, _, _, _) async {
        calls++;
        throw const TranslateException('坏了');
      }

      final result = await _run([('a', flaky), ('b', _ok('你好'))]);

      expect(calls, 3);
      expect(result.text, '你好');
      expect(result.engineId, 'b');
      expect(result.failures, hasLength(3));
    });

    test('重试中途成功就不再换', () async {
      var calls = 0;
      Future<String> second(_, _, _, _) async {
        if (++calls < 2) throw const TranslateException('坏了');
        return '好';
      }

      final result = await _run([('a', second), ('b', _ok('不该用到'))]);

      expect(result.engineId, 'a');
      expect(calls, 2);
    });

    test('超时算一次失败', () async {
      Future<String> slow(_, _, _, _) => Completer<String>().future;

      final result = await _run(
        [('slow', slow), ('b', _ok('好'))],
        attempts: 2,
        timeout: const Duration(milliseconds: 30),
      );

      expect(result.engineId, 'b');
      expect(result.failures, ['slow 第 1 次:超时', 'slow 第 2 次:超时']);
    });

    test('缺凭据的引擎不重试,直接换下一个', () async {
      var calls = 0;
      Future<String> unconfigured(_, _, _, _) async {
        calls++;
        throw const TranslateConfigException('没填 Key');
      }

      final result = await _run([('a', unconfigured), ('b', _ok('好'))]);

      expect(calls, 1);
      expect(result.engineId, 'b');
    });

    test('全部失败时报错并列出每次的原因;认不出的异常不原样转述', () async {
      Future<String> leaky(_, _, _, _) async =>
          throw StateError('url?key=sk-secret');

      await expectLater(
        _run([('a', leaky)], attempts: 1),
        throwsA(
          isA<TranslateException>()
              .having((e) => e.message, 'message', contains('a 第 1 次'))
              .having((e) => e.message, 'message', isNot(contains('sk-'))),
        ),
      );
    });

    test('一个引擎都没启用时直接报错', () {
      expect(_run([]), throwsA(isA<TranslateException>()));
    });
  });

  group('分段', () {
    test('每段不超过字节上限,拼回去内容不丢', () {
      final text = List.filled(40, 'a cybernetic android, 雨夜的霓虹.').join(' ');

      final chunks = splitByBytes(text, 100);

      expect(chunks.every((c) => utf8.encode(c).length <= 100), isTrue);
      expect(chunks.join().replaceAll(' ', ''), text.replaceAll(' ', ''));
    });

    test('没有标点和空格的超长内容也能切开', () {
      final chunks = splitByBytes('字' * 100, 30);

      expect(chunks.every((c) => utf8.encode(c).length <= 30), isTrue);
      expect(chunks.join(), '字' * 100);
    });
  });

  test('阿里云签名:空格、星号、波浪号按它的规则编码', () {
    expect(aliPercentEncode('a b*c~d/e'), 'a%20b%2Ac~d%2Fe');
  });

  group('翻译设置', () {
    test('默认只启用免费引擎,且排在最前', () {
      const cfg = AppConfig();

      expect(cfg.mtChain, ['google_free', 'mymemory']);
      expect(cfg.mtAttempts, 3);
      expect(cfg.mtTimeoutSeconds, 25);
    });

    test('旧版配置(没有顺序)升级后用新默认', () {
      final cfg = AppConfig.fromJson({'mtEnabled': <String>[]});

      expect(cfg.mtChain, ['google_free', 'mymemory']);
    });

    test('读取时补全漏掉的引擎、丢掉不认识的,并把数值限制在范围内', () {
      final cfg = AppConfig.fromJson({
        'mtOrder': ['baidu', 'nope', 'mymemory'],
        'mtEnabled': ['baidu'],
        'mtAttempts': 99,
        'mtTimeoutSeconds': 0,
      });

      expect(cfg.mtOrder.take(2), ['baidu', 'mymemory']);
      expect(cfg.mtOrder.toSet(), {for (final e in mtEngines) e.id});
      expect(cfg.mtChain, ['baidu']);
      expect(cfg.mtAttempts, maxMtAttempts);
      expect(cfg.mtTimeoutSeconds, minMtTimeoutSeconds);
    });

    test('保存再读取,顺序和规则不变', () {
      final saved = const AppConfig()
          .copyWith(
            mtOrder: ['baidu', 'ali', 'google', 'mymemory', 'google_free'],
            mtEnabled: {'baidu', 'mymemory'},
            mtAttempts: 5,
            mtTimeoutSeconds: 10,
          )
          .toJson();

      final cfg = AppConfig.fromJson(jsonDecode(jsonEncode(saved)));

      expect(cfg.mtChain, ['baidu', 'mymemory']);
      expect(cfg.mtAttempts, 5);
      expect(cfg.mtTimeoutSeconds, 10);
    });
  });
}
