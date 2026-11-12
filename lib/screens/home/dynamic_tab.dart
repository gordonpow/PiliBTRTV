import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/video.dart';
import '../../services/bilibili_api.dart';
import 'package:keframe/keframe.dart';
import '../../services/auth_service.dart';
import '../../utils/anim.dart';
import '../../widgets/tv_video_card.dart';
import '../../widgets/time_display.dart';
import '../player/player_screen.dart';

/// 動態 Tab
class DynamicTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final bool isVisible;

  const DynamicTab({super.key, this.sidebarFocusNode, this.isVisible = false});

  @override
  State<DynamicTab> createState() => DynamicTabState();
}

class DynamicTabState extends State<DynamicTab> {
  List<Video> _videos = [];
  bool _isLoading = true;
  String _offset = '';
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasLoaded = false;
  bool _isRefreshing = false; // 標記是否正在重新整理中（用於控制分幀渲染）
  // 每個影片卡片的 FocusNode
  final Map<int, FocusNode> _videoFocusNodes = {};

  @override
  void initState() {
    super.initState();
    // 只有第一次可見時才載入
    if (widget.isVisible) {
      _loadDynamic(refresh: true);
      _hasLoaded = true;
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(DynamicTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 之前不可見，現在可見了，且沒載入過 -> 載入
    if (widget.isVisible && !oldWidget.isVisible && !_hasLoaded) {
      _loadDynamic(refresh: true);
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
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  /// 公開的重新整理方法 - 供外部呼叫
  void refresh() {
    _hasLoaded = true; // 標記已載入，避免切換時重複載入
    _loadDynamic(refresh: true);
  }

  Future<void> _loadDynamic({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _isLoading = true;
        _isRefreshing = true; // 開始重新整理
        _videos = [];
        _offset = '';
        _hasMore = true;
      });
    }

    if (!_hasMore && !refresh) return;

    final feed = await BilibiliApi.getDynamicFeed(
      offset: refresh ? '' : _offset,
    );

    if (!mounted) return;

    setState(() {
      if (refresh) {
        _videos = feed.videos;
      } else {
        // 去重：過濾掉已存在的影片
        final existingBvids = _videos.map((v) => v.bvid).toSet();
        final newVideos = feed.videos
            .where((v) => !existingBvids.contains(v.bvid))
            .toList();
        _videos.addAll(newVideos);
      }
      _offset = feed.offset;
      _hasMore = feed.hasMore;
      _isLoading = false;
      _isLoadingMore = false;
      _isRefreshing = false; // 重新整理完成
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    await _loadDynamic(refresh: false);
  }

  void _onVideoTap(Video video) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => PlayerScreen(video: video)));
  }

  @override
  Widget build(BuildContext context) {
    // 載入中 → 內容以淡入切換（只依載入狀態換 key，內容間的更新不觸發動畫）
    return AnimatedSwitcher(
      duration: Anim.of(Anim.normal),
      child: KeyedSubtree(
        key: ValueKey(AuthService.isLoggedIn && _isLoading),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
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
              '登入後可檢視關注的動態',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/icons/dynamic.svg',
              width: 80,
              height: 80,
              colorFilter: ColorFilter.mode(
                Colors.white.withValues(alpha: 0.3),
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '暫無動態',
              style: TextStyle(color: Colors.white70, fontSize: 20),
            ),
          ],
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Column(
            children: [
              Expanded(
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
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final video = _videos[index];

                            // 構建卡片的內容
                            Widget buildCard(BuildContext ctx) {
                              return TvVideoCard(
                                video: video,
                                focusNode: _getFocusNode(index),
                                disableCache: false,
                                onTap: () => _onVideoTap(video),
                                // 最左列按左鍵跳到側邊欄
                                onMoveLeft: (index % 4 == 0)
                                    ? () => widget.sidebarFocusNode
                                          ?.requestFocus()
                                    : () => _getFocusNode(
                                        index - 1,
                                      ).requestFocus(),
                                // 強制向右導航
                                onMoveRight: (index + 1 < _videos.length)
                                    ? () => _getFocusNode(
                                        index + 1,
                                      ).requestFocus()
                                    : null,
                                // 嚴格按列向上移動（4個一行）
                                onMoveUp: index >= 4
                                    ? () => _getFocusNode(
                                        index - 4,
                                      ).requestFocus()
                                    : () {}, // 最頂行為無效輸入
                                // 嚴格按列向下移動
                                onMoveDown: (index + 4 < _videos.length)
                                    ? () => _getFocusNode(
                                        index + 4,
                                      ).requestFocus()
                                    : ((index ~/ 4 + 1) * 4 < _videos.length)
                                    // 最後一列不滿四張：移到最後一張
                                    ? () => _getFocusNode(
                                        _videos.length - 1,
                                      ).requestFocus()
                                    : null,
                                onFocus: () {
                                  if (!_scrollController.hasClients) return;

                                  final RenderObject? object = ctx
                                      .findRenderObject();
                                  if (object != null && object is RenderBox) {
                                    final viewport = RenderAbstractViewport.of(
                                      object,
                                    );
                                    final offsetToReveal = viewport
                                        .getOffsetToReveal(object, 0.0)
                                        .offset;
                                    final targetOffset = (offsetToReveal - 120)
                                        .clamp(
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

                            // 只有在重新整理時才使用分幀渲染，否則直接渲染
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

                            // 非重新整理狀態（從播放器返回）直接渲染
                            return Builder(builder: buildCard);
                          }, childCount: _videos.length),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isLoadingMore)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
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
              '關注動態',
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
