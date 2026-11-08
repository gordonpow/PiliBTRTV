import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/plugin/plugin_types.dart';
import '../../models/video.dart';
import '../../services/settings_service.dart';
import 'widgets/video_layer.dart';
import 'widgets/danmaku_layer.dart';
import 'widgets/controls_overlay.dart';
import 'widgets/settings_panel.dart';
import 'widgets/episode_panel.dart';
import 'widgets/pause_indicator.dart';
import 'widgets/action_buttons.dart';
import 'widgets/up_panel.dart';
import 'widgets/related_panel.dart';
import 'widgets/mini_progress_bar.dart';
import 'widgets/seek_thumbnail_strip.dart';
import '../../services/frame_service.dart';
import '../../widgets/time_display.dart';
import 'mixins/player_state_mixin.dart';
import 'mixins/player_action_mixin.dart';
import 'mixins/player_event_mixin.dart';

/// 影片播放器頁面 (使用 Mixin 重構)
class PlayerScreen extends StatefulWidget {
  final Video video;

  const PlayerScreen({super.key, required this.video});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with
        PlayerStateMixin,
        PlayerActionMixin,
        PlayerEventMixin,
        WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    WidgetsBinding.instance.addObserver(this);
    // 保持螢幕常亮，防止電視待機
    WakelockPlus.enable();
    loadSettings();
    initializePlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 應用進入後臺時上報進度 (包括按主頁鍵)
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      reportPlaybackProgress();
    }
  }

  @override
  void dispose() {
    // 恢復螢幕休眠
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    hideTimer?.cancel();
    progressReportTimer?.cancel();
    // 退出時上報進度
    reportPlaybackProgress();

    FrameService.release();

    // 通過 mixin 方法銷燬播放器
    disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: onPopInvoked,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Focus(
          autofocus: true,
          onKeyEvent: handleGlobalKeyEvent,
          child: Stack(
            children: [
              // 影片層
              VideoLayer(
                controller: videoController,
                isLoading: isLoading,
                errorMessage: errorMessage,
              ),

              // 彈幕層
              if (!isLoading && videoController != null && danmakuEnabled)
                DanmakuLayer(
                  onCreated: (c) => danmakuController = c,
                  option: DanmakuOption(
                    opacity: danmakuOpacity,
                    fontSize: danmakuFontSize,
                    // 彈幕飛行速度隨播放倍速同步調整
                    duration: danmakuSpeed / playbackSpeed,
                    area: danmakuArea,
                    hideTop: hideTopDanmaku,
                    hideBottom: hideBottomDanmaku,
                  ),
                ),

              // 暫停指示器
              if (!isLoading && videoController != null)
                PauseIndicator(controller: videoController),

              // 迷你進度條 (控制欄隱藏且非快退快進預覽時顯示)
              if (!isLoading &&
                  !showSeekIndicator &&
                  !isSeekPreviewMode &&
                  videoController != null &&
                  !showControls &&
                  SettingsService.showMiniProgress)
                MiniProgressBar(
                  position: videoController!.value.position,
                  duration: videoController!.value.duration,
                ),

              // Netflix 式快退快進進度條與預覽卡片 (AC-B1)
              if (isSeekPreviewMode &&
                  previewPosition != null &&
                  videoController != null)
                _buildNetflixSeekOverlay()
              else if (showSeekIndicator && videoController != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_formatSeekTime(videoController!.value.position)} / ${_formatSeekTime(videoController!.value.duration)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            blurRadius: 4,
                            color: Colors.black,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 控制介面
              if (!isLoading && videoController != null)
                AnimatedOpacity(
                  opacity: showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: ControlsOverlay(
                    video: getDisplayVideo(),
                    controller: videoController!,
                    showControls: showControls,
                    focusedIndex: focusedButtonIndex,
                    onPlayPause: togglePlayPause,
                    onSettings: () {
                      setState(() {
                        showSettingsPanel = true;
                        hideTimer?.cancel();
                      });
                    },
                    onEpisodes: () {
                      setState(() {
                        showEpisodePanel = true;
                        hideTimer?.cancel();
                      });
                    },
                    isDanmakuEnabled: danmakuEnabled,
                    onToggleDanmaku: toggleDanmaku,
                    currentQuality: currentQualityDesc,
                    onQualityClick: showQualityPicker,
                    isProgressBarFocused: isProgressBarFocused,
                    previewPosition: previewPosition,
                    alwaysShowPlayerTime: SettingsService.alwaysShowPlayerTime,
                    onlineCount: onlineCount,
                    danmakuCount: danmakuList.length,
                  ),
                ),

              // 常駐時間顯示 (當啟用且不顯示控制欄時，或 controlsOverlay 隱藏了其內部時間時)
              // 注意：ControlsOverlay 在 alwaysShowPlayerTime=true 時會隱藏內部時間但保留佔位
              // 常駐時間顯示 (當啟用且不顯示控制欄時，或 controlsOverlay 隱藏了其內部時間時)
              // 注意：ControlsOverlay 在 alwaysShowPlayerTime=true 時會隱藏內部時間但保留佔位
              if (SettingsService.alwaysShowPlayerTime)
                const Positioned(top: 20, right: 30, child: TimeDisplay()),

              // 進度條拖動預覽
              if (isProgressBarFocused &&
                  previewPosition != null &&
                  videoController != null)
                _buildProgressPreview(),

              // 點贊/投幣/收藏按鈕
              if (showActionButtons && !isLoading && videoController != null)
                Positioned(
                  bottom: 100,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ActionButtons(
                      video: widget.video,
                      aid: aid ?? 0,
                      isFocused: showActionButtons,
                      onFocusExit: () {
                        setState(() => showActionButtons = false);
                        startHideTimer();
                      },
                      onUserInteraction: () {
                        startHideTimer();
                      },
                    ),
                  ),
                ),

              // 選集面板
              if (showEpisodePanel)
                EpisodePanel(
                  episodes: episodes,
                  currentCid: cid ?? 0,
                  focusedIndex: focusedEpisodeIndex,
                  onEpisodeSave: switchEpisode,
                  onClose: () {
                    setState(() {
                      showEpisodePanel = false;
                      showControls = true;
                    });
                    startHideTimer();
                  },
                ),

              // 設定面板
              if (showSettingsPanel)
                SettingsPanel(
                  menuType: settingsMenuType,
                  focusedIndex: focusedSettingIndex,
                  qualityDesc: currentQualityDesc,
                  playbackSpeed: playbackSpeed,
                  availableSpeeds: availableSpeeds,
                  danmakuEnabled: danmakuEnabled,
                  danmakuOpacity: danmakuOpacity,
                  danmakuFontSize: danmakuFontSize,
                  danmakuArea: danmakuArea,
                  danmakuSpeed: danmakuSpeed,
                  hideTopDanmaku: hideTopDanmaku,
                  hideBottomDanmaku: hideBottomDanmaku,
                  onNavigate: (type, index) {
                    setState(() {
                      settingsMenuType = type;
                      focusedSettingIndex = index;
                    });
                  },
                  onQualityPicker: showQualityPicker,
                ),

              // UP主面板
              if (showUpPanel)
                UpPanel(
                  upName: widget.video.ownerName,
                  upFace: widget.video.ownerFace,
                  upMid: widget.video.ownerMid,
                  onVideoSelect: (video) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlayerScreen(video: video),
                      ),
                    );
                  },
                  onClose: () {
                    setState(() {
                      showUpPanel = false;
                      showControls = true;
                    });
                    startHideTimer();
                  },
                ),

              // 更多影片面板
              if (showRelatedPanel)
                RelatedPanel(
                  bvid: widget.video.bvid,
                  onVideoSelect: (video) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlayerScreen(video: video),
                      ),
                    );
                  },
                  onClose: () {
                    setState(() {
                      showRelatedPanel = false;
                      showControls = true;
                    });
                    startHideTimer();
                  },
                ),

              // 外掛跳過按鈕
              _buildSkipButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressPreview() {
    final total = videoController!.value.duration;
    final preview = previewPosition!;
    final progress = total.inMilliseconds > 0
        ? preview.inMilliseconds / total.inMilliseconds
        : 0.0;

    String formatDuration(Duration d) {
      final h = d.inHours;
      final m = d.inMinutes % 60;
      final s = d.inSeconds % 60;
      if (h > 0) {
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      }
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    return Positioned(
      bottom: 60,
      left: 40,
      right: 40,
      child: Column(
        children: [
          Text(
            '${formatDuration(preview)} / ${formatDuration(total)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFfb7299),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '← → 拖動  ↑ 取消  確定 跳轉',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  String _formatSeekTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildSkipButton() {
    if (currentSkipAction is! SkipActionShowButton) {
      return const SizedBox.shrink();
    }
    final action = currentSkipAction as SkipActionShowButton;

    return Positioned(
      bottom: 120,
      right: 40,
      child: Builder(
        builder: (context) {
          return Focus(
            autofocus: true, // Auto focus when it appears
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter)) {
                _executeSkip(action);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (ctx) {
                final hasFocus = Focus.of(ctx).hasFocus;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: hasFocus
                        ? Theme.of(context).primaryColor
                        : Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: hasFocus ? Colors.white : Colors.white30,
                      width: hasFocus ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.fast_forward,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        action.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _executeSkip(SkipActionShowButton action) {
    videoController!.seekTo(Duration(milliseconds: action.skipToMs));
    resetDanmakuIndex(Duration(milliseconds: action.skipToMs));
    setState(() {
      currentSkipAction = null;
    });
  }

  /// Netflix 式快退快進進度條與縮圖列
  Widget _buildNetflixSeekOverlay() {
    return SeekThumbnailStrip(
      videoshotData: videoshotData,
      previewPosition: previewPosition ?? videoController!.value.position,
      duration: videoController!.value.duration,
      previewFrameUrl: previewFrameUrl,
    );
  }
}
