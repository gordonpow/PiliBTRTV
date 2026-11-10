import 'package:bili_tv_app/services/log_service.dart' show sanitizeLogLine;
import 'package:flutter/foundation.dart';

/// 播放效能專用 log：獨立環形緩衝，不會被一般 log 擠掉，供錯誤報告輸出。
class PerfLog {
  PerfLog._();

  static const int maxLines = 200;
  static final List<String> _lines = [];

  static List<String> get lines => List.unmodifiable(_lines);

  static void add(String message) {
    final line = sanitizeLogLine(message);
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _lines.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} $line');
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
    debugPrint('📈 [Perf] $line');
  }

  @visibleForTesting
  static void clear() => _lines.clear();
}
