import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/video.dart';
import 'api/interaction_api.dart' show FavFolderState;

/// 本機收藏夾
class LocalFavFolder {
  final int id;
  final String name;
  final int createdAt; // 毫秒時間戳

  const LocalFavFolder({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  LocalFavFolder copyWith({String? name}) =>
      LocalFavFolder(id: id, name: name ?? this.name, createdAt: createdAt);
}

/// 本機收藏的一筆（某影片在某收藏夾）
class LocalFavEntry {
  final int folderId;
  final String bvid;
  final int aid;
  final String title;
  final String pic;
  final String ownerName;
  final int duration; // 秒
  final int addedAt; // 毫秒時間戳

  /// 播放來源（舊資料沒有時為 0，照舊以 bvid 開啟）
  final int cid; // 分 P 影片的 cid
  final int epId; // 番劇 ep_id
  final int seasonId; // 番劇 season_id（> 0 表示 PGC）

  bool get isPgc => seasonId > 0;

  const LocalFavEntry({
    required this.folderId,
    required this.bvid,
    required this.aid,
    required this.title,
    required this.pic,
    required this.ownerName,
    required this.duration,
    required this.addedAt,
    this.cid = 0,
    this.epId = 0,
    this.seasonId = 0,
  });

  Video toVideo() => Video(
    bvid: bvid,
    aid: aid,
    title: title,
    pic: pic,
    ownerName: ownerName,
    duration: duration,
    cid: cid,
    epId: epId,
    seasonId: seasonId,
  );

  Map<String, dynamic> toJson() => {
    'folderId': folderId,
    'bvid': bvid,
    'aid': aid,
    'title': title,
    'pic': pic,
    'ownerName': ownerName,
    'duration': duration,
    'addedAt': addedAt,
    'cid': cid,
    'epId': epId,
    'seasonId': seasonId,
  };

  static LocalFavEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final folderId = j['folderId'];
    final bvid = j['bvid'];
    if (folderId is! int || bvid is! String || bvid.isEmpty) return null;
    return LocalFavEntry(
      folderId: folderId,
      bvid: bvid,
      aid: j['aid'] is int ? j['aid'] as int : 0,
      title: j['title'] is String ? j['title'] as String : '',
      pic: j['pic'] is String ? j['pic'] as String : '',
      ownerName: j['ownerName'] is String ? j['ownerName'] as String : '',
      duration: j['duration'] is int ? j['duration'] as int : 0,
      addedAt: j['addedAt'] is int ? j['addedAt'] as int : 0,
      cid: j['cid'] is int ? j['cid'] as int : 0,
      epId: j['epId'] is int ? j['epId'] as int : 0,
      seasonId: j['seasonId'] is int ? j['seasonId'] as int : 0,
    );
  }
}

/// 未登入時使用的本機收藏。資料存在 app documents 的 JSON，
/// 寫入序列化並以 tmp → rename 取代，避免寫到一半損毀。
class LocalFavoritesService extends ChangeNotifier {
  static const int defaultFolderId = 1;
  static const String defaultFolderName = '本機收藏';
  static const String _fileName = 'local_favorites.json';
  static const String _declinedKey = 'local_fav_import_declined_at';

  static final LocalFavoritesService instance = LocalFavoritesService();

  LocalFavoritesService({
    Future<Directory> Function()? directoryProvider,
    int Function()? now,
  }) : _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory,
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Future<Directory> Function() _directoryProvider;
  final int Function() _now;

  List<LocalFavFolder> _folders = [];
  List<LocalFavEntry> _entries = [];
  int _nextId = defaultFolderId + 1;
  Future<void>? _loadFuture;

  /// 讀檔遇到 IO 錯誤（非 JSON 損毀）時為 true：保留原檔，不寫回
  bool _readOnly = false;

  /// 匯入帳號完成（有成功項目）時遞增，讓畫面重新載入帳號收藏夾
  final ValueNotifier<int> importDone = ValueNotifier(0);
  Future<void> _writeChain = Future.value();

  /// 資料夾，預設夾在最前，其餘依建立時間
  List<LocalFavFolder> get folders => List.unmodifiable(_folders);

  Future<File> _file() async =>
      File('${(await _directoryProvider()).path}/$_fileName');

  /// 載入檔案（只做一次）；必須在讀取任何資料前等待
  Future<void> ensureLoaded() => _loadFuture ??= _load();

