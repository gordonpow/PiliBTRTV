import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:bili_tv_app/widgets/content_text.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../mixins/player_state_mixin.dart';

/// 播完倒數時顯示在右下角的「接下來播放」卡片
class UpNextCard extends StatelessWidget {
  final UpNextInfo info;
  final int seconds;
  final int total;

  const UpNextCard({
    super.key,
    required this.info,
    required this.seconds,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 352,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '接下來播放',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 320,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: info.cover.isEmpty
                        ? const ColoredBox(color: Colors.white12)
                        : CachedNetworkImage(
                            imageUrl: info.cover,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) =>
                                const ColoredBox(color: Colors.white12),
                          ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          value: total > 0 ? seconds / total : 0,
                          strokeWidth: 3,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      Text(
                        '$seconds',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ContentText(
            info.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'OK 立即播放 · ↓ 更多影片 · 返回 取消',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
