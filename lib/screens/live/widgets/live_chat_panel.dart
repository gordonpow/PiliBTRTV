import 'dart:async';

import 'package:bili_tv_app/widgets/zh_material.dart';

/// 直播聊天列表的一則訊息
class LiveChatMessage {
  final int id;
  final String user;
  final String content;

  const LiveChatMessage({
    required this.id,
    required this.user,
    required this.content,
  });
}

/// 右側半透明聊天列表：「使用者名稱: 內容」，新訊息自動捲到底。
/// 不接收焦點與觸控，不影響遙控器操作。
class LiveChatPanel extends StatefulWidget {
  final List<LiveChatMessage> messages;

  /// true：彈出式（新留言浮現後自動消失）；false：列表式
  final bool popup;

  /// true：顯示在左側；false：右側
  final bool onLeft;

  const LiveChatPanel({
    super.key,
    required this.messages,
    this.popup = true,
    this.onLeft = false,
  });

  @override
  State<LiveChatPanel> createState() => _LiveChatPanelState();
}

class _LiveChatPanelState extends State<LiveChatPanel> {
  final ScrollController _controller = ScrollController();

  int _lastId(List<LiveChatMessage> list) => list.isEmpty ? 0 : list.last.id;

  @override
  void initState() {
    super.initState();
    _scrollToBottom();
  }

  @override
  void didUpdateWidget(LiveChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastId(widget.messages) != _lastId(oldWidget.messages)) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.popup) {
      return _LiveChatPopup(
        key: ValueKey('chat-popup-${widget.onLeft}'),
        messages: widget.messages,
        onLeft: widget.onLeft,
      );
    }
    final onLeft = widget.onLeft;
    return Positioned(
      top: 96,
      left: onLeft ? 0 : null,
      right: onLeft ? null : 0,
      bottom: 120,
      width: 320,
      child: IgnorePointer(
        child: ExcludeFocus(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: onLeft
                  ? const BorderRadius.horizontal(right: Radius.circular(12))
                  : const BorderRadius.horizontal(left: Radius.circular(12)),
            ),
            child: ListView.builder(
              controller: _controller,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: widget.messages.length,
              itemBuilder: (context, index) {
                final m = widget.messages[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${m.user}: ',
                          style: const TextStyle(color: Color(0xFFfb7299)),
                        ),
                        TextSpan(
                          text: m.content,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 14),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PopupItem {
  final LiveChatMessage msg;
  final DateTime addedAt;
  _PopupItem(this.msg, this.addedAt);
}

/// 彈出式留言：新留言從下方浮現，約 8 秒後淡出移除。
/// 不顯示開啟前的舊留言。
class _LiveChatPopup extends StatefulWidget {
  final List<LiveChatMessage> messages;
  final bool onLeft;

  const _LiveChatPopup({
    super.key,
    required this.messages,
    required this.onLeft,
  });

  @override
  State<_LiveChatPopup> createState() => _LiveChatPopupState();
}

class _LiveChatPopupState extends State<_LiveChatPopup> {
  static const int _maxItems = 6;
  static const Duration _life = Duration(seconds: 8);
  static const Duration _fadeAt = Duration(milliseconds: 7500);

  final List<_PopupItem> _items = [];
  int _lastSeenId = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _lastSeenId = widget.messages.isEmpty ? 0 : widget.messages.last.id;
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final before = _items.length;
      _items.removeWhere((e) => now.difference(e.addedAt) >= _life);
      // 接近淡出時間也要重繪，才會觸發淡出動畫
      final fading = _items.any((e) => now.difference(e.addedAt) >= _fadeAt);
      if (before != _items.length || fading) setState(() {});
    });
  }

  @override
  void didUpdateWidget(_LiveChatPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = DateTime.now();
    for (final m in widget.messages) {
      if (m.id > _lastSeenId) {
        _items.add(_PopupItem(m, now));
        _lastSeenId = m.id;
      }
    }
    while (_items.length > _maxItems) {
      _items.removeAt(0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onLeft = widget.onLeft;
    final now = DateTime.now();
    return Positioned(
      bottom: 140,
      left: onLeft ? 24 : null,
      right: onLeft ? null : 24,
      width: 420,
      child: IgnorePointer(
        child: ExcludeFocus(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: onLeft
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              for (final item in _items)
                _bubble(item, now.difference(item.addedAt) >= _fadeAt),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(_PopupItem item, bool fading) {
    final m = item.msg;
    return KeyedSubtree(
      key: ValueKey(m.id),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 200),
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 16),
            child: child,
          ),
        ),
        child: AnimatedOpacity(
          opacity: fading ? 0 : 1,
          duration: const Duration(milliseconds: 500),
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${m.user}: ',
                      style: const TextStyle(
                        color: Color(0xFFfb7299),
                        fontSize: 13,
                      ),
                    ),
                    TextSpan(
                      text: m.content,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
