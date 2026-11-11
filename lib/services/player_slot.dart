import 'dart:async';

/// 播放器名額：同一時間只允許一個播放器處於建立／釋放中（不依賴 Flutter）。
///
/// 取得名額的人必須在播放器完全釋放後呼叫 [release]。
/// 萬一漏釋放，等待者在 [acquire] 的 maxWait 之後會強制取得，避免永遠卡住。
class PlayerSlot {
  Object? _holder;
  final List<Completer<void>> _waiters = [];

  bool get busy => _holder != null;

  /// 取得名額；被占用時依序等待。
  /// 每次被喚醒都檢查 [cancelled]，為 true 回 null。
  /// 等待超過 [maxWait] 時強制取得。成功回傳 token。
  Future<Object?> acquire({
    required bool Function() cancelled,
    Duration maxWait = const Duration(seconds: 12),
  }) async {
    final watch = Stopwatch()..start();
    while (true) {
      if (cancelled()) {
        _wakeNext();
        return null;
      }
      if (_holder == null) return _holder = Object();
      final remaining = maxWait - watch.elapsed;
      if (remaining <= Duration.zero) return _holder = Object();
      final c = Completer<void>();
      _waiters.add(c);
      await c.future.timeout(remaining, onTimeout: () {});
      _waiters.remove(c);
    }
  }

  /// 釋放名額；可重複呼叫，只有目前持有者的 token 有效。
  void release(Object? token) {
    if (token == null || !identical(_holder, token)) return;
    _holder = null;
    _wakeNext();
  }

  void _wakeNext() {
    if (_holder != null) return;
    for (final c in _waiters) {
      if (!c.isCompleted) {
        c.complete();
        return;
      }
    }
  }
}
