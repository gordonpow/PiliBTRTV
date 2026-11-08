import 'package:flutter/services.dart';
import 'package:bili_tv_app/services/log_service.dart';

/// 閃退回報服務：透過 MethodChannel 取得上次崩潰紀錄並去識別化
class CrashReportService {
  CrashReportService._();

  static const MethodChannel _channel = MethodChannel('com.bili.tv/crash');

  /// 取得上次閃退資訊，若無閃退或已確認過則回傳 null。
  static Future<Map<String, dynamic>?> lastCrash() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getLastCrash',
      );
      if (res == null) return null;
      return Map<String, dynamic>.from(res);
    } catch (_) {
      return null;
    }
  }

  /// 確認已處理此時間戳記的閃退。
  static Future<void> ack(int ts) async {
    try {
      await _channel.invokeMethod<void>('ackCrash', {'timestamp': ts});
    } catch (_) {}
  }

  /// 格式化閃退資訊為文字區塊，每行皆經由 sanitizeLogLine 去識別化。
  static String format(Map<dynamic, dynamic> crash) {
    final b = StringBuffer();
    b.writeln('== 上次閃退 ==');

    final rawReason = crash['reason']?.toString() ?? '未知';
    final String reasonText;
    switch (rawReason) {
      case 'crash':
        reasonText = 'Java/Kotlin 例外崩潰 (crash)';
        break;
      case 'native':
        reasonText = '原生崩潰 (native crash)';
        break;
      case 'anr':
        reasonText = '無回應 (ANR)';
        break;
      default:
        reasonText = rawReason;
    }
    b.writeln(sanitizeLogLine('原因: $reasonText'));

    final ts = crash['timestamp'];
    if (ts is num) {
      final dt = DateTime.fromMillisecondsSinceEpoch(ts.toInt()).toLocal();
      b.writeln(sanitizeLogLine('時間: $dt ($ts)'));
    }

    final desc = crash['description']?.toString();
    if (desc != null && desc.trim().isNotEmpty) {
      final lines = desc.split('\n');
      if (lines.length == 1) {
        b.writeln(sanitizeLogLine('描述: $desc'));
      } else {
        b.writeln(sanitizeLogLine('描述:'));
        for (final l in lines) {
          if (l.isNotEmpty) b.writeln(sanitizeLogLine(l));
        }
      }
    }

    final stack = crash['stack']?.toString();
    if (stack != null && stack.trim().isNotEmpty) {
      b.writeln(sanitizeLogLine('堆疊:'));
      for (final line in stack.split('\n')) {
        if (line.isNotEmpty) {
          b.writeln(sanitizeLogLine(line));
        }
      }
    }

    final trace = crash['trace']?.toString();
    if (trace != null && trace.trim().isNotEmpty) {
      b.writeln(sanitizeLogLine('系統 Trace:'));
      for (final line in trace.split('\n')) {
        if (line.isNotEmpty) {
          b.writeln(sanitizeLogLine(line));
        }
      }
    }

    return b.toString().trimRight();
  }
}
