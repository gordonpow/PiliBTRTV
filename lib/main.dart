import 'dart:async';

import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'screens/splash_screen.dart'; // 引入 Splash Screen
import 'package:bili_tv_app/core/plugin/plugin_manager.dart';
import 'package:bili_tv_app/plugins/sponsor_block_plugin.dart';
import 'package:bili_tv_app/plugins/ad_filter_plugin.dart';
import 'package:bili_tv_app/plugins/danmaku_enhance_plugin.dart';
import 'services/auth_service.dart';
import 'services/local_server.dart';
import 'services/log_service.dart';
import 'services/settings_service.dart';
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
  await ZhConvert.init();

  // 🔥 增大圖片記憶體快取，防止播放影片時主頁圖片被回收
  PaintingBinding.instance.imageCache.maximumSize = 500; // 500張圖片
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 << 20; // 200MB

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

  runApp(const BiliTvApp());
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
