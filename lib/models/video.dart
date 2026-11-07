/// 影片資料模型
class Video {
  final String bvid;
  final String title;
  final String pic; // 封面圖 URL
  final String ownerName;
  final String ownerFace;
  final int ownerMid;
  final int view; // 播放量
  final int danmaku; // 彈幕數
  final int duration; // 時長(秒)
  final int pubdate; // 釋出時間戳
  final int progress; // 觀看進度(秒), -1表示未觀看
  final int viewAt; // 最後觀看時間戳
  final int cid; // 歷史記錄中的 CID
  final int historyPage; // 歷史記錄中的分P序號 (如 1)
  final String historyPart; // 歷史記錄中的分P標題 (如 "第一話")
  final int historyVideos; // 歷史記錄中的總分P數 (多P影片 > 1)
  final String badge; // 角標 (如 "付費", "充電專屬")
  final bool isLive; // 是否是直播

  Video({
    required this.bvid,
    required this.title,
    required this.pic,
    this.ownerName = '',
    this.ownerFace = '',
    this.ownerMid = 0,
    this.view = 0,
    this.danmaku = 0,
    this.duration = 0,
    this.pubdate = 0,
    this.progress = -1,
    this.viewAt = 0,
    this.cid = 0,
    this.historyPage = 0,
    this.historyPart = '',
    this.historyVideos = 0,
    String badge = '',
    this.isLive = false,
  }) : badge = _filterBadge(badge);

  static String _filterBadge(String badge) {
    // 與伺服器回傳的簡體文字比對，保留原文
    if (badge == '投稿视频' || badge == '投稿') return '';
    return badge;
  }

  /// 從推薦/熱門 API 響應解析
  factory Video.fromRecommend(Map<String, dynamic> json) {
    final owner = json['owner'] as Map<String, dynamic>? ?? {};
    final stat = json['stat'] as Map<String, dynamic>? ?? {};

    return Video(
      bvid: json['bvid'] ?? '',
      title: json['title'] ?? '',
      pic: _fixPicUrl(json['pic'] ?? ''),
      ownerName: owner['name'] ?? '',
      ownerFace: _fixPicUrl(owner['face'] ?? ''),
      ownerMid: owner['mid'] ?? 0,
      view: _toInt(stat['view']),
      danmaku: _toInt(stat['danmaku']),
      duration: json['duration'] ?? 0,
      pubdate: json['pubdate'] ?? 0,
      // 推薦流中可能有 badge 資訊，如 "充電專屬"
      badge: json['badge'] ?? '',
    );
  }

  /// 從歷史記錄 API 響應解析
  factory Video.fromHistory(Map<String, dynamic> json) {
    final history = json['history'] as Map<String, dynamic>? ?? {};

    // 封面優先使用 cover，其次 pic
    String cover = json['cover'] ?? '';
    if (cover.isEmpty) cover = json['pic'] ?? '';

    final videos = json['videos'] ?? 0;
    final duration = json['duration'] ?? 0;

    return Video(
      bvid: history['bvid'] ?? '',
      title: json['title'] ?? '',
      pic: _fixPicUrl(cover),
      ownerName: json['author_name'] ?? '',
      ownerFace: _fixPicUrl(json['author_face'] ?? ''),
      ownerMid: json['author_mid'] ?? 0,
      view: _toInt(json['stat']?['view']),
      danmaku: _toInt(json['stat']?['danmaku']),
      duration: duration,
      progress: json['progress'] ?? -1,
      viewAt: json['view_at'] ?? 0,
      cid: (history['cid'] != null && history['cid'] != 0)
          ? history['cid']
          : (history['oid'] ?? 0),
      historyPage: history['page'] ?? 0,
      historyPart: history['part'] ?? '',
      historyVideos: videos, // 分P總數 (多P > 1)
      badge: json['badge'] ?? '',
      // live_status: 0:未直播, 1:直播中
      isLive:
          (json['live_status'] ?? 0) == 1 ||
          (json['badge'] ?? '').toString().contains('直播') ||
          // 與伺服器回傳的簡體文字比對，保留原文
          (json['badge'] == '未开播'),
    );
  }

