import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import '../../../models/video.dart';
import '../../../services/api/pgc_api.dart';
import '../../../services/bilibili_api.dart';
import '../../../widgets/tv_video_card.dart';

/// 播放器底部的相關影片橫排。
///
/// 一排：貼齊畫面底部的漸層背景，影片繼續播放；展開：佔畫面約 65% 高度的多排網格。
/// 方向鍵由本元件處理（一排：下鍵展開、上鍵收起；展開：第一排按上鍵收回一排）；
/// 返回鍵不處理，交給播放器的全域按鍵處理（先收回一排，再關閉）。
class RelatedStrip extends StatefulWidget {
  /// 目前播放的 bvid（一般影片用來取得相關影片）
  final String bvid;

  /// 番劇的 season_id；大於 0 時改取番劇推薦
  final int seasonId;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<Video> onVideoSelect;

  /// 一排時按上鍵：關閉相關影片，回到控制列
  final VoidCallback onClose;

  const RelatedStrip({
    super.key,
    required this.bvid,
    required this.seasonId,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onVideoSelect,
    required this.onClose,
  });

  @override
  State<RelatedStrip> createState() => _RelatedStripState();
}

class _RelatedStripState extends State<RelatedStrip> {
  static const double _cardWidth = 260;
  static const double _gap = 20;
  static const double _itemExtent = _cardWidth + _gap;
  static const double _rowHeight = 224;
  static const double _stripHeight = 260;

  List<Video> _videos = [];
  bool _loading = true;
  int _focusedIndex = 0;
  int _columns = 1;
  final List<FocusNode> _nodes = [];
  final FocusNode _fallbackNode = FocusNode(debugLabel: 'relatedStrip');
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _videos.isEmpty) _fallbackNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(RelatedStrip old) {
    super.didUpdateWidget(old);
    if (old.expanded != widget.expanded) {
      // 一排與展開使用不同的捲動元件，重建後把焦點還給目前那張卡片
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goto(_focusedIndex);
      });
    }
  }

  @override
  void dispose() {
    _fallbackNode.dispose();
    for (final n in _nodes) {
      n.dispose();
    }
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<Video> videos;
    try {
      videos = widget.seasonId > 0
          ? await PgcApi.getSeasonRelated(widget.seasonId)
          : await BilibiliApi.getRelatedVideos(widget.bvid);
    } catch (_) {
      videos = [];
    }
    if (!mounted) return;
    setState(() {
      _videos = videos;
      _loading = false;
      while (_nodes.length < videos.length) {
        _nodes.add(FocusNode(debugLabel: 'relatedCard${_nodes.length}'));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_videos.isEmpty) {
        _fallbackNode.requestFocus();
      } else {
        _goto(0);
      }
    });
  }

  /// 把焦點移到第 [index] 張卡片；尚未建立的卡片先捲動過去再取得焦點
  void _goto(int index) {
    if (index < 0 || index >= _videos.length) return;
    final node = _nodes[index];
    if (node.context != null) {
      node.requestFocus();
      Scrollable.ensureVisible(
        node.context!,
        alignment: 0.5,
        duration: const Duration(milliseconds: 150),
      );
      return;
    }
    if (widget.expanded) {
      if (_vScroll.hasClients) {
        _vScroll.jumpTo(
          (index ~/ _columns * (_rowHeight + _gap)).clamp(
            0.0,
            _vScroll.position.maxScrollExtent,
          ),
        );
      }
    } else if (_hScroll.hasClients) {
      _hScroll.jumpTo(
        (index * _itemExtent).clamp(0.0, _hScroll.position.maxScrollExtent),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.context != null) node.requestFocus();
    });
  }

  KeyEventResult _onFallbackKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      if (widget.expanded) {
        widget.onExpandedChanged(false);
      } else {
        widget.onClose();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onUp(int index) {
    if (!widget.expanded) {
      widget.onClose();
    } else if (index < _columns) {
      widget.onExpandedChanged(false);
    } else {
      _goto(index - _columns);
    }
  }

  void _onDown(int index) {
    if (!widget.expanded) {
      widget.onExpandedChanged(true);
    } else if (index + _columns < _videos.length) {
      _goto(index + _columns);
    }
  }

  Widget _card(int index) {
    return TvVideoCard(
      video: _videos[index],
      focusNode: _nodes[index],
      showDanmaku: true,
      enablePreview: false,
      onFocus: () => _focusedIndex = index,
      onTap: () => widget.onVideoSelect(_videos[index]),
      onMoveLeft: () {
        if (index > 0) _goto(index - 1);
      },
      onMoveRight: () {
        if (index + 1 < _videos.length) _goto(index + 1);
      },
      onMoveUp: () => _onUp(index),
      onMoveDown: () => _onDown(index),
    );
  }

  Widget _buildBody(double width) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_videos.isEmpty) {
      return const Center(
        child: Text(
          '沒有相關推薦',
          style: TextStyle(color: Colors.white70, fontSize: 18),
        ),
      );
    }
    if (!widget.expanded) {
      return ListView.builder(
        controller: _hScroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        itemExtent: _itemExtent,
        itemCount: _videos.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(right: _gap),
          child: SizedBox(width: _cardWidth, child: _card(i)),
        ),
      );
    }
    final avail = width - 80;
    _columns = (avail / _itemExtent).floor().clamp(1, 8);
    return GridView.builder(
      controller: _vScroll,
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        crossAxisSpacing: _gap,
        mainAxisSpacing: _gap,
        mainAxisExtent: _rowHeight,
      ),
      itemCount: _videos.length,
      itemBuilder: (_, i) => _card(i),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final expanded = widget.expanded;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Focus(
        focusNode: _fallbackNode,
        onKeyEvent: _onFallbackKey,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: double.infinity,
          height: expanded ? size.height * 0.65 : _stripHeight,
          decoration: BoxDecoration(
            color: expanded ? Colors.black.withValues(alpha: 0.55) : null,
            gradient: expanded
                ? null
                : LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
          ),
          child: _buildBody(size.width),
        ),
      ),
    );
  }
}
