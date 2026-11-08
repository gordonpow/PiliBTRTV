import 'video.dart';

/// UP主 合集（ugc_season）或系列（series）
class SpaceCollection {
  final int id;
  final String title;
  final String cover;
  final int count;
  final bool isSeries;

  const SpaceCollection({
    required this.id,
    required this.title,
    required this.cover,
    required this.count,
    required this.isSeries,
  });

  bool sameAs(SpaceCollection other) =>
      id == other.id && isSeries == other.isSeries;
}

/// `app.bilibili.com/x/v2/space` 回傳資料（只保留 TV 頁面用得到的欄位）
class SpaceData {
  static const supportedTabs = ['home', 'dynamic', 'contribute'];

  final String name;
  final String face;
  final String sign;
  final int fans;
  final int following;
  final int likes;

  /// tab2 的 param，只保留 home / dynamic / contribute，順序同 API
  final List<String> tabs;

  /// home / dynamic / contribute（default_tab 為 video 時轉成 contribute）
  final String defaultTab;

  final List<Video> archive;
  final int archiveCount;
  final List<SpaceCollection> seasons;
  final List<SpaceCollection> series;
  final List<Video> coins;
  final List<Video> likesArchive;
  final List<Video> bangumi;

  const SpaceData({
    this.name = '',
    this.face = '',
    this.sign = '',
    this.fans = 0,
    this.following = 0,
    this.likes = 0,
    this.tabs = const [],
    this.defaultTab = 'contribute',
    this.archive = const [],
    this.archiveCount = 0,
    this.seasons = const [],
    this.series = const [],
    this.coins = const [],
    this.likesArchive = const [],
    this.bangumi = const [],
  });

  /// 是否有任何主頁內容
  bool get hasHomeContent =>
      archive.isNotEmpty ||
      seasons.isNotEmpty ||
      series.isNotEmpty ||
      coins.isNotEmpty ||
      likesArchive.isNotEmpty ||
      bangumi.isNotEmpty;

  factory SpaceData.fromJson(Map<String, dynamic> data) {
    final card = _map(data['card']);

    final tabs = <String>[];
    for (final t in _list(data['tab2'])) {
      final param = _map(t)['param']?.toString() ?? '';
      if (supportedTabs.contains(param) && !tabs.contains(param)) {
        tabs.add(param);
      }
    }

    var defaultTab = data['default_tab']?.toString() ?? '';
    if (defaultTab == 'video') defaultTab = 'contribute';
    if (tabs.isNotEmpty && !tabs.contains(defaultTab)) defaultTab = tabs.first;
    if (defaultTab.isEmpty) defaultTab = 'contribute';

    final archive = _map(data['archive']);

    return SpaceData(
      name: card['name']?.toString() ?? '',
      face: card['face']?.toString() ?? '',
      sign: card['sign']?.toString() ?? '',
      fans: _toInt(card['fans']),
      following: _toInt(card['attention']),
      likes: _toInt(_map(card['likes'])['like_num']),
      tabs: tabs,
      defaultTab: defaultTab,
      archive: _videos(archive['item']),
      archiveCount: _toInt(archive['count']),
      seasons: _list(_map(data['ugc_season'])['item'])
          .map((e) => _map(e))
          .where((e) => _toInt(e['season_id']) > 0)
          .map(
            (e) => SpaceCollection(
              id: _toInt(e['season_id']),
              title: e['title']?.toString() ?? '',
              cover: _fixUrl(e['cover']?.toString() ?? ''),
              count: _toInt(e['count']),
              isSeries: false,
            ),
          )
          .toList(),
      series: _list(_map(data['series'])['item'])
          .map((e) => _map(e))
          .where((e) => _toInt(e['series_id']) > 0)
          .map(
            (e) => SpaceCollection(
              id: _toInt(e['series_id']),
              title: e['name']?.toString() ?? '',
              cover: '',
              count: 0,
              isSeries: true,
            ),
          )
          .toList(),
      coins: _videos(_map(data['coin_archive'])['item']),
      likesArchive: _videos(_map(data['like_archive'])['item']),
      bangumi: _bangumi(_map(data['season'])['item']),
    );
  }

  static List<Video> _videos(dynamic list) {
    final result = <Video>[];
    for (final e in _list(list)) {
      final item = _map(e);
      if ((item['bvid']?.toString() ?? '').isEmpty) continue;
      result.add(Video.fromSpaceApp(item));
    }
    return result;
  }

  static List<Video> _bangumi(dynamic list) {
    final result = <Video>[];
    for (final e in _list(list)) {
      final item = _map(e);
      final seasonId = int.tryParse(item['param']?.toString() ?? '');
      if (seasonId == null || seasonId <= 0) continue;
      result.add(
        Video(
          bvid: '',
          title: item['title']?.toString() ?? '',
          pic: _fixUrl(item['cover']?.toString() ?? ''),
          seasonId: seasonId,
          epIndexText: item['newest_ep_index']?.toString() ?? '',
        ),
      );
    }
    return result;
  }

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static List _list(dynamic v) => v is List ? v : const [];

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static String _fixUrl(String url) =>
      url.startsWith('//') ? 'https:$url' : url;
}
