import 'package:flutter/foundation.dart' show debugPrint;
import 'package:video_player/video_player.dart';

import '../models/video.dart';
import 'api/base_api.dart';
import 'api/pgc_api.dart';
import 'api/playback_api.dart';
import 'bilibili_api.dart';
import 'btr/btr_proxy.dart';
import 'local_server.dart';
import 'mpd_generator.dart';
import 'perf_log.dart';
import 'play_params.dart';
import 'playback_perf.dart';
import 'playback_progress_cache.dart';
import 'prefetch_service.dart';
import 'resume_resolver.dart';
import 'settings_service.dart';

/// 已完成初始化、尚未播放的 UGC 播放資料（只含資料與 controller，不含任何 UI 副作用）
class PreparedPlayback {
  PreparedPlayback({
    required this.bvid,
    required this.controller,
    required this.videoInfo,
    required this.cid,
    required this.playInfo,
    required this.resumeSeconds,
    this.requestedQn = 0,
    this.mpdToken = 0,
  });

  final String bvid;
  final VideoPlayerController controller;
  final Map<String, dynamic>? videoInfo;
  final int cid;
  final Map<String, dynamic> playInfo;

  /// 已 seek 到的續播秒數；0 表示從頭
  final int resumeSeconds;

  /// 取得 [playInfo] 時請求的 qn（可能與 playInfo 的實際畫質不同）；
  /// 冷啟動沿用時必須與當時請求的 qn 相同才有效。
  final int requestedQn;

  /// 寫入 LocalServer 的 MPD token（沒有寫入為 0），供 clearMpdContentIf 使用
  final int mpdToken;
}

/// prepare 的結果；playback 為 null 時看其他欄位
class PrepareOutcome {
  const PrepareOutcome({
    this.playback,
    this.error,
    this.redirect = false,
    this.cancelled = false,
  });

  final PreparedPlayback? playback;
  final String? error;

  /// 此影片其實是番劇，呼叫端應走番劇流程
  final bool redirect;
  final bool cancelled;
}

/// 播放準備：網路請求 -> MPD -> controller -> initialize -> 續播 seek。
///
/// 不 setState、不 toast、不碰 PluginManager、不開計時器。
/// warm 為 true（焦點暖機）時初始化失敗不得寫入任何設定。
class PlaybackPreparer {
  PlaybackPreparer._();

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36';

  static bool _isDecoderError(Object? error) {
    if (error == null) return false;
    final msg = error.toString().toLowerCase();
    return msg.contains('mediacodec') || msg.contains('decoder');
  }

