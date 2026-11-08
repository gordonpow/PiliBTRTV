import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

final RegExp _reCookie = RegExp(r'cookie:.*', caseSensitive: false);
final RegExp _reUrl = RegExp(
  r'''https?://[^\s'")>\]]+''',
  caseSensitive: false,
);
final RegExp _reSecret = RegExp(
  r'''\b(SESSDATA|bili_jct|buvid\d*|b_nut|DedeUserID\w*|access_key|access_token|refresh_token|csrf|w_rid|mid|uid)(["']?\s*[=:]\s*["']?)[^\s;&,"'}\)\]]+''',
  caseSensitive: false,
);
final RegExp _reIpv4 = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b');
final RegExp _reSearchStatus = RegExp(r'(code=-?\d+|HTTP \d{3})');

/// 去識別化單行 log：寫入記憶體與檔案之前一律先經過這個函式。
String sanitizeLogLine(String line) {
  // 搜尋關鍵字可能出現在內容或例外訊息中，只保留狀態碼
  if (line.trimLeft().startsWith('searchVideos')) {
    final m = _reSearchStatus.firstMatch(line);
    return m == null ? 'searchVideos: (內容已省略)' : 'searchVideos: ${m.group(0)}';
  }
  var s = line.replaceAll(_reCookie, 'Cookie: ***');
  s = s.replaceAllMapped(_reUrl, (m) {
    final url = m.group(0)!;
    final cut = url.indexOf(RegExp(r'[?#]'));
    return cut < 0 ? url : url.substring(0, cut);
  });
  s = s.replaceAllMapped(_reSecret, (m) => '${m.group(1)}${m.group(2)}***');
  s = s.replaceAll(_reIpv4, 'x.x.x.x');
  return s;
}

/// App 內部 log：覆寫 debugPrint、捕捉錯誤，去識別化後存在記憶體與檔案。
class LogService {
  LogService._();

  static const int maxLines = 300;
  static const int _maxFileBytes = 512 * 1024;

  static final List<String> _lines = [];
  static File? _file;
  static Future<void> _queue = Future.value();
  static int _writeCount = 0;

  static Future<void> init() async {
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      if (message != null) add(message);
    };

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (originalOnError != null) {
        originalOnError(details);
      } else {
        FlutterError.presentError(details);
      }
      add('FlutterError: ${details.exceptionAsString()}');
      final stack = details.stack;
      if (stack != null) add(stack.toString());
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      recordError(error, stack);
      return true;
    };

    try {
      final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/logs',
      );
      await dir.create(recursive: true);
      _file = File('${dir.path}/app.log');
      await _rotateIfNeeded();
    } catch (_) {
      _file = null;
    }
    add('=== App 啟動 ===');
  }

  static void recordError(Object error, StackTrace? stack) {
    add('Uncaught: $error');
    if (stack != null) add(stack.toString());
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// 加入一則 log（可含多行），先去識別化再保存。
  static void add(String message) {
    final now = DateTime.now();
    final ts =
        '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final out = StringBuffer();
    for (final raw in message.split('\n')) {
      if (raw.trim().isEmpty) continue;
      final line = '$ts ${sanitizeLogLine(raw)}';
      _lines.add(line);
      out.writeln(line);
    }
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
    final file = _file;
    if (file == null || out.isEmpty) return;
    final text = out.toString();
    _queue = _queue.then((_) async {
      try {
        await file.writeAsString(text, mode: FileMode.append, flush: false);
        if (++_writeCount % 50 == 0) await _rotateIfNeeded();
      } catch (_) {}
    });
  }

  static Future<void> _rotateIfNeeded() async {
    final file = _file;
    if (file == null || !await file.exists()) return;
    if (await file.length() > _maxFileBytes) {
      final old = File('${file.path}.1');
      if (await old.exists()) await old.delete();
      await file.rename(old.path);
    }
  }

  /// 取得最近 [maxLines] 行（含前一次執行留下的紀錄）。
  static Future<List<String>> recentLines() async {
    await _queue;
    final file = _file;
    if (file == null) return List.of(_lines);
    final all = <String>[];
    try {
      final old = File('${file.path}.1');
      if (await old.exists()) all.addAll(await old.readAsLines());
      if (await file.exists()) all.addAll(await file.readAsLines());
    } catch (_) {
      return List.of(_lines);
    }
    return all.length > maxLines ? all.sublist(all.length - maxLines) : all;
  }
}
