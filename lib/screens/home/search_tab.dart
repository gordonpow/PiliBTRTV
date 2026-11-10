import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../widgets/time_display.dart';
import 'search/search_keyboard_view.dart';
import 'search/search_results_view.dart';

/// 搜尋 Tab
class SearchTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onBackToHome; // 搜尋鍵盤介面按返回 → 回主頁
  final bool Function()? shouldHandleBack; // 返回 true 表示搜尋結果介面，HomeScreen 不處理返回

  const SearchTab({
    super.key,
    this.sidebarFocusNode,
    this.onBackToHome,
    this.shouldHandleBack,
  });

  @override
  State<SearchTab> createState() => SearchTabState();
}

// 公開狀態類，以便 HomeScreen 可以呼叫 handleBack
class SearchTabState extends State<SearchTab> {
  String _searchText = '';
  bool _showResults = false; // true: 顯示影片結果, false: 顯示建議
  bool _returnedFromResults = false; // 從結果回到鍵盤：帶入關鍵字並聚焦搜尋框

  // 防止返回鍵重複處理
  DateTime? _lastBackHandled;

  /// 處理返回鍵，返回 true 表示已處理（結果介面回到鍵盤），返回 false 表示未處理（應該回主頁）
  bool handleBack() {
    // 如果剛剛被 TvVideoCard.onBack 處理過, 不再重複處理
    if (_lastBackHandled != null &&
        DateTime.now().difference(_lastBackHandled!) <
            const Duration(milliseconds: 100)) {
      return true; // 已處理，不要再跳主頁
    }

    if (_showResults) {
      // 結果介面 → 回到鍵盤
      _backToKeyboard();
      return true;
    }
    // 鍵盤介面 → 讓 HomeScreen 處理（回主頁）
    return false;
  }

  void _backToKeyboard() {
    _lastBackHandled = DateTime.now(); // 記錄處理時間，防止重複
    setState(() {
      _showResults = false;
      _returnedFromResults = true;
      // _searchText remains to show what was searched, allowing modification
    });
  }

  /// 側邊欄在搜尋頁再按確定：結果頁直接回到鍵盤重新搜尋
  void showKeyboard() {
    if (_showResults) _backToKeyboard();
  }

  void _onSearch(String query) {
    setState(() {
      _searchText = query;
      _showResults = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _showResults
            ? SearchResultsView(
                query: _searchText,
                sidebarFocusNode: widget.sidebarFocusNode,
                onBackToKeyboard: _backToKeyboard,
              )
            : SearchKeyboardView(
                sidebarFocusNode: widget.sidebarFocusNode,
                onBackToHome: widget.onBackToHome,
                onSearch: _onSearch,
                initialText: _returnedFromResults ? _searchText : '',
                autofocusBox: _returnedFromResults,
              ),
        const Positioned(top: 20, right: 30, child: TimeDisplay()),
      ],
    );
  }
}
