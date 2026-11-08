import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/space_data.dart';
import '../../../services/settings_service.dart'; // BiliCacheManager
import '../../../utils/image_url_utils.dart';
import '../../../widgets/base_tv_card.dart';

/// 合集／系列卡片：封面（系列沒有封面時用預設圖示）、標題、數量。
class SpaceCollectionCard extends StatelessWidget {
  final SpaceCollection collection;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final FocusNode? focusNode;

  const SpaceCollectionCard({
    super.key,
    required this.collection,
    required this.onTap,
    required this.onFocus,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = collection.isSeries ? '系列' : '合集・${collection.count} 個影片';
    return BaseTvCard(
      focusNode: focusNode,
      onTap: onTap,
      onFocus: onFocus,
      onMoveLeft: onMoveLeft,
      onMoveRight: onMoveRight,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      imageContent: collection.cover.isEmpty
          ? Container(
              color: const Color(0xFF2d2d2d),
              child: const Center(
                child: Icon(
                  Icons.video_library_outlined,
                  size: 48,
                  color: Colors.white38,
                ),
              ),
            )
          : CachedNetworkImage(
              imageUrl: ImageUrlUtils.getResizedUrl(
                collection.cover,
                width: 360,
                height: 200,
              ),
              fit: BoxFit.cover,
              memCacheWidth: 360,
              memCacheHeight: 200,
              cacheManager: BiliCacheManager.instance,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (context, url) =>
                  Container(color: const Color(0xFF2d2d2d)),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[900],
                child: const Icon(
                  Icons.broken_image,
                  size: 20,
                  color: Colors.white24,
                ),
              ),
            ),
      infoContentBuilder: (context, isFocused) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 20,
            child: Text(
              collection.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isFocused ? Colors.white : Colors.white70,
                fontSize: 14,
                fontWeight: isFocused ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
