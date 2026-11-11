import 'dart:io';

import 'package:bili_tv_app/models/video.dart';
import 'package:bili_tv_app/services/api/interaction_api.dart';
import 'package:bili_tv_app/services/local_fav_import.dart';
import 'package:bili_tv_app/services/local_favorites_service.dart';
import 'package:flutter_test/flutter_test.dart';

Video _v(String bvid, int aid) =>
    Video(bvid: bvid, aid: aid, title: bvid, pic: '', ownerName: 'up');

void main() {
  late Directory dir;
  late LocalFavoritesService svc;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('local_fav_import');
    svc = LocalFavoritesService(directoryProvider: () async => dir);
    await svc.ensureLoaded();
    final extra = svc.createFolder('額外')!;
    svc.setVideoFolders(_v('BV1', 1), {1, extra.id}); // 多夾仍只算一部
    svc.setVideoFolders(_v('BV2', 2), {1});
    svc.setVideoFolders(_v('BV3', 3), {extra.id});
  });
  tearDown(() async {
    await svc.flush();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows 偶爾仍持有剛寫完的檔案；暫存目錄留給系統清理
    }
  });

  FavFolderState folder(int id, {bool faved = false, bool def = false}) =>
      FavFolderState(
        id: id,
        title: 'f$id',
        mediaCount: 0,
        faved: faved,
        isDefault: def,
      );

  test('全部成功：逐部加入預設夾、已存在的略過，本機清空', () async {
    final added = <int>[];
    final r = await importLocalFavorites(
      svc,
      getFolders: (aid) async => [folder(10, faved: aid == 2, def: true)],
      addToFolder: (aid, fid) async {
        expect(fid, 10);
        added.add(aid);
        return null;
      },
    );
    expect(r, (ok: 3, skipped: 1, failed: 0));
    expect(added..sort(), [1, 3]);
    expect(svc.totalVideos, 0);
  });

  test('部分失敗：失敗的保留在本機', () async {
    final r = await importLocalFavorites(
      svc,
      getFolders: (aid) async => [folder(10, def: true)],
      addToFolder: (aid, fid) async => aid == 2 ? '網路錯誤' : null,
    );
    expect(r, (ok: 2, skipped: 0, failed: 1));
    expect(svc.distinctEntries().map((e) => e.bvid), ['BV2']);
  });

  test('查詢單部狀態失敗視為失敗並保留', () async {
    final r = await importLocalFavorites(
      svc,
      getFolders: (aid) async => aid == 3 ? null : [folder(10, def: true)],
      addToFolder: (aid, fid) async => null,
    );
    expect(r.failed, 1);
    expect(svc.distinctEntries().map((e) => e.bvid), ['BV3']);
  });

  test('取不到預設收藏夾：全部保留', () async {
    final r = await importLocalFavorites(
      svc,
      getFolders: (aid) async => aid == 0 ? null : [],
      addToFolder: (aid, fid) async => null,
    );
    expect(r, (ok: 0, skipped: 0, failed: 3));
    expect(svc.totalVideos, 3);
  });

  test('aid 未知（bvid 非合法 BV 號）的項目算失敗並保留；本機為空時不呼叫 API', () async {
    svc.setVideoFolders(_v('BV4', 0), {1});
    final r = await importLocalFavorites(
      svc,
      getFolders: (aid) async => [folder(10, def: true)],
      addToFolder: (aid, fid) async => null,
    );
    expect(r.failed, 1);
    expect(svc.distinctEntries().single.bvid, 'BV4');

    svc.removeVideo('BV4');
    var called = false;
    final r2 = await importLocalFavorites(
      svc,
      getFolders: (aid) async {
        called = true;
        return [];
      },
      addToFolder: (aid, fid) async => null,
    );
    expect(r2, (ok: 0, skipped: 0, failed: 0));
    expect(called, isFalse);
  });

  test('aid 為 0 時用 bvid 重算後加入', () async {
    // BV17x411w7KC 的 aid 為 170001
    svc.setVideoFolders(_v('BV17x411w7KC', 0), {1});
    final added = <int>[];
    final r = await importLocalFavorites(
      svc,
      getFolders: (aid) async => [folder(10, def: true)],
      addToFolder: (aid, fid) async {
        added.add(aid);
        return null;
      },
    );
    expect(added, contains(170001));
    expect(r, (ok: 4, skipped: 0, failed: 0));
    expect(svc.distinctEntries().any((e) => e.bvid == 'BV17x411w7KC'), isFalse);
  });
}
