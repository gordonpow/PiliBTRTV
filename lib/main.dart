import 'dart:async';

import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'screens/splash_screen.dart'; // 引入 Splash Screen
import 'package:bili_tv_app/core/plugin/plugin_manager.dart';
import 'package:bili_tv_app/plugins/sponsor_block_plugin.dart';
import 'package:bili_tv_app/plugins/ad_filter_plugin.dart';
import 'package:bili_tv_app/plugins/danmaku_enhance_plugin.dart';
import 'services/auth_service.dart';
import 'services/btr/btr_host_ranker.dart';
import 'services/card_preview_service.dart';
import 'services/device_profile.dart';
import 'services/live/live_timeshift.dart';
import 'services/local_server.dart';
import 'services/log_service.dart';
import 'services/memory_budget.dart';
import 'services/prefetch_service.dart';
import 'services/settings_service.dart';
import 'services/translate/content_translator.dart';
import 'utils/zh_convert.dart';

Future<void> main() async {
  // 整個啟動流程放在同一個 zone，未捕捉的非同步錯誤會寫入 log
  await runZonedGuarded(_main, LogService.recordError);
}

Future<void> _main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.init();

  // 語言設定需要 SharedPreferences，先初始化再載入繁簡轉換表
  await SettingsService.init();
  await DeviceProfile.init();
  // 清掉上次殘留的直播時移暫存（不等待）
  unawaited(LiveTimeshiftSession.cleanupStale());
  await ZhConvert.init();
  // 翻譯 B 站內容：開關為 true 才在背景檢查模型（不阻塞啟動）
  unawaited(ContentTranslator.instance.init());

  // 🔥 依記憶體等級設定圖片快取上限
  _applyImageCacheBudget();
  // 監聽等級變化，即時更新圖片快取
  DeviceProfile.tierNotifier.addListener(_applyImageCacheBudget);

  WidgetsBinding.instance.addObserver(_AppLifecycleObserver());

  // 啟動記憶體即時監控（每 15 秒查詢一次）
  DeviceProfile.startMonitor();

  // 初始化外掛管理器並註冊外掛
  final pluginManager = PluginManager();
  await pluginManager.init();
  pluginManager.register(SponsorBlockPlugin());
  pluginManager.register(AdFilterPlugin());
  pluginManager.register(DanmakuEnhancePlugin());

  // 啟動本地 HTTP 服務 (提供外掛配置 API)
  await LocalServer.instance.start();

  await AuthService.init(); // 全屏模式 - 隱藏狀態列和導航欄
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // 初始化邏輯已移交至 SplashScreen 處理，這裡僅啟動 APP
  // 這樣可以確保啟動畫面迅速出現，無需等待初始化完成

  // 背景測量 CDN 主機延遲（不阻塞啟動）
  BtrHostRanker.instance.warmUp();

  runApp(const BiliTvApp());
}

/// 依目前記憶體等級更新圖片快取上限
void _applyImageCacheBudget() {
  final tier = DeviceProfile.currentTier;
  PaintingBinding.instance.imageCache.maximumSize =
      MemoryBudget.imageCacheCount(tier);
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      MemoryBudget.imageCacheBytes(tier);
}

/// 監聽 App 生命週期與記憶體壓力事件
class _AppLifecycleObserver with WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() {
    debugPrint('🧹 [Memory] pressure');
    // 通知 DeviceProfile 立即進入 critical
    DeviceProfile.onMemoryPressure();
    CardPreviewService.instance.onMemoryPressure();
    PrefetchService.instance.trimMemory();
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App 進入背景時停止計時器，回前景恢復，節省資源（規格審查 #4）
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      DeviceProfile.stopMonitor();
    } else if (state == AppLifecycleState.resumed) {
      DeviceProfile.startMonitor();
    }
  }
}

class BiliTvApp extends StatelessWidget {
  const BiliTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiliTV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFFfb7299), // Bilibili 粉色
        useMaterial3: true,
        focusColor: Colors.white.withValues(alpha: 0.1),
      ),
      home: const SplashScreen(),
    );
  }
}
