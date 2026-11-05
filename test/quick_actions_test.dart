import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';

AppConfig _reload(AppConfig config) =>
    AppConfig.fromJson(jsonDecode(jsonEncode(config.toJson())));

void main() {
  test('旧配置没有快捷操作时给默认的两个', () {
    final config = AppConfig.fromJson(<String, dynamic>{});

    expect(config.quickActions.map((a) => a.label), ['转成自然语言', '转成 Tag']);
    expect(config.quickActions.every((a) => a.prompt.isNotEmpty), isTrue);
  });

  test('改过的快捷操作存盘后还在', () {
    const config = AppConfig(quickActions: [(label: '加雨', prompt: '给画面加上雨天')]);

    expect(_reload(config).quickActions, [(label: '加雨', prompt: '给画面加上雨天')]);
  });

  test('用户删空了就是空的,不会又变回默认', () {
    expect(_reload(const AppConfig(quickActions: [])).quickActions, isEmpty);
  });
}
