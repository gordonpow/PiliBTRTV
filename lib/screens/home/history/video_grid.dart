import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/rendering.dart';
import '../../../models/video.dart';
import '../../../widgets/tv_video_card.dart';
import '../../player/player_screen.dart';

/// 收藏／稍後再看共用的 4 欄影片格（焦點管理、捲動、接近底部時要求載入更多）
class HistoryVideoGrid extends StatefulWidget {
  final List<Video> videos;
  final FocusNode? sidebarFocusNode;

  /// 第一列按上鍵時的動作
  final VoidCallback? onMoveUpFromFirstRow;

  /// 焦點接近底部時呼叫（由焦點事件觸發，不在 build 中呼叫）
  final VoidCallback? onNeedMore;
  final bool isLoadingMore;

  /// 長按卡片的動作；null 時使用卡片預設的「影片選項」
  final Future<void> Function(Video video, int index)? onLongPressVideo;

  const HistoryVideoGrid({
    super.key,
    this.onLongPressVideo,
    required this.videos,
    this.sidebarFocusNode,
    this.onMoveUpFromFirstRow,
    this.onNeedMore,
    this.isLoadingMore = false,
  });

  @override
  State<HistoryVideoGrid> createState() => HistoryVideoGridState();
}

class HistoryVideoGridState extends State<HistoryVideoGrid> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, FocusNode> _nodes = {};

  FocusNode _node(int i) => _nodes.putIfAbsent(i, () => FocusNode());

  /// 聚焦第一張卡片
  void focusFirst() {
    if (widget.videos.isNotEmpty) _node(0).requestFocus();
  }

  /// 聚焦指定位置的卡片（超出範圍時夾到最後一張）。
  /// 該節點已持有焦點時先放開再要求，讓卡片重新收到焦點事件（內容已換成別部影片）。
  void focusIndex(int i) {
    if (widget.videos.isEmpty) return;
    final node = _node(i.clamp(0, widget.videos.length - 1));
    if (node.hasPrimaryFocus) node.unfocus();
    node.requestFocus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    _nodes.clear();
    super.dispose();
  }

  void _reveal(BuildContext ctx) {
    if (!_scrollController.hasClients) return;
    final object = ctx.findRenderObject();
    if (object is! RenderBox) return;
    final viewport = RenderAbstractViewport.of(object);
    final offsetToReveal = viewport.getOffsetToReveal(object, 0.0).offset;
    final target = (offsetToReveal - 120).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    if ((_scrollController.offset - target).abs() > 50) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final videos = widget.videos;
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(30, 20, 30, 80),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 320 / 280,
              crossAxisSpacing: 20,
              mainAxisSpacing: 30,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final video = videos[index];
              return Builder(
                builder: (ctx) => TvVideoCard(
                  video: video,
                  focusNode: _node(index),
                  onLongPress: widget.onLongPressVideo == null
                      ? null
                      : () => widget.onLongPressVideo!(video, index),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(video: video),
                    ),
                  ),
                  onMoveLeft: index % 4 == 0
                      ? () => widget.sidebarFocusNode?.requestFocus()
                      : () => _node(index - 1).requestFocus(),
                  onMoveRight: index + 1 < videos.length
                      ? () => _node(index + 1).requestFocus()
                      : null,
                  onMoveUp: index >= 4
                      ? () => _node(index - 4).requestFocus()
                      : () => widget.onMoveUpFromFirstRow?.call(),
                  onMoveDown: index + 4 < videos.length
                      ? () => _node(index + 4).requestFocus()
                      : null,
                  onFocus: () {
                    // 先判斷載入更多，再處理捲動
                    if (index >= videos.length - 8) widget.onNeedMore?.call();
                    _reveal(ctx);
                  },
                ),
              );
            }, childCount: videos.length),
          ),
        ),
        if (widget.isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}
