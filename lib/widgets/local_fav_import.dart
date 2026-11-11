import 'package:flutter/widgets.dart';

import '../services/api/interaction_api.dart';
import '../services/auth_service.dart';
import '../services/local_fav_import.dart';
import '../services/local_favorites_service.dart';
import '../utils/zh_toast.dart';
import 'video_action_dialogs.dart';

/// 把本機收藏加入帳號預設收藏夾並 toast 結果。回傳結果；未登入或本機沒有資料回傳 null。
Future<LocalFavImportResult?> runLocalFavImport() async {
  if (!AuthService.isLoggedIn) {
    showZhToast(msg: '請先登入');
    return null;
  }
  final svc = LocalFavoritesService.instance;
  await svc.ensureLoaded();
  if (svc.totalVideos == 0) return null;
  final r = await importLocalFavorites(
    svc,
    getFolders: InteractionApi.getFavFoldersForVideo,
    addToFolder: (aid, folderId) =>
        InteractionApi.dealFavorite(aid: aid, addIds: [folderId]),
  );
  showZhToast(
    msg: r.failed == 0
        ? '已加入 ${r.ok} 部到帳號預設收藏夾'
        : '已加入 ${r.ok} 部，失敗 ${r.failed} 部（保留在本機）',
  );
  // 有成功加入就視為使用者願意匯入，之後新增的本機收藏可再次詢問
  if (r.ok > 0) {
    await svc.clearImportDeclined();
    svc.importDone.value++;
  }
  return r;
}

/// 登入成功後呼叫：本機有收藏且使用者沒選過「否」時詢問是否匯入
Future<void> maybePromptLocalFavImport(BuildContext context) async {
  final svc = LocalFavoritesService.instance;
  await svc.ensureLoaded();
  if (!await svc.shouldPromptImport()) return;
  final n = svc.totalVideos;
  if (!context.mounted) return;
  final yes = await showConfirmDialog(
    context,
    title: '要把 $n 部本機收藏加入帳號的預設收藏夾嗎？',
    message:
        '會加入帳號的預設收藏夾，本機收藏夾的分類不會保留。'
        '選「否」會保留本機收藏，有新增影片後下次登入才會再詢問；也可到收藏分頁手動匯入。',
    confirmLabel: '是',
    cancelLabel: '否',
    autofocusConfirm: true,
  );
  if (yes == true) {
    await runLocalFavImport();
  } else if (yes == false) {
    await svc.declineImport();
  }
}
