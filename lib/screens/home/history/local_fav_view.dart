import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import '../../../models/video.dart';
import '../../../services/local_favorites_service.dart';
import '../../../utils/zh_toast.dart';
import '../../../widgets/local_fav_import.dart';
import '../../../widgets/tv_tab_bar.dart';
import '../../../widgets/video_action_dialogs.dart';
import 'video_grid.dart';

const Color _pink = Color(0xFFfb7299);

/// 本機收藏分頁內容：收藏夾列 + 管理按鈕列 + 影片格。
/// 未登入時是收藏分頁本體；已登入時以 [embedded] 嵌在「本機收藏」分頁，多一顆「匯入帳號」。
class LocalFavView extends StatefulWidget {
  final FocusNode? sidebarFocusNode;

  /// 收藏夾列按上鍵時回到上方分頁列
  final VoidCallback? onMoveUpToTabs;

  /// 已登入時嵌在帳號收藏下方，顯示「匯入帳號」按鈕
  final bool embedded;

  const LocalFavView({
    super.key,
    this.sidebarFocusNode,
    this.onMoveUpToTabs,
    this.embedded = false,
  });

  @override
  State<LocalFavView> createState() => LocalFavViewState();
}

class LocalFavViewState extends State<LocalFavView> {
  final _svc = LocalFavoritesService.instance;
  final GlobalKey<HistoryVideoGridState> _gridKey = GlobalKey();
  final List<FocusNode> _folderNodes = [];
  final List<FocusNode> _actionNodes = List.generate(4, (_) => FocusNode());
  bool _loaded = false;
  int _selected = 0;

  /// 聚焦收藏夾列（由上方分頁列按下鍵進入）
  void focusFolders() {
    if (_folderNodes.isEmpty) return;
    _folderNodes[_selected.clamp(0, _folderNodes.length - 1)].requestFocus();
  }