  /// 從搜尋結果解析
  factory Video.fromSearch(Map<String, dynamic> json) {
    // 搜尋結果的標題可能包含 <em> 高亮標籤，需要清理
    String title = json['title'] ?? '';
    title = title.replaceAll(RegExp(r'<[^>]*>'), '');

    return Video(
      bvid: json['bvid'] ?? '',
      title: title,
      pic: _fixPicUrl(json['pic'] ?? ''),
      ownerName: json['author'] ?? '',
      view: _toInt(json['play']),
      danmaku: _toInt(json['danmaku']),
      duration: _parseDuration(json['duration'] ?? ''),
      pubdate: json['pubdate'] ?? 0,
      badge: json['badge'] ?? '',
    );
  }

  /// 從 UP主空間影片列表解析
  factory Video.fromSpaceVideo(Map<String, dynamic> json) {
    return Video(
      bvid: json['bvid'] ?? '',
      title: json['title'] ?? '',
      pic: _fixPicUrl(json['pic'] ?? ''),
      ownerName: json['author'] ?? '',
      ownerMid: _toInt(json['mid']),
      view: _toInt(json['play']),
      danmaku: _toInt(json['video_review']),
      duration: _parseDuration(json['length'] ?? ''),
      pubdate: json['created'] ?? 0,
      badge: json['badge'] ?? '',
    );
  }

  /// 格式化播放量
  String get viewFormatted {
    if (view >= 100000000) return '${(view / 100000000).toStringAsFixed(1)}億';
    if (view >= 10000) return '${(view / 10000).toStringAsFixed(1)}萬';
    return view.toString();
  }

  /// 格式化彈幕數
  String get danmakuFormatted {
    if (danmaku >= 100000000) {
      return '${(danmaku / 100000000).toStringAsFixed(1)}億';
    }
    if (danmaku >= 10000) {
      return '${(danmaku / 10000).toStringAsFixed(1)}萬';
    }
    return danmaku.toString();
  }

  /// 格式化釋出時間
  String get pubdateFormatted {
    if (pubdate == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(pubdate * 1000);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 365) {
      return '${diff.inDays ~/ 365}年前';
    } else if (diff.inDays > 30) {
      return '${diff.inDays ~/ 30}月前';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小時前';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分鐘前';
    }
    return '剛剛';
  }

  /// 格式化最後觀看時間
  String get viewAtFormatted {
    if (viewAt == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(viewAt * 1000);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 365) {
      return '${diff.inDays ~/ 365}年前看過';
    } else if (diff.inDays > 30) {
      return '${diff.inDays ~/ 30}月前看過';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前看過';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小時前看過';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分鐘前看過';
    }
    return '剛剛看過';
  }

  /// 格式化時長
  String get durationFormatted {
    final h = duration ~/ 3600;
    final m = (duration % 3600) ~/ 60;
    final s = duration % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // 修復圖片 URL (處理 //xxx 格式)
  static String _fixPicUrl(String url) {
    if (url.startsWith('//')) return 'https:$url';
    return url;
  }

  // 安全轉換為 int
  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  // 解析時長字串 (如 "12:34" 或 "1:23:45")
  static int _parseDuration(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      final parts = value.split(':');
      if (parts.length == 2) {
        return (int.tryParse(parts[0]) ?? 0) * 60 +
            (int.tryParse(parts[1]) ?? 0);
      }
      if (parts.length == 3) {
        return (int.tryParse(parts[0]) ?? 0) * 3600 +
            (int.tryParse(parts[1]) ?? 0) * 60 +
            (int.tryParse(parts[2]) ?? 0);
      }
    }
    return 0;
  }
}
