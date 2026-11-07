import 'package:bili_tv_app/widgets/zh_material.dart';

/// TV 遙控器最佳化的影片進度條
///
/// 特性:
/// - 圓點指示器顯示當前位置
/// - 支援焦點高亮
/// - 顯示緩衝進度
class TvProgressBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool isFocused;
  final Duration? previewPosition; // 預覽位置（快進/快退時顯示）

  const TvProgressBar({
    super.key,
    required this.position,
    required this.duration,
    this.buffered = Duration.zero,
    this.isFocused = false,
    this.previewPosition,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final positionMs = position.inMilliseconds;
    final bufferedMs = buffered.inMilliseconds;
    final previewMs = previewPosition?.inMilliseconds;

    // 計算百分比
    final progress = totalMs > 0 ? positionMs / totalMs : 0.0;
    final bufferedProgress = totalMs > 0 ? bufferedMs / totalMs : 0.0;
    final previewProgress = (previewMs != null && totalMs > 0)
        ? previewMs / totalMs
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final dotX = progress * width;
        final previewDotX = previewProgress != null
            ? previewProgress * width
            : null;

        return SizedBox(
          height: 40, // 增加高度以容納預覽標籤
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 進度條主體
              Positioned(
                left: 0,
                right: 0,
                top: 16,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: Colors.grey.withValues(alpha: 0.3),
                  ),
                  child: Stack(
                    children: [
                      // 緩衝進度
                      FractionallySizedBox(
                        widthFactor: bufferedProgress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: Colors.white24,
                          ),
                        ),
                      ),
                      // 已播放進度
                      FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: const Color(0xFFfb7299), // B站粉
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 預覽位置指示器（快進/快退時）
              if (previewDotX != null && previewProgress != null)
                Positioned(
                  left: previewDotX.clamp(10.0, width - 10.0) - 10,
                  top: 8,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: const Color(0xFFfb7299),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.6),
                          blurRadius: 10,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),

              // 當前位置圓點
              if (previewDotX == null) // 正常播放時顯示
                Positioned(
                  left: dotX.clamp(8.0, width - 8.0) - 8,
                  top: isFocused ? 8 : 10,
                  child: Container(
                    width: isFocused ? 20 : 16,
                    height: isFocused ? 20 : 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFfb7299),
                      border: isFocused
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                      boxShadow: isFocused
                          ? [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.6),
                                blurRadius: 12,
                                spreadRadius: 3,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),

              // 預覽時間標籤
              if (previewPosition != null && previewDotX != null)
                Positioned(
                  left: (previewDotX - 30).clamp(0.0, width - 60),
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatDuration(previewPosition!),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
