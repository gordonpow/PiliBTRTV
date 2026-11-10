import '../models/video.dart';

/// 合集（ugc_season）攤平結果
class SeasonFlat {
  /// 依段落順序、段落內順序攤平的影片
  final List<Video> videos;

  /// [currentBvid] 在 [videos] 中的位置；找不到為 -1
  final int index;

  const SeasonFlat(this.videos, this.index);

  static const empty = SeasonFlat([], -1);
}

int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

String _str(dynamic v) => v is String ? v : '';

String _fixPic(String url) {
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('http://')) return 'https://${url.substring(7)}';
  return url;
}

/// 把 `view` API 回傳的 `ugc_season.sections[].episodes[]` 依序攤平成影片清單。
///
/// - bvid、aid、cid、title 取自 episode 本身；pic、duration、pubdate、owner 取自 `arc`。
/// - owner 先取 `arc.owner`（或 `arc.author`），沒有時用 [fallbackOwner]
///   （目前影片的 `owner`，合集通常是同一個 UP 主）。
/// - 沒有 `ugc_season`、沒有 sections 或找不到 [currentBvid] 時，回傳 [SeasonFlat.empty]。
SeasonFlat flattenUgcSeason(Map<String, dynamic>? info, String currentBvid) {
  final season = info?['ugc_season'];
  if (season is! Map) return SeasonFlat.empty;
  final sections = season['sections'];
  if (sections is! List) return SeasonFlat.empty;

  final fallback = info?['owner'] is Map
      ? Map<String, dynamic>.from(info!['owner'] as Map)
      : const <String, dynamic>{};

  final videos = <Video>[];
  for (final sec in sections) {
    if (sec is! Map) continue;
    final eps = sec['episodes'];
    if (eps is! List) continue;
    for (final ep in eps) {
      if (ep is! Map) continue;
      final bvid = _str(ep['bvid']);
      if (bvid.isEmpty) continue;
      final arc = ep['arc'] is Map ? ep['arc'] as Map : const {};
      final owner = arc['owner'] is Map
          ? arc['owner'] as Map
          : (arc['author'] is Map ? arc['author'] as Map : fallback);
      final stat = arc['stat'] is Map ? arc['stat'] as Map : const {};
      final title = _str(ep['title']);
      videos.add(
        Video(
          bvid: bvid,
          aid: _int(ep['aid']),
          cid: _int(ep['cid']),
          title: title.isNotEmpty ? title : _str(arc['title']),
          pic: _fixPic(_str(arc['pic'])),
          duration: _int(arc['duration']),
          pubdate: _int(arc['pubdate']),
          ownerName: _str(owner['name']),
          ownerFace: _fixPic(_str(owner['face'])),
          ownerMid: _int(owner['mid']),
          view: _int(stat['view']),
          danmaku: _int(stat['danmaku']),
        ),
      );
    }
  }

  final index = videos.indexWhere((v) => v.bvid == currentBvid);
  if (index < 0) return SeasonFlat.empty;
  return SeasonFlat(videos, index);
}
