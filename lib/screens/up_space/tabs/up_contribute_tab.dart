import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../../models/space_data.dart';
import '../../../models/video.dart';
import '../../../services/bilibili_api.dart';
import '../widgets/space_button.dart';
import '../widgets/space_collection_card.dart';
import '../widgets/space_grid.dart';
import 'space_tab.dart';

/// 子分頁代碼
abstract final class ContributeSub {
  static const video = 'video';
  static const collections = 'collections';
}

/// 投稿分頁：子分頁「影片」（最新／最多播放）與「合集／系列」。
///
/// 子分頁與已開啟的合集由外層持有（主頁的「更多」要能切過來），
/// 本元件只負責顯示與回報使用者操作。
class UpContributeTab extends StatefulWidget {
  final int mid;
  final List<SpaceCollection> collections;
  final String subTab;
  final SpaceCollection? openedCollection;
  final void Function(String subTab) onSubTab;
  final void Function(SpaceCollection collection) onOpenCollection;
  final void Function(Video video) onSelect;
  final VoidCallback onMoveUpFromTop;

  const UpContributeTab({
    super.key,
    required this.mid,
    required this.collections,
    required this.subTab,
    required this.openedCollection,
    required this.onSubTab,
    required this.onOpenCollection,
    required this.onSelect,
    required this.onMoveUpFromTop,
  });

  @override
  State<UpContributeTab> createState() => UpContributeTabState();
}

