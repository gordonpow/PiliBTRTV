import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/settings_service.dart'; // BiliCacheManager

/// 交錯載入圖片元件
/// 用於在低端硬體上避免同時解碼多張圖片導致的卡頓
class StaggeredImage extends StatefulWidget {
  final String imageUrl;
  final int delayMs;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;

  const StaggeredImage({
    super.key,
    required this.imageUrl,
    this.delayMs = 0,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
  });

  @override
  State<StaggeredImage> createState() => _StaggeredImageState();
}

class _StaggeredImageState extends State<StaggeredImage> {
  bool _shouldLoad = false;

  @override
  void initState() {
    super.initState();
    if (widget.delayMs <= 0) {
      _shouldLoad = true;
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) {
          setState(() => _shouldLoad = true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldLoad) {
      // 佔位：顯示灰色背景，避免佈局跳動
      return Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey[900],
      );
    }

    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 150),
      child: CachedNetworkImage(
        imageUrl: widget.imageUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        memCacheWidth: widget.cacheWidth,
        memCacheHeight: widget.cacheHeight,
        cacheManager: BiliCacheManager.instance, // 使用有限制的快取管理器
        fadeInDuration: const Duration(milliseconds: 100),
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) => Container(color: Colors.grey[900]),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey[800],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      ),
    );
  }
}
