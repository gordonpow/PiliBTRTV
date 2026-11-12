import 'dart:io';

import 'package:bili_tv_app/btr_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // App 內顯示版本、更新檢查、錯誤回報都用 btrVersion；
  // 發布時若只改 pubspec.yaml 而漏改常數，更新提示會一直出現（#42）。
  test('btrVersion 與 pubspec.yaml 的版本一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml 找不到 version');
    final name = match!.group(1)!.split('+').first;
    expect(btrVersion, 'v$name',
        reason: '請同步更新 lib/btr_version.dart 的 defaultValue');
  });
}