  /// [videoInfo] 已取得時傳入（呼叫端已處理 redirect）；null 則自行取得。
  /// [onHdrFallback] 非暖機時 HDR 解碼失敗、改以較低非 HDR 畫質重試後呼叫（由呼叫端 toast）。
  /// [onDecoderFallback] 非暖機時解碼器失敗、已改用 AVC 後呼叫（由呼叫端 toast）。
  /// [isCancelled] 在寫入 LocalServer 前與建立 controller 後檢查。
  /// [startCid] > 0 且在分 P 清單內時優先使用（合集換片、投放指定分 P）。
  /// [video.forceStartMs] 有值時，起播位置以它為準（投放）。
  /// [seed] 是被棄用的暖機結果：只讀它的 playInfo，且 cid 與請求 qn 都相同才沿用。
  static Future<PrepareOutcome> prepare(
    Video video, {
    required int qn,
    bool warm = false,
    Map<String, dynamic>? videoInfo,
    PreparedPlayback? seed,
    int startCid = 0,
    bool Function()? isCancelled,
    void Function(String step)? onStep,
    void Function()? onDecoderFallback,
    void Function()? onHdrFallback,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    void step(String s) => onStep?.call(s);
    final bvid = video.bvid;

    final fetchedHere = videoInfo == null;
    videoInfo ??= await BilibiliApi.getVideoInfo(bvid);
    step('videoInfo');
    if (cancelled()) return const PrepareOutcome(cancelled: true);

    if (fetchedHere) {
      final redirectUrl = videoInfo?['redirect_url'];
      if (redirectUrl is String &&
          redirectUrl.isNotEmpty &&
          PgcApi.parseBangumiUrl(redirectUrl) != null) {
        return const PrepareOutcome(redirect: true);
      }
    }

    // 第一輪（使用者編碼設定）的 playurl 來源：暖機留下的 > 預載 > 自行請求。
    // 暖機不消耗預載（consume: false），讓之後的播放頁仍能用。
    Future<Map<String, dynamic>?> fetchFirst(int c) async {
      if (seed != null && seed.cid == c && seed.requestedQn == qn) {
        debugPrint('⚡ [Startup] reuse warm playInfo cid=$c qn=$qn');
        return seed.playInfo;
      }
      final pre = await PrefetchService.instance.takePlayUrl(
        bvid,
        c,
        qn,
        null,
        consume: !warm,
      );
      if (pre != null) return pre;
      return PlayParams.resolvePlayInfo(
        bvid: bvid,
        cid: c,
        qn: qn,
        codec: null,
      );
    }

    // 與續播進度並行：先以 info.cid 發出 playurl；最後選定的 cid 相同才使用。
    final specCid = (videoInfo?['cid'] as num?)?.toInt();
    Future<Map<String, dynamic>?>? speculative;
    if (specCid != null && specCid > 0) {
      speculative = () async {
        try {
          return await fetchFirst(specCid);
        } catch (_) {
          return null;
        }
      }();
    }

    final cachedRecord = await PlaybackProgressCache.getCachedRecordWithTime(
      bvid,
    );
    if (cancelled()) return const PrepareOutcome(cancelled: true);

    // 伺服器續播進度（僅已登入才發請求，逾時 3 秒，失敗退回本地邏輯）
    ({int cid, int seconds})? serverProgress;
    final infoCid = (videoInfo?['cid'] as num?)?.toInt();
    if (videoInfo != null && infoCid != null) {
      serverProgress = await PlaybackApi.getPlayerProgress(
        bvid: bvid,
        aid: (videoInfo['aid'] as num?)?.toInt(),
        cid: infoCid,
        timeout: const Duration(seconds: 3),
      );
      if (cancelled()) return const PrepareOutcome(cancelled: true);
    }

    // cid 優先序：伺服器 last_play_cid（需在分 P 中）> 本地快取 > info.cid > 第一個分 P > 另外查詢
    int? cid;
    if (videoInfo != null) {
      final pages = videoInfo['pages'] ?? [];
      final server = serverProgress;
      if (startCid > 0 &&
          pages is List &&
          pages.any((p) => p is Map && p['cid'] == startCid)) {
        cid = startCid;
        debugPrint('🎬 [Init] Using startCid: $cid');
      } else if (server != null) {
        final inPages =
            pages is List &&
            pages.any((p) => p is Map && p['cid'] == server.cid);
        if (inPages || server.cid == infoCid) {
          cid = server.cid;
          debugPrint('🎬 [Init] Using SERVER last_play_cid: $cid');
        }
      }
      if (cid == null && cachedRecord != null) {
        cid = cachedRecord.cid;
        debugPrint('🎬 [Init] Using LOCAL CACHE cid: $cid');
      }
      cid ??= infoCid;
      if (cid == null && pages is List && pages.isNotEmpty) {
        cid = pages[0]['cid'];
      }
    }
    cid ??= await BilibiliApi.getVideoCid(bvid);
    step('cid');
    if (cancelled()) return const PrepareOutcome(cancelled: true);
    if (cid == null) return const PrepareOutcome(error: '獲取影片資訊失敗');
    final resolvedCid = cid;

    // 編碼器回退重試列表：null = 使用者設定優先，失敗後按相容性降級
    final userCodec = SettingsService.preferredCodec;
    final codecRetryList = <VideoCodec?>[
      null,
      VideoCodec.avc,
      VideoCodec.hevc,
      VideoCodec.av1,
    ];
    final uniqueCodecs = <VideoCodec?>[];
    final seen = <String>{};
    for (final codec in codecRetryList) {
      final key = codec?.name ?? 'user_setting';
      if (codec != null && userCodec != VideoCodec.auto && codec == userCodec) {
        continue;
      }
      if (!seen.contains(key)) {
        seen.add(key);
        uniqueCodecs.add(codec);
      }
    }

    String? lastError;
    var currentQn = qn;

    codecLoop:
    for (final tryCodec in uniqueCodecs) {
      if (SettingsService.codecFallbackAvc &&
          tryCodec != null &&
          tryCodec != VideoCodec.avc) {
        continue codecLoop;
      }

      // 只有第一輪（tryCodec == null）可使用焦點預載的結果
      Map<String, dynamic>? playInfo;
      if (tryCodec == null) {
        playInfo = (speculative != null && resolvedCid == specCid)
            ? await speculative
            : await fetchFirst(resolvedCid);
      } else {
        playInfo = await PlayParams.resolvePlayInfo(
          bvid: bvid,
          cid: resolvedCid,
          qn: currentQn,
          codec: tryCodec,
        );
      }
      step('playInfo');
      if (cancelled()) return const PrepareOutcome(cancelled: true);

      if (playInfo == null) {
        lastError = '無法取得播放網址，請稍後再試';
        continue codecLoop;
      }
      if (playInfo['error'] != null) {
        lastError = playInfo['error'];
        // B站業務錯誤（如地區限制）換編碼器也沒用
        if (playInfo['apiError'] == true) break codecLoop;
        continue codecLoop;
      }
      currentQn = playInfo['currentQuality'] ?? currentQn;
      final codecName = (playInfo['codec'] ?? '').toString();
      final isAvc = codecName.toLowerCase().startsWith('avc');

      String? mpdContent;
      String? playUrl;
      if (playInfo['dashData'] != null) {
        mpdContent = await MpdGenerator.generate(playInfo['dashData']);
      } else {
        final rawUrl = playInfo['url'] as String? ?? '';
        final backups =
            (playInfo['backupUrls'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        playUrl = rawUrl.isNotEmpty
            ? await BtrProxy.wrap(rawUrl, backups: backups)
            : null;
      }
      // 被取消就不能覆寫 LocalServer 的 MPD
      if (cancelled()) return const PrepareOutcome(cancelled: true);

      final maxRetries = warm ? 1 : 3;
      const retryDelay = Duration(milliseconds: 1500);
      VideoPlayerController? controller;
      var mpdToken = 0;

      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          // setMpdContent 與建立 controller／initialize 之間不得有其他 await
          if (mpdContent != null) {
            mpdToken = LocalServer.instance.setMpdContent(mpdContent);
            playUrl = LocalServer.instance.mpdUrl;
          }
          if (playUrl == null || playUrl.isEmpty) break;
          controller = VideoPlayerController.networkUrl(
            Uri.parse(playUrl),
            httpHeaders: {
              'User-Agent': _userAgent,
              'Referer': 'https://www.bilibili.com/',
              'Origin': 'https://www.bilibili.com',
              if (BaseApi.cookieHeader != null) 'Cookie': BaseApi.cookieHeader!,
            },
            viewType: warm
                ? VideoViewType.textureView
                : (SettingsService.playerTextureView
                      ? VideoViewType.textureView
                      : VideoViewType.platformView),
          );
          await controller.initialize();
          step('initialize');
          break;
        } catch (e) {
          await controller?.dispose();
          controller = null;

          if (warm) {
            // 暖機失敗：靜默，不改任何設定、不 toast
            debugPrint('🎬 [Warm] initialize failed: $e');
            return PrepareOutcome(error: '播放器初始化失敗: $e');
          }

          // HDR／10-bit 串流解碼失敗：不寫永久設定，改以較低非 HDR 畫質重試
          if (_isDecoderError(e) && !isAvc) {
            final video = (playInfo['dashData'] as Map?)?['video'];
            final stream =
                (video is List && video.isNotEmpty && video.first is Map)
                ? video.first as Map
                : null;
            if (isHdrStream(
              qn: currentQn,
              codecs: (stream?['codecs'] ?? '').toString(),
            )) {
              final hdrTarget = nonHdrFallbackQn(
                ((playInfo['qualities'] as List?) ?? const [])
                    .map((q) => ((q as Map)['qn'] as num?)?.toInt() ?? 0)
                    .where((q) => q > 0),
                currentQn,
              );
              if (hdrTarget != null) {
                debugPrint(
                  '🎬 [Codec] HDR decoder error during initialize: $e',
                );
                PerfLog.add('事件 HDR 解碼失敗 $currentQn->$hdrTarget');
                currentQn = hdrTarget;
                onHdrFallback?.call();
                lastError = '播放器初始化失敗: $e';
                continue codecLoop;
              }
            }
          }

          // 解碼器失敗且非 AVC：直接改用 AVC
          if (_isDecoderError(e) && !isAvc) {
            debugPrint('🎬 [Codec] Decoder error during initialize: $e');
            await SettingsService.setCodecFallbackAvc(true);
            onDecoderFallback?.call();
            lastError = '播放器初始化失敗: $e';
            continue codecLoop;
          }

          if (attempt < maxRetries) {
            debugPrint('影片初始化失敗 (嘗試 $attempt/$maxRetries): $e');
            await Future.delayed(retryDelay);
          } else {
            debugPrint('Codec execution failed: $e');
            lastError = '播放器初始化失敗: $e';
            continue codecLoop;
          }
        }
      }

      if (controller == null) {
        lastError = '無法取得播放網址，請稍後再試';
        continue codecLoop;
      }
      if (cancelled()) {
        await controller.dispose();
        return const PrepareOutcome(cancelled: true);
      }

      // 續播進度：伺服器 > 本地快取／列表（比新舊）
      final resume = ResumeResolver.resolve(
        resolvedCid: resolvedCid,
        serverCid: serverProgress?.cid,
        serverSeconds: serverProgress?.seconds,
        cacheCid: cachedRecord?.cid,
        cacheProgress: cachedRecord?.progress ?? 0,
        cacheSavedAt: cachedRecord?.savedAt ?? 0,
        listProgress: video.progress,
        listViewAt: video.viewAt,
      );
      final forcedMs = video.forceStartMs;
      final historyProgress = forcedMs != null
          ? forcedMs ~/ 1000
          : resume.seconds;
      debugPrint(
        '🎬 [Resume] source=${resume.source} progress=$historyProgress',
      );

      var resumeSeconds = 0;
      if (historyProgress > 0 || (forcedMs != null && forcedMs > 0)) {
        final duration = controller.value.duration.inSeconds;
        // 投放指定位置時不套用「接近片尾就從頭播」
        if (forcedMs == null &&
            duration > 0 &&
            historyProgress >= duration - 5) {
          debugPrint(
            '🎬 [Resume] Video was completed (progress $historyProgress >= duration $duration - 5), starting from beginning',
          );
        } else {
          resumeSeconds = historyProgress;
          try {
            await controller.seekTo(
              forcedMs != null
                  ? Duration(milliseconds: forcedMs)
                  : Duration(seconds: historyProgress),
            );
          } catch (_) {
            // seek 失敗：從頭播放
            resumeSeconds = 0;
          }
          if (cancelled()) {
            await controller.dispose();
            return const PrepareOutcome(cancelled: true);
          }
        }
      }

      return PrepareOutcome(
        playback: PreparedPlayback(
          bvid: bvid,
          controller: controller,
          videoInfo: videoInfo,
          cid: resolvedCid,
          playInfo: playInfo,
          resumeSeconds: resumeSeconds,
          requestedQn: qn,
          mpdToken: mpdToken,
        ),
      );
    }

    return PrepareOutcome(error: lastError ?? '無法取得播放網址，請稍後再試');
  }
}
