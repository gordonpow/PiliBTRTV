import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../../models/video.dart';
import '../../../services/api/fav_api.dart';
import '../../../services/api/interaction_api.dart';
import '../../../services/auth_service.dart';
import '../../../services/bilibili_api.dart';
import '../../../services/local_favorites_service.dart';
import '../../../widgets/video_action_dialogs.dart';
import '../../../widgets/tv_tab_bar.dart';
import 'local_fav_view.dart';
import 'video_grid.dart';

/// 我的收藏分頁內容：收藏夾列 + 影片格（往下捲動載入更多）。
/// 未登入時顯示本機收藏（[LocalFavView]）；已登入且本機有資料時多一個「本機收藏」分頁。
class FavView extends StatefulWidget {
  final FocusNode? sidebarFocusNode;

  /// 收藏夾列按上鍵時回到上方分頁列
  final VoidCallback? onMoveUpToTabs;

  const FavView({super.key, this.sidebarFocusNode, this.onMoveUpToTabs});

  @override
  State<FavView> createState() => FavViewState();
}

class FavViewState extends State<FavView> {
  final GlobalKey<HistoryVideoGridState> _gridKey = GlobalKey();
  final GlobalKey<LocalFavViewState> _localKey = GlobalKey();
  final _local = LocalFavoritesService.instance;
  List<FavFolder> _folders = [];
  final List<FocusNode> _folderNodes = [];
  int? _authMid; // 目前載入的帳號（登入／登出／換帳號時重載）
  bool _loadingFolders = true;
  int _selected = 0;

  List<Video> _videos = [];
  bool _loadingVideos = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  int _gen = 0; // 切換收藏夾時遞增，丟棄過期的回應

  /// 聚焦收藏夾列（由上方分頁列按下鍵進入）
  void focusFolders() {
    if (!AuthService.isLoggedIn) {
      _localKey.currentState?.focusFolders();
      return;
    }
    if (_folderNodes.isEmpty) return;
    _folderNodes[_selected.clamp(0, _folderNodes.length - 1)].requestFocus();
  }

  /// 重新整理目前收藏夾的影片
  void reload() {
    if (!AuthService.isLoggedIn) return;
    if (_folders.isEmpty) {
      setState(() => _loadingFolders = true);
      _loadFolders();
    } else {
      _loadVideos(reset: true);
    }
  }

  /// 本機有資料且已登入時，帳號收藏夾後面多一個「本機收藏」虛擬分頁
  bool get _showLocalTab => AuthService.isLoggedIn && _local.totalVideos > 0;
  bool get _onLocalTab => _showLocalTab && _selected == _folders.length;

  /// 登入狀態改變（登入、登出、換帳號）時重新載入帳號收藏夾
  void refreshAuth() {
    if (_authMid == AuthService.mid) return;
    _authMid = AuthService.mid;
    _gen++;
    setState(() {
      _folders = [];
      _videos = [];
      _selected = 0;
      _loadingFolders = AuthService.isLoggedIn;
    });
    if (AuthService.isLoggedIn) _loadFolders();
  }

  @override
  void initState() {
    super.initState();
    _authMid = AuthService.mid;
    _local.addListener(_onLocalChanged);
    _local.importDone.addListener(_afterImport);
    _local.ensureLoaded();
    if (AuthService.isLoggedIn) {
      _loadFolders();
    } else {
      _loadingFolders = false;
    }
  }

  @override
  void dispose() {
    _local.removeListener(_onLocalChanged);
    _local.importDone.removeListener(_afterImport);
    for (final n in _folderNodes) {
      n.dispose();
    }
    super.dispose();
  }

  bool _wasOnLocalTab = false;

  void _onLocalChanged() {
    if (!mounted) return;
    setState(() {});
    _refocusIfLocalTabGone();
  }

