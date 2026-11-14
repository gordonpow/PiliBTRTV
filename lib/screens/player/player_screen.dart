import 'package:bili_tv_app/services/translate/content_translator.dart';
import 'package:bili_tv_app/utils/anim.dart';
import '../../services/prefetch_service.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/plugin/plugin_types.dart';
import '../../models/video.dart';
import '../../services/settings_service.dart';
import '../../services/card_preview_service.dart';
import 'widgets/video_layer.dart';
import 'widgets/danmaku_layer.dart';
import 'widgets/subtitle_layer.dart';
import 'widgets/controls_overlay.dart';
import 'widgets/settings_panel.dart';
import 'widgets/episode_panel.dart';
import 'widgets/info_panel.dart';
import 'widgets/pause_indicator.dart';
import 'widgets/related_strip.dart';
import 'widgets/up_next_card.dart';
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

  /// > 0 時從這個分P開始（合集換片用）；其他入口維持原本的續播邏輯
  final int startCid;

  const PlayerScreen({super.key, required this.video, this.startCid = 0});

  /// 目前開著的播放頁數量；> 0 時卡片不暖機（避免覆寫 LocalServer 的 MPD）
  static int activeCount = 0;

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
    debugPrint('⏱ [E2E] open ${widget.video.bvid}');
    PlayerScreen.activeCount++;
    ContentTranslator.instance.changes.addListener(onTranslatorChanged);
    // 第一個 await 之前同步接手暖機播放器；沒有就釋放卡片預覽的解碼器。
    // 兩種畫面模式都接手暖機播放器；原生模式遇到 4K／HDR／杜比或直式影片
    // 才拒絕（見 CardPreviewService.warmRejectReason），改走冷啟動並沿用其資料。
    // 投放（forceStartMs）不接手暖機播放器
    final forced = widget.video.forceStartMs != null;
    warmPlayback = forced
        ? null
        : vetWarmPlayback(CardPreviewService.instance.take(widget.video.bvid));
    // 暖機還在準備且已保留給本頁時不要停掉它，initializePlayer 會等它完成
    if (warmPlayback == null &&
        (forced ||
            !CardPreviewService.instance.isPendingFor(widget.video.bvid))) {
      CardPreviewService.instance.stopAll();
    }
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
    PlayerScreen.activeCount--;
    ContentTranslator.instance.changes.removeListener(onTranslatorChanged);
    subtitleGen++; // 作廢進行中的字幕載入／翻譯
    // 接手了但還沒用到的暖機播放器要釋放
    warmPlayback?.controller.dispose();
    warmPlayback = null;
    // 恢復螢幕休眠
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    hideTimer?.cancel();
    cancelDanmakuHold();
    upNextTimer?.cancel();
    progressReportTimer?.cancel();
    // 退出時上報進度
    reportPlaybackProgress();

    FrameService.release();

    PrefetchService.instance.invalidate(widget.video.bvid);

    // 通過 mixin 方法銷燬播放器
    disposePlayer();
    playerFocusNode.dispose();
    videoActions.dispose();
    positionTick.dispose();
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
          focusNode: playerFocusNode,
          autofocus: true,
          onKeyEvent: handleGlobalKeyEvent,
          child: Stack(
            children: [
              // 影片層
              VideoLayer(
                controller: videoController,
                isLoading: isLoading,
                errorMessage: errorMessage,
                coverUrl: widget.video.pic,
              ),

              // 彈幕層
              if (!isLoading && videoController != null && danmakuEnabled)
                DanmakuLayer(
                  onCreated: (c) => danmakuController = c,
                  option: _danmakuOptionFor(),
                ),

              // CC 字幕層
              if (!isLoading &&
                  videoController != null &&
                  subtitleIndex >= 0 &&
                  subtitleLines.isNotEmpty)
                ValueListenableBuilder<int>(
                  valueListenable: positionTick,
                  builder: (context, _, _) => SubtitleLayer(
                    lines: subtitleLines,
                    position: videoController!.value.position,
                    controlsVisible: showControls,
                  ),
                ),

              // 暫停指示器
              if (!isLoading && videoController != null)
                PauseIndicator(controller: videoController),

              // 迷你進度條 (控制欄隱藏且非快退快進預覽時顯示；與控制列交替淡入淡出)
              if (!isLoading &&
                  videoController != null &&
                  SettingsService.showMiniProgress)
                ValueListenableBuilder<int>(
                  valueListenable: positionTick,
                  builder: (context, _, _) => MiniProgressBar(
                    visible:
                        !showSeekIndicator &&
                        !isSeekPreviewMode &&
                        !showControls,
                    position: videoController!.value.position,
                    duration: videoController!.value.duration,
                  ),
                ),

              // Netflix 式快退快進進度條與預覽卡片 (AC-B1)
              if (isSeekPreviewMode &&
                  previewPosition != null &&
                  videoController != null)
                _buildNetflixSeekOverlay()
              else if (showSeekIndicator && videoController != null)
                Center(
                  child: _fadeIn(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ValueListenableBuilder<int>(
                        valueListenable: positionTick,
                        builder: (context, _, _) => Text(
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
                  ),
                ),

              // 控制介面
              if (!isLoading && videoController != null)
                AnimatedOpacity(
                  opacity: showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: ValueListenableBuilder<int>(
                    valueListenable: positionTick,
                    builder: (context, _, _) => ControlsOverlay(
                      video: getDisplayVideo(),
                      controller: videoController!,
                      showControls: showControls,
                      focusedIndex: isCtrlBtnEnabled(focusedButtonIndex)
                          ? focusedButtonIndex
                          : CtrlBtn.playPause,
                      hasPrev: hasPrev,
                      hasNext: hasNext,
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
                      hasSubtitleTracks: subtitleTracks.isNotEmpty,
                      isSubtitleOn: subtitleIndex >= 0,
                      currentQuality: currentQualityDesc,
                      onQualityClick: showQualityPicker,
                      isProgressBarFocused: isProgressBarFocused,
                      previewPosition: previewPosition,
                      alwaysShowPlayerTime:
                          SettingsService.alwaysShowPlayerTime,
                      onlineCount: onlineCount,
                      actions: videoActions,
                    ),
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
                  playEndLabel: SettingsService.playRepeat.label,
                  subtitleTracks: subtitleTracks,
                  subtitleIndex: subtitleIndex,
                  audioOptions: audioOptions,
                  audioKind: currentAudioKind,
                  danmakuEnabled: danmakuEnabled,
                  danmakuOpacity: danmakuOpacity,
                  danmakuFontSize: danmakuFontSize,
                  danmakuArea: danmakuArea,
                  danmakuSpeed: danmakuSpeed,
                  hideTopDanmaku: hideTopDanmaku,
                  hideBottomDanmaku: hideBottomDanmaku,
                  onNavigate: (type, index) {
                    setState(() {
                      if (type == SettingsMenuType.danmaku) {
                        danmakuPanelDirect = false;
                      }
                      settingsMenuType = type;
                      focusedSettingIndex = index;
                    });
                  },
                  onQualityPicker: showQualityPicker,
                ),

              // 簡介／留言面板
              if (showInfoPanel)
                InfoPanel(
                  videoInfo: fullVideoInfo,
                  aid: aid ?? 0,
                  isPgc: isPgc,
                  onClose: closeInfoPanel,
                ),

              // 播完倒數卡片
              if (upNextSeconds != null && upNextInfo != null)
                Positioned(
                  right: 32,
                  bottom: 48,
                  child: EnterTransition(
                    offset: const Offset(0.15, 0.15),
                    child: UpNextCard(
                      info: upNextInfo!,
                      seconds: upNextSeconds!,
                      total: upNextTotal,
                    ),
                  ),
                ),

              // 相關影片底部橫排
              if (showRelatedPanel)
                RelatedStrip(
                  bvid: playingBvid,
                  seasonId: isPgc ? widget.video.seasonId : 0,
                  expanded: relatedExpanded,
                  onExpandedChanged: _onRelatedExpandedChanged,
                  onVideoSelect: navigateTo,
                  onClose: closeRelatedStrip,
                ),

              // 外掛跳過按鈕
              _buildSkipButton(),
            ],
          ),
        ),
      ),
    );
  }

  void _onRelatedExpandedChanged(bool v) => setState(() => relatedExpanded = v);

  // 彈幕設定沒變時沿用同一個 DanmakuOption，避免每次 build 新建
  DanmakuOption? _cachedDanmakuOption;
  Object? _cachedDanmakuKey;

  DanmakuOption _danmakuOptionFor() {
    final key = Object.hash(
      danmakuOpacity,
      danmakuFontSize,
      danmakuSpeed / playbackSpeed,
      danmakuArea,
      hideTopDanmaku,
      hideBottomDanmaku,
    );
    if (_cachedDanmakuOption == null || _cachedDanmakuKey != key) {
      _cachedDanmakuKey = key;
      _cachedDanmakuOption = DanmakuOption(
        opacity: danmakuOpacity,
        fontSize: danmakuFontSize,
        // 彈幕飛行速度隨播放倍速同步調整
        duration: danmakuSpeed / playbackSpeed,
        area: danmakuArea,
        hideTop: hideTopDanmaku,
        hideBottom: hideBottomDanmaku,
      );
    }
    return _cachedDanmakuOption!;
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
      child: _fadeIn(
        Column(
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
      ),
    );
  }

  /// 掛上時淡入 120ms（快退快進時間提示用）；低記憶體裝置不做動畫
  Widget _fadeIn(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Anim.of(const Duration(milliseconds: 120)),
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: child,
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
      child: EnterTransition(
        child: Builder(
          builder: (context) {
            return Focus(
              autofocus: true, // Auto focus when it appears
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.select ||
                        event.logicalKey == LogicalKeyboardKey.enter)) {
                  executeSkipAction();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (ctx) {
                  final hasFocus = Focus.of(ctx).hasFocus;
                  return AnimatedContainer(
                    duration: Anim.of(Anim.fast),
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
      ),
    );
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
