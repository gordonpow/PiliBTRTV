import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import '../models/video.dart';
import '../services/api/fav_api.dart';
import '../services/api/interaction_api.dart';
import '../services/auth_service.dart';
import '../utils/fav_utils.dart';
import '../utils/zh_toast.dart';

const Color _pink = Color(0xFFfb7299);
const Color _dialogBg = Color(0xFF2A2A2A);

void _toast(String msg) => showZhToast(msg: msg);

/// 確認鍵（只認 KeyDown，避免長按殘留的重複事件誤觸）
bool _isSelect(KeyEvent e) =>
    e is KeyDownEvent &&
    (e.logicalKey == LogicalKeyboardKey.select ||
        e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter ||
        e.logicalKey == LogicalKeyboardKey.gameButtonA);

// ───────────────────────── 對話框元件 ─────────────────────────

/// 可用遙控器操作的對話框按鈕
class TvDialogButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool autofocus;
  final bool primary;
  final FocusNode? focusNode;
  final VoidCallback onPressed;

  const TvDialogButton({
    super.key,
    this.focusNode,
    required this.label,
    required this.onPressed,
    this.icon,
    this.autofocus = false,
    this.primary = false,
  });

  @override
  State<TvDialogButton> createState() => _TvDialogButtonState();
}

