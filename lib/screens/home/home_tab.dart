import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import '../../models/video.dart';
import 'package:keframe/keframe.dart';
import '../../services/bilibili_api.dart';
import '../../services/settings_service.dart';
import '../../widgets/tv_video_card.dart';
import '../../widgets/time_display.dart';
import '../../core/plugin/plugin_manager.dart';
import '../../core/plugin/plugin_types.dart';
import '../../utils/anim.dart';
import '../player/player_screen.dart';
import '../up_space/widgets/space_button.dart';

class HomeTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onFirstLoadComplete;
  final List<Video>? preloadedVideos; // 接收預載入資料

  const HomeTab({
    super.key,
    this.sidebarFocusNode,
    this.onFirstLoadComplete,
    this.preloadedVideos,
  });

  @override
  State<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends State<HomeTab> {
  int _selectedCategoryIndex = 0;
  final ScrollController _scrollController = ScrollController();
  late List<HomeCategory> _categories;
  late List<FocusNode> _categoryFocusNodes;

  // 資料快取
  final Map<int, List<Video>> _categoryVideos = {};
  final Map<int, bool> _categoryLoading = {};
  final Map<int, int> _categoryPage = {};
  final Map<int, int> _categoryRefreshIdx = {};
  bool _firstLoadDone = false;
  bool _usedPreloadedData = false; // 標記是否使用了預載入資料
  bool _isRefreshing = false; // 標記是否正在重新整理中（用於控制分幀渲染）
  // 每個影片卡片的 FocusNode
  final Map<int, FocusNode> _videoFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _loadCategoryOrder();
    _categoryFocusNodes = List.generate(_categories.length, (_) => FocusNode());

    // 【最佳化核心 1】如果有預載入資料，立即填充，且標記 loading 為 false
    // 預載入的是「推薦」資料，只有第一個分類是推薦時才可使用
    if (_categories[0] == HomeCategory.recommend &&
        widget.preloadedVideos != null &&
        widget.preloadedVideos!.isNotEmpty) {
      _categoryVideos[0] = widget.preloadedVideos!;
      _categoryRefreshIdx[0] = 1;
      _categoryLoading[0] = false; // 關鍵：明確標記不載入
      _usedPreloadedData = true; // 標記使用了預載入資料
      _firstLoadDone = true;

      // 通知父元件（用於 Sidebar 焦點處理等）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onFirstLoadComplete?.call();
      });
    } else {
      // 只有沒資料時，才自己去請求
      _loadVideosForCategory(0);
    }
  }

  // ... (省略 _loadCategoryOrder, dispose 等未改動程式碼) ...

  void _loadCategoryOrder() {
    final order = SettingsService.categoryOrder;
    final enabled = SettingsService.enabledCategories;
    _categories = order
        .where((name) => enabled.contains(name))
        .map(
          (name) => HomeCategory.values.firstWhere(
            (c) => c.name == name,
            orElse: () => HomeCategory.recommend,
          ),
        )
        .toList();
    if (_categories.isEmpty) _categories = [HomeCategory.recommend];
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (var node in _categoryFocusNodes) {
      node.dispose();
    }
    // 清理影片卡片的 FocusNode
    for (final node in _videoFocusNodes.values) {
      node.dispose();
    }
    _retryNode.dispose();
    _videoFocusNodes.clear();
    super.dispose();
  }

  // 獲取或建立影片卡片的 FocusNode
  FocusNode _getFocusNode(int index) {
    return _videoFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  // 目前分類載入失敗（無資料）時顯示「重試」按鈕
  bool _loadFailed = false;
  final FocusNode _retryNode = FocusNode();

  List<Video> get _currentVideos =>
      _categoryVideos[_selectedCategoryIndex] ?? [];
  bool get _isLoading => _categoryLoading[_selectedCategoryIndex] ?? false;

  Future<void> _loadVideosForCategory(
    int categoryIndex, {
    bool refresh = false,
  }) async {
    if (_categoryLoading[categoryIndex] == true) return;
    _loadFailed = false;

    // ... (保持原有的分頁邏輯) ...
    final currentPage = _categoryPage[categoryIndex] ?? 1;
    final currentRefreshIdx = _categoryRefreshIdx[categoryIndex] ?? 0;

    if (refresh) {
      _categoryPage[categoryIndex] = 1;
      _categoryRefreshIdx[categoryIndex] = 0;
      setState(() {
        _categoryLoading[categoryIndex] = true;
        _categoryVideos[categoryIndex] = [];
        _isRefreshing = true; // 開始重新整理
      });
    } else {
      setState(() => _categoryLoading[categoryIndex] = true);
    }

    final category = _categories[categoryIndex];
    List<Video> videos;

    try {
      // 網路請求邏輯...
      switch (category) {
        case HomeCategory.recommend:
          final idx = refresh ? 0 : currentRefreshIdx;
          videos = await BilibiliApi.getRecommendVideos(idx: idx);
          _categoryRefreshIdx[categoryIndex] = idx + 1;
          break;
        case HomeCategory.popular:
          final page = refresh ? 1 : currentPage;
          videos = await BilibiliApi.getPopularVideos(page: page);
          break;
        case HomeCategory.anime:
          final page = refresh ? 1 : currentPage;
          videos = await BilibiliApi.getBangumiIndex(page: page);
          break;
        default:
          final page = refresh ? 1 : currentPage;
          videos = await BilibiliApi.getRegionVideos(
            tid: category.tid,
            page: page,
          );
          break;
      }
    } catch (e) {
      videos = [];
    }

    if (!mounted) return;

    // 非重新整理且取回 0 筆（失敗或空）：只還原 loading 與 page，下次往下移動會重試
    if (!refresh && videos.isEmpty) {
      final noData = (_categoryVideos[categoryIndex] ?? []).isEmpty;
      setState(() {
        _categoryLoading[categoryIndex] = false;
        if (currentPage > 1) _categoryPage[categoryIndex] = currentPage - 1;
        // 首次載入就失敗：顯示重試按鈕，並通知父元件啟用焦點系統
        if (noData && categoryIndex == _selectedCategoryIndex) {
          _loadFailed = true;
        }
        if (noData && !_firstLoadDone) {
          _firstLoadDone = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onFirstLoadComplete?.call();
          });
        }
      });
      return;
    }

    setState(() {
      // 是否取代清單：只看 refresh 或清單原本為空
      final replaceList =
          refresh || (_categoryVideos[categoryIndex] ?? []).isEmpty;

      // 外掛過濾
      final filteredVideos = _filterVideos(videos);

      if (replaceList) {
        _categoryVideos[categoryIndex] = filteredVideos;
      } else {
        // 去重 (分區 feed 翻頁可能重複)
        final existing = _categoryVideos[categoryIndex] ?? [];
        final seen = existing
            .map((v) => v.isPgc ? 'ss${v.seasonId}' : v.bvid)
            .toSet();
        _categoryVideos[categoryIndex] = [
          ...existing,
          ...filteredVideos.where(
            (v) => seen.add(v.isPgc ? 'ss${v.seasonId}' : v.bvid),
          ),
        ];
      }
      _categoryLoading[categoryIndex] = false;
      _isRefreshing = false; // 重新整理完成
      if ((_categoryVideos[categoryIndex] ?? []).isEmpty &&
          categoryIndex == _selectedCategoryIndex) {
        _loadFailed = true;
      }

      if (!_firstLoadDone) {
        _firstLoadDone = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onFirstLoadComplete?.call();
        });
      }
    });
  }

  // ... (省略 _loadMore, _switchCategory 等輔助方法) ...
  void _loadMore() {
    if (_isLoading) return;
    if (_currentVideos.isEmpty) return;
    final page = (_categoryPage[_selectedCategoryIndex] ?? 1) + 1;
    _categoryPage[_selectedCategoryIndex] = page;
    _loadVideosForCategory(_selectedCategoryIndex);
  }

  void _switchCategory(int index) {
    if (_selectedCategoryIndex == index) return;
    // 切換分類後不再是初始預載入狀態
    _usedPreloadedData = false;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _loadFailed = false;
    setState(() => _selectedCategoryIndex = index);
    if ((_categoryVideos[index] ?? []).isEmpty) _loadVideosForCategory(index);
  }

  void refreshCurrentCategory() {
    // 重新整理後不再是初始預載入狀態
    _usedPreloadedData = false;
    _loadVideosForCategory(_selectedCategoryIndex, refresh: true);
  }

  void _onVideoTap(Video video) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => PlayerScreen(video: video)));
  }

  Widget _buildRetry() {
    return Center(
      key: const ValueKey('retry'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '載入失敗，請檢查網路後重試',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 16),
          SpaceButton(
            focusNode: _retryNode,
            autofocus: true,
            onTap: () =>
                _loadVideosForCategory(_selectedCategoryIndex, refresh: true),
            onLeft: () => widget.sidebarFocusNode?.requestFocus(),
            onUp: () =>
                _categoryFocusNodes[_selectedCategoryIndex].requestFocus(),
            builder: (focused) => spacePill(
              focused: focused,
              color: Colors.grey[800]!,
              horizontal: 18,
              icon: Icons.refresh,
              label: '重試',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 判斷是否是"啟動後的第一屏資料"
    // 使用穩定的標誌變數，避免 List 引用比較在 loadMore 後失效
    final bool isInitialLoad =
        _selectedCategoryIndex == 0 && _usedPreloadedData;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: FocusTraversalGroup(
            child: AnimatedSwitcher(
              duration: Anim.of(Anim.normal),
              child: _isLoading && _currentVideos.isEmpty
                  ? const Center(
                      key: ValueKey('loading'),
                      child: CircularProgressIndicator(),
                    )
                  : _loadFailed && _currentVideos.isEmpty
                  ? _buildRetry()
                  : SizeCacheWidget(
                      key: const ValueKey('content'),
                      child: CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(30, 100, 30, 80),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 4,
                                    childAspectRatio: 320 / 280,
                                    crossAxisSpacing: 20,
                                    mainAxisSpacing: 30,
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final video = _currentVideos[index];

                                // 【最佳化】只有重新整理時才使用交錯載入
                                // 初始載入和從播放器返回時，圖片已在快取中，直接顯示
                                final int? staggerIdx = _isRefreshing
                                    ? (index % 8)
                                    : null;

                                // 構建卡片內容
                                Widget buildCard(BuildContext ctx) {
                                  return TvVideoCard(
                                    video: video,
                                    focusNode: _getFocusNode(index),
                                    autofocus: isInitialLoad && index == 0,
                                    disableCache: false,
                                    staggerIndex: staggerIdx,
                                    onTap: () => _onVideoTap(video),
                                    onMoveLeft: (index % 4 == 0)
                                        ? () => widget.sidebarFocusNode
                                              ?.requestFocus()
                                        : () => _getFocusNode(
                                            index - 1,
                                          ).requestFocus(),
                                    // 強制向右導航，避免 ScaleTransition 導致的誤判
                                    onMoveRight:
                                        (index + 1 < _currentVideos.length)
                                        ? () => _getFocusNode(
                                            index + 1,
                                          ).requestFocus()
                                        : null,
                                    // 嚴格按列向上移動（4個一行），最頂行跳到分類標籤
                                    onMoveUp: index >= 4
                                        ? () => _getFocusNode(
                                            index - 4,
                                          ).requestFocus()
                                        : () =>
                                              _categoryFocusNodes[_selectedCategoryIndex]
                                                  .requestFocus(),
                                    // 嚴格按列向下移動
                                    onMoveDown:
                                        (index + 4 < _currentVideos.length)
                                        ? () => _getFocusNode(
                                            index + 4,
                                          ).requestFocus()
                                        : ((index ~/ 4 + 1) * 4 <
                                              _currentVideos.length)
                                        // 最後一列不滿四張：移到最後一張
                                        ? () => _getFocusNode(
                                            _currentVideos.length - 1,
                                          ).requestFocus()
                                        // 真正最後一列：觸發載入更多
                                        : () => _loadMore(),
                                    onFocus: () {
                                      // 焦點接近底部時載入更多（不在 build 中呼叫）
                                      if (index >= _currentVideos.length - 12) {
                                        _loadMore();
                                      }
                                      if (!_scrollController.hasClients) {
                                        return;
                                      }

                                      final RenderObject? object = ctx
                                          .findRenderObject();
                                      if (object != null &&
                                          object is RenderBox) {
                                        final viewport =
                                            RenderAbstractViewport.of(object);
                                        final offsetToReveal = viewport
                                            .getOffsetToReveal(object, 0.0)
                                            .offset;
                                        final targetOffset =
                                            (offsetToReveal - 120).clamp(
                                              0.0,
                                              _scrollController
                                                  .position
                                                  .maxScrollExtent,
                                            );

                                        if ((_scrollController.offset -
                                                    targetOffset)
                                                .abs() >
                                            50) {
                                          _scrollController.animateTo(
                                            targetOffset,
                                            duration: const Duration(
                                              milliseconds: 500,
                                            ),
                                            curve: Curves.easeOutCubic,
                                          );
                                        }
                                      }
                                    },
                                  );
                                }

                                // 只有重新整理時使用分幀渲染，其他情況直接渲染
                                if (_isRefreshing) {
                                  return FrameSeparateWidget(
                                    index: index,
                                    placeHolder: const Center(
                                      child: SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                    child: Builder(builder: buildCard),
                                  );
                                }

                                return Builder(builder: buildCard);
                              }, childCount: _currentVideos.length),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),

        // ... (Header / Category Tabs 保持不變) ...
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 80,
          child: Container(
            color: const Color(0xFF121212),
            padding: const EdgeInsets.only(left: 30, right: 180, top: 20),
            child: FocusTraversalGroup(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(_categories.length, (index) {
                    return _CategoryTab(
                      label: _categories[index].label,
                      isSelected: _selectedCategoryIndex == index,
                      focusNode: _categoryFocusNodes[index],
                      onTap: () => _switchCategory(index),
                      onFocus: () => _switchCategory(index),
                      onConfirm: refreshCurrentCategory,
                      onMoveLeft: index == 0
                          ? () => widget.sidebarFocusNode?.requestFocus()
                          : null,
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

  List<Video> _filterVideos(List<Video> videos) {
    if (videos.isEmpty) return [];
    final plugins = PluginManager().getEnabledPlugins<FeedPlugin>();
    if (plugins.isEmpty) return videos;

    return videos.where((video) {
      for (final plugin in plugins) {
        if (!plugin.shouldShowItem(video)) return false;
      }
      return true;
    }).toList();
  }
}

/// 分類標籤元件
class _CategoryTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback onConfirm;
  final VoidCallback? onMoveLeft;

  const _CategoryTab({
    required this.label,
    required this.isSelected,
    required this.focusNode,
    required this.onTap,
    required this.onFocus,
    required this.onConfirm,
    this.onMoveLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Focus(
        focusNode: focusNode,
        onFocusChange: (f) {
          if (!f) return;
          if (context.mounted) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 150),
            );
          }
          onFocus();
        },
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                onMoveLeft != null) {
              onMoveLeft!();
              return KeyEventResult.handled;
            }
            // 確定鍵重新整理當前分類
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter) {
              onConfirm();
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
                // 緊湊的 padding 確保文字高度位置與普通標題接近
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

/// 首頁分類列舉
enum HomeCategory {
  recommend('推薦', 0),
  popular('熱門', 0),
  anime('番劇', 0), // 番劇走 PGC 索引，不使用分區 ID
  // 以下為新版分區 ID (region/feed/rcmd 的 from_region)
  movie('影視', 1001),
  game('遊戲', 1008),
  knowledge('知識', 1010),
  tech('科技', 1012),
  music('音樂', 1003),
  dance('舞蹈', 1004),
  life('生活', 1030),
  food('美食', 1020),
  douga('動畫', 1005);

  const HomeCategory(this.label, this.tid);
  final String label;
  final int tid;
}
