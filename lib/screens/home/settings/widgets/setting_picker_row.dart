import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'setting_focus_target.dart';
import 'tv_menu_dialog.dart';

/// 設定頁選單選擇行元件
///
/// 按確定鍵開啟選單對話框（[showTvMenuDialog]）選擇；左右鍵不切換值
/// （左鍵回側邊欄，右鍵不動作），上下鍵照常導航。
class SettingPickerRow<T> extends StatefulWidget {
  final String label;
  final String? subtitle;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final String? menuTitle;
  final ValueChanged<T> onChanged;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final FocusNode? sidebarFocusNode;
  final FocusNode? focusNode;
  final bool isFirst;
  final bool isLast;

  const SettingPickerRow({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.menuTitle,
    this.onMoveUp,
    this.onMoveDown,
    this.sidebarFocusNode,
    this.focusNode,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  State<SettingPickerRow<T>> createState() => _SettingPickerRowState<T>();
}

class _SettingPickerRowState<T> extends State<SettingPickerRow<T>>
    with SettingFocusTargetMixin<SettingPickerRow<T>> {
  FocusNode? _ownNode;

  @override
  String get focusTargetLabel => widget.label;

  @override
  FocusNode get focusTargetNode =>
      widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  Future<void> _openMenu() async {
    final picked = await showTvMenuDialog<T>(
      context: context,
      title: widget.menuTitle ?? widget.label,
      items: widget.items,
      current: widget.value,
      itemLabel: widget.itemLabel,
    );
    if (picked == null) return;
    widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusTargetNode,
      onKeyEvent: (node, event) {
        // 處理左右鍵導航；確定鍵開啟選單
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            widget.sidebarFocusNode?.requestFocus();
            return KeyEventResult.handled;

          case LogicalKeyboardKey.arrowUp:
            if (widget.isFirst && widget.onMoveUp != null) {
              widget.onMoveUp!();
              return KeyEventResult.handled;
            }
            return widget.isFirst
                ? KeyEventResult.handled
                : KeyEventResult.ignored;

          case LogicalKeyboardKey.arrowDown:
            if (widget.isLast && widget.onMoveDown != null) {
              widget.onMoveDown!();
              return KeyEventResult.handled;
            }
            return widget.isLast
                ? KeyEventResult.handled
                : KeyEventResult.ignored;

          case LogicalKeyboardKey.arrowRight:
            return KeyEventResult.handled;

          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.select:
            _openMenu();
            return KeyEventResult.handled;

          default:
            return KeyEventResult.ignored;
        }
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: isFocused
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isFocused
                  ? Border.all(color: const Color(0xFFfb7299), width: 2)
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: isFocused ? Colors.white : Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      if (widget.subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            widget.subtitle!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isFocused
                        ? const Color(0xFFfb7299)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.itemLabel(widget.value),
                        style: TextStyle(
                          color: isFocused ? Colors.white : Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: isFocused ? Colors.white : Colors.white54,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
