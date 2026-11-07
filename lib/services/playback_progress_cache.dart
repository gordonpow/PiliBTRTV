import 'package:shared_preferences/shared_preferences.dart';

/// 本地播放進度快取管理器
///
/// 用於在退出播放器時儲存進度，並在下次進入時恢復。
/// 這解決了 B站 API 的 `history` 欄位不總是返回的問題。
///
/// 一個影片只儲存一個最新進度（和 B站 API 行為一致）。
class PlaybackProgressCache {
  static SharedPreferences? _prefs;
  static const String _progressPrefix = 'playback_progress_v3_';
  static const String _cidPrefix = 'playback_cid_v3_';

  /// 初始化
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 儲存播放進度（覆蓋之前的進度）
  ///
  /// [bvid] 影片 BVID
  /// [cid] 當前分P的 CID
  /// [progress] 播放進度（秒）
  static Future<void> saveProgress(String bvid, int cid, int progress) async {
    await init();
    await _prefs?.setInt('$_progressPrefix$bvid', progress);
    await _prefs?.setInt('$_cidPrefix$bvid', cid);
  }

  /// 獲取快取的完整記錄（CID 和進度）
  ///
  /// [bvid] 影片 BVID
  /// 返回 (cid, progress)，如果沒有快取則返回 null
  static Future<({int cid, int progress})?> getCachedRecord(String bvid) async {
    await init();
    final cachedCid = _prefs?.getInt('$_cidPrefix$bvid');
    final cachedProgress = _prefs?.getInt('$_progressPrefix$bvid');

    if (cachedCid != null &&
        cachedCid > 0 &&
        cachedProgress != null &&
        cachedProgress > 0) {
      return (cid: cachedCid, progress: cachedProgress);
    }
    return null;
  }

  /// 清除指定影片的進度快取（播放完成時呼叫）
  static Future<void> clearProgress(String bvid) async {
    await init();
    await _prefs?.remove('$_progressPrefix$bvid');
    await _prefs?.remove('$_cidPrefix$bvid');
  }
}
