import 'dart:ffi' show Abi;

/// 播放效能的純函式與狀態：掉幀率、自動降畫質判斷、32 位元 4K 略過 BTR、log 格式。

/// 自動降畫質的掉幀率門檻（區間掉幀 ÷ 預期影格數）
const double kDropRateThreshold = 0.15;

/// 連續幾個區間超過門檻才降畫質
const int kDropIntervalsToDowngrade = 2;

/// 每部影片最多自動降幾次
const int kMaxAutoDowngrades = 2;

/// 統計區間秒數
const int kPerfIntervalSeconds = 10;

/// 掉幀率 = 區間掉幀 ÷（fps × 區間秒數）；fps 或秒數無效時回 0
double dropRate(int dropped, double fps, int seconds) {
  if (fps <= 0 || seconds <= 0 || dropped <= 0) return 0;
  return dropped / (fps * seconds);
}

/// 目前 ABI 是否為 32 位元 Android（armeabi-v7a／x86）
bool isProcess32Bit([Abi? abi]) {
  final a = abi ?? Abi.current();
  return a == Abi.androidArm || a == Abi.androidIA32;
}

/// 是否為 4K 串流：高 >= 2160 或 qn >= 120
bool is4kStream({int? qn, int? height}) =>
    (height ?? 0) >= 2160 || (qn ?? 0) >= 120;

/// 32 位元裝置播 4K 時略過 BTR 代理
bool shouldSkipBtr({required bool is32Bit, int? qn, int? height}) =>
    is32Bit && is4kStream(qn: qn, height: height);

/// qn 對應的畫面高度（只列 4K 以上，其餘回 0，不做同解析度過濾）
int _bigTierHeight(int qn) {
  if (qn >= 127) return 4320;
  if (qn >= 120) return 2160;
  return 0;
}

/// 4K 高幀率：qn >= 120 且 fps > 30
bool is4kHighFps({required int qn, required double fps}) =>
    qn >= 120 && fps > 30;

/// 已知此裝置 4K 60 幀不順時，自動選畫質的上限 qn（1080P60）
const int kKnownBad4k60CapQn = 116;

/// 自動選畫質的上限：已知 4K 60 幀不順、候選是 4K 高幀率、且不是使用者手動選時，
/// 回 [kKnownBad4k60CapQn]；其餘回 [qn] 本身（不限制）。
int autoQnCap({
  required int qn,
  required double fps,
  required bool known4k60Bad,
  required bool manual,
}) {
  if (manual || !known4k60Bad) return qn;
  return is4kHighFps(qn: qn, fps: fps) ? kKnownBad4k60CapQn : qn;
}

/// 在可用畫質中找比 [current] 低的下一級（qn 由大到小）。
/// 目前為 4K／8K 時，跳過同解析度的畫質（如 126／125／120），直接降到更低解析度。
int? nextLowerQn(Iterable<int> available, int current) {
  final curTier = _bigTierHeight(current);
  int? best;
  for (final q in available) {
    if (q >= current) continue;
    if (curTier > 0 && _bigTierHeight(q) == curTier) continue;
    if (best == null || q > best) best = q;
  }
  return best;
}

/// 兩次 /proc/self/stat 取樣的 CPU 使用率（百分比，已除以核心數）；資料無效回 null
double? cpuPercent({
  required int prevJiffies,
  required int prevElapsedMs,
  required int curJiffies,
  required int curElapsedMs,
  required int hz,
  required int cores,
}) {
  final dtMs = curElapsedMs - prevElapsedMs;
  final dj = curJiffies - prevJiffies;
  if (dtMs <= 0 || dj < 0 || hz <= 0 || cores <= 0) return null;
  return (dj / hz) / (dtMs / 1000) / cores * 100;
}

/// 每 10 秒那一行（不含 PerfLog 前綴）
String formatPerfLine({
  required int posSec,
  required int droppedInterval,
  required int droppedTotal,
  required double rate,
  required double offsetUs,
  required int rendered,
  required double bufSec,
  required double bandwidthBps,
  required double? cpu,
}) {
  final mbps = bandwidthBps / 1e6;
  final bw = mbps >= 10 ? mbps.round().toString() : mbps.toStringAsFixed(1);
  return 't=${posSec}s drop=$droppedInterval/$droppedTotal '
      '(${(rate * 100).toStringAsFixed(1)}%) '
      'offset=${offsetUs.round()}us rendered=$rendered '
      'buf=${bufSec.toStringAsFixed(1)}s bw=${bw}Mbps '
      'cpu=${cpu == null ? '?' : '${cpu.round()}%'}';
}

/// 自動降畫質的區間統計。每部影片（cid）一份，換片時 [resetForVideo]；
/// 重建播放器時只 [resetInterval]（保留降級次數與使用者選擇）。
class DowngradeTracker {
  int consecutive = 0;
  int autoCount = 0;
  bool userPicked = false;
  bool noLowerLevel = false;
  double lastRate = 0;

  void resetForVideo() {
    consecutive = 0;
    autoCount = 0;
    userPicked = false;
    noLowerLevel = false;
    lastRate = 0;
  }

  void resetInterval() {
    consecutive = 0;
    lastRate = 0;
  }

  /// 記錄一個完整的播放區間；回傳是否應該降畫質。
  /// 不會自行增加 [autoCount]，降級確定執行後呼叫 [commitDowngrade]。
  bool record(double rate, {required bool enabled}) {
    final prev = lastRate;
    lastRate = rate;
    if (!enabled ||
        userPicked ||
        noLowerLevel ||
        autoCount >= kMaxAutoDowngrades) {
      consecutive = 0;
      return false;
    }
    if (rate > kDropRateThreshold) {
      consecutive++;
    } else {
      consecutive = 0;
    }
    _prevRate = prev;
    return consecutive >= kDropIntervalsToDowngrade;
  }

  double _prevRate = 0;

  /// 觸發降級的前一個區間掉幀率（供 log）
  double get previousRate => _prevRate;

  void commitDowngrade() {
    autoCount++;
    consecutive = 0;
  }
}
