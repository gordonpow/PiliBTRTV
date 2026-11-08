/// 數字格式化：超過一萬顯示「萬」，超過一億顯示「億」。
String formatCount(int n) {
  if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}億';
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}萬';
  return n.toString();
}
