/// 續播來源優先序（純函式，方便測試）
class ResumeResolver {
  ResumeResolver._();

  /// 決定續播秒數與來源。
  ///
  /// 優先序：
  /// 1. 伺服器進度（[serverCid] 等於 [resolvedCid] 即採用，包含 0 秒）。
  /// 2. 本地快取（cid 需相符）與列表進度比新舊：快取 [cacheSavedAt] 對上
  ///    列表 [listViewAt]，取較新的；只有一邊時間 > 0 就用那一邊；
  ///    兩邊都沒有時間時用快取。
  /// 3. 都沒有則 none、0 秒。
  ///
  /// 列表進度 -1 且有 [listViewAt] 表示在其他裝置看完，視為 0 秒參與比新舊；
  /// 其他 <= 0 的值視為沒有資料。
  static ({int seconds, String source}) resolve({
    required int resolvedCid,
    int? serverCid,
    int? serverSeconds,
    int? cacheCid,
    int cacheProgress = 0,
    int cacheSavedAt = 0,
    int listProgress = 0,
    int listViewAt = 0,
  }) {
    if (serverCid != null &&
        serverSeconds != null &&
        serverCid == resolvedCid) {
      return (seconds: serverSeconds < 0 ? 0 : serverSeconds, source: 'server');
    }

    final hasCache = cacheCid == resolvedCid && cacheProgress > 0;
    // -1 = 已看完（B 站歷史）；需要 view_at 才能判斷是否比快取新
    final listFinished = listProgress == -1 && listViewAt > 0;
    final hasList = listProgress > 0 || listFinished;
    final listSeconds = listFinished ? 0 : listProgress;

    if (hasCache && hasList) {
      final useList = listViewAt > cacheSavedAt;
      return useList
          ? (seconds: listSeconds, source: 'list')
          : (seconds: cacheProgress, source: 'cache');
    }
    if (hasCache) return (seconds: cacheProgress, source: 'cache');
    if (listProgress > 0) return (seconds: listProgress, source: 'list');
    return (seconds: 0, source: 'none');
  }
}
