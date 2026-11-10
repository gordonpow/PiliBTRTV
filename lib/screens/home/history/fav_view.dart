import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../../models/video.dart';
import '../../../services/api/fav_api.dart';
import '../../../services/api/interaction_api.dart';
import '../../../services/bilibili_api.dart';
import '../../../widgets/video_action_dialogs.dart';
import '../../../widgets/tv_tab_bar.dart';
import 'video_grid.dart';

/// 我的收藏分頁內容：收藏夾列 + 影片格（往下捲動載入更多）
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
  List<FavFolder> _folders = [];
  List<FocusNode> _folderNodes = [];
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
    if (_folderNodes.isEmpty) return;
    _folderNodes[_selected.clamp(0, _folderNodes.length - 1)].requestFocus();
  }

  /// 重新整理目前收藏夾的影片
  void reload() {
    if (_folders.isEmpty) {
      setState(() => _loadingFolders = true);
      _loadFolders();
    } else {
      _loadVideos(reset: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  @override
  void dispose() {
    for (final n in _folderNodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFolders() async {
    final folders = await BilibiliApi.getFavFolders();
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _folderNodes = List.generate(folders.length, (_) => FocusNode());
      _loadingFolders = false;
    });
    if (folders.isNotEmpty) _loadVideos(reset: true);
  }

  void _selectFolder(int i) {
    if (i == _selected) return;
    setState(() => _selected = i);
    _loadVideos(reset: true);
  }

  Future<void> _loadVideos({required bool reset}) async {
    if (_folders.isEmpty) return;
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
    if (_loadingFolders) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_folders.isEmpty) {
      return const Center(
        child: Text(
          '還沒有收藏夾',
          style: TextStyle(color: Colors.white70, fontSize: 20),
        ),
      );
    }

    Widget content;
    if (_loadingVideos) {
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
              labels: _folders
                  .map((f) => '${f.title} (${f.mediaCount})')
                  .toList(),
              focusNodes: _folderNodes,
              selectedIndex: _selected,
              fontSize: 16,
              onSelect: _selectFolder,
              onMoveLeftAtFirst: () => widget.sidebarFocusNode?.requestFocus(),
              onMoveUp: widget.onMoveUpToTabs,
              onMoveDown: () => _gridKey.currentState?.focusFirst(),
            ),
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}
