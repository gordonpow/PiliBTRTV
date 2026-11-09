import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:video_player/video_player.dart';
import '../../../models/video.dart';
import '../../../widgets/time_display.dart';
import '../../../widgets/conditional_marquee.dart';
import 'tv_progress_bar.dart';

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
  final String currentQuality;
  final VoidCallback onQualityClick;
  final bool isProgressBarFocused; // 進度條是否獲得焦點
  final Duration? previewPosition; // 預覽位置（快進快退時）
  final String? onlineCount; // 線上觀看人數
  final int danmakuCount; // 彈幕總數

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
    required this.currentQuality,
    required this.onQualityClick,
    this.isProgressBarFocused = false,
    this.previewPosition,
    this.alwaysShowPlayerTime = false,
    this.onlineCount,
    this.danmakuCount = 0,
  });

  final bool alwaysShowPlayerTime;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    if (h > 0) return '${twoDigits(h)}:${twoDigits(m)}:${twoDigits(s)}';
    return '${twoDigits(m)}:${twoDigits(s)}';
  }

  // 構建影片資訊文本
  String _buildVideoInfoText() {
    final parts = <String>[];
    parts.add(video.ownerName);
    if (video.pubdate > 0) {
      parts.add('釋出於${video.pubdateFormatted}');
    }
    if (video.view > 0) {
      parts.add('${video.viewFormatted}次觀看');
    }
    return parts.join(' · ');
  }

  // 格式化彈幕數
  String _formatDanmakuCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}萬';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
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
                Text(
                  _buildVideoInfoText(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ),

        // 頂部時間顯示 (僅當非全域性常駐時顯示)
        // 位置與 PlayerScreen 的常駐時間保持一致 (top: 20, right: 30)
        // 注意：Global Time 在 PlayerScreen 中處理，這裡只處理 Controls overlay 內部的臨時顯示
        if (!alwaysShowPlayerTime)
          const Positioned(top: 20, right: 30, child: TimeDisplay()),

        // 底部控制區
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(40, 40, 40, 25),
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
                        position: previewPosition ?? controller.value.position,
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
                    // 播放/暫停 (index 0)
                    _buildControlButton(
                      index: 0,
                      icon: controller.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      onTap: onPlayPause,
                    ),
                    const SizedBox(width: 24),
                    // 選集 (index 1)
                    _buildControlButton(
                      index: 1,
                      icon: Icons.playlist_play,
                      onTap: onEpisodes,
                    ),
                    const SizedBox(width: 24),
                    // UP主 (index 2)
                    _buildControlButton(
                      index: 2,
                      icon: Icons.person,
                      onTap: () {},
                    ),
                    const SizedBox(width: 24),
                    // 更多影片 (index 3)
                    _buildControlButton(
                      index: 3,
                      icon: Icons.expand_more,
                      onTap: () {},
                    ),
                    const SizedBox(width: 24),
                    // 設定 (index 4)
                    _buildControlButton(
                      index: 4,
                      icon: Icons.tune,
                      onTap: onSettings,
                    ),
                    const SizedBox(width: 24),
                    // 點贊/投幣/收藏 (index 5)
                    _buildControlButton(
                      index: 5,
                      icon: Icons.thumb_up_outlined,
                      onTap: () {},
                    ),
                    const Spacer(),
                    // 線上人數 (純文字)
                    if (onlineCount != null && onlineCount!.isNotEmpty)
                      Text(
                        '在看:$onlineCount',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                      ),
                    if (onlineCount != null && onlineCount!.isNotEmpty)
                      const SizedBox(width: 16),
                    // 彈幕數 (純文字)
                    Text(
                      isDanmakuEnabled && danmakuCount > 0
                          ? '彈幕:${_formatDanmakuCount(danmakuCount)}'
                          : (isDanmakuEnabled ? '彈幕' : '彈幕關'),
                      style: TextStyle(
                        color: isDanmakuEnabled
                            ? Colors.white.withValues(alpha: 0.8)
                            : Colors.white.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 畫質 (純文字)
                    Text(
                      currentQuality,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required int index,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isFocused =
        !isProgressBarFocused && focusedIndex == index && showControls;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isFocused
            ? const Color(0xFFfb7299).withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: isFocused ? Border.all(color: Colors.white, width: 3) : null,
      ),
      child: Icon(icon, color: Colors.white, size: 36),
    );
  }
}
