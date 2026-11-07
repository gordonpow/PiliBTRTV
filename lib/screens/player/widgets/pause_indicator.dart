import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:video_player/video_player.dart';

class PauseIndicator extends StatelessWidget {
  final VideoPlayerController? controller;

  const PauseIndicator({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller == null) return const SizedBox.shrink();

    // 由於 VideoPlayerValue 不是 ValueListenable，我們依賴父元件重建
    final isPlaying = controller!.value.isPlaying;
    final isBuffering = controller!.value.isBuffering;

    if (!isPlaying && !isBuffering) {
      return Center(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(20),
          child: const Icon(Icons.pause, color: Colors.white, size: 64),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
