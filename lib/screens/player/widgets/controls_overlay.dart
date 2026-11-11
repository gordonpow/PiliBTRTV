import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:bili_tv_app/widgets/content_text.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:video_player/video_player.dart';
import '../../../models/video.dart';
import '../../../widgets/time_display.dart';
import '../../../widgets/conditional_marquee.dart';
import '../mixins/player_state_mixin.dart' show CtrlBtn;
import '../video_actions_controller.dart';
import 'tv_progress_bar.dart';
import '../../../services/settings_service.dart';

class ControlsOverlay extends StatelessWidget {
  final Video video;
  final VideoPlayerController controller;
  final bool showControls;
  final int focusedIndex;
  final VoidCallback onPlayPause;
  final VoidCallback onSettings;
  final VoidCallback onEpisodes;
  final bool isDanmakuEnabled;
  final VoidCallback onToggleDanmaku;
  final bool hasSubtitleTracks; // 沒有字幕軌時字幕按鈕變暗
  final bool isSubtitleOn;
  final String currentQuality;
  final VoidCallback onQualityClick;
  final bool isProgressBarFocused; // 進度條是否獲得焦點
  final Duration? previewPosition; // 預覽位置（快進快退時）
  final String? onlineCount; // 線上觀看人數
  final VideoActionsController actions; // 點讚／投幣／收藏狀態與動作
  final bool hasPrev; // 沒有上一部時按鈕變暗
  final bool hasNext; // 沒有下一部時按鈕變暗

  const ControlsOverlay({
    super.key,
    required this.video,
    required this.controller,
    required this.showControls,
    required this.focusedIndex,
    required this.onPlayPause,
    required this.onSettings,
    required this.onEpisodes,
    required this.isDanmakuEnabled,
    required this.onToggleDanmaku,
    required this.hasSubtitleTracks,
    required this.isSubtitleOn,
    required this.currentQuality,
    required this.onQualityClick,
    required this.actions,
    this.isProgressBarFocused = false,
    this.previewPosition,
    this.alwaysShowPlayerTime = false,
    this.onlineCount,
    this.hasPrev = false,
    this.hasNext = false,
  });

  final bool alwaysShowPlayerTime;

  /// 底部控制區（含上方漸層留白）目前的實際高度，字幕層用來避開控制列。
  static final ValueNotifier<double> bottomHeight = ValueNotifier<double>(0);

