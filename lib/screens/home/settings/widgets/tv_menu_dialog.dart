import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';

/// TV 用選單對話框：清單項目可用方向鍵選取，確定鍵選擇，返回鍵關閉。
///
/// 開啟時焦點在 [current]。回傳選到的值；關閉時回傳 null。
Future<T?> showTvMenuDialog<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required T current,
  required String Function(T) itemLabel,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => _TvMenuDialog<T>(
      title: title,
      items: items,
      current: current,
      itemLabel: itemLabel,
    ),
  );
}

class _TvMenuDialog<T> extends StatelessWidget {
  const _TvMenuDialog({
    required this.title,
    required this.items,
    required this.current,
    required this.itemLabel,
  });

  final String title;
  final List<T> items;
  final T current;
  final String Function(T) itemLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2A2A2A),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              for (final item in items)
                _TvMenuItem(
                  label: itemLabel(item),
                  selected: item == current,
                  autofocus: item == current,
                  onSelect: () => Navigator.of(context).pop(item),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvMenuItem extends StatelessWidget {
  const _TvMenuItem({
    required this.label,
    required this.selected,
    required this.autofocus,
    required this.onSelect,
  });

  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: autofocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select) {
          onSelect();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onSelect,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: focused
                    ? const Color(0xFFfb7299)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: focused ? Colors.white : Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check,
                      size: 18,
                      color: focused ? Colors.white : const Color(0xFFfb7299),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
