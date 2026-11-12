import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'setting_focus_target.dart';

/// 設定頁下拉選擇行元件
///
/// 使用統一的焦點管理系統，支援左右鍵切換選項
class SettingDropdownRow<T> extends StatefulWidget {
  final String label;
  final String? subtitle;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final FocusNode? sidebarFocusNode;
  final FocusNode? focusNode;
  final bool isFirst;
  final bool isLast;

  const SettingDropdownRow({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.onMoveUp,
    this.onMoveDown,
    this.sidebarFocusNode,
    this.focusNode,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  State<SettingDropdownRow<T>> createState() => _SettingDropdownRowState<T>();
}

class _SettingDropdownRowState<T> extends State<SettingDropdownRow<T>>
    with SettingFocusTargetMixin<SettingDropdownRow<T>> {
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

  void _nextValue() {
    final currentIndex = widget.items.indexOf(widget.value);
    final nextIndex = (currentIndex + 1) % widget.items.length;
    widget.onChanged(widget.items[nextIndex]);
  }

  void _prevValue() {
    final currentIndex = widget.items.indexOf(widget.value);
    final prevIndex =
        (currentIndex - 1 + widget.items.length) % widget.items.length;
    widget.onChanged(widget.items[prevIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusTargetNode,
      onKeyEvent: (node, event) {
        // 處理左右鍵導航和值切換
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            // 已在第一個值時回側欄，否則切到前一個值
            if (widget.items.indexOf(widget.value) <= 0) {
              widget.sidebarFocusNode?.requestFocus();
            } else {
              _prevValue();
            }
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
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.select:
            _nextValue();
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
