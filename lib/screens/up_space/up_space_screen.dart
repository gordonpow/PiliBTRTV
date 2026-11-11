import 'package:bili_tv_app/widgets/content_text.dart';
import 'dart:async';

import 'package:bili_tv_app/utils/zh_toast.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../models/space_data.dart';
import '../../models/video.dart';
import '../../services/bilibili_api.dart';
import '../../utils/format_count.dart';
import 'tabs/space_tab.dart';
import 'tabs/up_contribute_tab.dart';
import 'tabs/up_dynamic_tab.dart';
import 'tabs/up_home_tab.dart';
import 'widgets/space_button.dart';

/// UP主 全螢幕頁面：資訊區 + 分頁列（主頁／動態／投稿）+ 分頁內容。
///
/// 選擇影片時以 `Navigator.pop(context, video)` 回傳；按返回鍵回傳 null。
class UpSpaceScreen extends StatefulWidget {
  final int mid;
  final String name;
  final String face;

  /// 看自己的空間：隱藏關注按鈕，且不查詢關注狀態。
  final bool isSelf;

  const UpSpaceScreen({
    super.key,
    required this.mid,
    required this.name,
    required this.face,
    this.isSelf = false,
  });

  @override
  State<UpSpaceScreen> createState() => _UpSpaceScreenState();
}

class _UpSpaceScreenState extends State<UpSpaceScreen> {
  static const _tabLabels = {'home': '主頁', 'dynamic': '動態', 'contribute': '投稿'};
  static const _defaultTabs = ['home', 'dynamic', 'contribute'];

  final FocusNode _followNode = FocusNode();
  final Map<String, FocusNode> _tabNodes = {
    for (final t in _defaultTabs) t: FocusNode(),
  };
  final GlobalKey _homeKey = GlobalKey();
  final GlobalKey _dynamicKey = GlobalKey();
  final GlobalKey<UpContributeTabState> _contributeKey = GlobalKey();

  // 資料
  SpaceData? _space;
  bool _spaceLoading = true;
  bool _spaceFailed = false;
  bool _homeLoading = false; // 主頁重試中（不能動到整個內容區，否則分頁狀態會遺失）
  Map<String, dynamic>? _info; // getSpace 失敗時退回 getUpCard
  bool _isFollowing = false;
  int _spaceRequestId = 0;

  // 分頁
  List<String> _tabs = _defaultTabs;
  String _tab = 'contribute'; // 目前顯示的分頁
  String _focusedTab = 'contribute'; // 分頁列上聚焦（高亮）的分頁
  final Set<String> _created = {}; // 已建立過內容的分頁（首次選取才建立）
  Timer? _tabTimer;

  // 投稿分頁狀態（主頁的「更多」要能切過去，所以放在這裡）
  String _contribSub = ContributeSub.video;
  SpaceCollection? _openedCollection;

  // 資訊區收合：焦點在分頁內容時收成一行
  bool _headerFocused = true;

  @override
  void initState() {
    super.initState();
    _loadSpace();
    if (!widget.isSelf) _loadFollowStatus();
  }

