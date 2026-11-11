import 'dart:convert';
import 'dart:io';

import 'package:bili_tv_app/models/video.dart';
import 'package:bili_tv_app/services/local_favorites_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Video _v(String bvid, {int aid = 0, String title = 't'}) => Video(
  bvid: bvid,
  aid: aid,
  title: title,
  pic: 'http://p/$bvid.jpg',
  ownerName: 'up',
  duration: 61,
);

void main() {
  late Directory dir;
  var clock = 1000;
  final made = <LocalFavoritesService>[];

  LocalFavoritesService make() {
    final s = LocalFavoritesService(
      directoryProvider: () async => dir,
      now: () => clock++,
    );
    made.add(s);
    return s;
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('local_fav_test');
    clock = 1000;
  });
  tearDown(() async {
    for (final s in made) {
      await s.flush();
    }
    made.clear();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows 偶爾仍持有剛寫完的檔案；暫存目錄留給系統清理
    }
  });

  test('預設夾存在、可重新命名、不可刪除', () async {
    final s = make();
    await s.ensureLoaded();
    expect(s.folders.single.id, LocalFavoritesService.defaultFolderId);
    expect(s.folders.single.name, '本機收藏');
    expect(
      s.renameFolder(LocalFavoritesService.defaultFolderId, ' 我的 '),
      isTrue,
    );
    expect(s.folders.single.name, '我的');
    expect(s.deleteFolder(LocalFavoritesService.defaultFolderId), isFalse);
    expect(s.folders, hasLength(1));
    expect(
      s.renameFolder(LocalFavoritesService.defaultFolderId, '  '),
      isFalse,
    );
  });

  test('新增、重新命名、刪除收藏夾（含其中影片）', () async {
    final s = make();
    await s.ensureLoaded();
    expect(s.createFolder('   '), isNull);
    final f = s.createFolder('音樂')!;
    expect(s.folders.map((x) => x.name), ['本機收藏', '音樂']);
    s.setVideoFolders(_v('BV1aaaaaaaaa', aid: 1), {f.id});
    expect(s.countIn(f.id), 1);
    expect(s.renameFolder(f.id, '好歌'), isTrue);
    expect(s.folderById(f.id)!.name, '好歌');
    expect(s.deleteFolder(f.id), isTrue);
    expect(s.isFavorited('BV1aaaaaaaaa'), isFalse);
    expect(s.deleteFolder(999), isFalse);
  });

  test('多夾收藏、差異套用與移除', () async {
    final s = make();
    await s.ensureLoaded();
    final a = s.createFolder('A')!;
    final v = _v('BV1bbbbbbbbb', aid: 7);
    s.setVideoFolders(v, {1, a.id});
    expect(s.foldersOf(v.bvid), {1, a.id});
    expect(s.isFavoritedAid(7), isTrue);
    expect(s.totalVideos, 1);
    expect(s.folderStates(v.bvid).where((f) => f.faved).length, 2);

    s.setVideoFolders(v, {a.id});
    expect(s.foldersOf(v.bvid), {a.id});
    s.setVideoFolders(_v('BV1ccccccccc', aid: 8), {a.id});
    expect(s.entriesIn(a.id).map((e) => e.bvid), [
      'BV1ccccccccc',
      'BV1bbbbbbbbb',
    ]);
    expect(s.totalVideos, 2);

    s.removeFromFolder(a.id, v.bvid);
    expect(s.isFavorited(v.bvid), isFalse);
    s.setVideoFolders(v, {1, a.id});
    s.removeVideo(v.bvid);
    expect(s.isFavorited(v.bvid), isFalse);
    expect(s.distinctEntries().map((e) => e.bvid), ['BV1ccccccccc']);
    // 不存在的資料夾 id 會被忽略
    s.setVideoFolders(v, {12345});
    expect(s.isFavorited(v.bvid), isFalse);
  });

  test('影片資訊欄位完整並可轉回 Video', () async {
    final s = make();
    await s.ensureLoaded();
    s.setVideoFolders(_v('BV1ddddddddd', aid: 9, title: '標題'), {1});
    final e = s.entriesIn(1).single;
    expect(e.addedAt, greaterThan(0));
    final v = e.toVideo();
    expect(
      [v.bvid, v.aid, v.title, v.pic, v.ownerName, v.duration],
      ['BV1ddddddddd', 9, '標題', 'http://p/BV1ddddddddd.jpg', 'up', 61],
    );
  });

  test('持久化：重新載入後資料保留，且新建夾 id 不重複', () async {
    final s = make();
    await s.ensureLoaded();
    final f = s.createFolder('X')!;
    s.setVideoFolders(_v('BV1eeeeeeeee', aid: 3), {f.id});
    await s.flush();
    expect(File('${dir.path}/local_favorites.json.tmp').existsSync(), isFalse);

    final s2 = make();
    await s2.ensureLoaded();
    expect(s2.folders.map((x) => x.name), ['本機收藏', 'X']);
    expect(s2.entriesIn(f.id).single.bvid, 'BV1eeeeeeeee');
    final g = s2.createFolder('Y')!;
    expect(g.id, isNot(f.id));
  });

  test('損毀檔：改名 .bad、從空資料開始且可再寫入', () async {
    final file = File('${dir.path}/local_favorites.json');
    file.writeAsStringSync('{not json');
    final s = make();
    await s.ensureLoaded();
    expect(s.folders.single.id, LocalFavoritesService.defaultFolderId);
    expect(s.totalVideos, 0);
    final bad = dir.listSync().whereType<File>().where(
      (f) => RegExp(r'local_favorites\.json\.bad-\d{14}$').hasMatch(f.path),
    );
    expect(bad, hasLength(1));
    expect(bad.single.readAsStringSync(), '{not json');
    s.setVideoFolders(_v('BV1fffffffff', aid: 4), {1});
    await s.flush();
    final data = jsonDecode(file.readAsStringSync()) as Map;
    expect((data['entries'] as List), hasLength(1));
  });

  test('型別錯誤的檔案視同損毀；壞掉的單筆略過', () async {
    final file = File('${dir.path}/local_favorites.json');
    file.writeAsStringSync('[1,2]');
    var s = make();
    await s.ensureLoaded();
    expect(s.totalVideos, 0);

    file.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'folders': [
          {'id': 1, 'name': '本機收藏', 'createdAt': 1},
        ],
        'entries': [
          {'folderId': 1, 'bvid': 'BV1ggggggggg', 'aid': 5},
          {'folderId': 1},
          {'folderId': 77, 'bvid': 'BV1hhhhhhhhh'},
          'bad',
        ],
      }),
    );
    s = make();
    await s.ensureLoaded();
    expect(s.distinctEntries().map((e) => e.bvid), ['BV1ggggggggg']);
  });

  test('IO 錯誤（非 JSON 損毀）：不搬檔、不覆蓋，改動不寫回', () async {
    // 非法 UTF-8：readAsString 丟 FileSystemException（不是 FormatException）
    final file = File('${dir.path}/local_favorites.json');
    final bytes = [0xff, 0xfe, 0xfd];
    file.writeAsBytesSync(bytes);
    final s = make();
    await s.ensureLoaded();
    expect(s.totalVideos, 0);
    s.setVideoFolders(_v('BV1iiiiiiiii', aid: 6), {1});
    await s.flush();
    expect(file.readAsBytesSync(), bytes);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
    expect(dir.listSync().any((e) => e.path.contains('.bad')), isFalse);
  });

  test('收藏判斷以 bvid 為主：aid 未知或不同也能判斷', () async {
    final s = make();
    await s.ensureLoaded();
    s.setVideoFolders(_v('BV1jjjjjjjjj'), {1}); // 無合法 aid
    expect(s.isFavorited('BV1jjjjjjjjj'), isTrue);
    expect(s.isFavorited(''), isFalse);
    expect(s.isFavorited('BV1kkkkkkkkk'), isFalse);
    expect(s.isFavoritedAid(0), isFalse);
  });

  test('番劇／分 P 來源欄位持久化；舊資料缺欄位時為 0', () async {
    final s = make();
    await s.ensureLoaded();
    s.setVideoFolders(
      Video(
        bvid: 'BV1lllllllll',
        title: 'a',
        pic: '',
        aid: 2,
        cid: 55,
        epId: 66,
        seasonId: 77,
      ),
      {1},
    );
    await s.flush();
    final s2 = make();
    await s2.ensureLoaded();
    final v = s2.entriesIn(1).single.toVideo();
    expect([v.cid, v.epId, v.seasonId, v.isPgc], [55, 66, 77, true]);

    File('${dir.path}/local_favorites.json').writeAsStringSync(
      jsonEncode({
        'folders': [
          {'id': 1, 'name': 'x', 'createdAt': 1},
        ],
        'entries': [
          {'folderId': 1, 'bvid': 'BV1mmmmmmmmm', 'addedAt': 3},
        ],
      }),
    );
    final s3 = make();
    await s3.ensureLoaded();
    final o = s3.entriesIn(1).single;
    expect([o.cid, o.epId, o.seasonId, o.isPgc], [0, 0, 0, false]);
  });

  group('匯入提示旗標', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('無影片不問；有影片問；選否後不再問；之後新增影片再問', () async {
      final s = make();
      await s.ensureLoaded();
      expect(await s.shouldPromptImport(), isFalse);
      s.setVideoFolders(_v('BV1nnnnnnnnn', aid: 1), {1});
      expect(await s.shouldPromptImport(), isTrue);
      await s.declineImport();
      expect(await s.shouldPromptImport(), isFalse);
      s.setVideoFolders(_v('BV1ooooooooo', aid: 2), {1});
      expect(await s.shouldPromptImport(), isTrue);
      await s.declineImport();
      expect(await s.shouldPromptImport(), isFalse);
      // 只移除影片不會再問
      s.removeVideo('BV1ooooooooo');
      expect(await s.shouldPromptImport(), isFalse);
      await s.clearImportDeclined();
      expect(await s.shouldPromptImport(), isTrue);
    });
  });
}
