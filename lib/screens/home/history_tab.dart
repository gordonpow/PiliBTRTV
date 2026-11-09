import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../models/video.dart';
import '../../services/bilibili_api.dart';
import 'package:keframe/keframe.dart';
import '../../services/auth_service.dart';
import '../../widgets/history_video_card.dart';
import '../../widgets/time_display.dart';
import '../../widgets/tv_tab_bar.dart';
import '../player/player_screen.dart';
import 'history/fav_view.dart';
import 'history/watch_later_view.dart';

/// 觀看歷史 Tab
class HistoryTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final bool isVisible;

  const HistoryTab({super.key, this.sidebarFocusNode, this.isVisible = false});

  @override
  State<HistoryTab> createState() => HistoryTabState();
}

class HistoryTabState extends State<HistoryTab> {
  List<Video> _videos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _viewAt = 0;
  int _max = 0;
  final ScrollController _scrollController = ScrollController();
  bool _hasLoaded = false;
  bool _isRefreshing = false; // 標記是否正在重新整理中（用於控制分幀渲染）
  // 每個影片卡片的 FocusNode
  final Map<int, FocusNode> _videoFocusNodes = {};

  // 分頁：0 觀看歷史、1 我的收藏、2 稍後再看
  int _tab = 0;
  final List<FocusNode> _tabNodes = List.generate(3, (_) => FocusNode());
  final FocusNode _refreshNode = FocusNode();
  final GlobalKey<FavViewState> _favKey = GlobalKey();
  final GlobalKey<WatchLaterViewState> _laterKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.isVisible) {
      _loadHistory(reset: true);
      _hasLoaded = true;
    }
  }

  @override
  void didUpdateWidget(HistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible && !_hasLoaded) {
      _loadHistory(reset: true);
      _hasLoaded = true;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    // 清理所有影片卡片的 FocusNode
    for (final node in _videoFocusNodes.values) {
      node.dispose();
    }
    _videoFocusNodes.clear();
    for (final node in _tabNodes) {
      node.dispose();
    }
    _refreshNode.dispose();
    super.dispose();
  }

  // 獲取或建立影片卡片的 FocusNode
  FocusNode _getFocusNode(int index) {
    return _videoFocusNodes.putIfAbsent(index, () => FocusNode());
  }

  void _onScroll() {
    if (!_isLoading && !_isLoadingMore && _hasMore) {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadHistory(reset: false);
      }
    }
  }

  /// 公開的重新整理方法 - 供外部呼叫
  void refresh() {
    _hasLoaded = true; // 標記已載入，避免切換時重複載入
    _loadHistory(reset: true);
  }

  bool _silentLoading = false;

  /// 靜默重新整理：背景重抓第一頁後直接替換，不清空列表、不顯示載入中，
  /// 焦點留在原本的卡片位置。用於切到歷史分頁或從播放器返回時。
  Future<void> refreshSilently() async {
    if (!AuthService.isLoggedIn) return;
    if (_videos.isEmpty) {
      if (!_isLoading) refresh();
      return;
    }
    if (_silentLoading || _isLoading) return;
    _silentLoading = true;
    try {
      final result = await BilibiliApi.getHistory(ps: 30);
      if (!mounted) return;
      final newVideos = result['list'] as List<Video>;
      if (newVideos.isEmpty) return; // 失敗時保留舊資料
      setState(() {
        _videos = newVideos;
        _viewAt = result['viewAt'] as int;
        _max = result['max'] as int;
        _hasMore = result['hasMore'] as bool;
      });
    } finally {
      _silentLoading = false;
    }
  }

  Future<void> _loadHistory({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _isRefreshing = true; // 開始重新整理
        _videos = [];
        _viewAt = 0;
        _max = 0;
        _hasMore = true;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    final result = await BilibiliApi.getHistory(
      ps: 30,
      viewAt: reset ? 0 : _viewAt,
      max: reset ? 0 : _max,
    );

    if (!mounted) return;

    final newVideos = result['list'] as List<Video>;
    final nextViewAt = result['viewAt'] as int;
    final nextMax = result['max'] as int;
    final hasMore = result['hasMore'] as bool;

    setState(() {
      if (reset) {
        _videos = newVideos;
        _isLoading = false;
        _isRefreshing = false; // 重新整理完成
      } else {
        // 去重：過濾掉已存在的影片
        final existingBvids = _videos.map((v) => v.bvid).toSet();
        final uniqueNewVideos = newVideos
            .where((v) => !existingBvids.contains(v.bvid))
            .toList();
        _videos.addAll(uniqueNewVideos);
        _isLoadingMore = false;
      }

      _viewAt = nextViewAt;
      _max = nextMax;

      if (!hasMore || newVideos.isEmpty) {
        _hasMore = false;
      }
    });
  }

  Future<void> _onVideoTap(Video video) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PlayerScreen(video: video)));
    // 播放器在 dispose 時才上報進度（非同步），稍等再重抓，避免拿到上報前的資料
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) refreshSilently();
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = AuthService.isLoggedIn;
    Widget body;
    if (!loggedIn || _tab == 0) {
      // 未登入時三個分頁都顯示「請先登入」（由 _buildHistoryBody 處理）
      body = _buildHistoryBody(context);
    } else if (_tab == 1) {
      body = FavView(
        key: _favKey,
        sidebarFocusNode: widget.sidebarFocusNode,
        onMoveUpToTabs: () => _tabNodes[1].requestFocus(),
      );
    } else {
      body = WatchLaterView(
        key: _laterKey,
        sidebarFocusNode: widget.sidebarFocusNode,
        onMoveUpFromFirstRow: () => _tabNodes[2].requestFocus(),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(top: 64, child: body),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: const Color(0xFF121212),
            padding: const EdgeInsets.fromLTRB(30, 16, 200, 8),
            child: Row(
              children: [
                Flexible(
                  child: TvTabBar(
                    labels: const ['觀看歷史', '我的收藏', '稍後再看'],
                    focusNodes: _tabNodes,
                    selectedIndex: _tab,
                    fontSize: 22,
                    onSelect: (i) => setState(() => _tab = i),
                    onMoveLeftAtFirst: () =>
                        widget.sidebarFocusNode?.requestFocus(),
                    onMoveDown: _focusContent,
                    onMoveRightAtLast: () => _refreshNode.requestFocus(),
                  ),
                ),
                _buildRefreshButton(),
              ],
            ),
          ),
        ),
        const Positioned(top: 20, right: 30, child: TimeDisplay()),
      ],
    );
  }

  /// 重新整理目前分頁
  void _refreshCurrent() {
    if (!AuthService.isLoggedIn) return;
    switch (_tab) {
      case 0:
        if (!_isLoading) refresh();
      case 1:
        _favKey.currentState?.reload();
      case 2:
        _laterKey.currentState?.reload();
    }
  }

  /// 分頁列右側的重新整理按鈕
  Widget _buildRefreshButton() {
    return Focus(
      focusNode: _refreshNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.gameButtonA) {
          _refreshCurrent();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          _tabNodes[_tabNodes.length - 1].requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _focusContent();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowUp) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final f = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: _refreshCurrent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 14, 6),
              decoration: BoxDecoration(
                color: f ? const Color(0xFFfb7299) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: f ? Colors.white : Colors.white24,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.refresh,
                    size: 22,
                    color: f ? Colors.white : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '重新整理',
                    style: TextStyle(
                      color: f ? Colors.white : Colors.grey,
                      fontSize: 18,
                      fontWeight: f ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 分頁列按下鍵：進入目前分頁內容
  void _focusContent() {
    if (!AuthService.isLoggedIn) return;
    switch (_tab) {
      case 0:
        if (_videos.isNotEmpty) _getFocusNode(0).requestFocus();
      case 1:
        _favKey.currentState?.focusFolders();
      case 2:
        _laterKey.currentState?.focusFirst();
    }
  }

  Widget _buildHistoryBody(BuildContext context) {
    // 未登入提示
    if (!AuthService.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '請先登入',
              style: TextStyle(color: Colors.white70, fontSize: 20),
            ),
            const SizedBox(height: 10),
            const Text(
              '登入後可檢視觀看歷史',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_isLoading && _videos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/icons/history.svg',
              width: 80,
              height: 80,
              colorFilter: ColorFilter.mode(
                Colors.white.withValues(alpha: 0.3),
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '暫無觀看歷史',
              style: TextStyle(color: Colors.white70, fontSize: 20),
            ),
          ],
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 影片網格
        Positioned.fill(
          child: SizeCacheWidget(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(30, 20, 30, 80),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          childAspectRatio: 320 / 280,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 30,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final video = _videos[index];

                      // 構建卡片內容
                      Widget buildCard(BuildContext ctx) {
                        return HistoryVideoCard(
                          video: video,
                          focusNode: _getFocusNode(index),
                          onTap: () => _onVideoTap(video),
                          // 最左列按左鍵跳到側邊欄
                          onMoveLeft: (index % 4 == 0)
                              ? () => widget.sidebarFocusNode?.requestFocus()
                              : () => _getFocusNode(index - 1).requestFocus(),
                          // 強制向右導航
                          onMoveRight: (index + 1 < _videos.length)
                              ? () => _getFocusNode(index + 1).requestFocus()
                              : null,
                          // 嚴格按列向上移動（4個一行）
                          onMoveUp: index >= 4
                              ? () => _getFocusNode(index - 4).requestFocus()
                              : () => _tabNodes[0].requestFocus(), // 回到分頁列
                          // 嚴格按列向下移動
                          onMoveDown: (index + 4 < _videos.length)
                              ? () => _getFocusNode(index + 4).requestFocus()
                              : null,
                          onFocus: () {
                            if (!_scrollController.hasClients) return;

                            final RenderObject? object = ctx.findRenderObject();
                            if (object != null && object is RenderBox) {
                              final viewport = RenderAbstractViewport.of(
                                object,
                              );
                              final offsetToReveal = viewport
                                  .getOffsetToReveal(object, 0.0)
                                  .offset;
                              final targetOffset = (offsetToReveal - 120).clamp(
                                0.0,
                                _scrollController.position.maxScrollExtent,
                              );

                              if ((_scrollController.offset - targetOffset)
                                      .abs() >
                                  50) {
                                _scrollController.animateTo(
                                  targetOffset,
                                  duration: const Duration(milliseconds: 500),
                                  curve: Curves.easeOutCubic,
                                );
                              }
                            }
                          },
                        );
                      }

                      // 只有在重新整理時才使用分幀渲染，否則直接渲染
                      if (_isRefreshing) {
                        return FrameSeparateWidget(
                          index: index,
                          placeHolder: const Center(
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          child: Builder(builder: buildCard),
                        );
                      }

                      // 非重新整理狀態（從播放器返回）直接渲染
                      return Builder(builder: buildCard);
                    }, childCount: _videos.length),
                  ),
                ),
                if (_isLoadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
