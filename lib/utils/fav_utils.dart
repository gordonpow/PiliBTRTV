/// 收藏／觀看紀錄相關純函式（無外部相依，方便單元測試）
library;

const String _bvTable =
    'FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf';
const int _bvXor = 23442827791579;
const int _bvMask = 2251799813685247; // (1 << 51) - 1

/// BV 號換算成 aid；格式錯誤回傳 0。
int bvidToAid(String bvid) {
  if (bvid.length != 12 || !bvid.startsWith('BV1')) return 0;
  final chars = bvid.split('');
  void swap(int a, int b) {
    final t = chars[a];
    chars[a] = chars[b];
    chars[b] = t;
  }

  swap(3, 9);
  swap(4, 7);
  var tmp = 0;
  for (final c in chars.sublist(3)) {
    final idx = _bvTable.indexOf(c);
    if (idx < 0) return 0;
    tmp = tmp * 58 + idx;
  }
  return (tmp & _bvMask) ^ _bvXor;
}

/// 組出刪除觀看紀錄用的 kid（`<business>_<id>`）。
///
/// - archive：用 oid（即 aid）
/// - pgc：用 kid（season_id）
/// - 其他（live、article…）：用 oid
/// 缺值時回傳空字串。
String buildHistoryKid({
  required String business,
  required int oid,
  required int kid,
}) {
  if (business.isEmpty) return '';
  final id = business == 'pgc' ? kid : oid;
  if (id <= 0) return '';
  return '${business}_$id';
}

/// 收藏夾勾選差異：回傳要加入與要移出的收藏夾 id。
({List<int> add, List<int> del}) diffFavFolders(
  Set<int> original,
  Set<int> selected,
) {
  return (
    add: selected.difference(original).toList()..sort(),
    del: original.difference(selected).toList()..sort(),
  );
}

/// 以逗號串接 id（API 的 add_media_ids / del_media_ids 格式）。
String joinIds(Iterable<int> ids) => ids.join(',');
