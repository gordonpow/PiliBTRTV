import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

class VideoLayer extends StatelessWidget {
  final VideoPlayerController? controller;
  final bool isLoading;
  final String? errorMessage;

  /// 開播前顯示的封面（卡片已快取過，會立即出現），避免整個黑畫面轉圈
  final String? coverUrl;

  const VideoLayer({
    super.key,
    required this.controller,
    required this.isLoading,
    this.errorMessage,
    this.coverUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return Center(
        child: Text(
          errorMessage!,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }

    if (isLoading || controller == null || !controller!.value.isInitialized) {
      const spinner = CircularProgressIndicator(color: Color(0xFFfb7299));
      final cover = coverUrl;
      if (cover == null || cover.isEmpty) {
        return const Center(child: spinner);
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: cover,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          // 載入圈圈置中，加半透明圓底，亮色封面上也看得清楚
          Center(
            child: Container(
              width: 72,
              height: 72,
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: spinner,
            ),
          ),
        ],
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: controller!.value.aspectRatio,
        child: VideoPlayer(controller!),
      ),
    );
  }
}