  /// 內嵌的本機分頁因本機清空而消失時，焦點移回收藏夾列（避免焦點掉到無處）
  void _refocusIfLocalTabGone() {
    if (!_wasOnLocalTab || _local.totalVideos > 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_onLocalTab) focusFolders();
    });
  }

  /// 分頁焦點節點數量跟著分頁數（帳號收藏夾 + 可能的本機分頁）
  void _syncNodes(int count) {
    while (_folderNodes.length < count) {
      _folderNodes.add(FocusNode());
    }
    while (_folderNodes.length > count) {
      final n = _folderNodes.removeLast();
      WidgetsBinding.instance.addPostFrameCallback((_) => n.dispose());
    }
    if (_selected >= count) {
      _selected = count > 0 ? count - 1 : 0;
      // 落到帳號收藏夾（本機分頁消失）：重新載入該夾，避免顯示舊內容
      if (_selected < _folders.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selected < _folders.length) {
            _loadVideos(reset: true);
          }
        });
      }
    }
  }

  Future<void> _loadFolders() async {
    final folders = await BilibiliApi.getFavFolders();
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _loadingFolders = false;
    });
    if (folders.isNotEmpty) _loadVideos(reset: true);
  }

  void _selectFolder(int i) {
    if (i == _selected) return;
    setState(() => _selected = i);
    if (i < _folders.length) _loadVideos(reset: true);
  }

  /// 本機收藏匯入帳號後：重新讀取帳號收藏夾
  void _afterImport() {
    if (!mounted || !AuthService.isLoggedIn) return;
    _gen++;
    setState(() => _loadingFolders = true);
    _loadFolders().then((_) => _refocusIfLocalTabGone());
  }

  Future<void> _loadVideos({required bool reset}) async {
    if (_folders.isEmpty || _selected >= _folders.length) return;
    if (!reset && (_loadingMore || _loadingVideos || !_hasMore)) return;
    final gen = reset ? ++_gen : _gen;
    final folderId = _folders[_selected].id;
    final page = reset ? 1 : _page + 1;
    setState(() {
      if (reset) {
        _videos = [];
        _hasMore = true;
        _page = 1;
        _loadingVideos = true;
        _loadingMore = false;
      } else {
        _loadingMore = true;
      }
    });

    final result = await BilibiliApi.getFavVideos(folderId, page);
    if (!mounted || gen != _gen) return;
    final list = result['list'] as List<Video>;
    final hasMore = result['hasMore'] as bool;
    final ok = result['ok'] as bool;
    setState(() {
      if (reset) {
        _videos = list;
        _loadingVideos = false;
      } else {
        final seen = _videos.map((v) => v.bvid).toSet();
        _videos = [..._videos, ...list.where((v) => !seen.contains(v.bvid))];
        _loadingMore = false;
      }
      if (ok) _page = page;
      _hasMore = ok && hasMore;
    });
  }

  Future<void> _onLongPress(Video video, int index) async {
    if (_folders.isEmpty) return;
    final folder = _folders[_selected];
    final gen = _gen;
    final removed = await showVideoActionMenu(
      context,
      video,
      removeLabel: '從此收藏夾移除',
      removedMessage: '已從收藏夾移除',
      onRemove: () async {
        final aid = video.resolvedAid;
        if (aid <= 0) return '無法取得影片資訊';
        return InteractionApi.dealFavorite(aid: aid, delIds: [folder.id]);
      },
    );
    // 期間若切換了收藏夾，清單已重載，不再動畫面
    if (!removed || !mounted || gen != _gen) return;
    setState(() {
      _videos = _videos.where((v) => v != video).toList();
      final i = _folders.indexWhere((f) => f.id == folder.id);
      if (i >= 0) {
        final f = _folders[i];
        _folders = [..._folders]
          ..[i] = FavFolder(
            id: f.id,
            title: f.title,
            mediaCount: f.mediaCount > 0 ? f.mediaCount - 1 : 0,
          );
      }
    });
    // 長按結束時 BaseTvCard 會先還原長按前的焦點（microtask）；
    // 這裡等下一個 frame 之後才移焦點，確保最後生效的是移除後的目標
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_videos.isEmpty) {
        focusFolders();
      } else {
        _gridKey.currentState?.focusIndex(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn) {
      return LocalFavView(
        key: _localKey,
        sidebarFocusNode: widget.sidebarFocusNode,
        onMoveUpToTabs: widget.onMoveUpToTabs,
      );
    }
    if (_loadingFolders) {
      return const Center(child: CircularProgressIndicator());
    }
    final showLocal = _showLocalTab;
    _syncNodes(_folders.length + (showLocal ? 1 : 0));
    _wasOnLocalTab = _onLocalTab;
    if (_folders.isEmpty && !showLocal) {
      return const Center(
        child: Text(
          '還沒有收藏夾',
          style: TextStyle(color: Colors.white70, fontSize: 20),
        ),
      );
    }

    Widget content;
    if (_onLocalTab) {
      content = LocalFavView(
        key: _localKey,
        embedded: true,
        sidebarFocusNode: widget.sidebarFocusNode,
        onMoveUpToTabs: focusFolders,
      );
    } else if (_loadingVideos) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_videos.isEmpty) {
      content = const Center(
        child: Text(
          '這個收藏夾是空的',
          style: TextStyle(color: Colors.white70, fontSize: 20),
        ),
      );
    } else {
      content = HistoryVideoGrid(
        key: _gridKey,
        videos: _videos,
        onLongPressVideo: _onLongPress,
        sidebarFocusNode: widget.sidebarFocusNode,
        isLoadingMore: _loadingMore,
        onMoveUpFromFirstRow: focusFolders,
        onNeedMore: () => _loadVideos(reset: false),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TvTabBar(
              labels: [
                ..._folders.map((f) => '${f.title} (${f.mediaCount})'),
                if (showLocal) '本機收藏 (${_local.totalVideos})',
              ],
              focusNodes: _folderNodes,
              selectedIndex: _selected,
              fontSize: 16,
              onSelect: _selectFolder,
              onMoveLeftAtFirst: () => widget.sidebarFocusNode?.requestFocus(),
              onMoveUp: widget.onMoveUpToTabs,
              onMoveDown: () => _onLocalTab
                  ? _localKey.currentState?.focusActions()
                  : _gridKey.currentState?.focusFirst(),
            ),
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}
