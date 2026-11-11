import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../services/device_profile.dart';

/// 判斷方向鍵是否長按中，並決定卡片焦點停穩後多久才啟動預載／預覽。
class NavSettle {
  NavSettle._();
  static final NavSettle instance = NavSettle._();

  static final _arrows = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  /// 長按門檻：按下超過此時間視為長按
  static const _holdThreshold = Duration(milliseconds: 150);

  final Map<LogicalKeyboardKey, DateTime> _downAt = {};
  DateTime? _lastFocusAt;
  final List<DateTime> _recentFocus = [];
  bool _registered = false;

  void _ensureRegistered() {
    if (_registered) return;
    _registered = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    final key = event.logicalKey;
    if (_arrows.contains(key)) {
      if (event is KeyDownEvent) {
        _downAt[key] = DateTime.now();
      } else if (event is KeyRepeatEvent) {
        // handler 註冊前就按住的鍵：從第一個 repeat 開始算（必然已超過門檻）
        _downAt.putIfAbsent(
          key,
          () => DateTime.now().subtract(_holdThreshold * 2),
        );
      } else if (event is KeyUpEvent) {
        _downAt.remove(key);
      }
    }
    // 不吃按鍵
    return false;
  }

  /// 任一方向鍵目前按住且已超過 150ms
  bool get isHeld {
    _ensureRegistered();
    if (_downAt.isEmpty) return false;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final now = DateTime.now();
    for (final e in _downAt.entries) {
      if (pressed.contains(e.key) && now.difference(e.value) > _holdThreshold) {
        return true;
      }
    }
    return false;
  }

  /// 測試用：清除取得焦點紀錄
  @visibleForTesting
  void resetForTest() {
    _lastFocusAt = null;
    _recentFocus.clear();
    _downAt.clear();
  }

  /// 卡片取得焦點時呼叫，回傳要等多久再啟動；並更新取得焦點時間。
  /// 2 秒內（含這次）達 3 次視為連續移動，等待更久。[now] 只給測試用。
  Duration onFocusArrived({DateTime? now}) {
    _ensureRegistered();
    now ??= DateTime.now();
    final last = _lastFocusAt;
    _lastFocusAt = now;
    _recentFocus.removeWhere(
      (t) => now!.difference(t) > const Duration(seconds: 2),
    );
    _recentFocus.add(now);
    final burst = _recentFocus.length >= 3;
    final single =
        (last == null || now.difference(last).inMilliseconds >= 300) &&
        !isHeld;
    final low = DeviceProfile.lowMemory;
    if (burst) return Duration(milliseconds: low ? 600 : 500);
    if (single) return Duration(milliseconds: low ? 300 : 150);
    return Duration(milliseconds: low ? 300 : 250);
  }
}
