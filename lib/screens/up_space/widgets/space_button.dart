import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';

/// 讓 [ctx] 捲動到可見範圍（TV 焦點移動用）。
void spaceEnsureVisible(BuildContext ctx, double alignment) {
  if (!ctx.mounted) return;
  Scrollable.ensureVisible(
    ctx,
    alignment: alignment,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOutCubic,
  );
}

/// 膠囊樣式（按鈕外觀），聚焦時外圍加白框。
Widget spacePill({
  required bool focused,
  required Color color,
  required double horizontal,
  required String label,
  IconData? icon,
  double fontSize = 15,
}) {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    padding: EdgeInsets.all(focused ? 4 : 0),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      border: focused ? Border.all(color: Colors.white, width: 2) : null,
    ),
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(color: Colors.white, fontSize: fontSize),
          ),
        ],
      ),
    ),
  );
}

/// 可聚焦按鈕：方向鍵由回呼處理（未提供者吞掉按鍵，不讓焦點亂跳）。
class SpaceButton extends StatefulWidget {
  final FocusNode focusNode;
  final bool autofocus;
  final VoidCallback onTap;
  final void Function(BuildContext context)? onFocus;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final Widget Function(bool focused) builder;

  const SpaceButton({
    super.key,
    required this.focusNode,
    required this.onTap,
    required this.builder,
    this.onFocus,
    this.autofocus = false,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
  });

  @override
  State<SpaceButton> createState() => _SpaceButtonState();
}

class _SpaceButtonState extends State<SpaceButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) widget.onFocus?.call(context);
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          if (event is KeyDownEvent) widget.onTap();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          widget.onLeft?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          widget.onRight?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          if (event is KeyDownEvent) widget.onUp?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          if (event is KeyDownEvent) widget.onDown?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: widget.builder(_focused),
    );
  }
}
