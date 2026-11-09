import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../../../core/focus/focus_navigation.dart';
import 'setting_focus_target.dart';

/// 設定頁開關行元件
///
/// 使用統一的焦點管理系統
class SettingToggleRow extends StatefulWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final FocusNode? sidebarFocusNode;
  final bool isFirst;
  final bool isLast;

  const SettingToggleRow({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.autofocus = false,
    this.focusNode,
    this.onMoveUp,
    this.onMoveDown,
    this.sidebarFocusNode,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  State<SettingToggleRow> createState() => _SettingToggleRowState();
}

class _SettingToggleRowState extends State<SettingToggleRow>
    with SettingFocusTargetMixin<SettingToggleRow> {
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
      onSelect: () => widget.onChanged(!widget.value),
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
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ExcludeFocus(
                  child: Switch(
                    value: widget.value,
                    onChanged: widget.onChanged,
                    activeTrackColor: const Color(
                      0xFFfb7299,
                    ).withValues(alpha: 0.5),
                    thumbColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return const Color(0xFFfb7299);
                      }
                      return Colors.grey;
                    }),
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
