import 'package:bili_tv_app/widgets/content_text.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import '../../../services/auth_service.dart';
import '../../../services/bilibili_api.dart';
import '../../up_space/up_space_screen.dart';

/// 關注列表：4 欄卡片（頭像、名稱、簽名），焦點接近底部時載入下一頁。
class FollowingsScreen extends StatefulWidget {
  const FollowingsScreen({super.key});

  @override
  State<FollowingsScreen> createState() => _FollowingsScreenState();
}

class _FollowingsScreenState extends State<FollowingsScreen> {
  static const int _columns = 4;
  static const int _pageSize = 20;

  final List<FollowingUser> _users = [];
  final List<FocusNode> _nodes = [];
  final ScrollController _scroll = ScrollController();
  int _page = 0;
  int _total = 0;
  bool _loading = false;
  bool _hasMore = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMore() async {
    final mid = AuthService.mid;
    if (_loading || !_hasMore || mid == null) {
      if (mid == null && mounted) setState(() => _failed = _users.isEmpty);
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    final page = await BilibiliApi.getFollowings(mid, _page + 1);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (page == null) {
        _failed = _users.isEmpty;
        return;
      }
      _page++;
      _total = page.total;
      final seen = _users.map((u) => u.mid).toSet();
      for (final u in page.list) {
        if (seen.add(u.mid)) {
          _users.add(u);
          _nodes.add(FocusNode());
        }
      }
      // 空頁、少於一頁、或已載入數 >= total 時停止
      if (page.list.isEmpty ||
          page.list.length < _pageSize ||
          (_total > 0 && _users.length >= _total)) {
        _hasMore = false;
      }
    });
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _nodes.length) return;
    _nodes[target].requestFocus();
  }

  void _onFocused(int index) {
    final ctx = _nodes[index].context;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
      );
    }
    // 接近底部（最後兩列）時載入下一頁
    if (index >= _users.length - _columns * 2) _loadMore();
  }

  Future<void> _open(FollowingUser u) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UpSpaceScreen(mid: u.mid, name: u.name, face: u.face),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(30, 24, 30, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _total > 0 ? '關注列表（$_total）' : '關注列表',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_users.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Text(
          _failed ? '載入失敗，請按返回後重試' : '尚未關注任何人',
          style: const TextStyle(color: Colors.white54, fontSize: 16),
        ),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        mainAxisExtent: 96,
      ),
      itemCount: _users.length,
      itemBuilder: (context, i) => _FollowingCard(
        user: _users[i],
        focusNode: _nodes[i],
        autofocus: i == 0,
        onFocus: () => _onFocused(i),
        onTap: () => _open(_users[i]),
        onLeft: i % _columns == 0 ? null : () => _move(i, -1),
        onRight: i % _columns == _columns - 1 ? null : () => _move(i, 1),
        onUp: () => _move(i, -_columns),
        onDown: () => _move(i, _columns),
      ),
    );
  }
}

class _FollowingCard extends StatefulWidget {
  final FollowingUser user;
  final FocusNode focusNode;
  final bool autofocus;
  final VoidCallback onFocus;
  final VoidCallback onTap;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback onUp;
  final VoidCallback onDown;

  const _FollowingCard({
    required this.user,
    required this.focusNode,
    required this.autofocus,
    required this.onFocus,
    required this.onTap,
    required this.onLeft,
    required this.onRight,
    required this.onUp,
    required this.onDown,
  });

  @override
  State<_FollowingCard> createState() => _FollowingCardState();
}

class _FollowingCardState extends State<_FollowingCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) widget.onFocus();
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          if (event is KeyDownEvent) widget.onTap();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          widget.onLeft?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          widget.onRight?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          widget.onUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          widget.onDown();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _focused ? const Color(0xFF3A3A3A) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _focused ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.grey[800],
              backgroundImage: u.face.isNotEmpty ? NetworkImage(u.face) : null,
              child: u.face.isEmpty ? const Icon(Icons.person) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ContentText(
                    u.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (u.sign.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ContentText(
                      u.sign,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
