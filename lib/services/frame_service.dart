import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 影片畫面幀擷取服務 (串接原生 MediaMetadataRetriever)
class FrameService {
  static const MethodChannel _channel = MethodChannel('com.bili.tv/frame');
  static const int _maxCacheSize = 30;

  // 使用 LinkedHashMap 維護 LRU 快取（以插入/存取順序排列）
  static final LinkedHashMap<String, Uint8List> _cache =
      LinkedHashMap<String, Uint8List>();

  static int _requestIdCounter = 0;

  // 逾時 log 最多每 5 秒一次，略過的次數在下一次輸出時附上
  static const Duration _timeoutLogInterval = Duration(seconds: 5);
  static DateTime? _lastTimeoutLog;
  static int _skippedTimeoutLogs = 0;

  /// 獲取特定時間點的畫面幀
  ///
  /// [url] 影片串流網址
  /// [t] 欲擷取的時間點
  /// [width] 圖片寬度，預設 480
  static Future<Uint8List?> getFrame(
    String url,
    Duration t, {
    int width = 480,
  }) async {
    if (url.isEmpty) return null;

    final key = '$url:${t.inSeconds}';

    // 1. 檢查 LRU 快取
    if (_cache.containsKey(key)) {
      final cached = _cache.remove(key)!;
      _cache[key] = cached; // 移至最新位置
      return cached;
    }

    final requestId = ++_requestIdCounter;

    try {
      // 2. 呼叫原生抽幀
      final future = _channel.invokeMethod('getFrame', {
        'url': url,
        'timeMs': t.inMilliseconds,
        'width': width,
      });

      // 逾時處理：3 秒逾時，逾時先回傳 null；若原生結果稍後完成仍存入快取 (審查紀錄 3)
      final dynamic raw = await future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          final now = DateTime.now();
          final last = _lastTimeoutLog;
          if (last == null || now.difference(last) >= _timeoutLogInterval) {
            final skipped = _skippedTimeoutLogs > 0
                ? '（另有 $_skippedTimeoutLogs 次略過）'
                : '';
            _skippedTimeoutLogs = 0;
            _lastTimeoutLog = now;
            debugPrint(
              '🎬 [FrameService] 抽幀逾時: $key (req: $requestId)$skipped',
            );
          } else {
            _skippedTimeoutLogs++;
          }
          future
              .then((res) {
                final lateBytes = _extractBytes(res);
                if (lateBytes != null && lateBytes.isNotEmpty) {
                  _putCache(key, lateBytes);
                }
              })
              .catchError((_) {});
          return null;
        },
      );

      final bytes = _extractBytes(raw);
      if (bytes != null && bytes.isNotEmpty) {
        _putCache(key, bytes);
      }

      // 同時只保留最新一個等待中的請求；較舊的結果回來若已不是最新，只存快取不通知
      if (requestId != _requestIdCounter) {
        return null;
      }

      return bytes;
    } catch (e) {
      debugPrint('🎬 [FrameService] 抽幀失敗: $e');
      return null;
    }
  }

  static Uint8List? _extractBytes(dynamic raw) {
    if (raw == null) return null;
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    return null;
  }

  static void _putCache(String key, Uint8List bytes) {
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= _maxCacheSize) {
      // 移除最舊的項目 (開頭的 key)
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }
    _cache[key] = bytes;
  }

  /// 釋放原生抽幀器與重置請求狀態
  static Future<void> release() async {
    _requestIdCounter++;
    try {
      await _channel.invokeMethod('release');
    } catch (e) {
      debugPrint('🎬 [FrameService] 釋放失敗: $e');
    }
  }

  @visibleForTesting
  static void clearCache() {
    _cache.clear();
    _requestIdCounter = 0;
  }
}