  /// 聚焦管理按鈕列（由上方分頁列按下鍵進入）
  void focusActions() => _actionNodes[0].requestFocus();

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChanged);
    _svc.ensureLoaded().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _svc.removeListener(_onChanged);
    for (final n in [..._folderNodes, ..._actionNodes]) {
      n.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _syncNodes(int count) {
    while (_folderNodes.length < count) {
      _folderNodes.add(FocusNode());
    }
    while (_folderNodes.length > count) {
      final n = _folderNodes.removeLast();
      // 等焦點離開後再釋放，避免 build 期間 dispose 持有焦點的節點
      WidgetsBinding.instance.addPostFrameCallback((_) => n.dispose());
    }
    if (_selected >= count) _selected = count > 0 ? count - 1 : 0;
  }

  Future<void> _create() async {
    final f = await createLocalFavFolderFlow(context);
    if (f == null || !mounted) return;
    final i = _svc.folders.indexWhere((x) => x.id == f.id);
    if (i >= 0) setState(() => _selected = i);
  }

  Future<void> _rename() async {
    final folders = _svc.folders;
    if (folders.isEmpty) return;
    final folder = folders[_selected.clamp(0, folders.length - 1)];
    final name = await showNameInputDialog(
      context,
      title: '重新命名收藏夾',
      initial: folder.name,
    );
    if (name == null) return;
    if (!_svc.renameFolder(folder.id, name)) showZhToast(msg: '名稱不可為空');
  }

  Future<void> _delete() async {
    final folders = _svc.folders;
    if (folders.isEmpty) return;
    final folder = folders[_selected.clamp(0, folders.length - 1)];
    if (folder.id == LocalFavoritesService.defaultFolderId) {
      showZhToast(msg: '預設收藏夾不可刪除');
      return;
    }
    final n = _svc.countIn(folder.id);
    final ok = await showConfirmDialog(
      context,
      title: '刪除收藏夾「${folder.name}」？',
      message: n > 0 ? '其中 $n 部影片也會從本機收藏移除。' : null,
      confirmLabel: '刪除',
    );
    if (ok != true || !mounted) return;
    _svc.deleteFolder(folder.id);
    setState(() => _selected = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusFolders();
    });
  }

  Future<void> _import() async {
    // 完成後由 LocalFavoritesService.importDone 通知上層重新載入
    await runLocalFavImport();
  }

  Future<void> _onLongPress(Video video, int index) async {
    final folders = _svc.folders;
    if (folders.isEmpty) return;
    final folder = folders[_selected.clamp(0, folders.length - 1)];
    await showVideoActionMenu(
      context,
      video,
      removeLabel: '從此收藏夾移除',
      removedMessage: '已從收藏夾移除',
      onRemove: () async {
        _svc.removeFromFolder(folder.id, video.bvid);
        return null;
      },
    );
    if (!mounted) return;
    // 選單內無論是「從此收藏夾移除」或取消勾選本夾，卡片都可能消失；
    // 長按結束時 BaseTvCard 會先還原焦點，等下一個 frame 再移到相鄰卡片（沒有就到按鈕列）
    final gone = !_svc.entriesIn(folder.id).any((e) => e.bvid == video.bvid);
    if (!gone) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_svc.countIn(folder.id) == 0) {
        _actionNodes[0].requestFocus();
      } else {
        _gridKey.currentState?.focusIndex(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final folders = _svc.folders;
    _syncNodes(folders.length);
    final folder = folders[_selected.clamp(0, folders.length - 1)];
    final videos = [for (final e in _svc.entriesIn(folder.id)) e.toVideo()];

    final Widget content = videos.isEmpty
        ? const Center(
            child: Text(
              '這個收藏夾是空的',
              style: TextStyle(color: Colors.white70, fontSize: 20),
            ),
          )
        : HistoryVideoGrid(
            key: _gridKey,
            videos: videos,
            onLongPressVideo: _onLongPress,
            sidebarFocusNode: widget.sidebarFocusNode,
            onMoveUpFromFirstRow: () => _actionNodes[0].requestFocus(),
          );

    final actions = <_Action>[
      _Action('新增收藏夾', Icons.add, _create),
      _Action('重新命名', Icons.edit_outlined, _rename),
      _Action('刪除', Icons.delete_outline, _delete),
      if (widget.embedded)
        _Action('匯入帳號', Icons.cloud_upload_outlined, _import),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TvTabBar(
              labels: [
                for (final f in folders) '${f.name} (${_svc.countIn(f.id)})',
              ],
              focusNodes: _folderNodes,
              selectedIndex: _selected.clamp(0, folders.length - 1),
              fontSize: 16,
              onSelect: (i) => setState(() => _selected = i),
              onMoveLeftAtFirst: () => widget.sidebarFocusNode?.requestFocus(),
              onMoveUp: widget.onMoveUpToTabs,
              onMoveDown: () => _actionNodes[0].requestFocus(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 8, 30, 0),
          child: Row(
            children: [
              for (var i = 0; i < actions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _ActionButton(
                    focusNode: _actionNodes[i],
                    action: actions[i],
                    onLeft: i == 0
                        ? () => widget.sidebarFocusNode?.requestFocus()
                        : () => _actionNodes[i - 1].requestFocus(),
                    onRight: i + 1 < actions.length
                        ? () => _actionNodes[i + 1].requestFocus()
                        : null,
                    onUp: focusFolders,
                    onDown: videos.isEmpty
                        ? null
                        : () => _gridKey.currentState?.focusFirst(),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}

class _Action {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const _Action(this.label, this.icon, this.onPressed);
}

class _ActionButton extends StatefulWidget {
  final FocusNode focusNode;
  final _Action action;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  const _ActionButton({
    required this.focusNode,
    required this.action,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.gameButtonA) {
          widget.action.onPressed();
          return KeyEventResult.handled;
        }
        VoidCallback? cb;
        if (key == LogicalKeyboardKey.arrowLeft) {
          cb = widget.onLeft;
        } else if (key == LogicalKeyboardKey.arrowRight) {
          cb = widget.onRight;
        } else if (key == LogicalKeyboardKey.arrowUp) {
          cb = widget.onUp;
        } else if (key == LogicalKeyboardKey.arrowDown) {
          cb = widget.onDown;
        } else {
          return KeyEventResult.ignored;
        }
        cb?.call();
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        onTap: widget.action.onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _focused ? _pink : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? Colors.white : Colors.white24,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.action.icon,
                size: 18,
                color: _focused ? Colors.white : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                widget.action.label,
                style: TextStyle(
                  color: _focused ? Colors.white : Colors.grey,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
