import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../../services/auth_service.dart';
import '../../../services/bilibili_api.dart';
import '../../../utils/format_count.dart';
import '../../../widgets/vip_avatar_badge.dart';
import '../../up_space/up_space_screen.dart';
import '../../up_space/widgets/space_button.dart';
import '../login/login_view.dart';
import 'followings_screen.dart';

/// 個人頁面：基本資料、關注與粉絲、我的投稿、登入／登出。
class ProfileTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final bool isVisible;
  final VoidCallback? onLoginSuccess;
  final VoidCallback? onLogout;

  const ProfileTab({
    super.key,
    this.sidebarFocusNode,
    this.isVisible = false,
    this.onLoginSuccess,
    this.onLogout,
  });

  @override
  State<ProfileTab> createState() => ProfileTabState();
}

class ProfileTabState extends State<ProfileTab> {
  static const _pink = Color(0xFFfb7299);

  final FocusNode _followingsNode = FocusNode(debugLabel: 'profileFollowings');
  final FocusNode _spaceNode = FocusNode(debugLabel: 'profileSpace');
  final FocusNode _logoutNode = FocusNode(debugLabel: 'profileLogout');
  final FocusNode _loginNode = FocusNode(debugLabel: 'profileLogin');
  final FocusNode _retryNode = FocusNode(debugLabel: 'profileRetry');
  final GlobalKey<LoginViewState> _loginKey = GlobalKey<LoginViewState>();

