/// 按住方向鍵快轉的速度（秒／秒）。
///
/// 前 1 秒 30、1～3 秒 90、3 秒後取 `max(180, 片長秒數 / 20)`。
double holdSeekSpeed(Duration held, Duration total) {
  if (held < const Duration(seconds: 1)) return 30;
  if (held < const Duration(seconds: 3)) return 90;
  final byLength = total.inMilliseconds / 1000 / 20;
  return byLength > 180 ? byLength : 180;
}
