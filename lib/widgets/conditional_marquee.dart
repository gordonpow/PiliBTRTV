import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:bili_tv_app/widgets/content_text.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/widgets.dart' as flutter show Text;
import 'package:marquee/marquee.dart';

class ConditionalMarquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double blankSpace;
  final double velocity;
  final int? maxLines;
  final Duration pauseAfterRound;
  final bool alwaysScroll; // 如果為 true，則強制滾動（不推薦，除非無法計算寬度）

  /// true 表示 [text] 是 B 站內容（標題、UP 主名稱…），英文介面時走翻譯。
  final bool content;

  const ConditionalMarquee({
    super.key,
    required this.text,
    required this.style,
    this.blankSpace = 30.0,
    this.velocity = 50.0,
    this.maxLines = 1,
    this.pauseAfterRound = const Duration(seconds: 2),
    this.alwaysScroll = false,
    this.content = false,
  });

  @override
  State<ConditionalMarquee> createState() => _ConditionalMarqueeState();
}

class _ConditionalMarqueeState extends State<ConditionalMarquee> {
  late final ContentResolver _resolver = ContentResolver(
    () => setState(() {}),
    () => mounted,
  );

  String get _shown =>
      widget.content ? _resolver.display : ZhConvert.convert(widget.text);

  @override
  void initState() {
    super.initState();
    if (widget.content) _resolver.update(widget.text);
  }

  @override
  void didUpdateWidget(ConditionalMarquee old) {
    super.didUpdateWidget(old);
    if (old.content && !widget.content) _resolver.dispose();
    if (widget.content &&
        (old.text != widget.text || old.content != widget.content)) {
      _resolver.update(widget.text);
    }
  }

  @override
  void dispose() {
    _resolver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.alwaysScroll) {
      return _buildMarquee();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 使用 TextPainter 測量文本寬度
        final textPainter = TextPainter(
          text: TextSpan(text: _shown, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(minWidth: 0, maxWidth: double.infinity);

        // 如果文本寬度超出了容器的最大寬度，使用 Marquee
        if (textPainter.width > constraints.maxWidth) {
          return _buildMarquee();
        }

        // 否則顯示普通文本
        return flutter.Text(
          _shown,
          style: widget.style,
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  Widget _buildMarquee() {
    final shown = _shown;
    return Marquee(
      key: ValueKey(shown),
      text: shown,
      style: widget.style,
      scrollAxis: Axis.horizontal,
      crossAxisAlignment: CrossAxisAlignment.start,
      blankSpace: widget.blankSpace,
      velocity: widget.velocity,
      pauseAfterRound: widget.pauseAfterRound, // 預設停頓久一點
      startPadding: 0.0,
      accelerationDuration: const Duration(milliseconds: 500),
      accelerationCurve: Curves.linear,
      decelerationDuration: const Duration(milliseconds: 300),
      decelerationCurve: Curves.easeOut,
    );
  }
}
