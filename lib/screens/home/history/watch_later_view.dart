import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../../models/video.dart';
import '../../../services/api/interaction_api.dart';
import '../../../services/bilibili_api.dart';
import '../../../widgets/video_action_dialogs.dart';
import 'video_grid.dart';

/// 稍後再看分頁內容（一次載入）
class WatchLaterView extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onMoveUpFromFirstRow;

  const WatchLaterView({
    super.key,
    this.sidebarFocusNode,
    this.onMoveUpFromFirstRow,
  });

  @override
  State<WatchLaterView> createState() => WatchLaterViewState();
}

class WatchLaterViewState extends State<WatchLaterView> {
  final GlobalKey<HistoryVideoGridState> _gridKey = GlobalKey();
  List<Video> _videos = [];
  bool _isLoading = true;

  /// 聚焦第一張卡片
  void focusFirst() => _gridKey.currentState?.focusFirst();

  /// 重新整理稍後再看清單
  void reload() {
    setState(() => _isLoading = true);
    _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await BilibiliApi.getWatchLater();
    if (!mounted) return;
    setState(() {
      _videos = list;
      _isLoading = false;
    });
  }

  Future<void> _onLongPress(Video video, int index) async {
    final removed = await showVideoActionMenu(
      context,
      video,
      removeLabel: '從稍後再看移除',
      removedMessage: '已從稍後再看移除',
      onRemove: () async {
        final aid = video.resolvedAid;
        if (aid <= 0) return '無法取得影片資訊';
        return InteractionApi.removeWatchLater(aid);
      },
    );
    if (!removed || !mounted) return;
    setState(() => _videos = _videos.where((v) => v != video).toList());
    // 長按結束時 BaseTvCard 會先還原長按前的焦點（microtask）；
    // 這裡等下一個 frame 之後才移焦點，確保最後生效的是移除後的目標
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_videos.isEmpty) {
        widget.onMoveUpFromFirstRow?.call();
      } else {
        _gridKey.currentState?.focusIndex(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_videos.isEmpty) {
      return const Center(
        child: Text(
          '稍後再看清單是空的',
          style: TextStyle(color: Colors.white70, fontSize: 20),
        ),
      );
    }
    return HistoryVideoGrid(
      key: _gridKey,
      videos: _videos,
      onLongPressVideo: _onLongPress,
      sidebarFocusNode: widget.sidebarFocusNode,
      onMoveUpFromFirstRow: widget.onMoveUpFromFirstRow,
    );
  }
}
