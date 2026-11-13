/// 直播本機時移：錄製遠端 fmp4 HLS 到暫存目錄，再由本機 HTTP server 提供 live 清單。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../frame_service.dart';
import 'live_hls_playlist.dart';

/// 錄製狀態。
enum LiveTimeshiftState { recording, stalled, recovered, fatal }

class _DiskError implements Exception {
  const _DiskError(this.cause);
  final Object cause;
}

class _HttpStatusError implements Exception {
  const _HttpStatusError(this.status);
  final int status;
}

class _Resp {
  _Resp(this.status, this.body);
  final int status;
  final Uint8List body;
}

class _Job {
  _Job(this.uri, this.initUri, this.duration, this.discBefore);

  final Uri uri;
  final Uri? initUri;
  final double duration;
  bool discBefore;
  Future<Uint8List?>? future;
}

class _ThumbJob {
  _ThumbJob(this.n, this.paths, this.fallback, this.prevN);
  final int n;
  final List<String> paths;
  final List<String>? fallback;
  final int? prevN;
}

class LiveTimeshiftSession {
  LiveTimeshiftSession({
    required this.resolveUrl,
    required this.maxBuffer,
    this.headers = const {},
    this.mergeCount = 4,
    this.deleteDelay = const Duration(seconds: 15),
    this.retryBase = const Duration(seconds: 2),
    this.fatalAfter = const Duration(seconds: 60),
    this.startTimeout = const Duration(seconds: 15),
    Future<Uint8List?> Function(List<String> paths)? thumbnailer,
  }) : _thumbnailer = thumbnailer ?? _defaultThumbnailer;

  /// 背景縮圖擷取（gen = 0：原生端不會因預覽請求而丟棄，也不會讓預覽請求失效）。
  static Future<Uint8List?> _defaultThumbnailer(List<String> paths) =>
      FrameService.getLocalFrame(paths, gen: 0);

  final Future<Uint8List?> Function(List<String> paths) _thumbnailer;

  /// 取得新的遠端 fmp4 m3u8 完整網址；失敗回 null。
  final Future<String?> Function() resolveUrl;
  final Duration maxBuffer;

  /// 下載遠端用的標頭（UA、Referer、Cookie）。
  final Map<String, String> headers;

  // 以下參數預設值即正式行為，只給測試縮短時間用。
  final int mergeCount;
  final Duration deleteDelay;
  final Duration retryBase;
  final Duration fatalAfter;
  final Duration startTimeout;

  // ---- 靜態：共用 server 與暫存根目錄 ----
  static Future<HttpServer>? _serverFuture;
  static final Map<String, LiveTimeshiftSession> _sessions = {};
  static Future<void>? _cleanupFuture;

  /// 暫存根目錄提供者（測試可覆寫）。
  @visibleForTesting
  static Future<Directory> Function() tempRootProvider = getTemporaryDirectory;

  /// 測試用：重設 cleanupStale 快取。
  @visibleForTesting
  static void resetStaticForTest() => _cleanupFuture = null;

  static Future<Directory> _baseDir() async {
    final root = await tempRootProvider();
    return Directory('${root.path}${Platform.pathSeparator}live_timeshift');
  }

  /// App 啟動時呼叫：刪除 `<temp>/live_timeshift/` 下所有殘留目錄。整個 App 只執行一次。
  static Future<void> cleanupStale() => _cleanupFuture ??= () async {
        try {
          final d = await _baseDir();
          if (await d.exists()) await d.delete(recursive: true);
        } catch (e) {
          debugPrint('[LiveTimeshift] cleanupStale 失敗: ${e.runtimeType}');
        }
      }();

