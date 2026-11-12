import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import '../utils/anim.dart';

/// 通用 TV 橫向分頁標籤列：左右鍵切換、聚焦即選取。
/// 樣式與首頁分類標籤一致（粉紅字＋底線，焦點時粉紅底）。
class TvTabBar extends StatelessWidget {
  final List<String> labels;
  final List<FocusNode> focusNodes;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback? onMoveLeftAtFirst;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// 最後一個分頁按右鍵（例如移到分頁列右側的按鈕）
  final VoidCallback? onMoveRightAtLast;
  final double fontSize;

  const TvTabBar({
    super.key,
    required this.labels,
    required this.focusNodes,
    required this.selectedIndex,
    required this.onSelect,
    this.onMoveLeftAtFirst,
    this.onMoveUp,
    this.onMoveDown,
    this.onMoveRightAtLast,
    this.fontSize = 20,
  }) : assert(labels.length == focusNodes.length);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: List.generate(labels.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Focus(
              focusNode: focusNodes[i],
              onFocusChange: (f) {
                if (!f) return;
                final ctx = focusNodes[i].context;
                if (ctx != null) {
                  Scrollable.ensureVisible(
                    ctx,
                    duration: const Duration(milliseconds: 200),
                    alignment: 0.5,
                  );
                }
                if (i != selectedIndex) onSelect(i);
              },
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.arrowLeft) {
                  if (i == 0) {
                    if (onMoveLeftAtFirst == null) {
                      return KeyEventResult.ignored;
                    }
                    onMoveLeftAtFirst!();
                  } else {
                    focusNodes[i - 1].requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowRight) {
                  if (i + 1 < focusNodes.length) {
                    focusNodes[i + 1].requestFocus();
                  } else {
                    onMoveRightAtLast?.call();
                  }
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowDown) {
                  onMoveDown?.call();
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowUp) {
                  if (onMoveUp == null) return KeyEventResult.ignored;
                  onMoveUp!();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (ctx) {
                  final f = Focus.of(ctx).hasFocus;
                  final selected = i == selectedIndex;
                  return GestureDetector(
                    onTap: () => focusNodes[i].requestFocus(),
                    child: AnimatedContainer(
                      duration: Anim.of(Anim.fast),
                      curve: Anim.curve,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      decoration: BoxDecoration(
                        color: f ? const Color(0xFFfb7299) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: f ? Colors.white : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            labels[i],
                            style: TextStyle(
                              color: f
                                  ? Colors.white
                                  : (selected
                                        ? const Color(0xFFfb7299)
                                        : Colors.grey),
                              fontSize: fontSize,
                              fontWeight: f || selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 3,
                            width: 20,
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFFfb7299)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }),
      ),
    );
  }
}
