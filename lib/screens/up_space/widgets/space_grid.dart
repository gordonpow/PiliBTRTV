import 'package:bili_tv_app/widgets/zh_material.dart';
import 'space_button.dart';

/// 一頁資料。[cursor] 由各 API 自行定義，原樣傳回下一次 `load`。
class SpacePage<T> {
  final List<T> items;
  final bool hasMore;
  final Object? cursor;

  const SpacePage({required this.items, required this.hasMore, this.cursor});
}

/// 傳給 itemBuilder 的格狀焦點資訊。
class SpaceGridCell {
  final FocusNode node;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onFocus;

  const SpaceGridCell({
    required this.node,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onFocus,
  });
}

/// 共用的 4 欄格狀：分頁載入、捲到底載入更多、失敗重試、空狀態與 TV 焦點。
///
/// 影片以外的項目（合集卡片）也共用，由 [itemBuilder] 決定外觀。
class SpaceGrid<T> extends StatefulWidget {
  /// 載入一頁；第一頁的 cursor 為 null。失敗回傳 null。
  final Future<SpacePage<T>?> Function(Object? cursor) load;
  final Widget Function(
    BuildContext context,
    T item,
    int index,
    SpaceGridCell cell,
  )
  itemBuilder;

  /// 第一列按上鍵時呼叫。
  final VoidCallback onMoveUpFromTop;
  final String emptyText;
  final int columns;

  /// 非 null 時，第一頁載入完成後把焦點移到該項目（超出範圍取最後一個）。
  final int? autofocusIndex;

  const SpaceGrid({
    super.key,
    required this.load,
    required this.itemBuilder,
    required this.onMoveUpFromTop,
    this.emptyText = '暫無內容',
    this.columns = 4,
    this.autofocusIndex,
  });

  @override
  State<SpaceGrid<T>> createState() => SpaceGridState<T>();
}

class SpaceGridState<T> extends State<SpaceGrid<T>> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _retryNode = FocusNode();
  Map<int, FocusNode> _cardNodes = {};

  List<T> _items = [];
  Object? _cursor;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _loadFailed = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _requestId++;
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _retryNode.dispose();
    for (final node in _cardNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _cardNode(int index) =>
      _cardNodes.putIfAbsent(index, () => FocusNode());

  /// 清空列表時釋放舊的卡片 FocusNode（延後到下一幀，避免舊 widget 仍在使用）。
  void _retireCardNodes() {
    final old = _cardNodes.values.toList();
    _cardNodes = {};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final node in old) {
        node.dispose();
      }
    });
  }

  /// 重新載入第一頁（重試用）。
  void reload() => _loadFirstPage();

  /// 把焦點移到第一個項目（失敗時移到重試按鈕）。沒有可聚焦的內容回傳 false。
  bool focusFirst() => focusIndex(0);

  bool focusIndex(int index) {
    if (_isLoading) return false;
    if (_loadFailed) {
      _retryNode.requestFocus();
      return true;
    }
    if (_items.isEmpty) return false;
    _cardNode(index.clamp(0, _items.length - 1)).requestFocus();
    return true;
  }

  Future<void> _loadFirstPage() async {
    final id = ++_requestId;
    setState(() {
      _retireCardNodes();
      _items = [];
      _cursor = null;
      _hasMore = true;
      _isLoading = true;
      _isLoadingMore = false;
      _loadFailed = false;
    });

    final page = await widget.load(null);
    if (!mounted || id != _requestId) return;

    setState(() {
      _isLoading = false;
      if (page == null) {
        _loadFailed = true;
        _hasMore = false;
        return;
      }
      _items = List.of(page.items);
      _cursor = page.cursor;
      _hasMore = page.hasMore && page.items.isNotEmpty;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || id != _requestId) return;
      final target = widget.autofocusIndex;
      if (target != null) focusIndex(target);
      _onScroll();
    });
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore || _loadFailed) return;
    final id = _requestId;
    setState(() => _isLoadingMore = true);

    final page = await widget.load(_cursor);
    if (!mounted || id != _requestId) return;

    setState(() {
      _isLoadingMore = false;
      if (page == null) return; // 失敗：保留 _hasMore，下次捲動可再試
      _items.addAll(page.items);
      _cursor = page.cursor;
      _hasMore = page.hasMore && page.items.isNotEmpty;
    });
    // 載入後若仍在底部附近，繼續檢查
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadFailed) {
      return Center(
        child: SpaceButton(
          focusNode: _retryNode,
          onTap: _loadFirstPage,
          onUp: widget.onMoveUpFromTop,
          builder: (focused) => spacePill(
            focused: focused,
            color: Colors.grey[800]!,
            horizontal: 18,
            icon: Icons.refresh,
            label: '載入失敗，按確定重試',
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          widget.emptyText,
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    final columns = widget.columns;
    final lastIndex = _items.length - 1;
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(30, 10, 30, 40),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: 320 / 280,
              crossAxisSpacing: 20,
              mainAxisSpacing: 30,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              return Builder(
                builder: (cardContext) => widget.itemBuilder(
                  context,
                  _items[index],
                  index,
                  SpaceGridCell(
                    node: _cardNode(index),
                    onMoveLeft: index % columns == 0
                        ? () {}
                        : () => _cardNode(index - 1).requestFocus(),
                    onMoveRight:
                        (index % columns == columns - 1 || index >= lastIndex)
                        ? () {}
                        : () => _cardNode(index + 1).requestFocus(),
                    onMoveUp: index >= columns
                        ? () => _cardNode(index - columns).requestFocus()
                        : widget.onMoveUpFromTop,
                    onMoveDown: index + columns <= lastIndex
                        ? () => _cardNode(index + columns).requestFocus()
                        : (index ~/ columns < lastIndex ~/ columns)
                        ? () => _cardNode(lastIndex).requestFocus()
                        : () {},
                    onFocus: () => spaceEnsureVisible(cardContext, 0.3),
                  ),
                ),
              );
            }, childCount: _items.length),
          ),
        ),
        if (_isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}
