import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../../../models/space_data.dart';
import '../../../models/video.dart';
import '../../../widgets/base_tv_card.dart';
import '../../../widgets/tv_video_card.dart';
import '../widgets/space_button.dart';
import '../widgets/space_collection_card.dart';
import 'space_tab.dart';

/// 區塊最後一張「更多」卡片的標記
class _More {
  const _More();
}

class _Section {
  final String title;
  final List<Object> items; // Video、SpaceCollection 或 _More
  const _Section(this.title, this.items);
}

/// 主頁分頁：影片類區塊，每區塊一列可左右移動的卡片。
class UpHomeTab extends StatefulWidget {
  final SpaceData? data;
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;
  final void Function(Video video) onSelect;

  /// 「最新影片」的更多：切到投稿的影片。
  final VoidCallback onMoreVideos;

  /// 「合集／系列」的更多：切到投稿的合集／系列列表。
  final VoidCallback onMoreCollections;

  /// 選取合集／系列卡片：開啟該合集。
  final void Function(SpaceCollection collection) onOpenCollection;
  final VoidCallback onMoveUpFromTop;

  const UpHomeTab({
    super.key,
    required this.data,
    required this.loading,
    required this.failed,
    required this.onRetry,
    required this.onSelect,
    required this.onMoreVideos,
    required this.onMoreCollections,
    required this.onOpenCollection,
    required this.onMoveUpFromTop,
  });

  @override
  State<UpHomeTab> createState() => _UpHomeTabState();
}

class _UpHomeTabState extends State<UpHomeTab> implements SpaceTabController {
  static const double _itemExtent = 280; // 卡片 260 + 間距 20
  static const double _rowHeight = 224;

  final ScrollController _vScroll = ScrollController();
  final FocusNode _retryNode = FocusNode();
  final Map<int, ScrollController> _rowControllers = {};
  final Map<String, FocusNode> _nodes = {};

  List<_Section> _sections = const [];

  @override
  void dispose() {
    _vScroll.dispose();
    _retryNode.dispose();
    for (final c in _rowControllers.values) {
      c.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  FocusNode _node(int s, int c) =>
      _nodes.putIfAbsent('$s:$c', () => FocusNode());

  ScrollController _rowController(int s) =>
      _rowControllers.putIfAbsent(s, () => ScrollController());

  List<_Section> _buildSections(SpaceData? d) {
    if (d == null) return const [];
    const more = _More();
    return [
      if (d.archive.isNotEmpty) _Section('最新影片', [...d.archive, more]),
      if (d.seasons.isNotEmpty) _Section('合集', [...d.seasons, more]),
      if (d.series.isNotEmpty) _Section('系列', [...d.series, more]),
      if (d.coins.isNotEmpty) _Section('最近投幣', [...d.coins]),
      if (d.likesArchive.isNotEmpty) _Section('最近點讚', [...d.likesArchive]),
      if (d.bangumi.isNotEmpty) _Section('追番', [...d.bangumi]),
    ];
  }

  @override
  bool focusFirst() {
    if (widget.failed) {
      _retryNode.requestFocus();
      return true;
    }
    if (_sections.isEmpty) return false;
    _focus(0, 0);
    return true;
  }

  void _focus(int s, int c) {
    if (s < 0 || s >= _sections.length) return;
    final len = _sections[s].items.length;
    final col = c.clamp(0, len - 1);
    final node = _node(s, col);
    if (node.context != null) {
      node.requestFocus();
      return;
    }
    // 目標卡片尚未建立：先捲到位再聚焦
    final controller = _rowController(s);
    if (controller.hasClients) {
      controller.jumpTo(
        (col * _itemExtent).clamp(0.0, controller.position.maxScrollExtent),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.failed) {
      return Center(
        child: SpaceButton(
          focusNode: _retryNode,
          onTap: widget.onRetry,
          onUp: widget.onMoveUpFromTop,
          builder: (focused) => spacePill(
            focused: focused,
            color: Colors.grey[800]!,
            horizontal: 18,
            icon: Icons.refresh,
            label: '載入失敗，按確定重試',
          ),
        ),
      );
    }
    _sections = _buildSections(widget.data);
    if (_sections.isEmpty) {
      return const Center(
        child: Text('暫無內容', style: TextStyle(color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      controller: _vScroll,
      padding: const EdgeInsets.only(bottom: 40),
      clipBehavior: Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (var s = 0; s < _sections.length; s++) _buildSection(s)],
      ),
    );
  }

  Widget _buildSection(int s) {
    final section = _sections[s];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(34, 10, 30, 0),
          child: Text(
            section.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: _rowHeight,
          child: ListView.builder(
            controller: _rowController(s),
            scrollDirection: Axis.horizontal,
            itemExtent: _itemExtent,
            clipBehavior: Clip.none,
            scrollCacheExtent: const ScrollCacheExtent.pixels(4000),
            padding: const EdgeInsets.fromLTRB(30, 14, 10, 6),
            itemCount: section.items.length,
            itemBuilder: (context, c) => Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Builder(
                builder: (cardContext) => _buildItem(cardContext, s, c),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItem(BuildContext cardContext, int s, int c) {
    final items = _sections[s].items;
    final item = items[c];
    final node = _node(s, c);
    final lastCol = items.length - 1;

    void left() {
      if (c > 0) _focus(s, c - 1);
    }

    void right() {
      if (c < lastCol) _focus(s, c + 1);
    }

    void up() {
      if (s == 0) {
        widget.onMoveUpFromTop();
      } else {
        _focus(s - 1, c);
      }
    }

    void down() {
      if (s < _sections.length - 1) _focus(s + 1, c);
    }

    void onFocus() => spaceEnsureVisible(cardContext, 0.3);

    if (item is Video) {
      return TvVideoCard(
        video: item,
        focusNode: node,
        showDanmaku: true,
        onTap: () => widget.onSelect(item),
        onMoveLeft: left,
        onMoveRight: right,
        onMoveUp: up,
        onMoveDown: down,
        onFocus: onFocus,
      );
    }
    if (item is SpaceCollection) {
      return SpaceCollectionCard(
        collection: item,
        focusNode: node,
        onTap: () => widget.onOpenCollection(item),
        onMoveLeft: left,
        onMoveRight: right,
        onMoveUp: up,
        onMoveDown: down,
        onFocus: onFocus,
      );
    }
    // 更多
    final isVideoSection = _sections[s].title == '最新影片';
    return BaseTvCard(
      focusNode: node,
      onTap: isVideoSection ? widget.onMoreVideos : widget.onMoreCollections,
      onFocus: onFocus,
      onMoveLeft: left,
      onMoveRight: right,
      onMoveUp: up,
      onMoveDown: down,
      imageContent: Container(
        color: const Color(0xFF2d2d2d),
        child: const Center(
          child: Icon(Icons.more_horiz, size: 48, color: Colors.white54),
        ),
      ),
      infoContentBuilder: (context, isFocused) => SizedBox(
        height: 20,
        child: Text(
          '更多',
          style: TextStyle(
            color: isFocused ? Colors.white : Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
