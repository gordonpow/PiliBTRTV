import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../models/video.dart';
import '../../services/bilibili_api.dart';
import 'package:keframe/keframe.dart';
import '../../services/auth_service.dart';
import '../../services/api/interaction_api.dart';
import '../../utils/zh_toast.dart';
import '../../widgets/video_action_dialogs.dart';
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

  // 多選模式（僅觀看歷史）
  bool _selecting = false;
  final Set<String> _selected = {};
  int _lastFocusedIndex = 0;
  final List<FocusNode> _barNodes = List.generate(5, (_) => FocusNode());
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
    for (final node in _barNodes) {
      node.dispose();
    }
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

  String _selKey(Video v) => v.historyKid.isNotEmpty ? v.historyKid : v.bvid;

  List<Video> get _selectedVideos =>
      _videos.where((v) => _selected.contains(_selKey(v))).toList();

  void _enterSelect(Video v) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(_selKey(v));
    });
  }

  void _toggleSelect(Video v) {
    setState(() {
      final k = _selKey(v);
      if (!_selected.remove(k)) _selected.add(k);
    });
  }

  /// 離開多選並把焦點還給卡片（多選按鈕列消失後焦點會遺失）
  void _exitSelect() {
    if (!_selecting) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _videos.isEmpty) return;
      final i = _lastFocusedIndex.clamp(0, _videos.length - 1);
      _getFocusNode(i).requestFocus();
    });
  }

  /// 返回鍵：多選中離開多選。回傳 true 表示已處理
  bool handleBack() {
    if (!_selecting) return false;
    _exitSelect();
    return true;
  }

  void _selectAll() {
    setState(() {
      final all = _videos.map(_selKey).toSet();
      if (_selected.length == all.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final vids = _selectedVideos;
    if (vids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF2A2A2A),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '刪除 ${vids.length} 筆觀看紀錄？',
                style: const TextStyle(color: Colors.white, fontSize: 22),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TvDialogButton(
                    label: '取消',
                    autofocus: true,
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                  const SizedBox(width: 12),
                  TvDialogButton(
                    label: '刪除',
                    primary: true,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final kids = [
      for (final v in vids)
        if (v.historyKid.isNotEmpty) v.historyKid,
    ];
    final noKid = vids.length - kids.length;
    final failed = await InteractionApi.deleteHistory(kids) + noKid;
    if (!mounted) return;
    if (failed == 0) {
      setState(() {
        final keys = vids.map(_selKey).toSet();
        _videos = _videos.where((v) => !keys.contains(_selKey(v))).toList();
      });
      showZhToast(msg: '已刪除 ${vids.length} 筆觀看紀錄');
    } else {
      showZhToast(msg: '刪除失敗 $failed 筆');
      refreshSilently();
    }
    _exitSelect();
  }

  Future<void> _favSelected() async {
    final vids = _selectedVideos;
    if (vids.isEmpty) return;
    final r = await batchFavoriteFlow(context, vids);
    if (r != null && mounted) _exitSelect();
  }

  Future<void> _laterSelected() async {
    final vids = _selectedVideos;
    if (vids.isEmpty) return;
    final r = await batchWatchLaterFlow(vids);
    if (r != null && mounted) _exitSelect();
  }

  Widget _buildSelectionBar() {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (_videos.isNotEmpty) {
            _getFocusNode(
              _lastFocusedIndex.clamp(0, _videos.length - 1),
            ).requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowUp) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        color: const Color(0xFF121212),
        padding: const EdgeInsets.fromLTRB(30, 4, 30, 8),
        child: Row(
          children: [
            Text(
              '已選 ${_selected.length} 部',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 24),
            TvDialogButton(
              focusNode: _barNodes[0],
              label: '全選',
              onPressed: _selectAll,
            ),
            const SizedBox(width: 10),
            TvDialogButton(
              focusNode: _barNodes[1],
              label: '刪除',
              onPressed: _deleteSelected,
            ),
            const SizedBox(width: 10),
            TvDialogButton(
              focusNode: _barNodes[2],
              label: '加入收藏',
              onPressed: _favSelected,
            ),
            const SizedBox(width: 10),
            TvDialogButton(
              focusNode: _barNodes[3],
              label: '稍後再看',
              onPressed: _laterSelected,
            ),
            const SizedBox(width: 10),
            TvDialogButton(
              focusNode: _barNodes[4],
              label: '取消',
              onPressed: _exitSelect,
            ),
          ],
        ),
      ),
    );
  }

  /// 公開的重新整理方法 - 供外部呼叫
  void refresh() {
    _favKey.currentState?.refreshAuth();
    _selecting = false;
    _selected.clear();
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
    if (_tab == 1) {
      // 收藏分頁未登入時顯示本機收藏
      body = FavView(
        key: _favKey,
        sidebarFocusNode: widget.sidebarFocusNode,
        onMoveUpToTabs: () => _tabNodes[1].requestFocus(),
      );
    } else if (!loggedIn || _tab == 0) {
      // 未登入時觀看歷史與稍後再看顯示「請先登入」（由 _buildHistoryBody 處理）
      body = _buildHistoryBody(context);
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
        Positioned.fill(top: _selecting && _tab == 0 ? 120 : 64, child: body),
        if (_selecting && _tab == 0 && AuthService.isLoggedIn)
          Positioned(top: 64, left: 0, right: 0, child: _buildSelectionBar()),
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
                    onSelect: (i) => setState(() {
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(0);
                      }
                      _tab = i;
                      _selecting = false;
                      _selected.clear();
                    }),
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

  /// 側邊欄按右鍵：焦點放到目前分頁的第一個項目（左上角），
  /// 不交給預設方向導航（它會依位置挑到中間的卡片）
  void focusFirstItem() {
    if (_tab == 1 ||
        (AuthService.isLoggedIn && (_tab != 0 || _videos.isNotEmpty))) {
      _focusContent();
      return;
    }
    // 沒有內容（未登入或列表空）：改到分頁列
    final tabNode = _tabNodes[_tab];
    if (tabNode.context != null) tabNode.requestFocus();
  }

  /// 分頁列按下鍵：進入目前分頁內容
  void _focusContent() {
    if (_tab == 1) {
      _favKey.currentState?.focusFolders();
      return;
    }
    if (!AuthService.isLoggedIn) return;
    switch (_tab) {
      case 0:
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
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
                          selectionMode: _selecting,
                          selected: _selected.contains(_selKey(video)),
                          onTap: () => _selecting
                              ? _toggleSelect(video)
                              : _onVideoTap(video),
                          onLongPress: () async {
                            if (_selecting) {
                              _toggleSelect(video);
                            } else {
                              _enterSelect(video);
                            }
                          },
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
                              : () => (_selecting ? _barNodes[0] : _tabNodes[0])
                                    .requestFocus(), // 回到分頁列／多選按鈕列
                          // 嚴格按列向下移動
                          onMoveDown: (index + 4 < _videos.length)
                              ? () => _getFocusNode(index + 4).requestFocus()
                              : null,
                          onFocus: () {
                            _lastFocusedIndex = index;
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
