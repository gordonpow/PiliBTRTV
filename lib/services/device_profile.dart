import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:flutter/services.dart';

/// 記憶體等級：依總記憶體靜態分級，或依即時可用記憶體進入 critical。
enum MemoryTier { critical, low, mid, high }

/// 裝置等級資訊：用來在低記憶體裝置上降低預載與快取量。
class DeviceProfile {
  DeviceProfile._();

  static const _channel = MethodChannel('com.bili.tv/codec');

  /// 總記憶體上限（MB）：2.25GB 以下視為低記憶體裝置
  static const int lowMemoryThresholdMb = 2304;

  /// 是否為低記憶體裝置；[init] 之前為 false。
  /// NavSettle 與舊有呼叫端使用此 getter，不改介面。
  static bool get lowMemory => staticTier == MemoryTier.low;

  // 允許測試直接設定（nav_settle_test.dart 使用 DeviceProfile.lowMemory = true）
  static set lowMemory(bool v) {
    // 測試用：覆寫 staticTier 以模擬低記憶體裝置
    staticTier = v ? MemoryTier.low : MemoryTier.mid;
  }

  /// 靜態記憶體等級（依總記憶體決定，啟動時查一次）
  static MemoryTier staticTier = MemoryTier.mid;

  /// 目前的記憶體等級（可能因即時可用記憶體而進入 critical）
  static MemoryTier get currentTier => tierNotifier.value;

  /// 通知其他服務記憶體等級已改變
  static final ValueNotifier<MemoryTier> tierNotifier =
      ValueNotifier<MemoryTier>(MemoryTier.mid);

  // ---- 監控狀態（可注入，供測試使用）----

  static const Duration _monitorInterval = Duration(seconds: 15);
  static Timer? _monitorTimer;

  /// 連續兩次「不符合 critical」才離開 critical
  static int _exitCount = 0;

  // ---- 純函式（可測試）----

  /// [isLowRam] 為 true，或 [totalMemMb] 在 1 到 2304 之間時回傳 true。
  static bool isLowMemory({bool? isLowRam, int? totalMemMb}) {
    if (isLowRam == true) return true;
    return totalMemMb != null &&
        totalMemMb > 0 &&
        totalMemMb <= lowMemoryThresholdMb;
  }

  /// 依總記憶體與 isLowRam 決定靜態等級
  static MemoryTier tierFor({
    required int totalMemMb,
    required bool isLowRam,
  }) {
    if (isLowRam || (totalMemMb > 0 && totalMemMb <= 2304)) {
      return MemoryTier.low;
    }
    if (totalMemMb > 0 && totalMemMb <= 4096) return MemoryTier.mid;
    if (totalMemMb > 4096) return MemoryTier.high;
    return MemoryTier.mid; // 查詢失敗
  }

  /// 判斷是否應進入 critical
  static bool isCritical({
    required int availMb,
    required int thresholdMb,
    required bool lowMemory,
  }) {
    if (lowMemory) return true;
    final minAvail = (thresholdMb * 1.5).ceil();
    return availMb < (minAvail > 300 ? minAvail : 300);
  }

  // ---- 初始化 ----

  /// 讀取裝置資訊並設定 [staticTier]；失敗時維持 mid，不丟例外。
  static Future<void> init() async {
    try {
      final r = await _channel.invokeMethod<dynamic>('getDeviceInfo');
      if (r is! Map) return;
      final isLowRam = r['isLowRam'];
      final total = r['totalMemMb'];
      staticTier = tierFor(
        totalMemMb: total is num ? total.toInt() : 0,
        isLowRam: isLowRam is bool ? isLowRam : false,
      );
    } catch (_) {
      staticTier = MemoryTier.mid;
    }
    // 以靜態等級初始化通知器（尚未進入 critical）
    tierNotifier.value = staticTier;
    debugPrint('🧠 [Memory] init tier=${staticTier.name}');
  }

  // ---- 即時監控 ----

  /// 啟動每 15 秒查詢一次記憶體狀態的監控計時器。
  /// [queryFn] 可注入（測試用），null 時使用真實 MethodChannel。
  static void startMonitor({
    Future<Map<String, dynamic>?> Function()? queryFn,
  }) {
    _monitorTimer?.cancel();
    _exitCount = 0;
    _monitorTimer = Timer.periodic(_monitorInterval, (_) async {
      await _queryAndUpdate(queryFn);
    });
  }

  /// 停止監控計時器（App 進入背景時呼叫）
  static void stopMonitor() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  /// 系統回報記憶體壓力（由 main.dart 的 didHaveMemoryPressure 呼叫）
  static void onMemoryPressure() {
    _exitCount = 0;
    _applyTier(MemoryTier.critical, 'system pressure', 0, 0);
  }

  /// 測試用：直接執行一次查詢並更新等級（不依賴計時器）
  static Future<void> queryAndUpdateForTest(
    Future<Map<String, dynamic>?> Function() queryFn,
  ) => _queryAndUpdate(queryFn);

  /// 測試用：重置所有監控狀態（離開計數、計時器、等級）
  static void resetForTest({MemoryTier tier = MemoryTier.mid}) {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _exitCount = 0;
    staticTier = tier;
    tierNotifier.value = tier;
  }

  static Future<void> _queryAndUpdate(
    Future<Map<String, dynamic>?> Function()? queryFn,
  ) async {
    try {
      final Map<String, dynamic>? data;
      if (queryFn != null) {
        data = await queryFn();
      } else {
        final r = await _channel.invokeMethod<dynamic>('getMemoryState');
        data = r is Map
            ? {
                'availMemMb': r['availMemMb'],
                'thresholdMb': r['thresholdMb'],
                'lowMemory': r['lowMemory'],
              }
            : null;
      }
      if (data == null) return;

      final availMb = (data['availMemMb'] as num?)?.toInt() ?? 0;
      final thresholdMb = (data['thresholdMb'] as num?)?.toInt() ?? 0;
      final sysLow = data['lowMemory'] == true;

      final shouldBeCritical = isCritical(
        availMb: availMb,
        thresholdMb: thresholdMb,
        lowMemory: sysLow,
      );

      if (shouldBeCritical) {
        _exitCount = 0;
        if (currentTier != MemoryTier.critical) {
          final reason = sysLow
              ? 'system low'
              : 'avail=${availMb}MB < threshold=${thresholdMb}MB*1.5';
          _applyTier(MemoryTier.critical, reason, availMb, thresholdMb);
        }
      } else {
        if (currentTier == MemoryTier.critical) {
          _exitCount++;
          if (_exitCount >= 2) {
            _exitCount = 0;
            _applyTier(
              staticTier,
              'recovered (avail=${availMb}MB)',
              availMb,
              thresholdMb,
            );
          } else {
            debugPrint(
              '🧠 [Memory] still critical (exit check $_exitCount/2) '
              'avail=${availMb}MB',
            );
          }
        }
        // 非 critical 狀態：不做任何改變
      }
    } catch (e) {
      debugPrint('🧠 [Memory] monitor error: $e');
    }
  }

  static void _applyTier(
    MemoryTier tier,
    String reason,
    int availMb,
    int thresholdMb,
  ) {
    debugPrint(
      '🧠 [Memory] tier=${tier.name} avail=${availMb}MB reason=$reason',
    );
    tierNotifier.value = tier;
  }
}
