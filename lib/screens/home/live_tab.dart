import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import '../../services/api/live_api.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/time_display.dart';
import 'live/live_room_grid.dart';

class LiveTab extends StatefulWidget {
  final FocusNode sidebarFocusNode;
  final bool isVisible;

  const LiveTab({
    super.key,
    required this.sidebarFocusNode,
    required this.isVisible,
  });

  @override
  State<LiveTab> createState() => LiveTabState();
}

class LiveTabState extends State<LiveTab> {
  static const int _followPageSize = 20;

  // 已登入預設「關注」(0)，未登入預設「推薦直播」(1)
  int _selectedCategoryIndex = AuthService.isLoggedIn ? 0 : 1;
  final ScrollController _scrollController = ScrollController();
  late List<_LiveCategory> _categories;
  late List<FocusNode> _categoryFocusNodes;

  // Data Cache
  final Map<int, List<dynamic>> _categoryRooms = {};
  final Map<int, bool> _categoryLoading = {};
  final Map<int, int> _categoryPage = {};

  bool _isRefreshing = false;

  // 關注分類：分頁停止與去重
  bool _followHasMore = true;
  final Set<dynamic> _followRoomIds = {};

  @override
  void initState() {
    super.initState();
    _initCategories();
    _categoryFocusNodes = List.generate(_categories.length, (_) => FocusNode());
    _loadDataForCategory(_selectedCategoryIndex);
  }

