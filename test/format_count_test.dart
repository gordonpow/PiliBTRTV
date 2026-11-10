import 'package:bili_tv_app/utils/format_count.dart';
import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(ZhConvert.resetForTest);

  test('中文模式維持萬／億', () {
    ZhConvert.script = ZhScript.traditional;
    expect(formatCount(999), '999');
    expect(formatCount(12300), '1.2萬');
    expect(formatCount(120000000), '1.2億');
  });

  test('英文模式用 K／M／B', () {
    ZhConvert.script = ZhScript.english;
    expect(formatCount(0), '0');
    expect(formatCount(999), '999');
    expect(formatCount(1000), '1K');
    expect(formatCount(1234), '1.2K');
    expect(formatCount(123000), '123K');
    expect(formatCount(120000000), '120M');
    expect(formatCount(1500000000), '1.5B');
    expect(formatCount(999950), '1M');
  });
}
