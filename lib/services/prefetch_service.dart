import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/video.dart';
import 'api/pgc_api.dart';
import 'bilibili_api.dart';
import 'btr/btr_config.dart';
import 'btr/btr_proxy.dart';
import 'play_params.dart';
import 'playback_progress_cache.dart';
import 'settings_service.dart';

class _Entry {
  _Entry(this.bvid) : at = DateTime.now();

  final String bvid;
  final DateTime at;

  /// 去掉 history 的影片資訊（續播進度以播放器自己抓的為準）
  Map<String, dynamic>? info;

  /// 原始 history 欄位（續播 cid 與進度用；只給 peekVideoInfo 還原）
  dynamic history;
  int? cid;
  String? playKey;
  String? previewUrl;
  bool previewOk = false;
  bool consumed = false;

  /// 播放網址步驟的結果；失敗、取消時以 null 完成，等待者不會卡住
  final Completer<Map<String, dynamic>?> play = Completer();
}

/// 焦點預載服務（單例）
///
/// 預先抓影片資訊、播放網址、彈幕，並暖機影片／音訊開頭。
/// 不建立 VideoPlayerController、不碰 LocalServer、不改任何設定。
/// 失敗一律靜默，播放器拿不到快取時照原流程。
class PrefetchService {
  PrefetchService._();
  static final PrefetchService instance = PrefetchService._();

  static const Duration _entryTtl = Duration(minutes: 2);
  static const Duration _danmakuTtl = Duration(minutes: 5);
  static const Duration _waitLimit = Duration(seconds: 3);
  static const int _cacheMax = 30;
  static const int _headBytes = 2 * 1024 * 1024;

  final Map<String, _Entry> _entries = {}; // 依插入順序，最舊在前
  final Map<int, ({List<Map<String, dynamic>> list, DateTime at})> _danmaku =
      {};

  int _gen = 0;
  Object? _owner;
  _Entry? _active;
  CancelToken? _token;

  static bool _eligible(Video v) => v.bvid.isNotEmpty && !v.isLive && !v.isPgc;

  bool _fresh(_Entry e) => DateTime.now().difference(e.at) < _entryTtl;

  static String _key(String bvid, int cid, int qn, VideoCodec? codec) =>
      '$bvid|$cid|$qn|${codec?.name}|${SettingsService.codecFallbackAvc}|'
      '${SettingsService.preferredCodec.name}';

  /// 卡片焦點滿 0.3 秒後呼叫；同一時間只保留最新一個預載
  void schedule(Object owner, Video video) {
    if (!_eligible(video)) return;
    final existing = _entries[video.bvid];
    if (existing != null && _fresh(existing)) {
      if (identical(_active, existing)) {
        _owner = owner;
        return;
      }
      _abortActive();
      debugPrint('⚡ [Prefetch] skip (cached) ${video.bvid}');
      return;
    }
    _entries.remove(video.bvid);
    _abortActive();

    final gen = ++_gen;
    _owner = owner;
    final entry = _Entry(video.bvid);
    _entries[video.bvid] = entry;
    while (_entries.length > _cacheMax) {
      _entries.remove(_entries.keys.first);
    }
    _active = entry;
    final token = _token = CancelToken();
    debugPrint('⚡ [Prefetch] schedule ${video.bvid}');
    _run(entry, gen, token)
        .catchError((Object _) {
          // 預載失敗：靜默
        })
        .whenComplete(() {
          if (gen == _gen && identical(_active, entry)) {
            _active = null;
            _token = null;
          }
        });
  }

  /// 焦點離開卡片；只有該卡片是目前預載的擁有者才取消
  void cancel(Object owner) {
    if (!identical(_owner, owner)) return;
    _abortActive();
  }

  void _abortActive() {
    final active = _active;
    if (active == null) return;
    _gen++;
    _owner = null;
    _active = null;
    _token?.cancel();
    _token = null;
    if (!active.play.isCompleted) {
      _entries.remove(active.bvid);
      active.play.complete(null);
    }
    debugPrint('⚡ [Prefetch] cancel ${active.bvid}');
  }

