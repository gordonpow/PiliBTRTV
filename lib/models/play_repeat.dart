/// 播放完畢後的行為
enum PlayRepeat {
  pause('播完暫停'),
  listOrder('順序播放'),
  singleCycle('單個循環'),
  listCycle('列表循環'),
  autoPlayRelated('自動連播');

  final String label;
  const PlayRepeat(this.label);
}
