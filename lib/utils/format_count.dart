import 'package:bili_tv_app/utils/zh_convert.dart';

/// 數字格式化：超過一萬顯示「萬」，超過一億顯示「億」。
///
/// 英文模式（[ZhConvert.script] 為 english）改用 K／M／B：1000 以下照原數字，
/// 例如 123000 → 123K、120000000 → 120M、1234 → 1.2K。
String formatCount(int n) {
  if (ZhConvert.script == ZhScript.english) return _formatCountEnglish(n);
  if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}億';
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}萬';
  return n.toString();
}

String _formatCountEnglish(int n) {
  if (n < 1000) return n.toString();
  const units = ['K', 'M', 'B'];
  var value = n / 1000;
  var unit = 0;
  // 四捨五入到一位小數後若達 1000，進位到下一個單位
  while (unit < units.length - 1 &&
      double.parse(value.toStringAsFixed(1)) >= 1000) {
    value /= 1000;
    unit++;
  }
  var text = value.toStringAsFixed(1);
  if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
  return '$text${units[unit]}';
}
