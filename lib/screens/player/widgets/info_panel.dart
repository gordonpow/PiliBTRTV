import 'package:bili_tv_app/models/reply_item.dart';
import 'package:bili_tv_app/services/bilibili_api.dart';
import 'package:bili_tv_app/utils/anim.dart';
import 'package:bili_tv_app/utils/format_count.dart';
import 'package:bili_tv_app/widgets/content_text.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import '../focus/player_focus_handler.dart';

/// 播放器右側的資訊面板：簡介與留言兩個分頁。
///
/// 自管焦點。左右鍵切換分頁，上下鍵捲動簡介或逐則移動留言，
/// 確認鍵在留言載入失敗時重試。返回鍵不處理，交給播放器的全域按鍵處理
/// （關閉面板並把焦點還給控制列的「簡介」按鈕）。
class InfoPanel extends StatefulWidget {
  /// 完整影片資訊（fullVideoInfo）
  final Map? videoInfo;
  final int aid;

  /// 番劇沒有簡介欄位，固定顯示「沒有簡介」
  final bool isPgc;
  final VoidCallback onClose;

  const InfoPanel({
    super.key,
    required this.videoInfo,
    required this.aid,
    required this.onClose,
    this.isPgc = false,
  });

  @override
  State<InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<InfoPanel> {
  static const double _descScrollStep = 120;

  final FocusNode _focusNode = FocusNode(debugLabel: 'infoPanel');
  final ScrollController _descScroll = ScrollController();
  final ScrollController _replyScroll = ScrollController();

  int _tab = 0; // 0 簡介、1 留言

  // 留言狀態（第一次切到留言才載入）
  final List<ReplyItem> _replies = [];
  final Set<int> _seen = {};
  final Map<int, GlobalKey> _itemKeys = {};
  String _offset = '';
  bool _isEnd = false;
  bool _loading = false;
  bool _error = false;
  bool _started = false;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    // autofocus 只在範圍內沒有焦點時生效；播放器的 playerFocusNode 已有焦點，
    // 所以開啟後要主動搶焦點，否則方向鍵仍送到控制列。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _descScroll.dispose();
    _replyScroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || _isEnd) return;
    final aid = widget.aid;
    setState(() {
      _loading = true;
      _error = false;
    });
    final page = await BilibiliApi.getReplies(aid: aid, offset: _offset);
    if (!mounted || aid != widget.aid) return;
    setState(() {
      _loading = false;
      if (page == null) {
        _error = true;
        return;
      }
      for (final r in page.items) {
        if (_seen.add(r.rpid)) _replies.add(r);
      }
      _offset = page.nextOffset;
      _isEnd = page.isEnd;
    });
  }

  void _switchTab(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (tab == 1 && !_started) {
      _started = true;
      _loadMore();
    }
  }

  void _moveSelection(int delta) {
    if (_replies.isEmpty) return;
    final next = (_selected + delta).clamp(0, _replies.length - 1);
    if (next != _selected) setState(() => _selected = next);
    if (next >= _replies.length - 3 && !_isEnd && !_loading && !_error) {
      _loadMore();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || next >= _replies.length) return;
      final ctx = _itemKeys[_replies[next].rpid]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 120),
        );
      }
      // 選到最後一則時，一併捲到底，露出「沒有更多留言」
      if (next == _replies.length - 1 && _replyScroll.hasClients) {
        _replyScroll.animateTo(
          _replyScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollDesc(double delta) {
    if (!_descScroll.hasClients) return;
    final target = (_descScroll.offset + delta).clamp(
      0.0,
      _descScroll.position.maxScrollExtent,
    );
    _descScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // 返回鍵交給播放器全域處理
    if (PlayerFocusHandler.isBackKey(event)) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (event is KeyDownEvent) {
        // 簡介分頁按左鍵關閉面板；留言分頁回到簡介
        if (_tab == 0) {
          widget.onClose();
        } else {
          _switchTab(0);
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (event is KeyDownEvent) _switchTab(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final dir = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      if (_tab == 0) {
        _scrollDesc(dir * _descScrollStep);
      } else {
        _moveSelection(dir);
      }
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        PlayerFocusHandler.isSelectKey(event) &&
        _tab == 1 &&
        _error &&
        !_loading) {
      _loadMore();
    }
    // 面板開啟時吞掉其他按鍵，避免誤操作播放器
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: 520,
      child: EnterTransition(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Container(
            color: const Color(0xFF1F1F1F),
            child: Column(
              children: [
                _buildTabs(),
                Expanded(
                  // 只淡入、不保留舊分頁：留言與簡介共用 GlobalKey／捲動控制器
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_tab),
                    tween: Tween(begin: 0, end: 1),
                    duration: Anim.of(Anim.fast),
                    builder: (_, t, child) => Opacity(opacity: t, child: child),
                    child: _tab == 0 ? _buildDesc() : _buildReplies(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    Widget tab(String label, int index) {
      final active = _tab == index;
      return Expanded(
        child: AnimatedContainer(
          duration: Anim.of(Anim.fast),
          curve: Anim.curve,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? const Color(0xFFfb7299) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white54,
              fontSize: 20,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(children: [tab('簡介', 0), tab('留言', 1)]),
    );
  }

  // ───────────── 簡介 ─────────────

  String _formatDate(int seconds) {
    if (seconds <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
  }

  int _int(Object? v) => v is int ? v : 0;

  Widget _stat(String label, int value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 16),
        ),
        const SizedBox(width: 6),
        Text(
          formatCount(value),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildDesc() {
    final info = widget.videoInfo;
    final title = info?['title']?.toString() ?? '';
    final owner = info?['owner'];
    final ownerName = owner is Map ? (owner['name']?.toString() ?? '') : '';
    final pubdate = _int(info?['pubdate']);
    final statRaw = info?['stat'];
    final stat = statRaw is Map ? statRaw : const {};
    final desc = widget.isPgc ? '' : (info?['desc']?.toString().trim() ?? '');

    return SingleChildScrollView(
      controller: _descScroll,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            ContentText(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          const SizedBox(height: 12),
          if (ownerName.isNotEmpty)
            ContentText(
              ownerName,
              style: const TextStyle(color: Color(0xFFfb7299), fontSize: 18),
            ),
          if (pubdate > 0) ...[
            const SizedBox(height: 6),
            Text(
              _formatDate(pubdate),
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _stat('播放', _int(stat['view'])),
              _stat('彈幕', _int(stat['danmaku'])),
              _stat('讚', _int(stat['like'])),
              _stat('幣', _int(stat['coin'])),
              _stat('收藏', _int(stat['favorite'])),
              _stat('留言', _int(stat['reply'])),
            ],
          ),
          const SizedBox(height: 20),
          if (desc.isEmpty)
            const Text(
              '沒有簡介',
              style: TextStyle(color: Colors.white54, fontSize: 18),
            )
          else
            ContentText(
              desc,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }

  // ───────────── 留言 ─────────────

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 18),
        ),
      ),
    );
  }

  Widget _buildReplies() {
    if (_replies.isEmpty) {
      if (_error) return _hint('留言載入失敗，按確認鍵重試');
      if (_loading || !_started) return _hint('載入中…');
      return _hint('目前沒有留言');
    }
    return SingleChildScrollView(
      controller: _replyScroll,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _replies.length; i++) _buildReply(i),
          if (_error)
            _hint('留言載入失敗，按確認鍵重試')
          else if (_loading)
            _hint('載入中…')
          else if (_isEnd)
            _hint('沒有更多留言'),
        ],
      ),
    );
  }

  Widget _buildReply(int index) {
    final r = _replies[index];
    final selected = index == _selected;
    return Container(
      key: _itemKeys.putIfAbsent(r.rpid, () => GlobalKey()),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: selected ? 0.12 : 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? const Color(0xFFfb7299) : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (r.isTop) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFfb7299),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '置頂',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: ContentText(
                  r.uname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFfb7299),
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatDate(r.ctime),
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const Spacer(),
              const Icon(
                Icons.thumb_up_outlined,
                color: Colors.white54,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                formatCount(r.like),
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ContentText(
            r.message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              height: 1.4,
            ),
          ),
          if (r.replyCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              '共 ${r.replyCount} 則回覆',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}
