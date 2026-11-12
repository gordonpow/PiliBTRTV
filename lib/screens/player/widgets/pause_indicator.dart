import 'package:bili_tv_app/utils/anim.dart';
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
      // 出現時淡入並由 0.8 倍放大到 1 倍；消失不做動畫
      return Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Anim.of(Anim.fast),
          curve: Anim.curve,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.8 + 0.2 * t, child: child),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(20),
            child: const Icon(Icons.pause, color: Colors.white, size: 64),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
