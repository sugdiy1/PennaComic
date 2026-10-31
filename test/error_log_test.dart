import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/services/error_log.dart';

void main() {
  test('错误日志:追加写入,Key 换成 ***,太大时旧的挪成 .old', () {
    final dir = Directory.systemTemp.createTempSync('penna_log');
    final file = File('${dir.path}/sub/error.log');
    final log = ErrorLog(file, secrets: () => ['sk-secret-123', 'abc']);

    log.write('第一条 https://x/?key=sk-secret-123');
    log.write('第二条 abc');
    final text = file.readAsStringSync();
    expect(text, contains('第一条 https://x/?key=***'));
    expect(text, isNot(contains('sk-secret-123')));
    // 太短的值不换。
    expect(text, contains('第二条 abc'));

    file.writeAsStringSync('x' * (ErrorLog.maxBytes + 1));
    log.write('第三条');
    expect(File('${file.path}.old').lengthSync(), ErrorLog.maxBytes + 1);
    expect(file.readAsStringSync(), contains('第三条'));
    expect(file.lengthSync(), lessThan(100));
    dir.deleteSync(recursive: true);
  });
}
