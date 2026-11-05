import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/ui/shell.dart';

void main() {
  test('界面上的版本号和 pubspec.yaml 一致', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('\nversion: $appVersion+'),
    );
  });
}