  /// 播放頁離開時清掉該影片的快取（避免用到過期的進度與網址）
  void invalidate(String bvid) {
    final e = _entries.remove(bvid);
    if (e != null && !e.play.isCompleted) e.play.complete(null);
  }

  Future<void> _run(_Entry entry, int gen, CancelToken token) async {
    final bvid = entry.bvid;
    bool dead() => gen != _gen;

    void fail(String why) {
      debugPrint('⚡ [Prefetch] fail $bvid: $why');
      if (!entry.play.isCompleted) entry.play.complete(null);
    }

    // 1. 影片資訊
    final info = await BilibiliApi.getVideoInfo(bvid);
    if (dead()) return;
    if (info == null) return fail('info');
    entry.info = Map<String, dynamic>.of(info)..remove('history');
    entry.history = info['history'];

    // 2. cid：與播放器相同的優先序（API 歷史 > 本地進度快取 > info.cid）
    final cached = await PlaybackProgressCache.getCachedRecord(bvid);
    if (dead()) return;
    final cid = _pickCid(info, cached?.cid);
    if (cid == null || cid <= 0) return fail('cid');
    entry.cid = cid;

    // 3. 播放網址（最終 playInfo，含 VIP 升級）
    const qn = PlayParams.initialQn;
    entry.playKey = _key(bvid, cid, qn, null);
    final playInfo = await PlayParams.resolvePlayInfo(
      bvid: bvid,
      cid: cid,
      qn: qn,
      codec: null,
    );
    if (dead()) return fail('cancelled');
    if (playInfo == null || playInfo['error'] != null) {
      return fail('playurl');
    }
    final previewUrl = playInfo['previewUrl'];
    entry.previewOk =
        playInfo['isPreview'] != true &&
        playInfo['previewIsAvc'] == true &&
        previewUrl is String &&
        previewUrl.isNotEmpty;
    if (entry.previewOk) entry.previewUrl = previewUrl as String;
    entry.play.complete(playInfo);
    debugPrint('⚡ [Prefetch] playurl ready $bvid cid=$cid');

    // 4. 彈幕
    final known = _danmaku[cid];
    if (known == null || DateTime.now().difference(known.at) >= _danmakuTtl) {
      final danmaku = await BilibiliApi.getDanmaku(cid);
      if (dead()) return;
      _danmaku.remove(cid);
      _danmaku[cid] = (list: danmaku, at: DateTime.now());
      while (_danmaku.length > _cacheMax) {
        _danmaku.remove(_danmaku.keys.first);
      }
    }

    // 5. 媒體開頭暖機（關閉播放加速時略過）
    if (!BtrConfig.playback) {
      debugPrint('⚡ [Prefetch] done $bvid (API only)');
      return;
    }
    final dash = playInfo['dashData'];
    if (dash is Map) {
      final jobs = <Future<void>>[];
      final videos = dash['video'];
      if (videos is List && videos.isNotEmpty) {
        jobs.add(_warm(videos[0], token));
      }
      final audios = dash['audio'];
      final audioUrl = playInfo['audioUrl'];
      if (audios is List && audios.isNotEmpty) {
        // 與 MPD 實際放入的音訊串流一致（audioUrl 對應的那條，找不到用第一條）
        final match = audios.firstWhere(
          (a) => a is Map && (a['baseUrl'] ?? a['base_url']) == audioUrl,
          orElse: () => audios[0],
        );
        jobs.add(_warm(match, token));
      }
      await Future.wait(jobs);
    }
    if (dead()) return;
    debugPrint('⚡ [Prefetch] done $bvid');
  }

  static int? _pickCid(Map<String, dynamic> info, int? cachedCid) {
    int? cid = ((info['history'] as Map?)?['cid'] as num?)?.toInt();
    cid ??= cachedCid;
    cid ??= (info['cid'] as num?)?.toInt();
    if (cid == null) {
      final pages = info['pages'];
      if (pages is List && pages.isNotEmpty) {
        cid = (pages[0]['cid'] as num?)?.toInt();
      }
    }
    return cid;
  }