  MyInfo? _info;
  MyStat? _stat;
  bool _loading = false;
  bool _failed = false;
  bool _loaded = false; // 是否曾經載入過（isVisible 只在尚未載入時觸發）
  bool _showLogin = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    if (widget.isVisible) _load();
  }

  @override
  void didUpdateWidget(ProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible && !_loaded && !_loading) _load();
  }

  @override
  void dispose() {
    _followingsNode.dispose();
    _spaceNode.dispose();
    _logoutNode.dispose();
    _loginNode.dispose();
    _retryNode.dispose();
    super.dispose();
  }

  /// 重新載入（側邊欄按確認鍵時呼叫）。
  void refresh() => _load();

  /// 從側邊欄按右鍵進入。
  void focusFirstItem() {
    if (_showLogin && !AuthService.isLoggedIn) {
      _loginKey.currentState?.focusDefault();
    } else if (!AuthService.isLoggedIn) {
      _loginNode.requestFocus();
    } else if (_failed && _info == null) {
      _retryNode.requestFocus();
    } else {
      _followingsNode.requestFocus();
    }
  }

  /// 返回鍵：登入畫面開啟時關閉它並回傳 true。
  bool handleBack() {
    if (_showLogin) {
      setState(() => _showLogin = false);
      widget.sidebarFocusNode?.requestFocus();
      return true;
    }
    return false;
  }

  Future<void> _load() async {
    final id = ++_requestId;
    if (!AuthService.isLoggedIn) {
      setState(() {
        _info = null;
        _stat = null;
        _loading = false;
        _failed = false;
        _loaded = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    final results = await Future.wait<Object?>([
      BilibiliApi.getMyInfo(),
      BilibiliApi.getMyStat(),
    ]);
    if (!mounted || id != _requestId) return;
    final info = results[0] as MyInfo?;
    final stat = results[1] as MyStat?;
    setState(() {
      _loading = false;
      _loaded = info != null;
      _failed = info == null;
      if (info != null) _info = info;
      if (stat != null) _stat = stat;
    });
  }

  void _handleLoginSuccess() {
    setState(() => _showLogin = false);
    widget.onLoginSuccess?.call();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.sidebarFocusNode?.requestFocus();
    });
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('確認退出', style: TextStyle(color: Colors.white)),
        content: const Text(
          '確定要退出登入嗎？',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('確認', style: TextStyle(color: _pink)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.onLogout?.call();
    // onLogout 是非同步的（由 HomeScreen 呼叫 AuthService.logout），等登入狀態清除
    for (var i = 0; i < 20 && AuthService.isLoggedIn; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;
    setState(() {
      _info = null;
      _stat = null;
      _failed = false;
      _loaded = false;
      _requestId++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loginNode.requestFocus();
    });
  }

  void _openFollowings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FollowingsScreen()));
  }

  void _openMySpace() {
    final mid = AuthService.mid ?? _info?.mid;
    if (mid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UpSpaceScreen(
          mid: mid,
          name: _info?.uname ?? AuthService.uname ?? '',
          face: _info?.face ?? AuthService.face ?? '',
          isSelf: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn) {
      if (_showLogin) {
        return LoginView(
          key: _loginKey,
          sidebarFocusNode: widget.sidebarFocusNode,
          onLoginSuccess: _handleLoginSuccess,
        );
      }
      return _buildLoggedOut();
    }
    return _buildLoggedIn();
  }

  Widget _buildLoggedOut() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_circle, size: 80, color: Colors.white38),
          const SizedBox(height: 12),
          const Text(
            '尚未登入',
            style: TextStyle(color: Colors.white70, fontSize: 20),
          ),
          const SizedBox(height: 20),
          SpaceButton(
            focusNode: _loginNode,
            onTap: () => setState(() => _showLogin = true),
            onLeft: () => widget.sidebarFocusNode?.requestFocus(),
            builder: (focused) => spacePill(
              focused: focused,
              color: _pink,
              horizontal: 28,
              icon: Icons.login,
              label: '登入',
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoggedIn() {
    final info = _info;
    final face = info?.face.isNotEmpty == true
        ? info!.face
        : (AuthService.face ?? '');
    final name = info?.uname.isNotEmpty == true
        ? info!.uname
        : (AuthService.uname ?? '');
    final mid = info?.mid ?? AuthService.mid;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 30, 30, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VipAvatarBadge(
                size: 96,
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: Colors.grey[800],
                  backgroundImage: face.isNotEmpty
                      ? NetworkImage(
                          face.startsWith('//') ? 'https:$face' : face,
                        )
                      : null,
                  child: face.isEmpty
                      ? const Icon(Icons.person, size: 48)
                      : null,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(child: _buildInfoColumn(info, name, mid)),
            ],
          ),
          const SizedBox(height: 24),
          if (_failed && info == null) _buildError(),
          _buildStats(),
          const SizedBox(height: 24),
          _buildButtons(),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(MyInfo? info, String name, int? mid) {
    final lines = <Widget>[
      Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
      if (mid != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'UID: $mid',
            style: TextStyle(color: Colors.grey[400], fontSize: 15),
          ),
        ),
    ];
    if (info != null) {
      final next = info.nextExp;
      final progress = (next == null || next <= 0)
          ? 1.0
          : (info.currentExp / next).clamp(0.0, 1.0);
      lines.addAll([
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              'Lv${info.level}',
              style: const TextStyle(
                color: _pink,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(_pink),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              next == null
                  ? '${info.currentExp}（滿級）'
                  : '${info.currentExp} / $next',
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '硬幣 ${_fmtMoney(info.coins)}　B幣 ${_fmtMoney(info.bcoin)}',
          style: TextStyle(color: Colors.grey[300], fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          _vipText(info),
          style: TextStyle(
            color: info.isVip ? _pink : Colors.grey[500],
            fontSize: 15,
          ),
        ),
      ]);
    } else if (_loading) {
      lines.add(
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }

  static String _fmtMoney(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  static String _vipText(MyInfo info) {
    if (!info.isVip) return '大會員：未開通';
    final label = info.vipLabel.isNotEmpty ? info.vipLabel : '大會員';
    if (info.vipDueMs <= 0) return label;
    final d = DateTime.fromMillisecondsSinceEpoch(info.vipDueMs);
    String two(int n) => n.toString().padLeft(2, '0');
    return '$label　到期 ${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Widget _buildStats() {
    final s = _stat;
    String v(int? n) => n == null ? '-' : formatCount(n);
    Widget item(String label, String value) => Padding(
      padding: const EdgeInsets.only(right: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 14)),
        ],
      ),
    );
    return Row(
      children: [
        item('關注', v(s?.following)),
        item('粉絲', v(s?.follower)),
        item('動態', v(s?.dynamicCount)),
      ],
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const Text(
            '個人資料載入失敗',
            style: TextStyle(color: Colors.redAccent, fontSize: 15),
          ),
          const SizedBox(width: 16),
          SpaceButton(
            focusNode: _retryNode,
            onTap: _load,
            onLeft: () => widget.sidebarFocusNode?.requestFocus(),
            onDown: () => _followingsNode.requestFocus(),
            builder: (focused) => spacePill(
              focused: focused,
              color: Colors.grey[800]!,
              horizontal: 18,
              icon: Icons.refresh,
              label: '重試',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        SpaceButton(
          focusNode: _followingsNode,
          onTap: _openFollowings,
          onLeft: () => widget.sidebarFocusNode?.requestFocus(),
          onRight: () => _spaceNode.requestFocus(),
          onUp: _failed && _info == null
              ? () => _retryNode.requestFocus()
              : null,
          builder: (focused) => spacePill(
            focused: focused,
            color: _pink,
            horizontal: 22,
            icon: Icons.people,
            label: '關注列表',
            fontSize: 16,
          ),
        ),
        const SizedBox(width: 12),
        SpaceButton(
          focusNode: _spaceNode,
          onTap: _openMySpace,
          onLeft: () => _followingsNode.requestFocus(),
          onRight: () => _logoutNode.requestFocus(),
          builder: (focused) => spacePill(
            focused: focused,
            color: Colors.grey[800]!,
            horizontal: 22,
            icon: Icons.video_library,
            label: '我的投稿',
            fontSize: 16,
          ),
        ),
        const SizedBox(width: 12),
        SpaceButton(
          focusNode: _logoutNode,
          onTap: _confirmLogout,
          onLeft: () => _spaceNode.requestFocus(),
          builder: (focused) => spacePill(
            focused: focused,
            color: Colors.red.shade900,
            horizontal: 22,
            icon: Icons.logout,
            label: '退出登入',
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