class _TvDialogButtonState extends State<TvDialogButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (_isSelect(event)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: _focused
                ? _pink
                : (widget.primary
                      ? _pink.withValues(alpha: 0.25)
                      : Colors.white12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: Colors.white, size: 22),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: _focused ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── 影片選項 ─────────────────────────

/// 長按影片卡片的「影片選項」：收藏、稍後再看、（移除）、取消。
/// [removeLabel]、[onRemove] 都有值時多一顆移除按鈕；回傳 true 表示已成功移除。
Future<bool> showVideoActionMenu(
  BuildContext context,
  Video video, {
  String? removeLabel,
  String? removedMessage,
  Future<String?> Function()? onRemove,
}) async {
  final canRemove = removeLabel != null && onRemove != null;
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: _dialogBg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '影片選項',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TvDialogButton(
                label: '收藏',
                icon: Icons.star_border,
                autofocus: true,
                onPressed: () => Navigator.of(ctx).pop('fav'),
              ),
              const SizedBox(height: 10),
              TvDialogButton(
                label: '稍後再看',
                icon: Icons.watch_later_outlined,
                onPressed: () => Navigator.of(ctx).pop('later'),
              ),
              if (canRemove) ...[
                const SizedBox(height: 10),
                TvDialogButton(
                  label: removeLabel,
                  icon: Icons.delete_outline,
                  onPressed: () => Navigator.of(ctx).pop('remove'),
                ),
              ],
              const SizedBox(height: 10),
              TvDialogButton(
                label: '取消',
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (!context.mounted || action == null) return false;
  if (action == 'fav') {
    await favoriteVideoFlow(context, video.resolvedAid);
  } else if (action == 'later') {
    await watchLaterFlow(context, video);
  } else if (action == 'remove' && canRemove) {
    final err = await onRemove();
    _toast(err ?? removedMessage ?? '已移除');
    return err == null;
  }
  return false;
}

// ───────────────────────── 收藏夾選擇 ─────────────────────────

/// 收藏夾勾選對話框。回傳最後勾選的收藏夾 id 集合；取消回傳 null。
Future<Set<int>?> showFavFolderPicker(
  BuildContext context, {
  required List<FavFolderState> folders,
  bool preselect = true,
  String title = '選擇收藏夾',
}) {
  return showDialog<Set<int>>(
    context: context,
    builder: (ctx) => _FavFolderDialog(
      folders: folders,
      title: title,
      initial: preselect
          ? {
              for (final f in folders)
                if (f.faved) f.id,
            }
          : <int>{},
    ),
  );
}

class _FavFolderDialog extends StatefulWidget {
  final List<FavFolderState> folders;
  final String title;
  final Set<int> initial;

  const _FavFolderDialog({
    required this.folders,
    required this.title,
    required this.initial,
  });

  @override
  State<_FavFolderDialog> createState() => _FavFolderDialogState();
}

class _FavFolderDialogState extends State<_FavFolderDialog> {
  late final Set<int> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _dialogBg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < widget.folders.length; i++)
                      _FolderRow(
                        folder: widget.folders[i],
                        checked: _selected.contains(widget.folders[i].id),
                        autofocus: i == 0,
                        onToggle: () => setState(() {
                          final id = widget.folders[i].id;
                          if (!_selected.remove(id)) _selected.add(id);
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TvDialogButton(
                    label: '確定',
                    primary: true,
                    onPressed: () => Navigator.of(context).pop(_selected),
                  ),
                  const SizedBox(width: 12),
                  TvDialogButton(
                    label: '取消',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderRow extends StatefulWidget {
  final FavFolderState folder;
  final bool checked;
  final bool autofocus;
  final VoidCallback onToggle;

  const _FolderRow({
    required this.folder,
    required this.checked,
    required this.autofocus,
    required this.onToggle,
  });

  @override
  State<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<_FolderRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 150),
          );
        }
      },
      onKeyEvent: (node, event) {
        if (_isSelect(event)) {
          widget.onToggle();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onToggle,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _focused ? _pink.withValues(alpha: 0.3) : Colors.white10,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.checked
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                color: widget.checked ? _pink : Colors.white70,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.folder.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
              Text(
                '${widget.folder.mediaCount}',
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── 流程 ─────────────────────────

bool _requireLogin() {
  if (AuthService.isLoggedIn) return true;
  _toast('請先登入');
  return false;
}

/// 單支影片：選收藏夾並依差異加入／移出（AC-2、AC-3）
Future<void> favoriteVideoFlow(BuildContext context, int? aid) async {
  if (!_requireLogin()) return;
  if (aid == null || aid <= 0) {
    _toast('無法取得影片資訊');
    return;
  }
  final folders = await InteractionApi.getFavFoldersForVideo(aid);
  if (folders == null) {
    _toast('讀取收藏夾失敗');
    return;
  }
  if (folders.isEmpty) {
    _toast('尚無收藏夾');
    return;
  }
  if (!context.mounted) return;
  final selected = await showFavFolderPicker(context, folders: folders);
  if (selected == null) return;
  final original = {
    for (final f in folders)
      if (f.faved) f.id,
  };
  final diff = diffFavFolders(original, selected);
  if (diff.add.isEmpty && diff.del.isEmpty) return;
  final err = await InteractionApi.dealFavorite(
    aid: aid,
    addIds: diff.add,
    delIds: diff.del,
  );
  if (err != null) {
    _toast(err);
  } else if (selected.isEmpty) {
    _toast('已取消收藏');
  } else {
    _toast('已收藏到 ${selected.length} 個收藏夾');
  }
}

/// 單支影片加入稍後再看（AC-4）
Future<void> watchLaterFlow(BuildContext context, Video video) async {
  if (!_requireLogin()) return;
  final aid = video.resolvedAid;
  if (aid <= 0) {
    _toast('無法取得影片資訊');
    return;
  }
  // 已存在時 API 的回應不一定有錯誤碼，先查清單判斷
  final existing = await FavApi.getWatchLater();
  if (existing.any((v) => v.bvid == video.bvid)) {
    _toast('已在稍後再看');
    return;
  }
  final err = await InteractionApi.addWatchLater(aid);
  _toast(err ?? '已加入稍後再看');
}

/// 批次加入收藏（AC-7）。回傳 (成功, 失敗)；使用者取消回傳 null。
Future<({int ok, int fail})?> batchFavoriteFlow(
  BuildContext context,
  List<Video> videos,
) async {
  if (!_requireLogin()) return null;
  final folders = await InteractionApi.getFavFoldersForVideo(0);
  if (folders == null) {
    _toast('讀取收藏夾失敗');
    return null;
  }
  if (folders.isEmpty) {
    _toast('尚無收藏夾');
    return null;
  }
  if (!context.mounted) return null;
  final selected = await showFavFolderPicker(
    context,
    folders: folders,
    preselect: false,
    title: '加入 ${videos.length} 部影片到收藏夾',
  );
  if (selected == null) return null;
  if (selected.isEmpty) {
    _toast('未選擇收藏夾');
    return null;
  }
  var ok = 0;
  var fail = 0;
  for (final v in videos) {
    final aid = v.resolvedAid;
    if (v.isPgc || v.isLive || aid <= 0) {
      fail++;
      continue;
    }
    final err = await InteractionApi.dealFavorite(
      aid: aid,
      addIds: selected.toList()..sort(),
    );
    err == null ? ok++ : fail++;
  }
  _toast(fail == 0 ? '已收藏 $ok 部' : '已收藏 $ok 部，失敗 $fail 部');
  return (ok: ok, fail: fail);
}

/// 批次加入稍後再看（AC-7）。回傳 (成功, 失敗)；未登入回傳 null。
Future<({int ok, int fail})?> batchWatchLaterFlow(List<Video> videos) async {
  if (!_requireLogin()) return null;
  var ok = 0;
  var fail = 0;
  for (final v in videos) {
    final aid = v.resolvedAid;
    if (v.isPgc || v.isLive || aid <= 0) {
      fail++;
      continue;
    }
    final err = await InteractionApi.addWatchLater(aid);
    err == null ? ok++ : fail++;
  }
  _toast(fail == 0 ? '已加入稍後再看 $ok 部' : '已加入稍後再看 $ok 部，失敗 $fail 部');
  return (ok: ok, fail: fail);
}
