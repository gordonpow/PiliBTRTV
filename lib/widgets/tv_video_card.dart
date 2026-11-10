import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/video.dart';
import 'base_tv_card.dart';
import 'staggered_image.dart';
import 'conditional_marquee.dart';
import '../services/settings_service.dart'; // 包含 BiliCacheManager
import '../utils/image_url_utils.dart';
import 'video_action_dialogs.dart';

class TvVideoCard extends StatelessWidget {
  final Video video;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onBack;
  final bool autofocus;
  final bool disableCache;
  final FocusNode? focusNode;
  final int? staggerIndex;

  /// 長按動作；預設為「影片選項」（收藏／稍後再看），番劇、直播、無 BV 號者不啟用
  final Future<void> Function()? onLongPress;

  /// 是否在播放數旁顯示彈幕數（預設不顯示，其他頁面外觀不變）
  final bool showDanmaku;

  const TvVideoCard({
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
    this.disableCache = false,
    this.focusNode,
    this.staggerIndex,
    this.onLongPress,
    this.showDanmaku = false,
  });

  bool get _menuEnabled =>
      !video.isPgc && !video.isLive && video.bvid.isNotEmpty;

  String get _durationText => video.durationFormatted;

  @override
  Widget build(BuildContext context) {
    return BaseTvCard(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap,
      onFocus: onFocus,
      onMoveLeft: onMoveLeft,
      onMoveRight: onMoveRight,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onBack: onBack,
      onLongPress:
          onLongPress ??
          (_menuEnabled ? () => showVideoActionMenu(context, video) : null),
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
          // 底部資訊
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Row(
              children: [
                const Icon(
                  Icons.play_arrow_rounded,
                  size: 14,
                  color: Colors.white70,
                ),
                if (!video.isPgc)
                  Text(
                    video.viewFormatted,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                if (showDanmaku && !video.isPgc && video.danmaku > 0) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.subtitles_outlined,
                    size: 13,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    video.danmakuFormatted,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
                const Spacer(),
                Text(
                  video.isPgc ? video.epIndexText : _durationText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
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
                  ? ConditionalMarquee(
                      text: video.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      blankSpace: 30.0,
                      velocity: 30.0, // 稍微慢一點
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

            // UP主資訊 + 釋出時間
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
                // 釋出時間 - 固定位置，不省略
                if (video.pubdateFormatted.isNotEmpty)
                  Text(
                    video.pubdateFormatted,
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
    // 360x200 必須與 SplashScreen 的 precache 引數完全一致
    const int targetWidth = 360;
    const int targetHeight = 200;

    // 交錯載入邏輯
    if (staggerIndex != null) {
      return StaggeredImage(
        imageUrl: ImageUrlUtils.getResizedUrl(
          video.pic,
          width: 360,
          height: 200,
        ),
        delayMs: staggerIndex! * 80,
        fit: BoxFit.cover,
        cacheWidth: targetWidth,
        cacheHeight: targetHeight,
      );
    }

    // 標準載入邏輯 (用於預載入過的資料或不需要交錯的資料)
    return CachedNetworkImage(
      imageUrl: ImageUrlUtils.getResizedUrl(video.pic, width: 360, height: 200),
      fit: BoxFit.cover,
      // 這裡的尺寸必須和 SplashScreen 完全一致
      memCacheWidth: targetWidth,
      memCacheHeight: targetHeight,
      // 快取管理器必須一致
      cacheManager: BiliCacheManager.instance,
      // 【核心修復】淡入時間設為 0，因為圖片已經在記憶體裡了，不需要動畫
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
