import 'package:bili_tv_app/screens/home/settings/settings_index.dart';
import 'package:flutter_test/flutter_test.dart';

// 測試用的簡單繁簡轉換：只轉幾個字
String _fakeConvert(String s) => s.replaceAll('弹', '彈').replaceAll('设', '設');

void main() {
  test('空白 query 回傳空清單', () {
    expect(SettingsIndex.search('  '), isEmpty);
  });

  test('比對 label 與 subtitle，不分大小寫', () {
    expect(SettingsIndex.search('cdn').map((e) => e.label), contains('CDN 模式'));
    expect(SettingsIndex.search('倒數後播下一部'), isNotEmpty);
    expect(SettingsIndex.search('連播倒數'), isNotEmpty);
    expect(SettingsIndex.search('迷你')[0].label, '迷你進度條');
  });

  test('簡體 query 找到繁體項目', () {
    final r = SettingsIndex.search('弹幕', convert: _fakeConvert);
    expect(r.map((e) => e.label), contains('彈幕遮蔽'));
  });

  test('找不到時回傳空清單', () {
    expect(SettingsIndex.search('zzzzqqq'), isEmpty);
  });
}
