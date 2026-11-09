import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:marquee/marquee.dart';
import '../models/video.dart';
import '../services/settings_service.dart';
import 'base_tv_card.dart';
import '../utils/image_url_utils.dart';
import '../screens/live/live_player_screen.dart';

/// 歷史記錄專用影片卡片
/// 特點：
/// 1. 不顯示播放數（介面返回0）
/// 2. 顯示進度條和 xx:xx/yy:yy 格式的進度
/// 3. 播放完成顯示"已播完"
class HistoryVideoCard extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onBack;
  final bool autofocus;
  final FocusNode? focusNode;

  const HistoryVideoCard({
    super.key,
    required this.video,
    required this.onTap,
    required this.onFocus,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
    this.onBack,
    this.autofocus = false,
    this.focusNode,
  });

  /// 是否已播完（B站API返回 progress == -1 表示已看完）
  /// 或者進度非常接近總時長（允許1秒誤差，解決 19:33/19:33 顯示問題且不影響短影片）
  bool get _isCompleted {
    if (video.progress == -1) return true;
    if (video.duration > 0 && video.progress >= video.duration - 1) return true;
    return false;
  }

  /// 觀看進度比例 (0.0 ~ 1.0)
  double get _progressRatio {
    if (_isCompleted) return 1.0;
    if (video.duration <= 0 || video.progress <= 0) return 0.0;
    return (video.progress / video.duration).clamp(0.0, 1.0);
  }

  /// 格式化進度時間
  String _formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return BaseTvCard(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: () {
        // 只有當是直播且沒有 BVID 時（表示是直播間而非回放影片）才跳轉直播播放器
        // "直播回放"通常有 BVID，應作為普通影片播放
        if (video.isLive && video.bvid.isEmpty) {
          // 與伺服器回傳的簡體文字比對，保留原文
          if (video.badge == '未开播') {
            SettingsService.toast(context, '當前未開播');
            return;
          }

          // Navigate to LivePlayerScreen
          // For live history, cid is mapped from oid which is the room id
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LivePlayerScreen(
                roomId: video.cid,
                title: video.title,
                cover: video.pic,
                uname: video.ownerName,
                face: video.ownerFace,
                online: 0, // History doesn't have real-time online count
              ),
            ),
          );
          return;
        }
        onTap();
      },
      onFocus: onFocus,
      onMoveLeft: onMoveLeft,
      onMoveRight: onMoveRight,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onBack: onBack,
      previewVideo: video.isLive ? null : video,
      imageContent: Stack(
        fit: StackFit.expand,
        children: [
          _buildImage(),
          // 角標 (付費/充電專屬)
          if (video.badge.isNotEmpty)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFfb7299),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  video.badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          // 漸變遮罩
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 60,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.9),
                  ],
                ),
              ),
            ),
          ),
          // 底部資訊 - 歷史記錄顯示進度
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 時間資訊
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 左側：分P資訊（多P影片顯示，單P影片隱藏）
                      // historyVideos > 1 表示多P影片，顯示"已看至 Px"
                      if (video.historyVideos > 1)
                        Text(
                          '已看至 P${video.historyPage}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (video.historyVideos <= 1) const SizedBox(), // 佔位
                      // 右側：時間/進度 (直播/未開播不顯示)
                      if (!video.isLive)
                        Text(
                          _isCompleted
                              ? '已看完'
                              : '${_formatTime(video.progress > 0 ? video.progress : 0)} / ${_formatTime(video.duration)}',
                          style: TextStyle(
                            color: _isCompleted
                                ? const Color(0xFFfb7299)
                                : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // 進度條 - 貼底，全寬，無圓角
                SizedBox(
                  height: 3,
                  child: Stack(
                    children: [
                      // 背景條
                      Container(color: Colors.white.withValues(alpha: 0.3)),
                      // 進度條
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _progressRatio,
                        child: Container(color: const Color(0xFFfb7299)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      infoContentBuilder: (context, isFocused) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題區域
            SizedBox(
              height: 20,
              child: isFocused
                  ? Marquee(
                      text: ZhConvert.convert(video.title),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      scrollAxis: Axis.horizontal,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      blankSpace: 30.0,
                      velocity: 50.0,
                      pauseAfterRound: const Duration(seconds: 1),
                      startPadding: 0.0,
                      accelerationDuration: const Duration(milliseconds: 500),
                      accelerationCurve: Curves.linear,
                      decelerationDuration: const Duration(milliseconds: 300),
                      decelerationCurve: Curves.easeOut,
                    )
                  : Text(
                      video.title,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            // UP主資訊 + 觀看時間
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 12,
                  color: Colors.white38,
                ),
                const SizedBox(width: 4),
                // UP主名字 - 可省略
                Expanded(
                  child: Text(
                    video.ownerName,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 最後觀看時間 - 固定位置，不省略
                if (video.viewAtFormatted.isNotEmpty)
                  Text(
                    video.viewAtFormatted,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildImage() {
    const int targetWidth = 360;
    const int targetHeight = 200;

    return CachedNetworkImage(
      imageUrl: ImageUrlUtils.getResizedUrl(video.pic, width: 640, height: 360),
      fit: BoxFit.cover,
      memCacheWidth: targetWidth,
      memCacheHeight: targetHeight,
      cacheManager: BiliCacheManager.instance,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) => Container(color: const Color(0xFF2d2d2d)),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[900],
        child: const Icon(Icons.broken_image, size: 20, color: Colors.white24),
      ),
    );
  }
}
