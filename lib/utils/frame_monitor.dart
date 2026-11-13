import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 掉幀統計：每 5 秒在 log 印出超過 16.7ms 的幀數與最慢的 build／raster 時間。
/// 只在有掉幀的區間才輸出，供 logcat 量測卡頓（`⏱ [Jank]`）。
class FrameMonitor {
  FrameMonitor._();

  static bool _started = false;
  static int _total = 0;
  static int _slow = 0;
  static int _maxBuild = 0;
  static int _maxRaster = 0;
  static DateTime _windowStart = DateTime.now();

  static void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _total++;
      final build = t.buildDuration.inMicroseconds;
      final raster = t.rasterDuration.inMicroseconds;
      if (t.totalSpan.inMicroseconds > 16700) _slow++;
      if (build > _maxBuild) _maxBuild = build;
      if (raster > _maxRaster) _maxRaster = raster;
    }
    final now = DateTime.now();
    if (now.difference(_windowStart).inSeconds < 5) return;
    if (_slow > 0) {
      debugPrint(
        '⏱ [Jank] slow $_slow/$_total '
        'maxBuild ${(_maxBuild / 1000).toStringAsFixed(1)}ms '
        'maxRaster ${(_maxRaster / 1000).toStringAsFixed(1)}ms',
      );
    }
    _total = 0;
    _slow = 0;
    _maxBuild = 0;
    _maxRaster = 0;
    _windowStart = now;
  }
}
