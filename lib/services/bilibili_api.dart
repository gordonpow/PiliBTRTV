/// Bilibili API 服務 - 統一入口
///
/// 本檔案作為門面(Facade)，委託給各子模組實現。
/// 拆分後的模組位於 api/ 目錄：
/// - base_api.dart: 基礎工具方法
/// - auth_api.dart: 認證相關
/// - video_api.dart: 影片列表、搜尋
/// - playback_api.dart: 播放、彈幕、進度
/// - interaction_api.dart: 點贊、投幣、收藏、關注
library;

// 匯出子模組，供外部直接使用
export 'api/video_api.dart' show DynamicFeed;

import 'api/auth_api.dart';
import 'api/video_api.dart';
import 'api/playback_api.dart';
import 'api/interaction_api.dart';
import 'api/videoshot_api.dart';
import 'api/pgc_api.dart';
import 'settings_service.dart' show VideoCodec;
import '../models/video.dart';
import '../models/videoshot.dart';

/// Bilibili API 服務 (門面模式)
/// 保持與原有介面完全相容
class BilibiliApi {
  // ========== 使用者資訊相關 ==========

  /// 獲取使用者資訊 (頭像、暱稱等)
  static Future<void> fetchAndSaveUserInfo() => AuthApi.fetchAndSaveUserInfo();

  // ========== TV 登入相關 ==========

  /// 生成 TV 登入二維碼
  static Future<Map<String, String>?> generateTvQrCode() =>
      AuthApi.generateTvQrCode();

  /// 輪詢 TV 登入狀態
  static Future<Map<String, dynamic>> pollTvLogin(String authCode) =>
      AuthApi.pollTvLogin(authCode);

  // ========== 影片列表相關 ==========

  /// 獲取熱門影片 (無需登入)
  static Future<List<Video>> getPopularVideos({int page = 1}) =>
      VideoApi.getPopularVideos(page: page);

  /// 獲取推薦影片 (需要 WBI 簽名)
  static Future<List<Video>> getRecommendVideos({int idx = 0}) =>
      VideoApi.getRecommendVideos(idx: idx);

  /// 獲取分區影片 (按 tid)
  static Future<List<Video>> getRegionVideos({
    required int tid,
    int page = 1,
  }) => VideoApi.getRegionVideos(tid: tid, page: page);

  /// 獲取觀看歷史 (需要登入)
  static Future<Map<String, dynamic>> getHistory({
    int ps = 30,
    int viewAt = 0,
    int max = 0,
  }) => VideoApi.getHistory(ps: ps, viewAt: viewAt, max: max);

  // ========== 搜尋相關 ==========

  /// 獲取搜尋建議
  static Future<List<String>> getSearchSuggestions(String keyword) =>
      VideoApi.getSearchSuggestions(keyword);

  /// 搜尋影片 (需要 WBI 簽名)
  static Future<List<Video>> searchVideos(
    String keyword, {
    int page = 1,
    String order = 'totalrank',
  }) => VideoApi.searchVideos(keyword, page: page, order: order);

  // ========== 動態相關 ==========

  /// 獲取動態影片列表
  static Future<DynamicFeed> getDynamicFeed({String offset = ''}) =>
      VideoApi.getDynamicFeed(offset: offset);

  /// 獲取相關影片
  static Future<List<Video>> getRelatedVideos(String bvid) =>
      VideoApi.getRelatedVideos(bvid);

  /// 獲取 UP主 投稿影片列表
  static Future<List<Video>> getSpaceVideos({
    required int mid,
    int page = 1,
    String order = 'pubdate',
  }) => VideoApi.getSpaceVideos(mid: mid, page: page, order: order);

  // ========== 播放相關 ==========

  /// 獲取影片詳情（包含分P資訊和播放歷史）
  static Future<Map<String, dynamic>?> getVideoInfo(String bvid) =>
      PlaybackApi.getVideoInfo(bvid);

  /// 獲取影片的 cid
  static Future<int?> getVideoCid(String bvid) => PlaybackApi.getVideoCid(bvid);

  /// 獲取影片播放地址
  static Future<Map<String, dynamic>?> getVideoPlayUrl({
    required String bvid,
    required int cid,
    int qn = 80,
    VideoCodec? forceCodec,
    int? epId,
  }) => PlaybackApi.getVideoPlayUrl(
    bvid: bvid,
    cid: cid,
    qn: qn,
    forceCodec: forceCodec,
    epId: epId,
  );

  /// 獲取彈幕資料
  static Future<List<Map<String, dynamic>>> getDanmaku(int cid) =>
      PlaybackApi.getDanmaku(cid);

  /// 上報播放進度
  static Future<bool> reportProgress({
    required String bvid,
    required int cid,
    required int progress,
    int? epId,
    int? seasonId,
  }) => PlaybackApi.reportProgress(
    bvid: bvid,
    cid: cid,
    progress: progress,
    epId: epId,
    seasonId: seasonId,
  );

  // ========== 番劇 (PGC) ==========

  /// 番劇索引 (熱門排序)
  static Future<List<Video>> getBangumiIndex({int page = 1}) =>
      PgcApi.getBangumiIndex(page: page);

  /// 番劇季資訊
  static Future<Map<String, dynamic>> getPgcSeason({required int seasonId}) =>
      PgcApi.getSeason(seasonId: seasonId);

  /// 獲取影片線上觀看人數
  static Future<Map<String, String>?> getOnlineCount({
    required int aid,
    required int cid,
  }) => PlaybackApi.getOnlineCount(aid: aid, cid: cid);

  /// 獲取影片快照(雪碧圖)資料
  static Future<VideoshotData?> getVideoshot({
    required String bvid,
    int? cid,
  }) => VideoshotApi.getVideoshot(bvid: bvid, cid: cid);

  // ========== 使用者操作相關 ==========

  /// 點贊/取消點贊
  static Future<bool> likeVideo({required int aid, required bool like}) =>
      InteractionApi.likeVideo(aid: aid, like: like);

  /// 檢查是否已點贊
  static Future<bool> checkLikeStatus(int aid) =>
      InteractionApi.checkLikeStatus(aid);

  /// 投幣
  static Future<String?> coinVideo({required int aid, int count = 1}) =>
      InteractionApi.coinVideo(aid: aid, count: count);

  /// 檢查已投幣數
  static Future<int> checkCoinStatus(int aid) =>
      InteractionApi.checkCoinStatus(aid);

  /// 收藏/取消收藏
  static Future<bool> favoriteVideo({
    required int aid,
    required bool favorite,
  }) => InteractionApi.favoriteVideo(aid: aid, favorite: favorite);

  /// 檢查是否已收藏
  static Future<bool> checkFavoriteStatus(int aid) =>
      InteractionApi.checkFavoriteStatus(aid);

  /// 關注/取消關注 UP主
  static Future<bool> followUser({required int mid, required bool follow}) =>
      InteractionApi.followUser(mid: mid, follow: follow);

  /// 檢查是否已關注
  static Future<bool> checkFollowStatus(int mid) =>
      InteractionApi.checkFollowStatus(mid);
}