  void _initCategories() {
    _categories = [
      _LiveCategory(id: 'follow', label: '關注', type: _LiveCategoryType.follow),
      _LiveCategory(
        id: 'recommend',
        label: '推薦直播',
        type: _LiveCategoryType.recommend,
      ),
    ];

    final liveOrder = SettingsService.liveCategoryOrder;
    for (var key in liveOrder) {
      if (SettingsService.isLiveCategoryEnabled(key)) {
        final label = SettingsService.liveCategoryLabels[key] ?? key;
        final id = SettingsService.liveCategoryIds[key];
        if (id != null) {
          _categories.add(
            _LiveCategory(
              id: key,
              label: label,
              type: _LiveCategoryType.partition,
              parentId: id,
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (var node in _categoryFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Exposed method for sidebar navigation
  void focusFirstItem() {
    if (_categoryFocusNodes.isNotEmpty) {
      _categoryFocusNodes[_selectedCategoryIndex].requestFocus();
    }
  }

  void refresh() {
    _loadDataForCategory(_selectedCategoryIndex, refresh: true);
  }

  Future<void> _loadDataForCategory(int index, {bool refresh = false}) async {
    if (_categoryLoading[index] == true) return;

    final category = _categories[index];
    final currentPage = _categoryPage[index] ?? 1;

    if (category.type == _LiveCategoryType.follow) {
      await _loadFollow(index, refresh: refresh, page: currentPage);
      return;
    }

    if (refresh) {
      setState(() {
        _categoryLoading[index] = true;
        _categoryRooms[index] = [];
        _categoryPage[index] = 1;
        _isRefreshing = true;
      });
    } else {
      setState(() {
        _categoryLoading[index] = true;
      });
    }

    try {
      List<dynamic> rooms = [];
      if (category.type == _LiveCategoryType.recommend) {
        rooms = await LiveApi.getRecommended(
          page: refresh ? 1 : currentPage,
          pageSize: 30,
        );
      } else if (category.type == _LiveCategoryType.partition) {
        rooms = await LiveApi.getRecommended(
          parentId: category.parentId!,
          page: refresh ? 1 : currentPage,
          pageSize: 30,
        );
      }

      if (mounted) {
        setState(() {
          if (refresh) {
            _categoryRooms[index] = rooms;
          } else {
            _categoryRooms[index] = [
              ...(_categoryRooms[index] ?? []),
              ...rooms,
            ];
          }
          _categoryLoading[index] = false;
          _isRefreshing = false; // Clear refreshing
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _categoryLoading[index] = false;
          _isRefreshing = false; // Clear refreshing on error too
        });
      }
    }
  }

  Future<void> _loadFollow(
    int index, {
    required bool refresh,
    required int page,
  }) async {
    if (!AuthService.isLoggedIn) {
      setState(() {
        _categoryRooms[index] = [];
        _followRoomIds.clear();
        _followHasMore = false;
        _categoryLoading[index] = false;
        _isRefreshing = false;
      });
      return;
    }
    if (!refresh && !_followHasMore) return;

    final reqPage = refresh ? 1 : page;
    setState(() {
      _categoryLoading[index] = true;
      if (refresh) {
        _categoryRooms[index] = [];
        _categoryPage[index] = 1;
        _followHasMore = true;
        _followRoomIds.clear();
        _isRefreshing = true;
      }
    });

    List<dynamic> list = [];
    try {
      list = await LiveApi.getFollowedLive(
        page: reqPage,
        pageSize: _followPageSize,
      );
    } catch (_) {}
    if (!mounted) return;

    setState(() {
      final fresh = <dynamic>[];
      for (final room in list) {
        final id = room is Map ? room['roomid'] : null;
        if (id != null && !_followRoomIds.add(id)) continue;
        fresh.add(room);
      }
      _categoryRooms[index] = [...(_categoryRooms[index] ?? []), ...fresh];
      _categoryPage[index] = reqPage;
      if (list.isEmpty || list.length < _followPageSize) _followHasMore = false;
      _categoryLoading[index] = false;
      _isRefreshing = false;
    });
  }

  void _loadMore() {
    if (_categoryLoading[_selectedCategoryIndex] == true) return;
    if (_categories[_selectedCategoryIndex].type == _LiveCategoryType.follow &&
        !_followHasMore) {
      return;
    }

    // Following list often returns all or has limited pages, avoid infinite loop if empty
    // But for now, simple increment
    final page = (_categoryPage[_selectedCategoryIndex] ?? 1) + 1;
    _categoryPage[_selectedCategoryIndex] = page;
    _loadDataForCategory(_selectedCategoryIndex);
  }

  void _switchCategory(int index) {
    if (_selectedCategoryIndex == index) return;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    setState(() => _selectedCategoryIndex = index);
    if ((_categoryRooms[index] ?? []).isEmpty) {
      _loadDataForCategory(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    final currentRooms = _categoryRooms[_selectedCategoryIndex] ?? [];
    final isLoading = _categoryLoading[_selectedCategoryIndex] ?? false;
    final isFollowCat =
        _categories[_selectedCategoryIndex].type == _LiveCategoryType.follow;

    // 判斷是否是"啟動後的第一屏資料" (Simulated)
    final bool isInitialLoad =
        _categoryPage[_selectedCategoryIndex] == 1 &&
        !(_categoryLoading[_selectedCategoryIndex] ?? false);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: FocusTraversalGroup(
            child: isFollowCat && !AuthService.isLoggedIn
                ? const Center(
                    child: Text('請先登入', style: TextStyle(color: Colors.white)),
                  )
                : isLoading && currentRooms.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFfb7299)),
                  )
                : currentRooms.isEmpty
                ? const Center(
                    child: Text(
                      "暫無開播的主播",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : LiveRoomGrid(
                    rooms: currentRooms,
                    sidebarFocusNode: widget.sidebarFocusNode,
                    scrollController: _scrollController,
                    onLoadMore: _loadMore,
                    topPadding: 100,
                    autofocusFirst: isInitialLoad,
                    isRefreshing: _isRefreshing,
                    onMoveUpFromTop: () =>
                        _categoryFocusNodes[_selectedCategoryIndex]
                            .requestFocus(),
                  ),
          ),
        ),

        // Top Category Bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 80,
          child: Container(
            color: const Color(0xFF121212),
            padding: const EdgeInsets.only(left: 30, right: 30, top: 20),
            child: FocusTraversalGroup(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(_categories.length, (index) {
                    final tab = _LiveCategoryTab(
                      label: _categories[index].label,
                      isSelected: _selectedCategoryIndex == index,
                      focusNode: _categoryFocusNodes[index],
                      onTap: () {
                        if (_selectedCategoryIndex == index) {
                          refresh(); // Refresh if already selected
                        } else {
                          _switchCategory(index);
                        }
                      },
                      onFocus: () => _switchCategory(index),
                      onMoveLeft: index == 0
                          ? () => widget.sidebarFocusNode.requestFocus()
                          : null,
                    );
                    if (index != 0) return tab;
                    // 關注與推薦之間加直立分隔線
                    return Row(
                      children: [
                        tab,
                        Container(
                          width: 2,
                          height: 28,
                          margin: const EdgeInsets.only(right: 20),
                          color: Colors.white38,
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ),

        const Positioned(top: 20, right: 30, child: TimeDisplay()),
      ],
    );
  }
}

enum _LiveCategoryType { follow, recommend, partition }

class _LiveCategory {
  final String id;
  final String label;
  final _LiveCategoryType type;
  final int? parentId;

  _LiveCategory({
    required this.id,
    required this.label,
    required this.type,
    this.parentId,
  });
}

class _LiveCategoryTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback? onMoveLeft;

  const _LiveCategoryTab({
    required this.label,
    required this.isSelected,
    required this.focusNode,
    required this.onTap,
    required this.onFocus,
    this.onMoveLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Focus(
        focusNode: focusNode,
        onFocusChange: (f) => f ? onFocus() : null,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                onMoveLeft != null) {
              onMoveLeft!();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter) {
              // Refresh or select
              onTap();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (ctx) {
            final f = Focus.of(ctx).hasFocus;
            return GestureDetector(
              onTap: onTap,
              child: Container(
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
                      label,
                      style: TextStyle(
                        color: f
                            ? Colors.white
                            : (isSelected
                                  ? const Color(0xFFfb7299)
                                  : Colors.grey),
                        fontSize: 20,
                        fontWeight: f || isSelected
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
                        color: isSelected
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
  }
}
