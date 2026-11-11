import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';

import '../../../models/subtitle.dart';
import 'controls_overlay.dart';

/// CC 字幕層：依播放位置在 build 時二分搜尋當前行（R-11）。
class SubtitleLayer extends StatelessWidget {
  final List<SubtitleLine> lines;
  final Duration position;
  final bool controlsVisible;

  const SubtitleLayer({
    super.key,
    required this.lines,
    required this.position,
    required this.controlsVisible,
  });

  @override
  Widget build(BuildContext context) {
    final line = findSubtitleLine(lines, position.inMilliseconds / 1000.0);
    if (line == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: ValueListenableBuilder<double>(
        valueListenable: ControlsOverlay.bottomHeight,
        builder: (context, h, child) => Padding(
          // 控制列顯示時，字幕整個放在進度條上方（控制區高度扣掉頂端留白，再留 12）
          padding: EdgeInsets.only(
            left: 120,
            right: 120,
            bottom: controlsVisible
                ? (h - ControlsOverlay.bottomTopPadding + 12).clamp(48.0, 600.0)
                : 48,
          ),
          child: Align(alignment: Alignment.bottomCenter, child: child),
        ),
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                ZhConvert.convertContent(line.content),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
