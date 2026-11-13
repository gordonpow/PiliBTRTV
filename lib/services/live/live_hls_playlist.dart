/// HLS 播放清單解析（遠端）與產生（本機時移）。純邏輯，不碰網路與磁碟。
library;

/// 遠端清單中的一個片段。
class RemoteSegment {
  const RemoteSegment(this.sequence, this.uri, this.duration);

  /// 遠端 media sequence（已加上偏移）。
  final int sequence;

  /// 已用遠端 m3u8 網址 resolve 過的完整網址。
  final Uri uri;
  final double duration;
}

/// 解析後的遠端播放清單。
class RemotePlaylist {
  const RemotePlaylist({
    required this.mediaSequence,
    required this.targetDuration,
    required this.mapUri,
    required this.segments,
  });

  final int mediaSequence;
  final double targetDuration;

  /// `#EXT-X-MAP` 的 init 網址（已 resolve），沒有則為 null。
  final Uri? mapUri;
  final List<RemoteSegment> segments;

  /// 解析 [text]；相對 URI 以 [base] resolve（保留目錄、捨棄 query）。
  /// 格式不合（沒有 #EXTM3U）時回傳 null。
  static RemotePlaylist? parse(String text, Uri base) {
    final lines = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).toList();
    if (lines.isEmpty || !lines.first.startsWith('#EXTM3U')) return null;

    var seq = 0;
    var target = 1.0;
    Uri? map;
    double? pendingDuration;
    final segs = <RemoteSegment>[];
    final mapRe = RegExp(r'URI="([^"]+)"');

    for (final line in lines) {
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        seq = int.tryParse(line.substring(22).trim()) ?? 0;
      } else if (line.startsWith('#EXT-X-TARGETDURATION:')) {
        target = double.tryParse(line.substring(22).trim()) ?? 1.0;
      } else if (line.startsWith('#EXT-X-MAP:')) {
        final m = mapRe.firstMatch(line);
        if (m != null) map = base.resolve(m.group(1)!);
      } else if (line.startsWith('#EXTINF:')) {
        final body = line.substring(8);
        final comma = body.indexOf(',');
        pendingDuration =
            double.tryParse(comma < 0 ? body : body.substring(0, comma));
      } else if (!line.startsWith('#')) {
        if (pendingDuration != null) {
          segs.add(RemoteSegment(
              seq + segs.length, base.resolve(line), pendingDuration));
          pendingDuration = null;
        }
      }
    }
    return RemotePlaylist(
      mediaSequence: seq,
      targetDuration: target,
      mapUri: map,
      segments: segs,
    );
  }
}

/// 本機時移清單中的一個片段（可能由多個遠端片段合併）。
class LiveLocalSegment {
  const LiveLocalSegment({
    required this.n,
    required this.duration,
    required this.discontinuity,
    required this.initIndex,
  });

  final int n;
  final Duration duration;

  /// 此片段前有不連續。
  final bool discontinuity;

  /// 使用的 init 編號；-1 表示沒有 init。
  final int initIndex;

  String get fileName => 's$n.m4s';
}

String liveInitFileName(int k) => 'init$k.m4s';

/// 本機時移播放清單的記憶體結構：片段、刪除統計與清單文字（有變化才重建）。
class LiveLocalPlaylist {
  final List<LiveLocalSegment> _segments = [];
  int _nextN = 0;
  Duration _dropped = Duration.zero;
  int _droppedDisc = 0;
  String? _cache;

  List<LiveLocalSegment> get segments => List.unmodifiable(_segments);

  /// 下一個片段的本機編號（先用它命名檔案再 [add]）。
  int get nextN => _nextN;

  Duration get bufferedDuration =>
      _segments.fold(Duration.zero, (a, s) => a + s.duration);

  Duration get droppedDuration => _dropped;
  int get droppedDiscontinuities => _droppedDisc;

  /// 第一個保留片段的本機編號；沒有片段時為下一個編號。
  int get mediaSequence => _segments.isEmpty ? _nextN : _segments.first.n;

  /// 最大片段長度無條件進位，至少 1。
  int get targetDuration {
    var maxUs = 0;
    for (final s in _segments) {
      if (s.duration.inMicroseconds > maxUs) maxUs = s.duration.inMicroseconds;
    }
    final sec = (maxUs / 1000000).ceil();
    return sec < 1 ? 1 : sec;
  }

  LiveLocalSegment add({
    required Duration duration,
    required bool discontinuity,
    required int initIndex,
  }) {
    final s = LiveLocalSegment(
      n: _nextN++,
      duration: duration,
      discontinuity: discontinuity,
      initIndex: initIndex,
    );
    _segments.add(s);
    _cache = null;
    return s;
  }

  /// 總長超過 [maxBuffer] 時從最舊刪起（至少保留 1 個），回傳被移除的片段。
  List<LiveLocalSegment> trim(Duration maxBuffer) {
    final removed = <LiveLocalSegment>[];
    var total = bufferedDuration;
    while (_segments.length > 1 && total > maxBuffer) {
      final s = _segments.removeAt(0);
      total -= s.duration;
      _dropped += s.duration;
      if (s.discontinuity) _droppedDisc++;
      removed.add(s);
    }
    if (removed.isNotEmpty) _cache = null;
    return removed;
  }

  /// 目前仍被片段引用的 init 編號。
  Set<int> get usedInits =>
      {for (final s in _segments) if (s.initIndex >= 0) s.initIndex};

  String render() {
    final cached = _cache;
    if (cached != null) return cached;
    final b = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:7')
      ..writeln('#EXT-X-TARGETDURATION:$targetDuration')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:$mediaSequence')
      ..writeln('#EXT-X-DISCONTINUITY-SEQUENCE:$_droppedDisc');
    var curInit = -2;
    for (var i = 0; i < _segments.length; i++) {
      final s = _segments[i];
      if (s.discontinuity) b.writeln('#EXT-X-DISCONTINUITY');
      // 第一個保留片段使用的 init 一定出現在清單開頭
      if (s.initIndex != curInit) {
        if (s.initIndex >= 0) {
          b.writeln('#EXT-X-MAP:URI="${liveInitFileName(s.initIndex)}"');
        }
        curInit = s.initIndex;
      }
      b.writeln(
          '#EXTINF:${(s.duration.inMicroseconds / 1000000).toStringAsFixed(3)},');
      b.writeln(s.fileName);
    }
    return _cache = b.toString();
  }
}
