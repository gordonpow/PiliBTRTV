import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/rendering.dart';
import 'package:keframe/keframe.dart';
import '../../../services/api/base_api.dart';
import '../../../widgets/tv_live_card.dart';
import '../../live/live_player_screen.dart';

/// 直播間 4 欄網格（直播頁與關注直播頁共用）
class LiveRoomGrid extends StatefulWidget {
  final List<dynamic> rooms;
  final FocusNode? sidebarFocusNode;

  /// 第一列按上鍵時呼叫（例如回到分類列）；為 null 則不處理
  final VoidCallback? onMoveUpFromTop;
  final VoidCallback? onLoadMore;
  final ScrollController scrollController;
  final double topPadding;

  /// 第一張卡片自動取得焦點
  final bool autofocusFirst;

  /// 重新整理中，使用分幀渲染
  final bool isRefreshing;

  const LiveRoomGrid({
    super.key,
    required this.rooms,
    required this.scrollController,
    this.sidebarFocusNode,
    this.onMoveUpFromTop,
    this.onLoadMore,
    this.topPadding = 100,
    this.autofocusFirst = false,
    this.isRefreshing = false,
  });

  @override
  State<LiveRoomGrid> createState() => LiveRoomGridState();
}

class LiveRoomGridState extends State<LiveRoomGrid> {
  final Map<int, FocusNode> _roomFocusNodes = {};

  FocusNode _getFocusNode(int index) =>
      _roomFocusNodes.putIfAbsent(index, () => FocusNode());

  /// 聚焦第一張卡片
  void focusFirst() {
    if (widget.rooms.isNotEmpty) _getFocusNode(0).requestFocus();
  }

  @override
  void dispose() {
    for (final node in _roomFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _navigateToRoom(dynamic room) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LivePlayerScreen(
          roomId: room['roomid'],
          title: room['title'],
          cover:
              room['pic'] ??
              room['room_cover'] ??
              room['cover'] ??
              room['user_cover'] ??
              room['keyframe'],
          uname: room['uname'],
          face: room['face'],
          online: BaseApi.toInt(room['online'] ?? room['text_small']),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rooms = widget.rooms;
    final controller = widget.scrollController;
    return SizeCacheWidget(
      child: CustomScrollView(
        controller: controller,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(30, widget.topPadding, 30, 80),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 320 / 280,
                crossAxisSpacing: 20,
                mainAxisSpacing: 30,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index == rooms.length - 4) {
                  widget.onLoadMore?.call();
                }

                final room = rooms[index];

                Widget buildCard(BuildContext ctx) {
                  return TvLiveCard(
                    room: room,
                    autofocus: widget.autofocusFirst && index == 0,
                    focusNode: _getFocusNode(index),
                    onTap: () => _navigateToRoom(room),
                    onFocus: () {
                      if (!controller.hasClients) return;
                      final RenderObject? object = ctx.findRenderObject();
                      if (object != null && object is RenderBox) {
                        final viewport = RenderAbstractViewport.of(object);
                        final offsetToReveal = viewport
                            .getOffsetToReveal(object, 0.0)
                            .offset;
                        final targetOffset = (offsetToReveal - 120).clamp(
                          0.0,
                          controller.position.maxScrollExtent,
                        );
                        if ((controller.offset - targetOffset).abs() > 50) {
                          controller.animateTo(
                            targetOffset,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      }
                    },
                    onMoveLeft: (index % 4 == 0)
                        ? () => widget.sidebarFocusNode?.requestFocus()
                        : () => _getFocusNode(index - 1).requestFocus(),
                    onMoveRight: (index + 1 < rooms.length)
                        ? () => _getFocusNode(index + 1).requestFocus()
                        : null,
                    onMoveUp: index >= 4
                        ? () => _getFocusNode(index - 4).requestFocus()
                        : widget.onMoveUpFromTop,
                    onMoveDown: (index + 4 < rooms.length)
                        ? () => _getFocusNode(index + 4).requestFocus()
                        : null,
                  );
                }

                // 只有重新整理時使用分幀渲染 (match HomeTab)
                if (widget.isRefreshing) {
                  return FrameSeparateWidget(
                    index: index,
                    placeHolder: const SizedBox(width: 30, height: 30),
                    child: Builder(builder: buildCard),
                  );
                }

                return Builder(builder: buildCard);
              }, childCount: rooms.length),
            ),
          ),
        ],
      ),
    );
  }
}
