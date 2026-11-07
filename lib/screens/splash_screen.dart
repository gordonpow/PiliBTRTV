import 'package:bili_tv_app/services/btr/btr_config.dart';
import 'dart:async';

import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart'; // 包含 BiliCacheManager
import '../services/update_service.dart';
import '../services/bilibili_api.dart';
import '../services/api/base_api.dart';
import '../models/video.dart';
import 'home_screen.dart';
import '../utils/image_url_utils.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  VideoPlayerController? _videoController;
  bool _showSplash = false; // 只有啟用動畫時才顯示佔位圖
  Completer<void>? _videoCompleter; // 用於等待影片播放完成

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    List<Video> preloadedVideos = [];
    bool videoInitSuccess = false;

    // 1. 初始化影片播放器 (儘早開始，與服務初始化並行)
    _videoController = VideoPlayerController.asset(
      'assets/icons/startup.mp4',
      viewType: VideoViewType.platformView,
    );
    _videoCompleter = Completer<void>();

    // 影片初始化 Future，新增超時和錯誤處理
    final videoInitFuture = () async {
      try {
        await _videoController!.initialize().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('影片初始化超時');
          },
        );
        _videoController!.setVolume(0); // 無聲

        // 新增播放完成監聽器
        _videoController!.addListener(_onVideoPositionChanged);

        _videoController!.play();
        videoInitSuccess = true;
        if (mounted) setState(() {});
      } catch (e) {
        debugPrint('Video initialization failed: $e');
        // 影片初始化失敗，立即完成 completer，跳過動畫
        if (!_videoCompleter!.isCompleted) {
          _videoCompleter!.complete();
        }
        // 清理失敗的控制器
        _videoController?.dispose();
        _videoController = null;
      }
    }();

    // 3. 初始化基礎服務 (與影片初始化並行)
    await Future.wait([
      videoInitFuture,
      AuthService.init(),
      SettingsService.init(),
      UpdateService.init(),
    ]);

    // Ensure buvid3 cookie exists before any Bilibili API call
    try {
      await BaseApi.ensureBuvid().timeout(
        const Duration(seconds: 6),
        onTimeout: () {},
      );
    } catch (e) {
      debugPrint('ensureBuvid failed: $e');
    }

    try {
      BtrConfig.applyLocaleDefault();
    } catch (e) {
      debugPrint('BTR applyLocaleDefault failed: $e');
    }

    // 4. 如果已登入，更新一下使用者資訊 (獲取最新 VIP 狀態)
    // 不 await，讓它在後臺跑，或者如果很快完成也沒關係
    // 這裡選擇放在後面單獨調一下，不阻塞核心服務初始化，但儘量在進入主頁前完成
    if (AuthService.isLoggedIn) {
      BilibiliApi.fetchAndSaveUserInfo().catchError((e) {
        debugPrint('Failed to update user info on splash: $e');
      });
    }

    // 檢查是否停用了啟動動畫 或 影片初始化失敗
    if (!SettingsService.splashAnimationEnabled || !videoInitSuccess) {
      _videoController?.removeListener(_onVideoPositionChanged);
      _videoController?.dispose();
      _videoController = null;
      _showSplash = false;
      if (!_videoCompleter!.isCompleted) {
        _videoCompleter!.complete();
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, a1, a2) => const HomeScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 200),
          ),
        );
      }
      return;
    }

    // 啟用動畫，顯示佔位圖和影片
    _showSplash = true;
    if (mounted) setState(() {});

    // 4. 非同步預載入資料 (不 await，讓它並行跑)
    final preloadFuture = Future(() async {
      try {
        final videos = await BilibiliApi.getRecommendVideos(idx: 0);
        preloadedVideos = videos;

        if (mounted && preloadedVideos.isNotEmpty) {
          // 【使用者請求】取消 12 個的數量限制，全部預載入
          final int count = preloadedVideos.length;

          // 【核心修復】建立預載入任務列表
          List<Future<void>> imageTasks = [];

          for (int i = 0; i < count; i++) {
            final url = preloadedVideos[i].pic;
            if (url.isNotEmpty) {
              // 【必須完全匹配 TvVideoCard 的引數】
              // 1. maxWidth: 360
              // 2. maxHeight: 200 (原本缺失導致快取不匹配)
              // 3. cacheManager: BiliCacheManager.instance (原本缺失導致路徑不匹配)
              final optimizedUrl = ImageUrlUtils.getResizedUrl(
                url,
                width: 640,
                height: 360,
              );
              final imageProvider = CachedNetworkImageProvider(
                optimizedUrl,
                maxWidth: 360,
                maxHeight: 200,
                cacheManager: BiliCacheManager.instance,
              );

              imageTasks.add(
                precacheImage(imageProvider, context).catchError((e) {
                  debugPrint('Image preload failed: $url');
                }),
              );
            }
          }
          // 並行等待所有圖片下載
          if (imageTasks.isNotEmpty) {
            await Future.wait(imageTasks);
          }
        }
      } catch (e) {
        debugPrint('Preload videos failed: $e');
      }
    });

    // 3. 等待影片真正播放完成 (而不是用 Future.delayed)
    await _videoCompleter!.future;

    // 嘗試獲取預載入結果 (如果預載入還沒跑完，就不用等了，直接 timeout 拿空資料進主頁)
    try {
      await preloadFuture.timeout(Duration.zero);
    } catch (e) {
      // 預載入未完成，忽略異常，preloadedVideos 可能是空的
    }

    if (mounted) {
      // 轉場前暫停影片，防止繼續播放
      _videoController?.pause();

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          opaque: false,
          pageBuilder: (context, a1, a2) =>
              HomeScreen(preloadedVideos: preloadedVideos),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  /// 監聽影片播放進度，當播放完成時觸發 Completer
  void _onVideoPositionChanged() {
    final controller = _videoController;
    if (controller == null || _videoCompleter == null) return;

    final position = controller.value.position;
    final duration = controller.value.duration;

    // 當播放位置接近結尾時（允許 100ms 誤差），認為播放完成
    if (duration.inMilliseconds > 0 &&
        position.inMilliseconds >= duration.inMilliseconds - 100) {
      if (!_videoCompleter!.isCompleted) {
        _videoCompleter!.complete();
      }
    }
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoPositionChanged);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SizedBox.expand(
        child: _videoController != null && _videoController!.value.isInitialized
            ? FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              )
            : _showSplash
            ? Image.asset(
                'assets/icons/startup_frame.jpg',
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