  /// 底部控制區內容（進度條）上緣距離控制區頂端的留白。
  static const double bottomTopPadding = 40;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    if (h > 0) return '${twoDigits(h)}:${twoDigits(m)}:${twoDigits(s)}';
    return '${twoDigits(m)}:${twoDigits(s)}';
  }

  // 構建影片資訊：UP 主名稱是 B 站內容（走 ContentText），其餘為介面字串
  Widget _buildVideoInfo() {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.7),
      fontSize: 18,
    );
    // 每段各自走字典（整串合併會對不到「{0}天前」等 template）
    final rest = <String>[];
    if (video.pubdate > 0) {
      rest.add(
        ZhConvert.convert('釋出於${ZhConvert.convert(video.pubdateFormatted)}'),
      );
    }
    if (video.view > 0) {
      rest.add(ZhConvert.convert('${video.viewFormatted}次觀看'));
    }
    return Row(
      children: [
        Flexible(
          child: ContentText(
            video.ownerName,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (rest.isNotEmpty) Text(' · ${rest.join(' · ')}', style: style),
      ],
    );
  }

  static const Color accent = Color(0xFFfb7299);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: actions,
      builder: (context, _) => _buildContent(),
    );
  }

  Widget _buildContent() {
    // 計算緩衝時長
    Duration buffered = Duration.zero;
    if (controller.value.buffered.isNotEmpty) {
      buffered = controller.value.buffered.last.end;
    }

    return Stack(
      children: [
        // 頂部漸變 + 標題
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            // 右側預留空間給時間顯示 (150)
            padding: const EdgeInsets.fromLTRB(40, 20, 150, 40),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.8),
                  Colors.transparent,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 30, // 固定高度
                        child: ConditionalMarquee(
                          text: video.title.isNotEmpty ? video.title : '載入中...',
                          content: video.title.isNotEmpty,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22, // 固定字號
                            fontWeight: FontWeight.bold,
                          ),
                          blankSpace: 50.0,
                          velocity: 40.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _buildVideoInfo(),
              ],
            ),
          ),
        ),

        // 頂部時間顯示 (僅當非全域性常駐時顯示)
        // 位置與 PlayerScreen 的常駐時間保持一致 (top: 20, right: 30)
        // 注意：Global Time 在 PlayerScreen 中處理，這裡只處理 Controls overlay 內部的臨時顯示
        if (!alwaysShowPlayerTime)
          const Positioned(top: 20, right: 30, child: TimeDisplay()),

        // 右上角時間下方：在看人數與畫質
        Positioned(
          top: 54,
          right: 30,
          child: Text(
            [
              if (onlineCount != null && onlineCount!.isNotEmpty)
                '在看:$onlineCount',
              currentQuality,
            ].join(' · '),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
        ),

        // 底部控制區
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _MeasureHeight(
            onHeight: (h) => bottomHeight.value = h,
            child: Container(
              padding: const EdgeInsets.fromLTRB(40, bottomTopPadding, 40, 25),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 進度條
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TvProgressBar(
                          position:
                              previewPosition ?? controller.value.position,
                          duration: controller.value.duration,
                          buffered: buffered,
                          isFocused: isProgressBarFocused,
                          previewPosition: previewPosition,
                        ),
                      ),
                      const SizedBox(width: 20),
                      // 放大時間碼字型
                      Text(
                        '${_formatDuration(previewPosition ?? controller.value.position)} / ${_formatDuration(controller.value.duration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildControlButton(
                        index: CtrlBtn.prev,
                        icon: Icons.skip_previous,
                        enabled: hasPrev,
                      ),
                      const SizedBox(width: 12),
                      _buildControlButton(
                        index: CtrlBtn.playPause,
                        icon: controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                      const SizedBox(width: 12),
                      _buildControlButton(
                        index: CtrlBtn.next,
                        icon: Icons.skip_next,
                        enabled: hasNext,
                      ),
                      const SizedBox(width: 12),
                      _buildControlButton(
                        index: CtrlBtn.episodes,
                        icon: Icons.playlist_play,
                      ),
                      const SizedBox(width: 12),
                      _buildControlButton(
                        index: CtrlBtn.up,
                        icon: Icons.person,
                      ),
                      const SizedBox(width: 12),
                      _buildControlButton(
                        index: CtrlBtn.danmaku,
                        icon: isDanmakuEnabled
                            ? Icons.subtitles
                            : Icons.subtitles_off,
                      ),
                      const SizedBox(width: 12),
                      _buildControlButton(
                        index: CtrlBtn.subtitle,
                        icon: isSubtitleOn
                            ? Icons.closed_caption
                            : Icons.closed_caption_off,
                        enabled: hasSubtitleTracks,
                      ),
                      const SizedBox(width: 12),
                      _buildControlButton(
                        index: CtrlBtn.settings,
                        icon: Icons.tune,
                      ),
                      // 左側按鈕群與右側（讚/幣/藏）至少間隔 48，避免字幕鈕加入後貼在一起
                      const Spacer(),
                      // 依設定過濾後，按鈕之間才補間距；全部隱藏時不留間距
                      for (final (i, btn) in [
                        if (SettingsService.showLikeButton)
                          _buildControlButton(
                            index: CtrlBtn.like,
                            icon: actions.isLiked
                                ? Icons.thumb_up
                                : Icons.thumb_up_outlined,
                            iconColor: actions.isLiked ? accent : Colors.white,
                          ),
                        if (SettingsService.showCoinButton)
                          _buildControlButton(
                            index: CtrlBtn.coin,
                            icon: actions.coinCount > 0
                                ? Icons.monetization_on
                                : Icons.monetization_on_outlined,
                            iconColor: actions.coinCount > 0
                                ? accent
                                : Colors.white,
                          ),
                        if (SettingsService.showFavButton)
                          _buildControlButton(
                            index: CtrlBtn.fav,
                            icon: actions.isFavorited
                                ? Icons.star
                                : Icons.star_border,
                            iconColor: actions.isFavorited
                                ? accent
                                : Colors.white,
                          ),
                      ].indexed) ...[SizedBox(width: i == 0 ? 48 : 12), btn],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required int index,
    required IconData icon,
    bool enabled = true,
    Color iconColor = Colors.white,
  }) {
    final isFocused =
        !isProgressBarFocused && focusedIndex == index && showControls;
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isFocused
              ? const Color(0xFFfb7299).withValues(alpha: 0.8)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: isFocused ? Border.all(color: Colors.white, width: 3) : null,
        ),
        child: Icon(icon, color: iconColor, size: 36),
      ),
    );
  }
}

/// 每次 build 後回報子樹高度（變動才回報）。
class _MeasureHeight extends StatefulWidget {
  const _MeasureHeight({required this.onHeight, required this.child});

  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  State<_MeasureHeight> createState() => _MeasureHeightState();
}

class _MeasureHeightState extends State<_MeasureHeight> {
  double _last = -1;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = context.size?.height;
      if (h == null || (h - _last).abs() < 0.5) return;
      _last = h;
      widget.onHeight(h);
    });
    return widget.child;
  }
}