  static Future<HttpServer> _ensureServer() {
    return _serverFuture ??= () async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen(_handle, onError: (_) {});
      return s;
    }();
  }

  static final RegExp _fileRe = RegExp(r'^[A-Za-z0-9_]+\.m4s$');

  static Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final seg = req.uri.pathSegments;
      if (req.method != 'GET' || seg.length != 3 || seg[0] != 'live') {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final session = _sessions[seg[1]];
      if (session == null || session._disposed) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final name = seg[2];
      if (name == 'index.m3u8') {
        final bytes = Uint8List.fromList(session._local.render().codeUnits);
        res.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
        res.headers.set('Cache-Control', 'no-cache');
        res.contentLength = bytes.length;
        res.add(bytes);
      } else if (_fileRe.hasMatch(name)) {
        final f = File('${session._dir.path}${Platform.pathSeparator}$name');
        if (!await f.exists()) {
          res.statusCode = HttpStatus.notFound;
          return;
        }
        res.headers.set('Content-Type', 'video/mp4');
        res.contentLength = await f.length();
        await res.addStream(f.openRead());
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (_) {
      try {
        res.statusCode = HttpStatus.notFound;
      } catch (_) {}
    } finally {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  // ---- 實例狀態 ----
  final String _id = _randomId();
  final LiveLocalPlaylist _local = LiveLocalPlaylist();
  final StreamController<LiveTimeshiftState> _states =
      StreamController<LiveTimeshiftState>.broadcast();
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _wake = Completer<void>();
  final List<Timer> _deleteTimers = [];
  final List<_Job> _queue = [];
  final BytesBuilder _group = BytesBuilder(copy: false);
  late Directory _dir;

  bool _disposed = false;
  bool _started = false;
  bool _isReady = false;
  bool _pumping = false;
  bool _stopped = false; // 磁碟錯誤後停止錄製

  String _url = '';
  int _lastSeq = -1;
  bool _pendingDisc = false;
  Uri? _curInitUri;
  int _curInitIdx = -1;
  int _nextInit = 0;
  final Set<int> _knownInits = {};

  // 合併中的片段
  int _groupCount = 0;
  double _groupSeconds = 0;
  bool _groupDisc = false;
  int _groupInit = -1;

  double _remoteTarget = 1;

  static int _idCounter = 0;
  static String _randomId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '${now}_${(_idCounter++).toRadixString(36)}';
  }

  // ---- 公開 API ----

  /// 目前暫存的總長度（播放清單中所有片段的 EXTINF 總和）。
  Duration get bufferedDuration => _local.bufferedDuration;

  /// 錄製開始至今已刪除的片段總長度。
  Duration get droppedDuration => _local.droppedDuration;

  /// 錄製狀態變化。
  Stream<LiveTimeshiftState> get states => _states.stream;

  /// 距離直播最新位置的安全距離（3 × 本機 TARGETDURATION）。
  Duration get liveEdgeOffset => Duration(seconds: 3 * _local.targetDuration);

  /// 目前直播最新位置的絕對時間。
  Duration get liveAbsolute => droppedDuration + bufferedDuration;

  /// 播放器位置換成絕對位置。
  Duration absoluteOf(Duration playerPos) => droppedDuration + playerPos;

  /// 絕對位置換成播放器位置，夾在 `[0, bufferedDuration - liveEdgeOffset]`。
  Duration playerPosFor(Duration absolute) {
    var max = bufferedDuration - liveEdgeOffset;
    if (max < Duration.zero) max = Duration.zero;
    var p = absolute - droppedDuration;
    if (p < Duration.zero) p = Duration.zero;
    if (p > max) p = max;
    return p;
  }

  /// 預覽縮圖用：找出 [absolute] 所在的本機片段，回傳片段編號與要串接的檔案
  /// （init 檔在前，片段檔在後）。不複製位元組，由原生端虛擬串接。
  /// 尚未啟動、已 dispose 或沒有片段時回 null。
  ({int n, List<String> paths})? previewSource(Duration absolute) {
    if (_disposed || !_started) return null;
    final segs = _local.segments;
    if (segs.isEmpty) return null;
    var offset = absolute - droppedDuration;
    if (offset < Duration.zero) offset = Duration.zero;
    var seg = segs.last;
    var acc = Duration.zero;
    for (final s in segs) {
      acc += s.duration;
      if (offset < acc) {
        seg = s;
        break;
      }
    }
    final sep = Platform.pathSeparator;
    return (
      n: seg.n,
      paths: [
        if (seg.initIndex >= 0)
          '${_dir.path}$sep${liveInitFileName(seg.initIndex)}',
        '${_dir.path}$sep${seg.fileName}',
      ],
    );
  }

  // ---- 背景預先擷取縮圖 ----

  final Map<int, Uint8List> _thumbs = {};
  final List<_ThumbJob> _thumbQueue = [];
  bool _thumbBusy = false;
  static const int _thumbQueueMax = 3;

  bool _thumbsEnabled = false;

  /// 背景縮圖是否處理佇列（預設 false，由直播頁在播放穩定後開啟）。
  /// 關閉期間新片段仍會入佇列（只保留最新 3 個），只是不處理。
  bool get thumbnailsEnabled => _thumbsEnabled;
  set thumbnailsEnabled(bool v) {
    if (_thumbsEnabled == v) return;
    _thumbsEnabled = v;
    if (v) unawaited(_pumpThumbs());
  }

  /// 片段 [n] 預先擷取好的縮圖（JPEG）；尚未完成或沒有則回 null。
  Uint8List? thumbnailFor(int n) => _thumbs[n];

  List<String> _segPaths(LiveLocalSegment s) {
    final sep = Platform.pathSeparator;
    return [
      if (s.initIndex >= 0) '${_dir.path}$sep${liveInitFileName(s.initIndex)}',
      '${_dir.path}$sep${s.fileName}',
    ];
  }

  void _enqueueThumb(LiveLocalSegment seg, LiveLocalSegment? prev) {
    if (_disposed) return;
    // 沒有關鍵幀時改串「init＋前一片段＋本片段」重試（前一片段需同一個 init 且連續）
    List<String>? fallback;
    if (prev != null && !seg.discontinuity && prev.initIndex == seg.initIndex) {
      final sep = Platform.pathSeparator;
      fallback = [
        if (seg.initIndex >= 0)
          '${_dir.path}$sep${liveInitFileName(seg.initIndex)}',
        '${_dir.path}$sep${prev.fileName}',
        '${_dir.path}$sep${seg.fileName}',
      ];
    }
    _thumbQueue.add(_ThumbJob(seg.n, _segPaths(seg), fallback, prev?.n));
    // 只保留最新 3 個待處理項目
    while (_thumbQueue.length > _thumbQueueMax) {
      _thumbQueue.removeAt(0);
    }
    unawaited(_pumpThumbs());
  }

  Future<void> _pumpThumbs() async {
    if (_thumbBusy) return;
    _thumbBusy = true;
    try {
      while (!_disposed && _thumbsEnabled && _thumbQueue.isNotEmpty) {
        final job = _thumbQueue.removeAt(0);
        // 片段已被 trim 掉就略過
        if (job.n < _local.mediaSequence) continue;
        Uint8List? bytes;
        try {
          bytes = await _thumbnailer(job.paths);
          if (bytes == null && job.fallback != null && !_disposed) {
            bytes = await _thumbnailer(job.fallback!);
          }
        } catch (_) {}
        if (_disposed) return;
        bytes ??= job.prevN == null ? null : _thumbs[job.prevN!];
        if (bytes != null && job.n >= _local.mediaSequence) {
          _thumbs[job.n] = bytes;
        }
      }
    } finally {
      _thumbBusy = false;
    }
  }

  /// 開始錄製並啟動本機 server，回傳本機播放網址。超時或被 dispose 時丟例外。
  Future<String> start() async {
    if (_started) throw StateError('LiveTimeshiftSession 已啟動');
    _started = true;
    await cleanupStale();
    if (_disposed) throw StateError('session 已 dispose');
    final first = await resolveUrl();
    if (_disposed) throw StateError('session 已 dispose');
    if (first == null) throw StateError('無法取得直播網址');
    _url = first;
    final server = await _ensureServer();
    if (_disposed) throw StateError('session 已 dispose');
    _dir = Directory('${(await _baseDir()).path}${Platform.pathSeparator}$_id');
    await _dir.create(recursive: true);
    if (_disposed) {
      try {
        await _dir.delete(recursive: true);
      } catch (_) {}
      throw StateError('session 已 dispose');
    }
    _sessions[_id] = this;
    unawaited(_loop());
    try {
      await _ready.future.timeout(startTimeout);
    } catch (_) {
      await dispose();
      rethrow;
    }
    return 'http://127.0.0.1:${server.port}/live/$_id/index.m3u8';
  }

  /// 停止輪詢、關閉路由、刪除暫存目錄。可重複呼叫。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _sessions.remove(_id);
    if (!_wake.isCompleted) _wake.complete();
    try {
      _client.close(force: true);
    } catch (_) {}
    for (final t in _deleteTimers) {
      t.cancel();
    }
    _deleteTimers.clear();
    _thumbQueue.clear();
    _thumbs.clear();
    if (!_ready.isCompleted) {
      _ready.future.ignore();
      _ready.completeError(StateError('session 已 dispose'));
    }
    if (!_states.isClosed) unawaited(_states.close());
    if (_started) {
      try {
        await _dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  // ---- 錄製迴圈 ----

  void _emit(LiveTimeshiftState s) {
    if (!_disposed && !_states.isClosed) _states.add(s);
  }

  Future<void> _sleep(Duration d) async {
    if (_disposed) return;
    final c = Completer<void>();
    final t = Timer(d, () {
      if (!c.isCompleted) c.complete();
    });
    unawaited(_wake.future.then((_) {
      if (!c.isCompleted) c.complete();
    }));
    await c.future;
    t.cancel();
  }

  /// 輪詢間隔 = 0.5 × 遠端 TARGETDURATION，最少 500ms。
  Duration get _poll {
    final ms = (_remoteTarget * 500).round();
    return Duration(milliseconds: ms < 500 ? 500 : ms);
  }

  Future<_Resp> _get(Uri uri) async {
    final req = await _client.getUrl(uri).timeout(const Duration(seconds: 5));
    headers.forEach((k, v) => req.headers.set(k, v));
    final res = await req.close().timeout(const Duration(seconds: 5));
    final builder = BytesBuilder(copy: false);
    await for (final c in res.timeout(const Duration(seconds: 15))) {
      builder.add(c);
    }
    return _Resp(res.statusCode, builder.takeBytes());
  }

  Future<void> _loop() async {
    var fails = 0;
    DateTime? failStart;
    var stalled = false;
    var fatalSent = false;
    var backoff = retryBase;
    while (!_disposed && !_stopped) {
      try {
        final uri = Uri.parse(_url);
        final r = await _get(uri);
        if (_disposed) return;
        if (r.status != 200) throw _HttpStatusError(r.status);
        final pl = RemotePlaylist.parse(String.fromCharCodes(r.body), uri);
        if (pl == null) throw const FormatException('not m3u8');
        if (stalled) {
          _emit(LiveTimeshiftState.recovered);
          stalled = false;
          fatalSent = false;
        }
        fails = 0;
        failStart = null;
        backoff = retryBase;
        _ingest(pl);
        await _sleep(_poll);
      } catch (e) {
        if (_disposed || _stopped) return;
        fails++;
        failStart ??= DateTime.now();
        final status = e is _HttpStatusError ? e.status : null;
        debugPrint('[LiveTimeshift] m3u8 失敗 host=${_hostOf(_url)} '
            'status=${status ?? e.runtimeType}');
        if (!stalled && (fails >= 3 || status == 403 || status == 404)) {
          stalled = true;
          _emit(LiveTimeshiftState.stalled);
        }
        if (stalled) {
          // 重新取流並退避：2、4、8… 秒，上限 30 秒
          String? fresh;
          try {
            fresh = await resolveUrl();
          } catch (_) {}
          if (_disposed) return;
          if (fresh != null) _url = fresh;
          await _sleep(backoff);
          final next = backoff * 2;
          backoff = next > const Duration(seconds: 30)
              ? const Duration(seconds: 30)
              : next;
        } else {
          await _sleep(_poll);
        }
        if (!fatalSent && DateTime.now().difference(failStart) > fatalAfter) {
          fatalSent = true;
          _emit(LiveTimeshiftState.fatal);
        }
      }
    }
  }

  void _fail() {
    _stopped = true;
    _emit(LiveTimeshiftState.fatal);
  }

  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return '?';
    }
  }

  // ---- 新片段入列 ----

  void _ingest(RemotePlaylist pl) {
    _remoteTarget = pl.targetDuration;
    final segs = pl.segments;
    if (segs.isEmpty) return;
    var disc = false;
    // 重新取流後 sequence 倒退：重設基準並標記不連續
    if (_lastSeq >= 0 && segs.last.sequence < _lastSeq) {
      _lastSeq = segs.first.sequence - 1;
      disc = true;
    }
    var added = false;
    for (final s in segs) {
      if (s.sequence <= _lastSeq) continue;
      // 遠端 sequence 跳號（漏片段）
      if (_lastSeq >= 0 && s.sequence > _lastSeq + 1) disc = true;
      _queue.add(_Job(s.uri, pl.mapUri, s.duration, disc));
      disc = false;
      _lastSeq = s.sequence;
      added = true;
    }
    if (!added) return;
    // 佇列上限 20：丟最舊且尚未開始的，並讓後一個標記不連續
    while (_queue.length > 20) {
      final i = _queue.indexWhere((j) => j.future == null);
      if (i < 0 || i + 1 >= _queue.length) break;
      _queue.removeAt(i);
      _queue[i].discBefore = true;
    }
    unawaited(_pump());
  }

  /// 最多 3 個並行下載，依 sequence 順序處理。
  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (!_disposed && !_stopped && _queue.isNotEmpty) {
        for (final j in _queue.take(3)) {
          j.future ??= _downloadRetry(j.uri);
        }
        final head = _queue.first;
        final bytes = await head.future;
        if (_disposed || _stopped) break;
        _queue.remove(head);
        await _consume(head, bytes);
      }
    } on _DiskError catch (e) {
      if (!_disposed) {
        debugPrint('[LiveTimeshift] 寫檔失敗，停止錄製: ${e.cause.runtimeType}');
        _fail();
      }
    } catch (e) {
      debugPrint('[LiveTimeshift] pump 錯誤: ${e.runtimeType}');
    } finally {
      _pumping = false;
    }
  }

  /// 下載（失敗重試 2 次）；仍失敗回 null。
  Future<Uint8List?> _downloadRetry(Uri uri) async {
    for (var i = 0; i < 3; i++) {
      if (_disposed) return null;
      try {
        final r = await _get(uri);
        if (r.status == 200) return r.body;
        debugPrint('[LiveTimeshift] 片段 host=${uri.host} status=${r.status}');
      } catch (e) {
        if (_disposed) return null;
        debugPrint('[LiveTimeshift] 片段 host=${uri.host} ${e.runtimeType}');
      }
    }
    return null;
  }

  Future<void> _consume(_Job job, Uint8List? bytes) async {
    if (bytes == null) {
      // 略過失敗片段並標記不連續
      _pendingDisc = true;
      return;
    }
    var disc = job.discBefore || _pendingDisc;
    if (_curInitUri != job.initUri) {
      // init 改變：結束目前合併中的片段，換新 init
      await _flush();
      if (_disposed) return;
      Uint8List? initBytes;
      if (job.initUri != null) {
        initBytes = await _downloadRetry(job.initUri!);
        if (_disposed) return;
        if (initBytes == null) {
          _pendingDisc = true;
          return;
        }
      }
      if (_curInitUri != null) disc = true;
      if (initBytes != null) {
        final k = _nextInit++;
        await _write(liveInitFileName(k), initBytes);
        _knownInits.add(k);
        _curInitIdx = k;
      } else {
        _curInitIdx = -1;
      }
      _curInitUri = job.initUri;
    }
    _pendingDisc = false;
    if (disc) await _flush();
    if (_disposed) return;
    if (_groupCount == 0) {
      _groupDisc = disc;
      _groupInit = _curInitIdx;
    }
    _group.add(bytes);
    _groupCount++;
    _groupSeconds += job.duration;
    // 就緒前每個遠端片段單獨成檔，盡快湊到 3 個
    if (_groupCount >= (_isReady ? mergeCount : 1)) await _flush();
  }

  Future<void> _write(String name, List<int> data) async {
    if (_disposed) return;
    try {
      await File('${_dir.path}${Platform.pathSeparator}$name')
          .writeAsBytes(data);
    } on FileSystemException catch (e) {
      if (_disposed) return;
      throw _DiskError(e);
    }
  }

  /// 把合併中的 moof+mdat 位元組串接寫成一個本機片段。
  Future<void> _flush() async {
    if (_groupCount == 0) return;
    final data = _group.takeBytes();
    final secs = _groupSeconds;
    final disc = _groupDisc;
    final init = _groupInit;
    _groupCount = 0;
    _groupSeconds = 0;
    _groupDisc = false;
    await _write('s${_local.nextN}.m4s', data);
    if (_disposed) return;
    final prev = _local.segments.isEmpty ? null : _local.segments.last;
    final seg = _local.add(
      duration: Duration(microseconds: (secs * 1000000).round()),
      discontinuity: disc,
      initIndex: init,
    );
    _enqueueThumb(seg, prev);
    final removed = _local.trim(maxBuffer);
    for (final s in removed) {
      _scheduleDelete(s.fileName);
      _thumbs.remove(s.n);
    }
    if (removed.isNotEmpty) {
      final used = {..._local.usedInits, if (_curInitIdx >= 0) _curInitIdx};
      for (final k in _knownInits.where((k) => !used.contains(k)).toList()) {
        _knownInits.remove(k);
        _scheduleDelete(liveInitFileName(k));
      }
    }
    if (!_isReady && _local.segments.length >= 3) {
      _isReady = true;
      if (!_ready.isCompleted) _ready.complete();
      _emit(LiveTimeshiftState.recording);
    }
  }

  /// 已移出清單的檔案延遲刪除，避免播放器仍在讀取。
  void _scheduleDelete(String name) {
    final path = '${_dir.path}${Platform.pathSeparator}$name';
    late Timer t;
    t = Timer(deleteDelay, () {
      _deleteTimers.remove(t);
      File(path).delete().then((_) {}, onError: (_) {});
    });
    _deleteTimers.add(t);
  }
}