  // ---- 鄰近卡片背景預先解析（只抓 videoInfo 與 playurl，序列執行）----

  static const int _bgMax = 4;
  List<Video> _bgQueue = [];
  bool _bgRunning = false;

  /// 預先解析鄰近卡片；新呼叫取代尚未開始的舊佇列。
  /// 不抓 2MB 開頭與彈幕，不受 [cancel] 影響，不動 _active。
  void preResolve(List<Video> videos) {
    final queue = <Video>[];
    final seen = <String>{};
    for (final v in videos) {
      if (!_eligible(v) || !seen.add(v.bvid)) continue;
      final e = _entries[v.bvid];
      if (e != null && _fresh(e)) continue;
      queue.add(v);
      if (queue.length >= _bgMax) break;
    }
    _bgQueue = queue;
    if (queue.isEmpty) {
      debugPrint('⚡ [PreResolve] skip: all ${videos.length} candidates cached');
      return;
    }
    if (_bgRunning) {
      debugPrint('⚡ [PreResolve] skip: busy, queue replaced (${queue.length})');
      return;
    }
    _bgRunning = true;
    _drainBg();
  }

  Future<void> _drainBg() async {
    try {
      while (_bgQueue.isNotEmpty) {
        final v = _bgQueue.removeAt(0);
        final existing = _entries[v.bvid];
        if (existing != null && _fresh(existing)) continue;
        _entries.remove(v.bvid);
        final entry = _Entry(v.bvid);
        _entries[v.bvid] = entry;
        while (_entries.length > _cacheMax) {
          _entries.remove(_entries.keys.first);
        }
        try {
          // http 請求沒有逾時，加總時限避免卡住後 _bgRunning 永遠為 true
          await _runBg(entry).timeout(const Duration(seconds: 20));
        } catch (_) {
          // 預先解析失敗或逾時：靜默（逾時後 entry 一併移除，避免卡住等待者）
          if (identical(_entries[entry.bvid], entry) && entry.cid == null) {
            _entries.remove(entry.bvid);
          }
          if (!entry.play.isCompleted) entry.play.complete(null);
        }
      }
    } finally {
      _bgRunning = false;
    }
  }

  Future<void> _runBg(_Entry entry) async {
    final bvid = entry.bvid;
    bool dead() => !identical(_entries[bvid], entry);
    void fail(String why) {
      debugPrint('⚡ [PreResolve] fail $bvid: $why');
      if (!entry.play.isCompleted) entry.play.complete(null);
    }

    debugPrint('⚡ [PreResolve] start $bvid');
    final info = await BilibiliApi.getVideoInfo(bvid);
    if (dead()) return;
    if (info == null) return fail('info');
    entry.info = Map<String, dynamic>.of(info)..remove('history');
    entry.history = info['history'];

    final cached = await PlaybackProgressCache.getCachedRecord(bvid);
    if (dead()) return;
    final cid = _pickCid(info, cached?.cid);
    if (cid == null || cid <= 0) return fail('cid');
    entry.cid = cid;

    const qn = PlayParams.initialQn;
    entry.playKey = _key(bvid, cid, qn, null);
    final playInfo = await PlayParams.resolvePlayInfo(
      bvid: bvid,
      cid: cid,
      qn: qn,
      codec: null,
    );
    if (dead()) return fail('cancelled');
    if (playInfo == null || playInfo['error'] != null) {
      return fail('playurl');
    }
    final previewUrl = playInfo['previewUrl'];
    entry.previewOk =
        playInfo['isPreview'] != true &&
        playInfo['previewIsAvc'] == true &&
        previewUrl is String &&
        previewUrl.isNotEmpty;
    if (entry.previewOk) entry.previewUrl = previewUrl as String;
    entry.play.complete(playInfo);
    debugPrint('⚡ [PreResolve] done $bvid cid=$cid');
  }

