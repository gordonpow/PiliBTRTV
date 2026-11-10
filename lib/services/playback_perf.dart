import 'dart:ffi' show Abi;

import 'settings_service.dart' show VideoCodec;

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

/// 判斷為解碼卡住所需的連續緩衝秒數
const int kStallBufferingSeconds = 8;

/// 判斷為解碼卡住所需的已緩衝毫秒數（播放位置之後）
const int kStallBufferedAheadMs = 10000;

/// 首選編碼為自動時的編碼家族順序。
/// [fallbackToAvc] 優先；[preferHevc]（隧道模式 4K 高幀率）時 HEVC 排在 AV1 前。
List<String> autoCodecOrder({
  required bool fallbackToAvc,
  required bool preferHevc,
}) {
  if (fallbackToAvc) return const ['avc'];
  if (preferHevc) return const ['hevc', 'av1', 'avc'];
  return const ['av1', 'hevc', 'avc'];
}

/// 是否為 4K 高幀率串流：高 >= 2160 且（fps > 30 或 fps 解析不到＝0，視為高幀率）
bool is4kHighFps({required int height, required double fps}) =>
    height >= 2160 && (fps > 30 || fps <= 0);

/// 是否判定為解碼卡住：使用者想播放、原生狀態為緩衝中超過門檻，
/// 但播放位置之後已有足夠資料（排除單純網路慢）。
bool isDecoderStall({
  required bool playWhenReady,
  required int? playbackState,
  required Duration bufferingFor,
  required int? bufferedAheadMs,
}) =>
    playWhenReady &&
    playbackState == 2 &&
    bufferingFor >= const Duration(seconds: kStallBufferingSeconds) &&
    bufferedAheadMs != null &&
    bufferedAheadMs >= kStallBufferedAheadMs;

/// 卡住時的下一個編碼：av01 -> hevc、hev -> avc、avc -> null；跳過 [tried] 已有的家族。
VideoCodec? nextStallCodec(String currentCodec, Set<String> tried) {
  final c = currentCodec.toLowerCase();
  final String cur;
  if (c.startsWith('av01') || c.startsWith('av1')) {
    cur = 'av01';
  } else if (c.startsWith('hev') || c.startsWith('hvc')) {
    cur = 'hev';
  } else {
    cur = 'avc';
  }
  const chain = <String, VideoCodec>{
    'av01': VideoCodec.hevc,
    'hev': VideoCodec.avc,
  };
  const order = ['av01', 'hev', 'avc'];
  for (var i = order.indexOf(cur); i < order.length - 1; i++) {
    final next = chain[order[i]]!;
    if (!tried.contains(next.prefix)) return next;
  }
  return null;
}

/// 解碼卡住的 PerfLog 一行（不含前綴）
String formatStallLog({
  required String from,
  required String? to,
  required int bufferingSec,
  required double bufferedAheadSec,
}) {
  final tail =
      '緩衝=${bufferingSec}s 已緩衝=${bufferedAheadSec.toStringAsFixed(1)}s';
  if (to == null) return '事件 解碼卡住 已是 AVC，不再切換 $tail';
  return '事件 解碼卡住 $from->$to $tail';
}

/// 是否為 HDR／10-bit 串流：qn 125／126，或 codecs 為 HEVC Main10（hvc1.2／hev1.2），
/// 或 AV1 codecs 第 4 段位元深度為 10／12（如 av01.0.13M.10）。
bool isHdrStream({required int qn, required String codecs}) {
  if (qn == 125 || qn == 126) return true;
  final c = codecs.toLowerCase();
  if (c.startsWith('hvc1.2') || c.startsWith('hev1.2')) return true;
  if (c.startsWith('av01')) {
    final parts = c.split('.');
    if (parts.length >= 4) {
      final depth = parts[3];
      return depth == '10' || depth == '12';
    }
  }
  return false;
}

/// HDR 解碼失敗時的退路：可用畫質中，比 [current] 低且不是 125／126 的最高 qn；沒有回 null。
int? nonHdrFallbackQn(Iterable<int> available, int current) {
  int? best;
  for (final q in available) {
    if (q >= current || q == 125 || q == 126) continue;
    if (best == null || q > best) best = q;
  }
  return best;
}