  @override
  void dispose() {
    _tabTimer?.cancel();
    _followNode.dispose();
    for (final node in _tabNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSpace() async {
    final id = ++_spaceRequestId;
    final firstLoad = _created.isEmpty;
    setState(() {
      if (firstLoad) {
        _spaceLoading = true;
      } else {
        _homeLoading = true;
      }
      _spaceFailed = false;
    });

    final space = await BilibiliApi.getSpace(widget.mid);
    Map<String, dynamic>? info;
    if (space == null) info = await BilibiliApi.getUpCard(widget.mid);
    if (!mounted || id != _spaceRequestId) return;

    setState(() {
      _spaceLoading = false;
      _homeLoading = false;
      _space = space;
      _spaceFailed = space == null;
      if (info != null) _info = info;
      if (firstLoad) {
        _tabs = (space != null && space.tabs.isNotEmpty)
            ? space.tabs
            : _defaultTabs;
        _tab = space?.defaultTab ?? 'contribute';
        if (!_tabs.contains(_tab)) _tab = _tabs.first;
        _focusedTab = _tab;
        _created.add(_tab);
      }
    });

    if (firstLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // 初始焦點在關注按鈕（或尚無焦點）時，移到目前分頁的按鈕
        final primary = FocusManager.instance.primaryFocus;
        if (widget.isSelf || _followNode.hasFocus || primary == null) {
          _tabNodes[_tab]?.requestFocus();
        }
      });
    } else if (_tab == 'home') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controllerOf('home')?.focusFirst();
      });
    }
  }

  Future<void> _loadFollowStatus() async {
    final following = await BilibiliApi.checkFollowStatus(widget.mid);
    if (!mounted) return;
    setState(() => _isFollowing = following);
  }

  Future<void> _toggleFollow() async {
    final target = !_isFollowing;
    final success = await BilibiliApi.followUser(
      mid: widget.mid,
      follow: target,
    );
    if (!mounted) return;
    if (success) {
      setState(() => _isFollowing = target);
      showZhToast(msg: target ? '已關注' : '已取消關注');
    } else {
      showZhToast(msg: '操作失敗');
    }
  }

  // ===== 分頁切換與焦點 =====

  void _onTabFocused(String tab) {
    if (_focusedTab != tab) setState(() => _focusedTab = tab);
    _tabTimer?.cancel();
    if (_tab == tab) return;
    // 按住方向鍵連續切換時，只建立最後一個分頁的內容
    _tabTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {
        _tab = _focusedTab;
        _created.add(_tab);
      });
    });
  }

  void _moveTab(int delta) {
    final i = _tabs.indexOf(_focusedTab) + delta;
    if (i < 0 || i >= _tabs.length) return;
    _tabNodes[_tabs[i]]?.requestFocus();
  }

  SpaceTabController? _controllerOf(String tab) {
    final state = switch (tab) {
      'home' => _homeKey.currentState,
      'dynamic' => _dynamicKey.currentState,
      _ => _contributeKey.currentState,
    };
    return state is SpaceTabController ? state as SpaceTabController : null;
  }

  /// 分頁列按下鍵：進入目前分頁的內容。
  void _enterContent() {
    _tabTimer?.cancel();
    if (_tab != _focusedTab) {
      setState(() {
        _tab = _focusedTab;
        _created.add(_tab);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controllerOf(_tab)?.focusFirst();
      });
    } else {
      _controllerOf(_tab)?.focusFirst();
    }
  }

  void _focusTabBar() => _tabNodes[_tab]?.requestFocus();

  /// 主頁的「更多」或合集卡片：切到投稿分頁。
  void _gotoContribute(String sub, SpaceCollection? opened) {
    _tabTimer?.cancel();
    setState(() {
      _contribSub = sub;
      _openedCollection = opened;
      _tab = 'contribute';
      _focusedTab = 'contribute';
      _created.add('contribute');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contributeKey.currentState?.focusGrid();
    });
  }

  void _select(Video video) => Navigator.pop(context, video);

  // ===== 畫面 =====

  @override
  Widget build(BuildContext context) {
    final collectionOpen = _tab == 'contribute' && _openedCollection != null;
    return PopScope(
      // 開著合集影片時，返回鍵先回到合集列表
      canPop: !collectionOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && collectionOpen) {
          setState(() => _openedCollection = null);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Column(
          children: [
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (focused) {
                if (_headerFocused != focused) {
                  setState(() => _headerFocused = focused);
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _headerFocused
                        ? _buildHeader()
                        : _buildCollapsedHeader(),
                  ),
                  if (!_spaceLoading) _buildTabBar(),
                ],
              ),
            ),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  ({String name, String face, String sign, int fans, int archiveCount})
  _headerInfo() {
    final space = _space;
    final info = _info;
    var name = widget.name;
    var face = widget.face;
    var sign = '';
    var fans = 0;
    var archiveCount = 0;
    var hasStats = false;
    if (space != null) {
      if (space.name.isNotEmpty) name = space.name;
      if (space.face.isNotEmpty) face = space.face;
      sign = space.sign;
      fans = space.fans;
      archiveCount = space.archiveCount;
      hasStats = true;
    } else if (info != null) {
      if ((info['name'] as String?)?.isNotEmpty == true) {
        name = info['name'] as String;
      }
      if ((info['face'] as String?)?.isNotEmpty == true) {
        face = info['face'] as String;
      }
      sign = (info['sign'] as String?) ?? '';
      fans = info['fans'] as int? ?? 0;
      archiveCount = info['archiveCount'] as int? ?? 0;
      hasStats = true;
    }
    if (face.startsWith('//')) face = 'https:$face';
    return (
      name: name,
      face: face,
      sign: sign,
      fans: hasStats ? fans : -1,
      archiveCount: archiveCount,
    );
  }

  Widget _buildCollapsedHeader() {
    final h = _headerInfo();
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 10, 30, 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Colors.grey[800],
            backgroundImage: h.face.isNotEmpty ? NetworkImage(h.face) : null,
            child: h.face.isEmpty ? const Icon(Icons.person, size: 14) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ContentText(
              h.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final h = _headerInfo();
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 24, 30, 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.grey[800],
            backgroundImage: h.face.isNotEmpty ? NetworkImage(h.face) : null,
            child: h.face.isEmpty ? const Icon(Icons.person, size: 36) : null,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ContentText(
                  h.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (h.sign.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ContentText(
                    h.sign,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                ],
                if (h.fans >= 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '粉絲 ${formatCount(h.fans)}・投稿 ${formatCount(h.archiveCount)}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
          if (!widget.isSelf) ...[
            const SizedBox(width: 20),
            SpaceButton(
              focusNode: _followNode,
              autofocus: true,
              onTap: _toggleFollow,
              onDown: _spaceLoading ? null : _focusTabBar,
              builder: (focused) => spacePill(
                focused: focused,
                color: _isFollowing
                    ? Colors.grey[700]!
                    : const Color(0xFFfb7299),
                horizontal: 18,
                icon: _isFollowing ? Icons.check : Icons.add,
                label: _isFollowing ? '已關注' : '關注',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 0, 30, 6),
      child: Row(
        children: [
          for (final tab in _tabs) ...[
            SpaceButton(
              focusNode: _tabNodes[tab]!,
              onTap: _enterContent,
              onFocus: (_) => _onTabFocused(tab),
              onLeft: () => _moveTab(-1),
              onRight: () => _moveTab(1),
              onUp: widget.isSelf ? null : () => _followNode.requestFocus(),
              onDown: _enterContent,
              builder: (focused) => spacePill(
                focused: focused,
                color: tab == _focusedTab
                    ? const Color(0xFFfb7299)
                    : Colors.grey[800]!,
                horizontal: 22,
                label: _tabLabels[tab] ?? tab,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_spaceLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        for (final tab in _tabs)
          if (_created.contains(tab))
            Offstage(
              key: ValueKey(tab),
              offstage: tab != _tab,
              child: ExcludeFocus(
                excluding: tab != _tab,
                child: _buildTab(tab),
              ),
            ),
      ],
    );
  }

  Widget _buildTab(String tab) {
    switch (tab) {
      case 'home':
        return UpHomeTab(
          key: _homeKey,
          data: _space,
          loading: _homeLoading,
          failed: _spaceFailed,
          onRetry: _loadSpace,
          onSelect: _select,
          onMoreVideos: () => _gotoContribute(ContributeSub.video, null),
          onMoreCollections: () =>
              _gotoContribute(ContributeSub.collections, null),
          onOpenCollection: (c) =>
              _gotoContribute(ContributeSub.collections, c),
          onMoveUpFromTop: _focusTabBar,
        );
      case 'dynamic':
        return UpDynamicTab(
          key: _dynamicKey,
          mid: widget.mid,
          onSelect: _select,
          onMoveUpFromTop: _focusTabBar,
        );
      default:
        final space = _space;
        return UpContributeTab(
          key: _contributeKey,
          mid: widget.mid,
          collections: space == null
              ? const []
              : [...space.seasons, ...space.series],
          subTab: _contribSub,
          openedCollection: _openedCollection,
          onSubTab: (sub) => setState(() {
            _contribSub = sub;
            _openedCollection = null;
          }),
          onOpenCollection: (c) => setState(() {
            _contribSub = ContributeSub.collections;
            _openedCollection = c;
          }),
          onSelect: _select,
          onMoveUpFromTop: _focusTabBar,
        );
    }
  }
}
