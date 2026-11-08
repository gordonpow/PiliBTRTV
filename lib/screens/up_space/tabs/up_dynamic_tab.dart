import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../../models/video.dart';
import '../../../services/bilibili_api.dart';
import '../widgets/space_grid.dart';
import 'space_tab.dart';

/// 動態分頁：UP主的影片動態（含轉發的影片），4 欄格狀。
class UpDynamicTab extends StatefulWidget {
  final int mid;
  final void Function(Video video) onSelect;
  final VoidCallback onMoveUpFromTop;

  const UpDynamicTab({
    super.key,
    required this.mid,
    required this.onSelect,
    required this.onMoveUpFromTop,
  });

  @override
  State<UpDynamicTab> createState() => _UpDynamicTabState();
}

class _UpDynamicTabState extends State<UpDynamicTab>
    implements SpaceTabController {
  final GlobalKey<SpaceGridState<Video>> _gridKey = GlobalKey();

  @override
  bool focusFirst() => _gridKey.currentState?.focusFirst() ?? false;

  /// 動態可能整頁都不是影片：自動再載下一頁，最多連續 3 次，避免空白畫面。
  Future<SpacePage<Video>?> _load(Object? cursor) async {
    var offset = (cursor as String?) ?? '';
    final videos = <Video>[];
    var hasMore = true;
    for (var attempt = 0; attempt < 3; attempt++) {
      final result = await BilibiliApi.getSpaceDynamics(
        widget.mid,
        offset: offset,
      );
      if (result == null) {
        // 第一次就失敗才算失敗；後續失敗保留已取得的內容
        if (attempt == 0) return null;
        break;
      }
      videos.addAll(result.videos);
      offset = result.offset;
      hasMore = result.hasMore;
      if (videos.isNotEmpty || !hasMore) break;
    }
    return SpacePage(items: videos, hasMore: hasMore, cursor: offset);
  }

  @override
  Widget build(BuildContext context) {
    return SpaceGrid<Video>(
      key: _gridKey,
      load: _load,
      emptyText: '暫無影片動態',
      onMoveUpFromTop: widget.onMoveUpFromTop,
      itemBuilder: (context, video, index, cell) =>
          buildSpaceVideoCard(context, video, cell, widget.onSelect),
    );
  }
}
