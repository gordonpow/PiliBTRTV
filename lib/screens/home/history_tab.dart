import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/rendering.dart';
import '../../models/video.dart';
import '../../services/bilibili_api.dart';
import 'package:keframe/keframe.dart';
import '../../services/auth_service.dart';
import '../../widgets/history_video_card.dart';
import '../../widgets/time_display.dart';
import '../player/player_screen.dart';

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

  void _onVideoTap(Video video) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PlayerScreen(video: video)));
  }

  @override
  Widget build(BuildContext context) {
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
                  padding: const EdgeInsets.fromLTRB(30, 80, 30, 80),
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
                              : () {}, // 最頂行為無效輸入
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
        // 固定標題
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: const Color(0xFF121212),
            padding: const EdgeInsets.fromLTRB(30, 20, 30, 15),
            child: const Text(
              '觀看歷史',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        // 右上角時間
        const Positioned(top: 20, right: 30, child: TimeDisplay()),
      ],
    );
  }
}
