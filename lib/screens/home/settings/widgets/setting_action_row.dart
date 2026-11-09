import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../../../core/focus/focus_navigation.dart';
import 'setting_focus_target.dart';

/// 設定頁操作按鈕行元件
///
/// 使用統一的焦點管理系統
class SettingActionRow extends StatefulWidget {
  final String label;
  final String value;
  final String buttonLabel;
  final VoidCallback? onTap;
  final bool autofocus;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final FocusNode? sidebarFocusNode;
  final FocusNode? focusNode;
  final bool isFirst;
  final bool isLast;

  /// 值文字旁是否顯示紅點
  final bool showDot;

  const SettingActionRow({
    super.key,
    required this.label,
    required this.value,
    required this.buttonLabel,
    required this.onTap,
    this.autofocus = false,
    this.onMoveUp,
    this.onMoveDown,
    this.sidebarFocusNode,
    this.focusNode,
    this.isFirst = false,
    this.isLast = false,
    this.showDot = false,
  });

  @override
  State<SettingActionRow> createState() => _SettingActionRowState();
}

class _SettingActionRowState extends State<SettingActionRow>
    with SettingFocusTargetMixin<SettingActionRow> {
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

  @override
  Widget build(BuildContext context) {
    return TvFocusScope(
      pattern: FocusPattern.vertical,
      focusNode: focusTargetNode,
      autofocus: widget.autofocus,
      exitLeft: widget.sidebarFocusNode,
      onExitUp: widget.isFirst ? widget.onMoveUp : null,
      onExitDown: widget.isLast ? widget.onMoveDown : null,
      isFirst: widget.isFirst,
      isLast: widget.isLast,
      onSelect: widget.onTap,
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
                      if (widget.value.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.value,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                              if (widget.showDot) ...[
                                const SizedBox(width: 6),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isFocused
                        ? const Color(0xFFfb7299)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.buttonLabel,
                    style: TextStyle(
                      color: isFocused ? Colors.white : Colors.white70,
                      fontSize: 14,
                    ),
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