  /// 不消耗地取得新鮮 entry 的影片資訊，並還原 history（續播 cid 與 prepare 一致）。
  /// 資訊指向番劇（redirect_url）時回 null，讓呼叫端自己取得並走原流程。
  Map<String, dynamic>? peekVideoInfo(String bvid) {
    final e = _entries[bvid];
    if (e == null || !_fresh(e)) return null;
    final info = e.info;
    if (info == null) return null;
    final redirectUrl = info['redirect_url'];
    if (redirectUrl is String &&
        redirectUrl.isNotEmpty &&
        PgcApi.parseBangumiUrl(redirectUrl) != null) {
      return null;
    }
    final result = Map<String, dynamic>.of(info);
    if (e.history != null) result['history'] = e.history;
    return result;
  }

  Future<void> _warm(dynamic stream, CancelToken token) async {
    if (stream is! Map) return;
    final url = (stream['baseUrl'] ?? stream['base_url'])?.toString();
    if (url == null || url.isEmpty) return;
    final backups = <String>[
      if (stream['backupUrl'] is List)
        for (final b in stream['backupUrl'])
          if (b is String && b.isNotEmpty) b,
    ];
    try {
      await BtrProxy.prefetchHead(
        url,
        backups: backups,
        bandwidth: int.tryParse('${stream['bandwidth']}') ?? 0,
        bytes: _headBytes,
        cancel: token,
      );
    } catch (_) {
      // 暖機失敗：靜默
    }
  }

  // ---- 查詢（播放器、卡片預覽使用）----

  /// 取得預載的最終 playInfo；參數須與預載完全相同，且只能取用一次。
  /// 預載仍在進行時最多等 3 秒。
  Future<Map<String, dynamic>?> takePlayUrl(
    String bvid,
    int cid,
    int qn,
    VideoCodec? codec,
  ) async {
    final e = _entries[bvid];
    if (e == null || !_fresh(e) || e.consumed) {
      debugPrint('⚡ [Prefetch] miss playurl $bvid (none)');
      return null;
    }
    final info = await e.play.future.timeout(_waitLimit, onTimeout: () => null);
    if (info == null || e.consumed || e.playKey != _key(bvid, cid, qn, codec)) {
      debugPrint('⚡ [Prefetch] miss playurl $bvid (mismatch or failed)');
      return null;
    }
    e.consumed = true;
    debugPrint('⚡ [Prefetch] hit playurl $bvid cid=$cid');
    return info;
  }

  /// 預載的彈幕；取用後移除（播放器會就地排序）
  List<Map<String, dynamic>>? takeDanmaku(int cid) {
    final d = _danmaku[cid];
    if (d == null || DateTime.now().difference(d.at) >= _danmakuTtl) {
      return null;
    }
    _danmaku.remove(cid);
    debugPrint('⚡ [Prefetch] hit danmaku cid=$cid');
    return d.list;
  }

  /// 預載的影片資訊（已去掉 history）
  Map<String, dynamic>? takeVideoInfo(String bvid) {
    final e = _entries[bvid];
    if (e == null || !_fresh(e)) return null;
    return e.info;
  }

  /// 預載得到的影片 cid（影片資訊裡的主 cid，供卡片預覽使用）
  int? peekInfoCid(String bvid) {
    final c = (takeVideoInfo(bvid)?['cid'] as num?)?.toInt();
    return (c != null && c > 0) ? c : null;
  }

  /// 預載得到的預覽串流網址（不消耗，可重複取）；沒有則回 null
  Future<String?> takePreviewUrl(String bvid) async {
    final e = _entries[bvid];
    if (e == null || !_fresh(e)) return null;
    await e.play.future.timeout(_waitLimit, onTimeout: () => null);
    if (!e.previewOk) return null;
    debugPrint('⚡ [Prefetch] hit preview $bvid');
    return e.previewUrl;
  }
}