class UpContributeTabState extends State<UpContributeTab>
    implements SpaceTabController {
  final FocusNode _videoSubNode = FocusNode();
  final FocusNode _collectionSubNode = FocusNode();
  final FocusNode _sortNode = FocusNode();
  final GlobalKey<SpaceGridState<Video>> _videoGridKey = GlobalKey();
  final GlobalKey<SpaceGridState<SpaceCollection>> _collectionGridKey =
      GlobalKey();
  GlobalKey<SpaceGridState<Video>> _openedGridKey = GlobalKey();

  String _order = 'pubdate'; // 'pubdate' = 最新, 'click' = 最熱

  /// 關閉合集後，合集列表要還原焦點的位置（只用一次）。
  int? _restoreIndex;

  bool get _hasCollections => widget.collections.isNotEmpty;
  bool get _showingCollections =>
      widget.subTab == ContributeSub.collections && _hasCollections;

  @override
  void dispose() {
    _videoSubNode.dispose();
    _collectionSubNode.dispose();
    _sortNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(UpContributeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldOpened = oldWidget.openedCollection;
    final newOpened = widget.openedCollection;
    if (newOpened != null &&
        (oldOpened == null || !newOpened.sameAs(oldOpened))) {
      // 換了合集：用新的 key 讓格狀重新載入
      _openedGridKey = GlobalKey();
    }
    if (oldOpened != null && widget.openedCollection == null) {
      final idx = widget.collections.indexWhere((c) => c.sameAs(oldOpened));
      _restoreIndex = idx < 0 ? 0 : idx;
    }
  }

  /// 焦點移到目前子分頁的按鈕（分頁列按下鍵時進入這裡）。
  @override
  bool focusFirst() {
    _currentSubNode().requestFocus();
    return true;
  }

  /// 焦點直接移到格狀內容；格狀尚未載入完成時退回子分頁按鈕。
  bool focusGrid() {
    final ok = widget.openedCollection != null
        ? (_openedGridKey.currentState?.focusFirst() ?? false)
        : _showingCollections
        ? (_collectionGridKey.currentState?.focusFirst() ?? false)
        : (_videoGridKey.currentState?.focusFirst() ?? false);
    if (!ok) _currentSubNode().requestFocus();
    return ok;
  }

  FocusNode _currentSubNode() =>
      _showingCollections || widget.openedCollection != null
      ? _collectionSubNode
      : _videoSubNode;

  Future<SpacePage<Video>?> _loadVideos(String order, Object? cursor) async {
    final result = await BilibiliApi.getArchives(
      widget.mid,
      order: order,
      cursor: (cursor as String?) ?? '',
    );
    if (result == null) return null;
    return SpacePage(
      items: result.videos,
      hasMore: result.hasMore,
      cursor: result.nextCursor,
    );
  }

  Future<SpacePage<Video>?> _loadCollectionVideos(
    SpaceCollection collection,
    Object? cursor,
  ) async {
    final page = (cursor as int?) ?? 1;
    final result = await BilibiliApi.getCollectionVideos(
      collection,
      mid: widget.mid,
      pn: page,
    );
    if (result == null) return null;
    return SpacePage(
      items: result.videos,
      hasMore: result.hasMore,
      cursor: page + 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final opened = widget.openedCollection;
    final collectionsMode = _showingCollections || opened != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 6, 30, 4),
          child: Row(
            children: [
              _subButton(
                node: _videoSubNode,
                label: '影片',
                selected: !collectionsMode,
                onTap: () => widget.onSubTab(ContributeSub.video),
                onRight: _hasCollections
                    ? () => _collectionSubNode.requestFocus()
                    : (!collectionsMode
                          ? () => _sortNode.requestFocus()
                          : null),
              ),
              if (_hasCollections) ...[
                const SizedBox(width: 12),
                _subButton(
                  node: _collectionSubNode,
                  label: '合集／系列',
                  selected: collectionsMode,
                  onTap: () => widget.onSubTab(ContributeSub.collections),
                  onLeft: () => _videoSubNode.requestFocus(),
                  onRight: !collectionsMode
                      ? () => _sortNode.requestFocus()
                      : null,
                ),
              ],
              const Spacer(),
              if (!collectionsMode)
                SpaceButton(
                  focusNode: _sortNode,
                  onTap: () => setState(
                    () => _order = _order == 'pubdate' ? 'click' : 'pubdate',
                  ),
                  onLeft: () =>
                      (_hasCollections ? _collectionSubNode : _videoSubNode)
                          .requestFocus(),
                  onUp: widget.onMoveUpFromTop,
                  onDown: focusGrid,
                  builder: (focused) => spacePill(
                    focused: focused,
                    color: Colors.grey[800]!,
                    horizontal: 14,
                    icon: _order == 'pubdate' ? Icons.schedule : Icons.whatshot,
                    label: _order == 'pubdate' ? '最新' : '最熱',
                  ),
                ),
            ],
          ),
        ),
        if (opened != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(34, 4, 30, 0),
            child: Text(
              opened.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Expanded(child: _buildGrid(opened)),
      ],
    );
  }

  Widget _buildGrid(SpaceCollection? opened) {
    void toSubRow() => _currentSubNode().requestFocus();

    if (opened != null) {
      return SpaceGrid<Video>(
        key: _openedGridKey,
        load: (cursor) => _loadCollectionVideos(opened, cursor),
        onMoveUpFromTop: toSubRow,
        autofocusIndex: 0,
        itemBuilder: (context, video, index, cell) =>
            buildSpaceVideoCard(context, video, cell, widget.onSelect),
      );
    }

    if (_showingCollections) {
      final restore = _restoreIndex;
      if (restore != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _restoreIndex = null;
        });
      }
      return SpaceGrid<SpaceCollection>(
        key: _collectionGridKey,
        load: (_) async => SpacePage(items: widget.collections, hasMore: false),
        emptyText: '暫無合集或系列',
        onMoveUpFromTop: toSubRow,
        autofocusIndex: restore,
        itemBuilder: (context, collection, index, cell) => SpaceCollectionCard(
          collection: collection,
          focusNode: cell.node,
          onTap: () => widget.onOpenCollection(collection),
          onMoveLeft: cell.onMoveLeft,
          onMoveRight: cell.onMoveRight,
          onMoveUp: cell.onMoveUp,
          onMoveDown: cell.onMoveDown,
          onFocus: cell.onFocus,
        ),
      );
    }

    final order = _order;
    return SpaceGrid<Video>(
      key: _videoGridKey,
      load: (cursor) => _loadVideos(order, cursor),
      emptyText: '暫無影片',
      onMoveUpFromTop: toSubRow,
      itemBuilder: (context, video, index, cell) =>
          buildSpaceVideoCard(context, video, cell, widget.onSelect),
    );
  }

  Widget _subButton({
    required FocusNode node,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onLeft,
    VoidCallback? onRight,
  }) {
    return SpaceButton(
      focusNode: node,
      onTap: onTap,
      onLeft: onLeft,
      onRight: onRight,
      onUp: widget.onMoveUpFromTop,
      onDown: focusGrid,
      builder: (focused) => spacePill(
        focused: focused,
        color: selected ? const Color(0xFFfb7299) : Colors.grey[800]!,
        horizontal: 18,
        label: label,
      ),
    );
  }
}
