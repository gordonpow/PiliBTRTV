import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import '../../../services/update_service.dart';
import 'tabs/playback_settings.dart';
import 'tabs/btr_settings.dart';
import 'tabs/interface_settings.dart';
import 'tabs/plugins_settings.dart';
import 'tabs/storage_settings.dart';
import 'tabs/about_settings.dart';
import '../../../widgets/time_display.dart';
import '../search/search_keyboard_view.dart' show SearchImeBackGuard;
import 'settings_index.dart';

export 'settings_index.dart' show SettingsCategory;

class SettingsView extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onLogout;
  final VoidCallback? onLogin;

  const SettingsView({
    super.key,
    this.sidebarFocusNode,
    this.onLogout,
    this.onLogin,
  });

  @override
  State<SettingsView> createState() => SettingsViewState();
}

class SettingsViewState extends State<SettingsView>
    with WidgetsBindingObserver {
  int _selectedCategoryIndex = 0;
  late List<FocusNode> _categoryFocusNodes;
  final FocusNode _boxFocus = FocusNode(debugLabel: 'settingsSearchBox');
  late final FocusNode _textFocus;
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  bool _imeVisible = false;
  final FocusNode _contentNode = FocusNode(
    skipTraversal: true,
    canRequestFocus: false,
    debugLabel: 'settingsContent',
  );

  @override
  void initState() {
    super.initState();
    _textFocus = FocusNode(
      debugLabel: 'settingsSearchText',
      skipTraversal: true,
      onKeyEvent: _onTextKey,
    );
    _textFocus.addListener(_onTextFocusChanged);
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addObserver(this);
    _categoryFocusNodes = List.generate(
      SettingsCategory.values.length,
      (_) => FocusNode(),
    );
  }

  @override
  void dispose() {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    WidgetsBinding.instance.removeObserver(this);
    if (SearchImeBackGuard.imeOpen) SearchImeBackGuard.markClosed();
    _controller.removeListener(_onControllerChanged);
    _textFocus.removeListener(_onTextFocusChanged);
    _controller.dispose();
    _textFocus.dispose();
    _boxFocus.dispose();
    _contentNode.dispose();
    for (var node in _categoryFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// 請求第一個分類標籤的焦點（用於從側邊欄導航）
  void focusFirstCategory() {
    if (_categoryFocusNodes.isNotEmpty) {
      _categoryFocusNodes[_selectedCategoryIndex].requestFocus();
    }
  }

  /// 把焦點移到內容區第一個可聚焦項目
  void _focusFirstContentItem() {
    for (final n in _contentNode.traversalDescendants) {
      if (n.canRequestFocus && !n.skipTraversal) {
        n.requestFocus();
        return;
      }
    }
  }

  void _moveToCurrentTab() {
    if (_categoryFocusNodes.isNotEmpty) {
      _categoryFocusNodes[_selectedCategoryIndex].requestFocus();
    }
  }

  /// 內容區向上的保底處理：預設遍歷失敗或會離開內容區時回到分類標籤
  KeyEventResult _handleContentKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    // 不用 Flutter 預設的方向遍歷：它會依先前的移動紀錄回跳，可能直接跳到分類列。
    // 改為自己找正上方最近的可聚焦項目，找不到才回到分類標籤。
    final target = _nearestContentItemAbove(primary);
    if (target != null) {
      target.requestFocus();
      final ctx = target.context;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          duration: const Duration(milliseconds: 150),
        );
      }
      return KeyEventResult.handled;
    }
    _moveToCurrentTab();
    return KeyEventResult.handled;
  }

  /// 內容區中位於 [from] 上方、垂直距離最近（同距離取水平最近）的可聚焦項目
  FocusNode? _nearestContentItemAbove(FocusNode from) {
    final fromRect = from.rect;
    FocusNode? best;
    double bestDy = double.infinity;
    double bestDx = double.infinity;
    for (final n in _contentNode.traversalDescendants) {
      if (n == from || !n.canRequestFocus || n.skipTraversal) continue;
      // 排除 from 的祖先與子孫（例如外框包住內層按鈕）
      if (n.ancestors.contains(from) || from.ancestors.contains(n)) continue;
      final r = n.rect;
      if (r.isEmpty) continue;
      if (r.center.dy >= fromRect.top) continue; // 只取在上方的
      final dy = fromRect.top - r.bottom;
      final dx = (r.center.dx - fromRect.center.dx).abs();
      if (dy < bestDy - 1 || ((dy - bestDy).abs() <= 1 && dx < bestDx)) {
        best = n;
        bestDy = dy;
        bestDx = dx;
      }
    }
    return best;
  }

  // ---- 搜尋 ----

  bool get _searching => _query.trim().isNotEmpty;

  double _viewInsetsBottom() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    return views.isEmpty ? 0 : views.first.viewInsets.bottom;
  }

  @override
  void didChangeMetrics() {
    final visible = _viewInsetsBottom() > 0;
    if (visible == _imeVisible) return;
    _imeVisible = visible;
    if (!visible && _textFocus.hasFocus) {
      // 系統鍵盤被收起（例如按返回鍵）：焦點回到搜尋框
      SearchImeBackGuard.markClosed();
      _boxFocus.requestFocus();
    }
  }

  bool _isBackKey(KeyEvent event) =>
      event.logicalKey == LogicalKeyboardKey.escape ||
      event.logicalKey == LogicalKeyboardKey.goBack ||
      event.logicalKey == LogicalKeyboardKey.browserBack;

  KeyEventResult _onTextKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isBackKey(event)) {
      // 先關閉系統鍵盤，不讓 HomeScreen 同時處理返回
      _closeIme();
      _boxFocus.requestFocus();
      return KeyEventResult.handled;
    }
    // 系統鍵盤未顯示時，方向鍵不要被 TextField 困住
    if (!_imeVisible) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowLeft:
          _boxFocus.requestFocus();
          widget.sidebarFocusNode?.requestFocus();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _boxFocus.requestFocus();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _closeIme();
          _moveToCurrentTab();
          return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onTextFocusChanged() {
    if (_textFocus.hasFocus) {
      SearchImeBackGuard.imeOpen = true;
      return;
    }
    if (SearchImeBackGuard.imeOpen) SearchImeBackGuard.markClosed();
  }

  void _onControllerChanged() {
    final text = _controller.text;
    if (text == _query) return;
    setState(() => _query = text);
  }

  void _openIme() {
    _textFocus.requestFocus();
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _textFocus.hasFocus) {
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    });
  }

  void _closeIme() {
    _textFocus.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    SearchImeBackGuard.markClosed();
  }

  /// 返回鍵：搜尋鍵盤或搜尋結果開啟時關閉並回傳 true，否則回傳 false。
  bool handleBack() {
    final wasOpen = _textFocus.hasFocus || _searching;
    if (!wasOpen) return false;
    _closeIme();
    _controller.clear();
    _boxFocus.requestFocus();
    return true;
  }

  /// 選擇搜尋結果：清空搜尋、切到分類並聚焦對應設定項目
  void _selectEntry(SettingsEntry entry) {
    _closeIme();
    _controller.clear();
    setState(() {
      _selectedCategoryIndex = SettingsCategory.values.indexOf(entry.category);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SettingsFocusTarget.notifier.value = entry.label;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        SettingsFocusTarget.notifier.value = null;
        // 沒有 row 接手（自訂區塊）時，聚焦該分類第一個項目
        if (!_contentHasFocus()) _focusFirstContentItem();
      });
    });
  }

  bool _contentHasFocus() {
    final primary = FocusManager.instance.primaryFocus;
    return primary != null && primary.ancestors.contains(_contentNode);
  }

  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 360,
          child: Stack(
            children: [
              Focus(
                focusNode: _boxFocus,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  switch (event.logicalKey) {
                    case LogicalKeyboardKey.enter:
                    case LogicalKeyboardKey.select:
                      _openIme();
                      return KeyEventResult.handled;
                    case LogicalKeyboardKey.arrowLeft:
                      widget.sidebarFocusNode?.requestFocus();
                      return KeyEventResult.handled;
                    case LogicalKeyboardKey.arrowUp:
                      return KeyEventResult.handled;
                    case LogicalKeyboardKey.arrowDown:
                      _moveToCurrentTab();
                      return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (ctx) {
                    final focused = Focus.of(ctx).hasFocus;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: focused
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: focused
                              ? const Color(0xFFfb7299)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search,
                            size: 20,
                            color: focused ? Colors.white : Colors.white54,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _query.isEmpty ? '搜尋設定' : _query,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _query.isEmpty
                                    ? Colors.white38
                                    : Colors.white,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // 隱藏的 TextField：負責接收系統鍵盤（IME）輸入
              Positioned(
                left: 0,
                top: 0,
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: Opacity(
                    opacity: 0,
                    child: TextField(
                      controller: _controller,
                      focusNode: _textFocus,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) {
                        _closeIme();
                        _boxFocus.requestFocus();
                      },
                      enableSuggestions: true,
                      autocorrect: false,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final results = SettingsIndex.search(_query);
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(15),
        child: Text('找不到符合的設定', style: TextStyle(color: Colors.white54)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in results)
          _SearchResultTile(
            key: ValueKey('${e.category.name}/${e.label}'),
            entry: e,
            sidebarFocusNode: widget.sidebarFocusNode,
            onSelect: () => _selectEntry(e),
          ),
      ],
    );
  }

  /// 構建分類標籤
  Widget _buildCategoryTab({
    required String label,
    required bool isSelected,
    required FocusNode focusNode,
    required VoidCallback onTap,
    VoidCallback? onMoveLeft,
    bool showDot = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Focus(
        focusNode: focusNode,
        onFocusChange: (f) => f ? onTap() : null,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
              onMoveLeft != null) {
            onMoveLeft();
            return KeyEventResult.handled;
          }
          // 向上導航跳轉到搜尋框
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _boxFocus.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _focusFirstContentItem();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (ctx) {
            final isFocused = Focus.of(ctx).hasFocus;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isFocused ? const Color(0xFFfb7299) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isFocused ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: isFocused
                              ? Colors.white
                              : (isSelected
                                    ? const Color(0xFFfb7299)
                                    : Colors.grey),
                          fontSize: 15,
                          fontWeight: isFocused || isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      if (showDot)
                        ValueListenableBuilder<UpdateInfo?>(
                          valueListenable: UpdateService.available,
                          builder: (_, info, _) => info == null
                              ? const SizedBox.shrink()
                              : Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 3,
                    width: 24,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFfb7299)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moveToCurrentTab = _moveToCurrentTab;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 搜尋框
            _buildSearchBox(),

            // 設定分類標籤欄
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                children: List.generate(SettingsCategory.values.length, (
                  index,
                ) {
                  final category = SettingsCategory.values[index];
                  final isSelected = _selectedCategoryIndex == index;
                  return _buildCategoryTab(
                    label: category.label,
                    isSelected: isSelected,
                    showDot: category == SettingsCategory.about,
                    focusNode: _categoryFocusNodes[index],
                    onTap: () => setState(() => _selectedCategoryIndex = index),
                    onMoveLeft: index == 0
                        ? () => widget.sidebarFocusNode?.requestFocus()
                        : null,
                  );
                }),
              ),
            ),

            const SizedBox(height: 20),

            // 設定內容區域
            Expanded(
              child: Focus(
                focusNode: _contentNode,
                onKeyEvent: _handleContentKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: _searching
                      ? _buildSearchResults()
                      : _buildContent(moveToCurrentTab),
                ),
              ),
            ),
          ],
        ),

        // 常駐時間顯示 (與主介面位置保持一致)
        const Positioned(top: 20, right: 30, child: TimeDisplay()),
      ],
    );
  }

  Widget _buildContent(VoidCallback moveToCurrentTab) {
    switch (SettingsCategory.values[_selectedCategoryIndex]) {
      case SettingsCategory.playback:
        return PlaybackSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.btr:
        return BtrSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.interface_:
        return InterfaceSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.plugins:
        return PluginsSettingsTab(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.storage:
        return StorageSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.about:
        return AboutSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
    }
  }
}

/// 搜尋結果的一列：名稱、說明、所屬分類
class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    super.key,
    required this.entry,
    required this.onSelect,
    this.sidebarFocusNode,
  });

  final SettingsEntry entry;
  final VoidCallback onSelect;
  final FocusNode? sidebarFocusNode;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        switch (event.logicalKey) {
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.select:
            onSelect();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowLeft:
            sidebarFocusNode?.requestFocus();
            return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: focused
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
                        entry.label,
                        style: TextStyle(
                          color: focused ? Colors.white : Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      if (entry.subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            entry.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  entry.category.label,
                  style: TextStyle(
                    color: focused ? const Color(0xFFfb7299) : Colors.white54,
                    fontSize: 13,
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
