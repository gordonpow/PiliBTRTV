import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:marquee/marquee.dart';

class ConditionalMarquee extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double blankSpace;
  final double velocity;
  final int? maxLines;
  final bool alwaysScroll; // 如果為 true，則強制滾動（不推薦，除非無法計算寬度）

  const ConditionalMarquee({
    super.key,
    required this.text,
    required this.style,
    this.blankSpace = 30.0,
    this.velocity = 50.0,
    this.maxLines = 1,
    this.alwaysScroll = false,
  });

  @override
  Widget build(BuildContext context) {
    if (alwaysScroll) {
      return _buildMarquee();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 使用 TextPainter 測量文本寬度
        final textPainter = TextPainter(
          text: TextSpan(text: ZhConvert.convert(text), style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(minWidth: 0, maxWidth: double.infinity);

        // 如果文本寬度超出了容器的最大寬度，使用 Marquee
        if (textPainter.width > constraints.maxWidth) {
          return _buildMarquee();
        }

        // 否則顯示普通文本
        return Text(
          text,
          style: style,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  Widget _buildMarquee() {
    return Marquee(
      text: ZhConvert.convert(text),
      style: style,
      scrollAxis: Axis.horizontal,
      crossAxisAlignment: CrossAxisAlignment.start,
      blankSpace: blankSpace,
      velocity: velocity,
      pauseAfterRound: const Duration(seconds: 2), // 停頓久一點
      startPadding: 0.0,
      accelerationDuration: const Duration(milliseconds: 500),
      accelerationCurve: Curves.linear,
      decelerationDuration: const Duration(milliseconds: 300),
      decelerationCurve: Curves.easeOut,
    );
  }
}
