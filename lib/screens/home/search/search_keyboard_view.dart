import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../services/bilibili_api.dart';
import '../../../services/search_history_service.dart';
import '../../../widgets/tv_keyboard_button.dart';

/// 系統鍵盤（IME）返回鍵防護：IME 開啟或剛關閉時，HomeScreen 不處理返回鍵。
class SearchImeBackGuard {
  static bool imeOpen = false;
  static DateTime? _closedAt;

  static void markClosed() {
    imeOpen = false;
    _closedAt = DateTime.now();
  }

  static bool shouldSwallowBack() {
    if (imeOpen) return true;
    final t = _closedAt;
    return t != null &&
        DateTime.now().difference(t) < const Duration(milliseconds: 400);
  }
}

class SearchKeyboardView extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onBackToHome;
  final ValueChanged<String> onSearch;

  const SearchKeyboardView({
    super.key,
    this.sidebarFocusNode,
    this.onBackToHome,
    required this.onSearch,
  });

  @override
  State<SearchKeyboardView> createState() => _SearchKeyboardViewState();
}

class _SearchKeyboardViewState extends State<SearchKeyboardView>
    with WidgetsBindingObserver {
  String _searchText = '';
  List<String> _suggestions = [];

  // 搜尋框（D-pad 焦點）與隱藏的 TextField（系統鍵盤輸入）
  final FocusNode _boxFocus = FocusNode(debugLabel: 'searchBox');
  late final FocusNode _textFocus;
  final TextEditingController _controller = TextEditingController();
  bool _boxFocused = false;
  bool _imeVisible = false;

  final List<String> _gridKeys = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '0',
  ];

  @override
  void initState() {
    super.initState();
    SearchHistoryService.init(); // Initialize history
    _textFocus = FocusNode(
      debugLabel: 'searchText',
      skipTraversal: true,
      onKeyEvent: _onTextKey,
    );
    _textFocus.addListener(_onTextFocusChanged);
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addObserver(this);
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
    super.dispose();
  }

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
      // 先關閉輸入狀態與系統鍵盤，不讓 HomeScreen 同時處理返回
      _closeIme();
      _boxFocus.requestFocus();
      return KeyEventResult.handled;
    }
    // 系統鍵盤未顯示時，方向鍵不要被 TextField 困住
    if (!_imeVisible) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _boxFocus.requestFocus();
        widget.sidebarFocusNode?.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _boxFocus.requestFocus();
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _boxFocus.focusInDirection(TraversalDirection.down);
        }
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
    // 失去焦點後若沒有其他焦點目標，回到搜尋框（而非側邊欄）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary == null || primary is FocusScopeNode) {
        _boxFocus.requestFocus();
      }
    });
  }

  void _onControllerChanged() {
    final text = _controller.text;
    if (text == _searchText) return;
    // IME 輸入（含注音/拼音組字中的文字）同步到 _searchText
    setState(() => _searchText = text);
    _fetchSuggestions();
  }

  /// 以內建鍵盤更新文字，並同步到 controller（IME 組字由 IME 自己寫入，這裡不回寫）
  void _setText(String text) {
    _searchText = text;
    if (_controller.text != text) {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
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

  void _submit() {
    _closeIme();
    if (_searchText.trim().isNotEmpty) {
      SearchHistoryService.add(_searchText.trim());
    }
    widget.onSearch(_searchText);
  }

  void _handleKeyboardTap(String key) {
    if (key == '後退') {
      if (_searchText.isNotEmpty) {
        setState(
          () => _setText(_searchText.substring(0, _searchText.length - 1)),
        );
        _fetchSuggestions();
      }
    } else if (key == '清空') {
      setState(() {
        _setText('');
        _suggestions = [];
      });
    } else if (key == '搜尋') {
      _submit();
    } else {
      setState(() => _setText(_searchText + key));
      _fetchSuggestions();
    }
  }

  Future<void> _fetchSuggestions() async {
    if (_searchText.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    final suggestions = await BilibiliApi.getSearchSuggestions(_searchText);

    if (!mounted) return;
    setState(() {
      _suggestions = suggestions;
    });
  }

  void _selectSuggestion(String suggestion) {
    _closeIme();
    setState(() => _setText(suggestion));
    SearchHistoryService.add(suggestion);
    widget.onSearch(suggestion);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左側鍵盤區
        SizedBox(
          width: 380,
          child: Container(
            color: const Color(0xFF252525),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // 搜尋輸入框：D-pad 可聚焦，確認鍵開啟系統鍵盤
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(0.0),
                    child: Focus(
                      focusNode: _boxFocus,
                      onFocusChange: (f) => setState(() => _boxFocused = f),
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                          widget.sidebarFocusNode?.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (_isBackKey(event) && widget.onBackToHome != null) {
                          widget.onBackToHome!();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.select ||
                            event.logicalKey ==
                                LogicalKeyboardKey.numpadEnter) {
                          _openIme();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: GestureDetector(
                        onTap: _openIme,
                        child: Stack(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              height: 50,
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                              ),
                              decoration: BoxDecoration(
                                color: _boxFocused
                                    ? Colors.white24
                                    : Colors.white10,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _boxFocused
                                      ? Colors.white
                                      : Colors.white12,
                                  width: _boxFocused ? 2 : 1,
                                ),
                              ),
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _searchText.isEmpty
                                          ? '輸入關鍵詞搜尋...'
                                          : _searchText,
                                      style: TextStyle(
                                        fontSize: 22,
                                        color: _searchText.isEmpty
                                            ? Colors.white24
                                            : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 2,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Icon(
                                    Icons.keyboard,
                                    size: 22,
                                    color: _boxFocused
                                        ? Colors.white
                                        : Colors.white24,
                                  ),
                                ],
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
                                    onSubmitted: (_) => _submit(),
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
                  ),
                  if (_boxFocused)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        '按確認鍵開啟系統鍵盤',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 10),
                  // 清空/後退按鈕
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        Expanded(
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(1.0),
                            child: TvKeyboardButton(
                              label: '清空',
                              onTap: () => _handleKeyboardTap('清空'),
                              onMoveLeft: () =>
                                  widget.sidebarFocusNode?.requestFocus(),
                              onBack: widget.onBackToHome,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(1.1),
                            child: TvKeyboardButton(
                              label: '後退',
                              onTap: () => _handleKeyboardTap('後退'),
                              onBack: widget.onBackToHome,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 字母數字鍵盤
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // 依可用高度計算按鍵比例，避免底部溢位
                        const rows = 6;
                        const spacing = 8.0;
                        final cellW = (constraints.maxWidth - spacing * 5) / 6;
                        final cellH =
                            (constraints.maxHeight - spacing * (rows - 1)) /
                            rows;
                        final ratio = cellH > 0 ? cellW / cellH : 1.1;
                        return GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 6,
                                childAspectRatio: ratio.clamp(0.8, 1.6),
                                crossAxisSpacing: spacing,
                                mainAxisSpacing: spacing,
                              ),
                          itemCount: _gridKeys.length,
                          itemBuilder: (context, index) => FocusTraversalOrder(
                            order: NumericFocusOrder(2.0 + (index * 0.001)),
                            child: TvKeyboardButton(
                              label: _gridKeys[index],
                              onTap: () => _handleKeyboardTap(_gridKeys[index]),
                              onMoveLeft: (index % 6 == 0)
                                  ? () =>
                                        widget.sidebarFocusNode?.requestFocus()
                                  : null,
                              onBack: widget.onBackToHome,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 搜尋按鈕
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(3.0),
                    child: SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: TvActionButton(
                        label: '搜尋',
                        color: const Color(0xFFfb7299),
                        onTap: () => _handleKeyboardTap('搜尋'),
                        onMoveLeft: () =>
                            widget.sidebarFocusNode?.requestFocus(),
                        onBack: widget.onBackToHome,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 右側建議區
        Expanded(child: _buildSuggestions()),
      ],
    );
  }

  /// 構建搜尋建議列表
  Widget _buildSuggestions() {
    // 如果沒有建議，顯示搜尋歷史
    if (_suggestions.isEmpty) {
      final history = SearchHistoryService.getAll();
      if (history.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                'assets/icons/search.svg',
                width: 80,
                height: 80,
                colorFilter: ColorFilter.mode(
                  Colors.white.withValues(alpha: 0.2),
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '輸入關鍵詞開始搜尋',
                style: TextStyle(color: Colors.white38, fontSize: 16),
              ),
            ],
          ),
        );
      }

      // 顯示搜尋歷史
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '搜尋歷史',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            Expanded(
              child: ListView.builder(
                itemCount: history.length + 1, // +1 為清除按鈕
                itemBuilder: (context, index) {
                  if (index == history.length) {
                    // 清除搜尋記錄按鈕
                    return Padding(
                      padding: const EdgeInsets.only(top: 15),
                      child: _SuggestionItem(
                        text: '清除搜尋記錄',
                        icon: Icons.delete_outline,
                        onTap: () async {
                          await SearchHistoryService.clear();
                          setState(() {});
                        },
                        onBack: widget.onBackToHome,
                      ),
                    );
                  }
                  final item = history[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SuggestionItem(
                      text: item,
                      icon: Icons.history,
                      onTap: () => _selectSuggestion(item),
                      onBack: widget.onBackToHome,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 30),
      child: ListView.builder(
        itemCount: _suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = _suggestions[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SuggestionItem(
              text: suggestion,
              onTap: () => _selectSuggestion(suggestion),
              onBack: widget.onBackToHome,
            ),
          );
        },
      ),
    );
  }
}

/// 搜尋建議項
class _SuggestionItem extends StatefulWidget {
  final String text;
  final VoidCallback onTap;
  final VoidCallback? onBack;
  final IconData? icon;

  const _SuggestionItem({
    required this.text,
    required this.onTap,
    this.onBack,
    this.icon,
  });

  @override
  State<_SuggestionItem> createState() => _SuggestionItemState();
}

class _SuggestionItemState extends State<_SuggestionItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Focus(
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            // 返回鍵
            if ((event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack ||
                    event.logicalKey == LogicalKeyboardKey.browserBack) &&
                widget.onBack != null) {
              widget.onBack!();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select) {
              widget.onTap();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _isFocused ? Colors.white : Colors.white12,
            borderRadius: BorderRadius.circular(8),
            border: _isFocused
                ? Border.all(color: Colors.white, width: 2)
                : null,
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 18,
                  color: _isFocused ? Colors.black54 : Colors.white54,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  widget.text,
                  style: TextStyle(
                    color: _isFocused ? Colors.black : Colors.white70,
                    fontSize: 16,
                    fontWeight: _isFocused
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