  Future<void> _load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        try {
          _parse(jsonDecode(await file.readAsString()));
        } on FormatException {
          // JSON 損毀：原檔改名保留（加時間戳），從空資料開始
          _folders = [];
          _entries = [];
          _nextId = defaultFolderId + 1;
          try {
            await file.rename('${file.path}.bad-${_stamp()}');
          } catch (_) {}
        }
      }
    } catch (e) {
      // 其他 IO 錯誤：不搬檔也不覆蓋，本次以空資料執行且不寫回，下次啟動再讀
      _readOnly = true;
      if (kDebugMode) debugPrint('local favorites load failed: $e');
    }
    _ensureDefaultFolder();
  }

  String _stamp() {
    final t = DateTime.fromMillisecondsSinceEpoch(_now());
    String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
    return '${p(t.year, 4)}${p(t.month)}${p(t.day)}'
        '${p(t.hour)}${p(t.minute)}${p(t.second)}';
  }

  void _parse(Object? data) {
    if (data is! Map) throw const FormatException('not a map');
    final folders = <LocalFavFolder>[];
    final fl = data['folders'];
    if (fl is! List) throw const FormatException('folders');
    for (final f in fl) {
      if (f is! Map || f['id'] is! int || f['name'] is! String) {
        throw const FormatException('folder');
      }
      folders.add(
        LocalFavFolder(
          id: f['id'] as int,
          name: f['name'] as String,
          createdAt: f['createdAt'] is int ? f['createdAt'] as int : 0,
        ),
      );
    }
    final ids = folders.map((f) => f.id).toSet();
    final entries = <LocalFavEntry>[];
    final el = data['entries'];
    if (el is! List) throw const FormatException('entries');
    for (final e in el) {
      final entry = LocalFavEntry.fromJson(e);
      if (entry != null && ids.contains(entry.folderId)) entries.add(entry);
    }
    _folders = folders;
    _entries = entries;
    final maxId = folders.fold<int>(0, (m, f) => f.id > m ? f.id : m);
    final next = data['nextId'];
    _nextId = next is int && next > maxId ? next : maxId + 1;
  }

  void _ensureDefaultFolder() {
    if (!_folders.any((f) => f.id == defaultFolderId)) {
      _folders.insert(
        0,
        LocalFavFolder(
          id: defaultFolderId,
          name: defaultFolderName,
          createdAt: _now(),
        ),
      );
    }
    _folders.sort((a, b) {
      if (a.id == defaultFolderId) return -1;
      if (b.id == defaultFolderId) return 1;
      return a.createdAt != b.createdAt
          ? a.createdAt.compareTo(b.createdAt)
          : a.id.compareTo(b.id);
    });
    if (_nextId <= defaultFolderId) _nextId = defaultFolderId + 1;
  }

  void _changed() {
    notifyListeners();
    if (_readOnly) return;
    final json = jsonEncode({
      'version': 1,
      'nextId': _nextId,
      'folders': [
        for (final f in _folders)
          {'id': f.id, 'name': f.name, 'createdAt': f.createdAt},
      ],
      'entries': [for (final e in _entries) e.toJson()],
    });
    _writeChain = _writeChain.then((_) => _write(json));
  }

  Future<void> _write(String json) async {
    try {
      final file = await _file();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      if (kDebugMode) debugPrint('local favorites write failed: $e');
    }
  }

  /// 等待所有已排入的寫入完成（測試與匯入後使用）
  Future<void> flush() => _writeChain;

  // ───────────── 資料夾 ─────────────

  LocalFavFolder? folderById(int id) {
    for (final f in _folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// 建立收藏夾；名稱空白回傳 null
  LocalFavFolder? createFolder(String name) {
    final n = name.trim();
    if (n.isEmpty) return null;
    final folder = LocalFavFolder(id: _nextId++, name: n, createdAt: _now());
    _folders = [..._folders, folder];
    _changed();
    return folder;
  }

  /// 重新命名；名稱空白或找不到回傳 false
  bool renameFolder(int id, String name) {
    final n = name.trim();
    final i = _folders.indexWhere((f) => f.id == id);
    if (n.isEmpty || i < 0) return false;
    _folders = [..._folders]..[i] = _folders[i].copyWith(name: n);
    _changed();
    return true;
  }

  /// 刪除收藏夾與其中的影片；預設夾不可刪除
  bool deleteFolder(int id) {
    if (id == defaultFolderId) return false;
    if (!_folders.any((f) => f.id == id)) return false;
    _folders = _folders.where((f) => f.id != id).toList();
    _entries = _entries.where((e) => e.folderId != id).toList();
    _changed();
    return true;
  }

  // ───────────── 影片 ─────────────

  /// 某收藏夾內的影片，新加入的在前
  List<LocalFavEntry> entriesIn(int folderId) {
    final list = _entries.where((e) => e.folderId == folderId).toList();
    list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  int countIn(int folderId) =>
      _entries.where((e) => e.folderId == folderId).length;

  /// 不重複的影片（以 bvid 去重，取最近加入的一筆）
  List<LocalFavEntry> distinctEntries() {
    final map = <String, LocalFavEntry>{};
    for (final e in _entries) {
      final old = map[e.bvid];
      if (old == null || e.addedAt > old.addedAt) map[e.bvid] = e;
    }
    final list = map.values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  int get totalVideos => _entries.map((e) => e.bvid).toSet().length;

  Set<int> foldersOf(String bvid) => {
    for (final e in _entries)
      if (e.bvid == bvid) e.folderId,
  };

  bool isFavorited(String bvid) =>
      bvid.isNotEmpty && _entries.any((e) => e.bvid == bvid);

  bool isFavoritedAid(int aid) => aid > 0 && _entries.any((e) => e.aid == aid);

  /// 給收藏夾選單用的清單（faved 表示該影片已在其中）
  List<FavFolderState> folderStates(String bvid) {
    final inIds = foldersOf(bvid);
    return [
      for (final f in _folders)
        FavFolderState(
          id: f.id,
          title: f.name,
          mediaCount: countIn(f.id),
          faved: inIds.contains(f.id),
          isDefault: f.id == defaultFolderId,
        ),
    ];
  }

  /// 把影片設定為只在 [selected] 這些收藏夾內（差異加入／移出）
  void setVideoFolders(Video video, Set<int> selected) {
    final valid = {
      for (final id in selected)
        if (_folders.any((f) => f.id == id)) id,
    };
    final current = foldersOf(video.bvid);
    final kept = _entries
        .where((e) => e.bvid != video.bvid || valid.contains(e.folderId))
        .toList();
    final aid = video.resolvedAid;
    for (final id in valid.difference(current)) {
      kept.add(
        LocalFavEntry(
          folderId: id,
          bvid: video.bvid,
          aid: aid,
          title: video.title,
          pic: video.pic,
          ownerName: video.ownerName,
          duration: video.duration,
          addedAt: _now(),
          cid: video.cid,
          epId: video.epId,
          seasonId: video.seasonId,
        ),
      );
    }
    _entries = kept;
    _changed();
  }

  /// 從單一收藏夾移除
  void removeFromFolder(int folderId, String bvid) {
    final before = _entries.length;
    _entries = _entries
        .where((e) => !(e.folderId == folderId && e.bvid == bvid))
        .toList();
    if (_entries.length != before) _changed();
  }

  /// 從所有收藏夾移除
  void removeVideo(String bvid) {
    final before = _entries.length;
    _entries = _entries.where((e) => e.bvid != bvid).toList();
    if (_entries.length != before) _changed();
  }

  // ───────────── 匯入提示旗標 ─────────────

  /// 最近一次加入的時間（沒有影片為 0）
  int get latestAddedAt =>
      _entries.fold<int>(0, (m, e) => e.addedAt > m ? e.addedAt : m);

  /// 登入後是否該詢問匯入：本機有影片，且沒選過「否」，
  /// 或選「否」之後又有新增影片（最新加入時間比當時新）。
  Future<bool> shouldPromptImport() async {
    await ensureLoaded();
    if (totalVideos == 0) return false;
    try {
      final p = await SharedPreferences.getInstance();
      final declinedAt = p.getInt(_declinedKey);
      return declinedAt == null || latestAddedAt > declinedAt;
    } catch (_) {
      return true;
    }
  }

  /// 使用者選「否」：記下當下的最新加入時間
  Future<void> declineImport() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_declinedKey, latestAddedAt);
    } catch (_) {}
  }

  Future<void> clearImportDeclined() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_declinedKey);
    } catch (_) {}
  }
}
