import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:bili_tv_app/models/play_repeat.dart';
import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';

/// 影片編解碼器列舉
enum VideoCodec {
  auto('自動', ''),
  avc('H.264', 'avc'),
  hevc('H.265', 'hev'),
  av1('AV1', 'av01');

  final String label;
  final String prefix; // codecs 欄位字首
  const VideoCodec(this.label, this.prefix);
}

/// 自定義快取管理器 - 限制 200MB
class BiliCacheManager {
  static const key = 'biliTvCache';
  static CacheManager? _instance;

  static CacheManager get instance {
    _instance ??= CacheManager(
      Config(
        key,
        stalePeriod: const Duration(days: 7), // 7天過期
        maxNrOfCacheObjects: 350, // 最多350個快取物件 (約200MB)
      ),
    );
    return _instance!;
  }
}

/// 設定服務
class SettingsService {
  static const String _useHardwareDecodeKey = 'use_hardware_decode';
  static SharedPreferences? _prefs;

  /// 取得 SharedPreferences（尚未 init 時丟擲 StateError）
  static SharedPreferences get prefs {
    final p = _prefs;
    if (p == null) {
      throw StateError('SettingsService.init() has not been called');
    }
    return p;
  }

  /// 初始化
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 顯示 Toast 提示
  static void toast(BuildContext? context, String msg) {
    Fluttertoast.showToast(
      msg: ZhConvert.convert(msg),
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.CENTER,
      timeInSecForIosWeb: 2,
      backgroundColor: const Color(0xFF333333),
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  /// 獲取圖片快取大小 (MB)
  static Future<double> getImageCacheSizeMB() async {
    double totalSize = 0;

    try {
      // 獲取臨時目錄
      final tempDir = await getTemporaryDirectory();
      totalSize += await _getDirectorySize(tempDir);

      // 獲取應用快取目錄
      final cacheDir = await getApplicationCacheDirectory();
      if (cacheDir.path != tempDir.path) {
        totalSize += await _getDirectorySize(cacheDir);
      }
    } catch (e) {
      // 忽略錯誤
    }

    // 轉換為 MB
    return totalSize / (1024 * 1024);
  }

  /// 計算目錄大小
  static Future<double> _getDirectorySize(Directory dir) async {
    double size = 0;
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            size += await entity.length();
          }
        }
      }
    } catch (e) {
      // 忽略許可權錯誤等
    }
    return size;
  }

  /// 清除圖片快取 (不包含播放進度)
  static Future<void> clearImageCache() async {
    // 清除圖片快取
    await CachedNetworkImage.evictFromCache('');
    await BiliCacheManager.instance.emptyCache();
    await DefaultCacheManager().emptyCache();

    // 清除臨時檔案
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list()) {
          try {
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (e) {
            // 忽略單個檔案刪除失敗
          }
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
  }

  /// 是否使用硬體解碼
  static bool get useHardwareDecode {
    return _prefs?.getBool(_useHardwareDecodeKey) ?? true; // 預設硬解
  }

  /// 設定硬體解碼
  static Future<void> setUseHardwareDecode(bool value) async {
    await init();
    await _prefs!.setBool(_useHardwareDecodeKey, value);
  }

  // 播放完畢後行為
  static const String _legacyAutoPlayKey = 'auto_play'; // 舊設定，只用於遷移
  static const String _legacyPlayRepeatKey = 'play_repeat'; // 舊 enum index，只用於遷移
  static const String _playEndModeKey = 'play_end_mode'; // 新設定，存 enum 名稱
  static const String _upNextCountdownKey = 'up_next_countdown';

  /// 連播倒數可選秒數（「直接播下一部」已取代原本的 0 秒）
  static const List<int> upNextCountdownOptions = [3, 5, 10, 15];

  /// 測試用：注入 SharedPreferences
  @visibleForTesting
  static void debugSetPrefs(SharedPreferences? prefs) => _prefs = prefs;

  /// 播放完畢後行為。讀取順序：新 key、舊 play_repeat（依倒數秒數轉換）、
  /// 更舊的 auto_play。由舊 play_repeat 轉換時，把結果寫進新 key。
  static PlayRepeat get playRepeat {
    final r = PlayRepeat.resolve(
      name: _prefs?.getString(_playEndModeKey),
      legacyIndex: _prefs?.getInt(_legacyPlayRepeatKey),
      legacyAutoPlay: _prefs?.getBool(_legacyAutoPlayKey),
      // 先用原始倒數秒數轉換，再正規化（讀到 0 時當作 5）
      countdown: _prefs?.getInt(_upNextCountdownKey),
    );
    if (r.fromLegacy) {
      _prefs?.setString(_playEndModeKey, r.mode.name);
    }
    return r.mode;
  }

  static Future<void> setPlayRepeat(PlayRepeat value) async {
    await init();
    await _prefs!.setString(_playEndModeKey, value.name);
  }

  /// 連播倒數秒數，預設 5
  static int get upNextCountdown {
    final v = _prefs?.getInt(_upNextCountdownKey) ?? 5;
    return upNextCountdownOptions.contains(v) ? v : 5;
  }

  static Future<void> setUpNextCountdown(int value) async {
    await init();
    await _prefs!.setInt(_upNextCountdownKey, value);
  }

  // 自動檢查更新
  static const String _autoUpdateKey = 'auto_update';
  static const String _updateIntervalKey = 'update_interval_hours';

  /// 可選的檢查間隔（小時）
  static const List<int> updateIntervalOptions = [1, 6, 12, 24, 48, 168];

  static bool get autoUpdate => _prefs?.getBool(_autoUpdateKey) ?? true;

  static Future<void> setAutoUpdate(bool value) async {
    await init();
    await _prefs!.setBool(_autoUpdateKey, value);
  }

  static int get updateIntervalHours =>
      _prefs?.getInt(_updateIntervalKey) ?? 24;

  static Future<void> setUpdateIntervalHours(int value) async {
    await init();
    await _prefs!.setInt(_updateIntervalKey, value);
  }

  // 介面語言設定（0 跟隨系統、1 繁體中文、2 簡體中文）
  static const String _appLanguageKey = 'app_language';

  /// 介面語言：0 跟隨系統、1 繁體中文、2 簡體中文
  static int get appLanguage {
    return _prefs?.getInt(_appLanguageKey) ?? 0;
  }

  /// 設定介面語言（重新啟動前必須 await，確保已寫入）
  static Future<void> setAppLanguage(int value) async {
    await init();
    await _prefs!.setInt(_appLanguageKey, value);
  }

  // 啟動動畫設定
  static const String _splashAnimationKey = 'splash_animation';

  /// 是否顯示啟動動畫
  static bool get splashAnimationEnabled {
    return _prefs?.getBool(_splashAnimationKey) ?? true; // 預設開啟
  }

  /// 設定啟動動畫
  static Future<void> setSplashAnimationEnabled(bool value) async {
    await init();
    await _prefs!.setBool(_splashAnimationKey, value);
  }

  // 首選編解碼器設定
  static const String _preferredCodecKey = 'preferred_codec';
  static const String _codecFallbackAvcKey = 'codec_fallback_avc';

  /// 當前是否已因解碼失敗自動降級改用 AVC
  static bool get codecFallbackAvc =>
      _prefs?.getBool(_codecFallbackAvcKey) ?? false;

  /// 設定是否自動降級改用 AVC
  static Future<void> setCodecFallbackAvc(bool value) async {
    await init();
    await _prefs!.setBool(_codecFallbackAvcKey, value);
  }

  /// 獲取未套用自動降級的首選編解碼器（供設定頁顯示）
  static VideoCodec get rawPreferredCodec {
    final index = _prefs?.getInt(_preferredCodecKey) ?? 0; // 預設自動 (index 0)
    return VideoCodec.values[index.clamp(0, VideoCodec.values.length - 1)];
  }

  /// 獲取首選編解碼器（若已自動降級則回傳 AVC）
  static VideoCodec get preferredCodec {
    if (codecFallbackAvc) return VideoCodec.avc;
    return rawPreferredCodec;
  }

  /// 設定首選編解碼器
  static Future<void> setPreferredCodec(VideoCodec codec) async {
    await init();
    await _prefs!.setInt(_preferredCodecKey, codec.index);
    // 使用者手動設定時，清除自動降級標記
    await setCodecFallbackAvc(false);
  }

  // 迷你進度條設定
  static const String _showMiniProgressKey = 'show_mini_progress';

  /// 是否顯示迷你進度條
  static bool get showMiniProgress {
    return _prefs?.getBool(_showMiniProgressKey) ?? false; // 預設關閉
  }

  /// 設定迷你進度條
  static Future<void> setShowMiniProgress(bool value) async {
    await init();
    await _prefs!.setBool(_showMiniProgressKey, value);
  }

  // 預設隱藏控制欄設定
  static const String _hideControlsOnStartKey = 'hide_controls_on_start';

  /// 是否預設隱藏控制欄
  static bool get hideControlsOnStart {
    // 相容直播 (User request: hide live controls by default setting)
    return _prefs?.getBool(_hideControlsOnStartKey) ?? false;
  }

  // 直播: 預設隱藏控制欄設定
  static const String _hideLiveControlsOnStartKey =
      'hide_live_controls_on_start';
  static bool get hideLiveControlsOnStart {
    return _prefs?.getBool(_hideLiveControlsOnStartKey) ?? false;
  }

  static Future<void> setHideLiveControlsOnStart(bool value) async {
    await init();
    await _prefs!.setBool(_hideLiveControlsOnStartKey, value);
  }

  // 直播: 播放器右上角時間顯示設定
  static const String _showLiveTimeDisplayKey = 'show_live_time_display';
  static bool get showLiveTimeDisplay {
    return _prefs?.getBool(_showLiveTimeDisplayKey) ?? false;
  }

  static Future<void> setShowLiveTimeDisplay(bool value) async {
    await init();
    await _prefs!.setBool(_showLiveTimeDisplayKey, value);
  }

  /// 設定預設隱藏控制欄
  static Future<void> setHideControlsOnStart(bool value) async {
    await init();
    await _prefs!.setBool(_hideControlsOnStartKey, value);
  }

  // 播放器右上角時間顯示設定
  static const String _alwaysShowPlayerTimeKey = 'always_show_player_time';

  /// 是否在播放器右上角常駐顯示時間
  static bool get alwaysShowPlayerTime {
    return _prefs?.getBool(_alwaysShowPlayerTimeKey) ?? false; // 預設關閉
  }

  /// 設定是否在播放器右上角常駐顯示時間
  static Future<void> setAlwaysShowPlayerTime(bool value) async {
    await init();
    await _prefs!.setBool(_alwaysShowPlayerTimeKey, value);
  }

  // 影片卡片焦點預覽設定
  static const String _cardPreviewKey = 'card_video_preview';

  /// 游標停在影片卡片上時是否播放靜音預覽
  static bool get cardPreview {
    return _prefs?.getBool(_cardPreviewKey) ?? true; // 預設開啟
  }

  /// 設定是否啟用影片卡片預覽
  static Future<void> setCardPreview(bool value) async {
    await init();
    await _prefs!.setBool(_cardPreviewKey, value);
  }

  // 分區順序設定
  static const String _categoryOrderKey = 'home_category_order';

  // 預設分區順序 (使用列舉名稱字串)
  static const List<String> _defaultCategoryOrder = [
    'recommend',
    'popular',
    'anime',
    'movie',
    'game',
    'knowledge',
    'tech',
    'music',
    'dance',
    'life',
    'food',
    'douga',
  ];

  /// 獲取分區順序
  static List<String> get categoryOrder {
    final saved = _prefs?.getStringList(_categoryOrderKey);
    if (saved != null && saved.isNotEmpty) {
      // 確保所有分區都在列表中 (防止新增分區丟失)
      final result = List<String>.from(saved);
      for (final cat in _defaultCategoryOrder) {
        if (!result.contains(cat)) {
          result.add(cat);
        }
      }
      return result;
    }
    return List<String>.from(_defaultCategoryOrder);
  }

  /// 設定分區順序
  static Future<void> setCategoryOrder(List<String> order) async {
    await init();
    await _prefs!.setStringList(_categoryOrderKey, order);
  }

  // 分區啟用設定
  static const String _enabledCategoriesKey = 'enabled_categories';

  /// 獲取啟用的分區 (預設全部啟用)
  static Set<String> get enabledCategories {
    final saved = _prefs?.getStringList(_enabledCategoriesKey);
    if (saved != null) {
      return saved.toSet();
    }
    // 預設全部啟用
    return _defaultCategoryOrder.toSet();
  }

  /// 設定啟用的分區
  static Future<void> setEnabledCategories(Set<String> categories) async {
    await init();
    await _prefs!.setStringList(_enabledCategoriesKey, categories.toList());
  }

  /// 檢查分區是否啟用
  static bool isCategoryEnabled(String name) {
    return enabledCategories.contains(name);
  }

  /// 切換分區啟用狀態
  static Future<void> toggleCategory(String name, bool enabled) async {
    final current = enabledCategories;
    if (enabled) {
      current.add(name);
    } else {
      current.remove(name);
    }
    await setEnabledCategories(current);
  }

  // 播放畫面模式（false=原生 SurfaceView，true=相容 TextureView）
  static const String _playerTextureViewKey = 'player_texture_view';

  static bool get playerTextureView {
    return _prefs?.getBool(_playerTextureViewKey) ?? false;
  }

  static Future<void> setPlayerTextureView(bool value) async {
    await init();
    await _prefs!.setBool(_playerTextureViewKey, value);
  }

  // 卡頓時自動降畫質（預設開）
  static const String _autoDowngradeOnDropsKey = 'auto_downgrade_on_drops';

  static bool get autoDowngradeOnDrops {
    return _prefs?.getBool(_autoDowngradeOnDropsKey) ?? true;
  }

  static Future<void> setAutoDowngradeOnDrops(bool value) async {
    await init();
    await _prefs!.setBool(_autoDowngradeOnDropsKey, value);
  }

  // 隧道播放（實驗，預設關）。原生端 PlatformViewVideoPlayer 會直接讀
  // SharedPreferences 檔 FlutterSharedPreferences 的 flutter.player_tunneling
  static const String _playerTunnelingKey = 'player_tunneling';

  static bool get playerTunneling {
    return _prefs?.getBool(_playerTunnelingKey) ?? false;
  }

  static Future<void> setPlayerTunneling(bool value) async {
    await init();
    await _prefs!.setBool(_playerTunnelingKey, value);
  }

  // 此裝置 4K 高幀率（60fps）播放不順：觸發過自動降畫質就記下來
  static const String _known4k60BadKey = 'known_4k60_bad';

  static bool get known4k60Bad {
    return _prefs?.getBool(_known4k60BadKey) ?? false;
  }

  static Future<void> setKnown4k60Bad(bool value) async {
    await init();
    await _prefs!.setBool(_known4k60BadKey, value);
  }

  /// 清除「4K 60 幀不順」記錄
  static Future<void> clearKnown4k60Bad() async {
    await init();
    await _prefs!.remove(_known4k60BadKey);
  }

  // 快進預覽模式設定
  static const String _seekPreviewModeKey = 'seek_preview_mode';

  /// 是否開啟快進預覽模式 (顯示縮圖)
  static bool get seekPreviewMode {
    return _prefs?.getBool(_seekPreviewModeKey) ?? true; // 預設開啟
  }

  /// 設定快進預覽模式
  static Future<void> setSeekPreviewMode(bool value) async {
    await init();
    await _prefs!.setBool(_seekPreviewModeKey, value);
  }

  // ==================== 直播分區設定 ====================

  static const Map<String, String> liveCategoryLabels = {
    'online_games': '網遊',
    'mobile_games': '手遊',
    'console_games': '單機',
    'virtual': '虛擬主播',
    'entertainment': '娛樂',
    'radio': '電臺',
    'match': '賽事',
    'chat': '聊天室',
    'lifestyle': '生活',
    'knowledge': '知識',
    'interactive': '互動玩法',
  };

  static const Map<String, int> liveCategoryIds = {
    'online_games': 2,
    'mobile_games': 3,
    'console_games': 6,
    'virtual': 9,
    'entertainment': 1,
    'radio': 5,
    'match': 13,
    'chat': 14,
    'lifestyle': 10,
    'knowledge': 11,
    'interactive': 15,
  };

  static const List<String> _defaultLiveCategoryOrder = [
    'online_games',
    'mobile_games',
    'console_games',
    'virtual',
    'entertainment',
    'radio',
    'match',
    'chat',
    'lifestyle',
    'knowledge',
    'interactive',
  ];

  static const String _liveCategoryOrderKey = 'live_category_order';
  static const String _enabledLiveCategoriesKey = 'enabled_live_categories';

  /// 獲取直播分區順序
  static List<String> get liveCategoryOrder {
    final saved = _prefs?.getStringList(_liveCategoryOrderKey);
    if (saved != null && saved.isNotEmpty) {
      final result = List<String>.from(saved);
      for (final cat in _defaultLiveCategoryOrder) {
        if (!result.contains(cat)) {
          result.add(cat);
        }
      }
      return result;
    }
    return List<String>.from(_defaultLiveCategoryOrder);
  }

  /// 設定直播分區順序
  static Future<void> setLiveCategoryOrder(List<String> order) async {
    await init();
    await _prefs!.setStringList(_liveCategoryOrderKey, order);
  }

  /// 獲取啟用的直播分區
  static Set<String> get enabledLiveCategories {
    final saved = _prefs?.getStringList(_enabledLiveCategoriesKey);
    if (saved != null) {
      return saved.toSet();
    }
    return _defaultLiveCategoryOrder.toSet();
  }

  /// 設定啟用的直播分區
  static Future<void> setEnabledLiveCategories(Set<String> categories) async {
    await init();
    await _prefs!.setStringList(_enabledLiveCategoriesKey, categories.toList());
  }

  /// 檢查直播分區是否啟用
  static bool isLiveCategoryEnabled(String name) {
    return enabledLiveCategories.contains(name);
  }

  /// 切換直播分區啟用狀態
  static Future<void> toggleLiveCategory(String name, bool enabled) async {
    final current = enabledLiveCategories;
    if (enabled) {
      current.add(name);
    } else {
      current.remove(name);
    }
    await setEnabledLiveCategories(current);
  }
}
