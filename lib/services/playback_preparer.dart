import 'package:flutter/foundation.dart' show debugPrint;
import 'package:video_player/video_player.dart';

import '../models/video.dart';
import 'api/base_api.dart';
import 'api/pgc_api.dart';
import 'bilibili_api.dart';
import 'btr/btr_proxy.dart';
import 'local_server.dart';
import 'mpd_generator.dart';
import 'perf_log.dart';
import 'play_params.dart';
import 'playback_perf.dart';
import 'playback_progress_cache.dart';
import 'prefetch_service.dart';
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
  });

  final String bvid;
  final VideoPlayerController controller;
  final Map<String, dynamic>? videoInfo;
  final int cid;
  final Map<String, dynamic> playInfo;

  /// 已 seek 到的續播秒數；0 表示從頭
  final int resumeSeconds;
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
  static Future<PrepareOutcome> prepare(
    Video video, {
    required int qn,
    bool warm = false,
    Map<String, dynamic>? videoInfo,
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

    final cachedRecord = await PlaybackProgressCache.getCachedRecord(bvid);
    if (cancelled()) return const PrepareOutcome(cancelled: true);

    // cid 優先序：API 歷史 > 本地快取 > info.cid > 第一個分 P > 另外查詢
    int? cid;
    if (videoInfo != null) {
      final history = videoInfo['history'];
      if (history != null && history['cid'] != null) {
        cid = history['cid'];
        debugPrint('🎬 [Init] Using API history cid: $cid');
      }
      if (cid == null && cachedRecord != null) {
        cid = cachedRecord.cid;
        debugPrint('🎬 [Init] Using LOCAL CACHE cid: $cid');
      }
      cid ??= videoInfo['cid'];
      final pages = videoInfo['pages'] ?? [];
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
      var playInfo = tryCodec == null
          ? await PrefetchService.instance.takePlayUrl(
              bvid,
              resolvedCid,
              currentQn,
              tryCodec,
            )
          : null;
      playInfo ??= await PlayParams.resolvePlayInfo(
        bvid: bvid,
        cid: resolvedCid,
        qn: currentQn,
        codec: tryCodec,
      );
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
            ? await BtrProxy.wrap(
                rawUrl,
                backups: backups,
                qn: (playInfo['currentQuality'] as num?)?.toInt() ?? 0,
              )
            : null;
      }
      // 被取消就不能覆寫 LocalServer 的 MPD
      if (cancelled()) return const PrepareOutcome(cancelled: true);

      final maxRetries = warm ? 1 : 3;
      const retryDelay = Duration(milliseconds: 1500);
      VideoPlayerController? controller;

      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          // setMpdContent 與建立 controller／initialize 之間不得有其他 await
          if (mpdContent != null) {
            LocalServer.instance.setMpdContent(mpdContent);
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

      // 續播進度：API 歷史 > 本地快取 > 列表傳入
      int historyProgress = 0;
      final history = videoInfo?['history'];
      if (history != null) {
        debugPrint(
          '🎬 [Resume] API History: cid=${history['cid']}, progress=${history['progress']}',
        );
        historyProgress = history['progress'] as int? ?? 0;
        final historyCid = history['cid'] as int?;
        if (historyCid != null && historyCid != resolvedCid) {
          debugPrint(
            '🎬 [Resume] CID mismatch: historyCid=$historyCid, cid=$resolvedCid - resetting progress',
          );
          historyProgress = 0;
        }
      } else {
        debugPrint('🎬 [Resume] No API history available');
      }
      if (historyProgress == 0 &&
          cachedRecord != null &&
          cachedRecord.cid == resolvedCid) {
        debugPrint(
          '🎬 [Resume] Using LOCAL CACHE: cid=${cachedRecord.cid}, progress=${cachedRecord.progress}',
        );
        historyProgress = cachedRecord.progress;
      }
      if (historyProgress == 0 && video.progress > 0) {
        debugPrint(
          '🎬 [Resume] Using list progress (fallback): ${video.progress}',
        );
        historyProgress = video.progress;
      }

      var resumeSeconds = 0;
      if (historyProgress > 0) {
        final duration = controller.value.duration.inSeconds;
        if (duration > 0 && historyProgress >= duration - 5) {
          debugPrint(
            '🎬 [Resume] Video was completed (progress $historyProgress >= duration $duration - 5), starting from beginning',
          );
        } else {
          resumeSeconds = historyProgress;
          try {
            await controller.seekTo(Duration(seconds: historyProgress));
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
        ),
      );
    }

    return PrepareOutcome(error: lastError ?? '無法取得播放網址，請稍後再試');
  }
}
