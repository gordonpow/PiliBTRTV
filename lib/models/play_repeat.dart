/// 播放完畢後的行為
enum PlayRepeat {
  pause('播完暫停'),
  playNext('直接播下一部'),
  countdownNext('倒數後播下一部'),
  singleCycle('循環播放此影片'),
  listCycle('列表循環');

  final String label;
  const PlayRepeat(this.label);

  /// 預設模式
  static const PlayRepeat defaultMode = PlayRepeat.countdownNext;

  /// 由新 key `play_end_mode` 存的名稱還原；無法辨識時回傳 null
  static PlayRepeat? fromName(String? name) {
    if (name == null) return null;
    for (final v in PlayRepeat.values) {
      if (v.name == name) return v;
    }
    return null;
  }

  /// 解析播完模式（純函式，方便測試）。順序：
  /// 1. 新 key 的名稱 [name]
  /// 2. 舊 `play_repeat` 的 index [legacyIndex]（舊 enum 依序為
  ///    pause、listOrder、singleCycle、listCycle、autoPlayRelated），
  ///    listOrder／autoPlayRelated 依 [countdown] 分成 playNext（0 秒）或 countdownNext
  /// 3. 更舊的 bool `auto_play` [legacyAutoPlay]：false 為 pause，其他為 countdownNext
  /// [fromLegacy] 回報這次是否由舊設定轉換而來（呼叫端據此寫回新 key）。
  static ({PlayRepeat mode, bool fromLegacy}) resolve({
    String? name,
    int? legacyIndex,
    bool? legacyAutoPlay,
    int? countdown,
  }) {
    final byName = fromName(name);
    if (byName != null) return (mode: byName, fromLegacy: false);

    if (legacyIndex != null && legacyIndex >= 0 && legacyIndex <= 4) {
      final PlayRepeat mode;
      switch (legacyIndex) {
        case 0:
          mode = PlayRepeat.pause;
        case 2:
          mode = PlayRepeat.singleCycle;
        case 3:
          mode = PlayRepeat.listCycle;
        default: // 1 = listOrder, 4 = autoPlayRelated
          mode = (countdown ?? 5) == 0
              ? PlayRepeat.playNext
              : PlayRepeat.countdownNext;
      }
      return (mode: mode, fromLegacy: true);
    }

    if (legacyAutoPlay == false) {
      return (mode: PlayRepeat.pause, fromLegacy: false);
    }
    return (mode: defaultMode, fromLegacy: false);
  }
}
