import '../utils/fav_utils.dart';
import 'api/interaction_api.dart' show FavFolderState;
import 'local_favorites_service.dart';

/// 本機收藏匯入結果。[ok] 含 [skipped]（帳號預設夾已有，不重複加入）。
typedef LocalFavImportResult = ({int ok, int skipped, int failed});

/// 把本機收藏逐部加入帳號預設收藏夾。成功（含略過）的從本機移除，失敗保留。
///
/// [getFolders] 取得帳號收藏夾（aid > 0 時 faved 表示該影片已在其中），
/// [addToFolder] 把影片加入指定收藏夾，回傳 null 表示成功，否則為錯誤訊息。
Future<LocalFavImportResult> importLocalFavorites(
  LocalFavoritesService service, {
  required Future<List<FavFolderState>?> Function(int aid) getFolders,
  required Future<String?> Function(int aid, int folderId) addToFolder,
}) async {
  await service.ensureLoaded();
  final items = service.distinctEntries();
  if (items.isEmpty) return (ok: 0, skipped: 0, failed: 0);

  final folders = await getFolders(0);
  FavFolderState? def;
  for (final f in folders ?? const <FavFolderState>[]) {
    if (f.isDefault) {
      def = f;
      break;
    }
  }
  if (def == null) return (ok: 0, skipped: 0, failed: items.length);

  var ok = 0;
  var skipped = 0;
  var failed = 0;
  for (final e in items) {
    // 舊資料或番劇可能沒有 aid：先用 bvid 重算，仍失敗才算失敗
    final aid = e.aid > 0 ? e.aid : bvidToAid(e.bvid);
    if (aid <= 0) {
      failed++;
      continue;
    }
    final state = await getFolders(aid);
    if (state == null) {
      failed++;
      continue;
    }
    final inDefault = state.any((f) => f.id == def!.id && f.faved);
    if (inDefault) {
      skipped++;
      ok++;
      service.removeVideo(e.bvid);
      continue;
    }
    final err = await addToFolder(aid, def.id);
    if (err == null) {
      ok++;
      service.removeVideo(e.bvid);
    } else {
      failed++;
    }
  }
  await service.flush();
  return (ok: ok, skipped: skipped, failed: failed);
}
