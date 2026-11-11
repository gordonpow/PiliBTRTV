import 'package:bili_tv_app/services/auth_service.dart';
import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:bili_tv_app/utils/zh_toast.dart';
import 'dart:async';
import 'dart:ffi' show Abi;
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:video_player/video_player.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/video.dart' as models;
import '../../../models/play_repeat.dart';
import '../../../models/nav_target.dart';
import '../../../services/play_session_history.dart';
import '../../../utils/ugc_season_utils.dart';
import '../../../services/bilibili_api.dart';
import '../../../services/settings_service.dart';
import '../../../services/audio_track.dart';
import '../../../services/codec_service.dart';
import '../../../services/mpd_generator.dart';
import '../../../services/local_server.dart';
import '../../../services/api/videoshot_api.dart';
import '../../../services/api/subtitle_api.dart';
import '../../../services/translate/content_translator.dart';
import '../../../models/subtitle.dart';
import '../../../services/api/base_api.dart';
import '../widgets/settings_panel.dart';
import '../../../widgets/video_action_dialogs.dart';
import '../player_screen.dart';
import '../widgets/quality_picker_sheet.dart';
import 'player_state_mixin.dart';
import '../../../core/plugin/plugin_manager.dart';
import '../../../core/plugin/plugin_types.dart';
import '../../../services/playback_progress_cache.dart';
import '../../../services/btr/btr_proxy.dart';
import '../../../services/frame_service.dart';
import '../../../services/api/pgc_api.dart';
import '../../../services/play_params.dart';
import '../../../services/prefetch_service.dart';
import '../../../services/card_preview_service.dart';
import '../../../services/playback_preparer.dart';
import '../../../services/playback_perf.dart';
import '../../../services/perf_log.dart';
import '../../../services/btr/btr_config.dart';
import '../../../utils/seek_speed.dart';

/// 播放器邏輯 Mixin
mixin PlayerActionMixin on PlayerStateMixin {
  // 初始化
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      danmakuEnabled = prefs.getBool('danmaku_enabled') ?? true;
      danmakuOpacity = prefs.getDouble('danmaku_opacity') ?? 0.6;
      danmakuFontSize = prefs.getDouble('danmaku_font_size') ?? 17.0;
      danmakuArea = prefs.getDouble('danmaku_area') ?? 0.25;
      danmakuSpeed = prefs.getDouble('danmaku_speed') ?? 10.0;
      hideTopDanmaku = prefs.getBool('hide_top_danmaku') ?? false;
      hideBottomDanmaku = prefs.getBool('hide_bottom_danmaku') ?? false;
      // 根據設定決定是否顯示控制欄
      showControls = !SettingsService.hideControlsOnStart;
      updateDanmakuOption();
    });
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('danmaku_enabled', danmakuEnabled);
    await prefs.setDouble('danmaku_opacity', danmakuOpacity);
    await prefs.setDouble('danmaku_font_size', danmakuFontSize);
    await prefs.setDouble('danmaku_area', danmakuArea);
    await prefs.setDouble('danmaku_speed', danmakuSpeed);
    await prefs.setBool('hide_top_danmaku', hideTopDanmaku);
    await prefs.setBool('hide_bottom_danmaku', hideBottomDanmaku);
  }

  Future<void> initializePlayer() async {
    final startupWatch = Stopwatch()..start();
    // 換片：先重設音軌，避免舊 controller 殘留的錯誤事件以舊音軌觸發退回
    currentAudioKind = AudioKind.standard;
    void mark(String step) =>
        debugPrint('⏱ [Startup] $step ${startupWatch.elapsedMilliseconds}ms');
    cancelUpNext();
    setState(() {
      isLoading = true;
      errorMessage = null;
      hasHandledVideoComplete = false; // 重置播放完成標誌
    });

    try {
      // 只有 epId 沒有 seasonId：先以 epId 查出 seasonId 再轉向番劇模式
      if (widget.video.seasonId == 0 && widget.video.epId > 0) {
        final season = await BilibiliApi.getPgcSeason(epId: widget.video.epId);
        final sid = season['seasonId'] as int? ?? 0;
        if (season['error'] == null && sid > 0) {
          _redirectToPgc(sid, widget.video.epId);
          return;
        }
        if (!mounted) return;
        setState(() {
          errorMessage = season['error'] ?? '此番劇目前沒有可播放的集數';
          isLoading = false;
        });
        return;
      }

      // UGC：接手暖機播放器，或由 PlaybackPreparer 準備後套用（見 _initializeUgc）
      if (!isPgc) {
        await _initializeUgc(mark);
        return;
      }

      // 番劇不走 UGC 的 view API，改由季資訊取得集數
      final videoInfo = isPgc
          ? null
          : await BilibiliApi.getVideoInfo(widget.video.bvid);
      mark('videoInfo');

      // UGC 影片其實是番劇時（view API 帶 redirect_url），轉向番劇播放
      final redirectUrl = videoInfo?['redirect_url'];
      if (redirectUrl is String && redirectUrl.isNotEmpty) {
        final target = PgcApi.parseBangumiUrl(redirectUrl);
        if (target != null) {
          var sid = target.seasonId;
          if (sid == 0) {
            final season = await BilibiliApi.getPgcSeason(epId: target.epId);
            if (season['error'] == null) {
              sid = season['seasonId'] as int? ?? 0;
            }
          }
          if (sid > 0) {
            _redirectToPgc(sid, target.epId);
            return;
          }
          // 查不到 season：繼續原本的 UGC 流程
        }
      }

      // 🔥 預先獲取本地快取（在 setState 外部執行 async 操作）
      final cachedRecord = await PlaybackProgressCache.getCachedRecord(
        progressCacheKey,
      );

      if (isPgc) {
        final ok = await _setupPgcSeason(cachedRecord);
        if (!ok) return;
      }

      if (videoInfo != null) {
        if (mounted) {
          setState(() {
            fullVideoInfo = videoInfo; // 儲存完整影片資訊
            episodes = videoInfo['pages'] ?? [];

            // 優先檢查歷史記錄中的 cid
            if (videoInfo['history'] != null &&
                videoInfo['history']['cid'] != null) {
              cid = videoInfo['history']['cid'];
              debugPrint('🎬 [Init] Using API history cid: $cid');
            }

            // 🔥 如果 API 沒有返回歷史記錄，檢查本地快取
            if (cid == null && cachedRecord != null) {
              cid = cachedRecord.cid;
              debugPrint('🎬 [Init] Using LOCAL CACHE cid: $cid');
            }

            cid ??= videoInfo['cid'];
            aid = videoInfo['aid']; // 儲存 aid 用於操作 API

            // 由合集換片時，指定從該部影片的第 1 個分P開始
            final startCid = widget.startCid;
            if (startCid > 0 && episodes.any((e) => e['cid'] == startCid)) {
              cid = startCid;
            }
          });
          if (cid == null && episodes.isNotEmpty) {
            cid = episodes[0]['cid'];
          }

          // 獲取線上人數（首次獲取 + 每60秒更新）
          _fetchOnlineCount();
          onlineCountTimer?.cancel();
          onlineCountTimer = Timer.periodic(
            const Duration(seconds: 60),
            (_) => _fetchOnlineCount(),
          );
        }
      }

      if (!isPgc) cid ??= await BilibiliApi.getVideoCid(widget.video.bvid);
      mark('cid');

      if (cid == null) {
        setState(() {
          errorMessage = '獲取影片資訊失敗';
          isLoading = false;
        });
        return;
      }

      // 立即啟動快照資料預載入 (並行執行)
      loadVideoshot();

      // Initialize focus index based on cid
      if (episodes.isNotEmpty) {
        final idx = episodes.indexWhere((e) => e['cid'] == cid);
        if (idx != -1) focusedEpisodeIndex = idx;
      }

      // 非同步載入相關影片 (用於自動連播)；番劇不載入推薦
      if (!isPgc) {
        BilibiliApi.getRelatedVideos(widget.video.bvid).then((videos) {
          if (mounted) {
            relatedVideos = videos
                .map(
                  (v) => {
                    'bvid': v.bvid,
                    'title': v.title,
                    'pic': v.pic,
                    'duration': v.duration,
                    'pubdate': v.pubdate,
                    'owner': {'name': v.ownerName, 'face': v.ownerFace},
                    'stat': {'view': v.view},
                  },
                )
                .toList();
          }
        });
      }

      // 編碼器回退重試列表:
      // 1. null = 使用者設定優先（自動則按硬體最優 AV1>HEVC>AVC）
      // 2. 失敗後按相容性降級: AVC > HEVC > AV1
      final userCodec = SettingsService.preferredCodec;
      final codecRetryList = <VideoCodec?>[
        null, // 首次：使用者設定（自動=智慧硬解）
        VideoCodec.avc, // H.264 (相容性最好)
        VideoCodec.hevc, // HEVC
        VideoCodec.av1, // AV1
      ];

      // 去重（跳過和使用者設定相同的，因為首次已經用過）
      final uniqueCodecs = <VideoCodec?>[];
      final seen = <String>{};
      for (final codec in codecRetryList) {
        final key = codec?.name ?? 'user_setting';
        if (codec != null &&
            userCodec != VideoCodec.auto &&
            codec == userCodec) {
          continue;
        }
        if (!seen.contains(key)) {
          seen.add(key);
          uniqueCodecs.add(codec);
        }
      }

      String? lastError;

      // 嘗試每個編碼器
      codecLoop:
      for (final tryCodec in uniqueCodecs) {
        // 若已觸發自動降級到 AVC，略過非 AVC 選項
        if (SettingsService.codecFallbackAvc &&
            tryCodec != null &&
            tryCodec != VideoCodec.avc) {
          continue codecLoop;
        }

        // 初次 qn 請求 + VIP 智慧升級（邏輯見 PlayParams）。
        // 只有第一輪（tryCodec == null）的 UGC 影片可使用焦點預載的結果。
        var playInfo = (!isPgc && tryCodec == null)
            ? await PrefetchService.instance.takePlayUrl(
                playingBvid,
                cid!,
                currentQuality,
                tryCodec,
              )
            : null;
        playInfo ??= await PlayParams.resolvePlayInfo(
          bvid: playingBvid,
          cid: cid!,
          qn: currentQuality,
          codec: tryCodec,
          epId: isPgc ? currentEpId : null,
        );
        mark('playInfo');

        if (playInfo == null) {
          lastError = '無法取得播放網址，請稍後再試';
          continue codecLoop;
        }

        // 檢查是否返回了錯誤資訊
        if (playInfo['error'] != null) {
          lastError = playInfo['error'];
          // B站業務錯誤 (如 -10403 地區限制) 換編碼器也沒用，直接顯示訊息
          if (playInfo['apiError'] == true) break codecLoop;
          continue codecLoop;
        }

        if (!mounted) return;
        isPreview = playInfo['isPreview'] == true;
        if (isPreview) {
          showZhToast(msg: '此集為大會員專屬，目前僅提供試看', toastLength: Toast.LENGTH_LONG);
        }
        qualities = List<Map<String, dynamic>>.from(
          playInfo['qualities'] ?? [],
        );
        currentQuality = playInfo['currentQuality'] ?? 80;
        currentCodec = playInfo['codec'] ?? '';
        _recordStream(playInfo);
        currentAudioUrl = playInfo['audioUrl'];
        recordAudio(playInfo);
        previewFrameUrl = playInfo['previewUrl'] as String?;

        String? playUrl;

        // 如果有 DASH 資料，生成 MPD 並使用全域性伺服器
        if (playInfo['dashData'] != null) {
          final mpdContent = await MpdGenerator.generate(playInfo['dashData']);

          // 使用全域性 LocalServer 提供 MPD 內容 (純記憶體)
          LocalServer.instance.setMpdContent(mpdContent);
          playUrl = LocalServer.instance.mpdUrl;
        } else {
          // 回退到直接 URL (mp4/flv)
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

        if (playUrl == null || playUrl.isEmpty) {
          lastError = '無法取得播放網址，請稍後再試';
          continue codecLoop;
        }

        // 建立 VideoPlayerController (帶重試邏輯)
        const maxRetries = 3;
        const retryDelay = Duration(milliseconds: 1500);

        for (int attempt = 1; attempt <= maxRetries; attempt++) {
          try {
            videoController = VideoPlayerController.networkUrl(
              Uri.parse(playUrl),
              httpHeaders: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
                'Referer': 'https://www.bilibili.com/',
                'Origin': 'https://www.bilibili.com',
                if (BaseApi.cookieHeader != null)
                  'Cookie': BaseApi.cookieHeader!,
              },
              viewType: SettingsService.playerTextureView
                  ? VideoViewType.textureView
                  : VideoViewType.platformView,
            );

            // 初始化
            await videoController!.initialize();
            mark('initialize');
            break; // 成功，跳出迴圈
          } catch (e) {
            // 清理失敗的控制器
            await videoController?.dispose();
            videoController = null;

            // HDR／10-bit 串流解碼失敗：不寫永久設定，改以較低非 HDR 畫質重試
            if (_isDecoderError(e) && !isCurrentCodecAvc) {
              final hdrTarget = _hdrFallbackTarget();
              if (hdrTarget != null) {
                debugPrint(
                  '🎬 [Codec] HDR decoder error during initialize: $e',
                );
                PerfLog.add('事件 HDR 解碼失敗 $currentQuality->$hdrTarget');
                showZhToast(
                  msg: '此裝置無法播放 HDR，已改用較低畫質',
                  toastLength: Toast.LENGTH_LONG,
                );
                currentQuality = hdrTarget;
                lastError = '播放器初始化失敗: $e';
                continue codecLoop;
              }
            }

            // 解碼器失敗 (MediaCodec / Decoder) 且非 AVC：直接改用 AVC，不浪費時間重試同編碼
            if (_isDecoderError(e) && !isCurrentCodecAvc) {
              debugPrint('🎬 [Codec] Decoder error during initialize: $e');
              await SettingsService.setCodecFallbackAvc(true);
              showZhToast(
                msg: '此裝置無法解碼 H.265／AV1，已改用 H.264',
                toastLength: Toast.LENGTH_LONG,
              );
              lastError = '播放器初始化失敗: $e';
              continue codecLoop;
            }

            if (attempt < maxRetries) {
              // 還有重試機會，等待後重試
              debugPrint('影片初始化失敗 (嘗試 $attempt/$maxRetries): $e');
              await Future.delayed(retryDelay);
            } else {
              // 重試次數用盡，嘗試下一個編碼器
              debugPrint('Codec execution failed: $e');
              lastError = '播放器初始化失敗: $e';
              continue codecLoop;
            }
          }
        }

        if (!mounted) return;

        // 監聽播放狀態變化
        _setupPlayerListeners();

        // 初始化外掛
        final plugins = PluginManager().getEnabledPlugins<PlayerPlugin>();
        for (var plugin in plugins) {
          plugin.onVideoLoad(playingBvid, cid!);
        }

        setState(() {
          isLoading = false;
        });

        // 自動續播:
        // 1. 如果 API 返回了歷史記錄，無條件使用歷史記錄的進度 (解決多端同步和本地列表過期問題)
        // 2. 如果沒有 API 歷史，才使用本地列表傳進來的 progress
        int historyProgress = 0;
        if (videoInfo != null && videoInfo['history'] != null) {
          final historyData = videoInfo['history'];
          debugPrint(
            '🎬 [Resume] API History: cid=${historyData['cid']}, progress=${historyData['progress']}',
          );
          historyProgress = historyData['progress'] as int? ?? 0;
          // 再次確認 CID 匹配 (一般都匹配，因為前面已經強行切換 CID 了)
          final historyCid = historyData['cid'] as int?;
          if (historyCid != null && historyCid != cid) {
            // 如果歷史記錄的 CID 和當前 CID 不一致（理論上不該發生，防止萬一），不自動跳轉進度以防錯亂
            debugPrint(
              '🎬 [Resume] CID mismatch: historyCid=$historyCid, cid=$cid - resetting progress',
            );
            historyProgress = 0;
          }
        } else {
          debugPrint('🎬 [Resume] No API history available');
        }

        // 2. 🔥 優先使用本地快取（比列表資料更新鮮）
        if (historyProgress == 0 &&
            cachedRecord != null &&
            cachedRecord.cid == cid) {
          debugPrint(
            '🎬 [Resume] Using LOCAL CACHE: cid=${cachedRecord.cid}, progress=${cachedRecord.progress}',
          );
          historyProgress = cachedRecord.progress;
        }

        // 番劇：季資訊提供的續播進度
        if (historyProgress == 0 && isPgc && pgcResumeProgress > 0) {
          historyProgress = pgcResumeProgress;
          pgcResumeProgress = 0;
        }

        // 3. 最後兜底：使用列表傳入的 progress（可能是舊資料）
        if (historyProgress == 0 && widget.video.progress > 0) {
          debugPrint(
            '🎬 [Resume] Using list progress (fallback): ${widget.video.progress}',
          );
          historyProgress = widget.video.progress;
        }

        if (historyProgress > 0) {
          // 🔥 如果進度接近影片總時長（最後5秒內），說明影片已播完，從頭開始
          final videoDuration = videoController!.value.duration.inSeconds;
          if (videoDuration > 0 && historyProgress >= videoDuration - 5) {
            debugPrint(
              '🎬 [Resume] Video was completed (progress $historyProgress >= duration $videoDuration - 5), starting from beginning',
            );
            // 不 seek，直接從頭開始播放
          } else {
            initialProgress = historyProgress;

            final seekPos = Duration(seconds: historyProgress);
            await videoController!.seekTo(seekPos);
            resetDanmakuIndex(seekPos);

            final min = historyProgress ~/ 60;
            final sec = historyProgress % 60;
            showZhToast(
              msg:
                  '從${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}繼續播放',
              toastLength: Toast.LENGTH_SHORT,
            );
          }
        }

        await videoController!.play();
        mark('play');
        startHideTimer();

        await loadDanmaku();
        unawaited(loadSubtitles());
        return; // 成功，退出
      } // codecLoop 結束

      // 所有編碼器都失敗了
      throw Exception(lastError ?? '無法取得播放網址，請稍後再試');
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString().replaceFirst('Exception: ', '');
          isLoading = false;
        });
      }
    }
  }

  /// UGC 初始化：先用卡片暖機好的播放器；沒有就自己 prepare。之後共用 [_adoptPlayback]。
  Future<void> _initializeUgc(void Function(String) mark) async {
    var prepared = warmPlayback;
    warmPlayback = null;
    // 按 OK 時暖機還在準備：等它完成後接手（比從頭再準備一次快）
    // 「原生」畫面模式不接手 textureView 暖機播放器（見 PlayerScreen.initState）
    if (prepared == null &&
        SettingsService.playerTextureView &&
        CardPreviewService.instance.isPendingFor(widget.video.bvid)) {
      prepared = await CardPreviewService.instance.waitAndTake(
        widget.video.bvid,
      );
      if (!mounted) {
        prepared?.controller.dispose();
        return;
      }
      if (prepared != null) mark('waited warm');
    }
    final fromWarm = prepared != null;

    if (fromWarm) {
      mark('adopted');
    } else {
      final videoInfo = await BilibiliApi.getVideoInfo(widget.video.bvid);
      mark('videoInfo');

      // UGC 影片其實是番劇時（view API 帶 redirect_url），轉向番劇播放
      final redirectUrl = videoInfo?['redirect_url'];
      if (redirectUrl is String && redirectUrl.isNotEmpty) {
        final target = PgcApi.parseBangumiUrl(redirectUrl);
        if (target != null) {
          var sid = target.seasonId;
          if (sid == 0) {
            final season = await BilibiliApi.getPgcSeason(epId: target.epId);
            if (season['error'] == null) {
              sid = season['seasonId'] as int? ?? 0;
            }
          }
          if (sid > 0) {
            _redirectToPgc(sid, target.epId);
            return;
          }
          // 查不到 season：繼續原本的 UGC 流程
        }
      }

      final outcome = await PlaybackPreparer.prepare(
        widget.video,
        qn: currentQuality,
        videoInfo: videoInfo,
        isCancelled: () => !mounted,
        onStep: mark,
        onDecoderFallback: () => showZhToast(
          msg: '此裝置無法解碼 H.265／AV1，已改用 H.264',
          toastLength: Toast.LENGTH_LONG,
        ),
        onHdrFallback: () => showZhToast(
          msg: '此裝置無法播放 HDR，已改用較低畫質',
          toastLength: Toast.LENGTH_LONG,
        ),
      );
      prepared = outcome.playback;
      if (prepared == null) {
        if (outcome.cancelled) return;
        if (outcome.redirect) throw Exception('無法取得播放網址，請稍後再試');
        // 與原流程相同：cid 取不到時直接顯示錯誤，其餘丟出由外層處理
        if (outcome.error == '獲取影片資訊失敗') {
          if (!mounted) return;
          setState(() {
            errorMessage = outcome.error;
            isLoading = false;
          });
          return;
        }
        throw Exception(outcome.error ?? '無法取得播放網址，請稍後再試');
      }
    }

    if (!mounted) {
      await prepared.controller.dispose();
      return;
    }
    await _adoptPlayback(prepared, fromWarm, mark);
  }

  /// 接手已初始化的播放資料：套用狀態、掛 listener、開始播放。
  /// [fromWarm] 為 true 時沿用暖機播放器目前的位置，不 seek 回去（避免丟緩衝）。
  Future<void> _adoptPlayback(
    PreparedPlayback p,
    bool fromWarm,
    void Function(String) mark,
  ) async {
    final videoInfo = p.videoInfo;
    final playInfo = p.playInfo;
    final controller = p.controller;
    videoController = controller;

    setState(() {
      cid = p.cid;
      if (videoInfo != null) {
        fullVideoInfo = videoInfo; // 儲存完整影片資訊
        episodes = videoInfo['pages'] ?? [];
        aid = videoInfo['aid']; // 儲存 aid 用於操作 API
      }
    });

    // 獲取線上人數（首次獲取 + 每60秒更新）
    if (videoInfo != null) {
      _fetchOnlineCount();
      onlineCountTimer?.cancel();
      onlineCountTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _fetchOnlineCount(),
      );
    }

    // 立即啟動快照資料預載入 (並行執行)
    loadVideoshot();

    if (episodes.isNotEmpty) {
      final idx = episodes.indexWhere((e) => e['cid'] == cid);
      if (idx != -1) focusedEpisodeIndex = idx;
    }

    // 非同步載入相關影片 (用於自動連播)
    BilibiliApi.getRelatedVideos(widget.video.bvid).then((videos) {
      if (mounted) {
        relatedVideos = videos
            .map(
              (v) => {
                'bvid': v.bvid,
                'title': v.title,
                'pic': v.pic,
                'duration': v.duration,
                'pubdate': v.pubdate,
                'owner': {'name': v.ownerName, 'face': v.ownerFace},
                'stat': {'view': v.view},
              },
            )
            .toList();
      }
    });

    isPreview = playInfo['isPreview'] == true;
    if (isPreview) {
      showZhToast(msg: '此集為大會員專屬，目前僅提供試看', toastLength: Toast.LENGTH_LONG);
    }
    qualities = List<Map<String, dynamic>>.from(playInfo['qualities'] ?? []);
    currentQuality = playInfo['currentQuality'] ?? 80;
    currentCodec = playInfo['codec'] ?? '';
    _recordStream(playInfo);
    currentAudioUrl = playInfo['audioUrl'];
    recordAudio(playInfo);
    previewFrameUrl = playInfo['previewUrl'] as String?;

    // 暖機播放器正在靜音播放：先立刻顯示畫面並開聲音，不等平台呼叫回來，
    // 其餘初始化放在後面，避免拖慢「按 OK 到看到畫面」
    if (fromWarm) {
      setState(() => isLoading = false);
      mark('shown');
      unawaited(controller.setVolume(1.0));
      unawaited(controller.play());
    }

    // 監聽播放狀態變化
    _setupPlayerListeners();

    // 初始化外掛
    final plugins = PluginManager().getEnabledPlugins<PlayerPlugin>();
    for (var plugin in plugins) {
      plugin.onVideoLoad(playingBvid, p.cid);
    }

    setState(() {
      isLoading = false;
    });

    // 續播：prepare 已 seek 好。暖機接手時以目前位置為準。
    final startPos = fromWarm
        ? controller.value.position
        : Duration(seconds: p.resumeSeconds);
    if (p.resumeSeconds > 0) initialProgress = p.resumeSeconds;
    resetDanmakuIndex(startPos);
    final startSec = startPos.inSeconds;
    // 暖機的位置包含卡片預覽播過的秒數，只有真的有續播紀錄才提示
    if (startSec > 0 && (!fromWarm || p.resumeSeconds > 0)) {
      final min = startSec ~/ 60;
      final sec = startSec % 60;
      showZhToast(
        msg:
            '從${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}繼續播放',
        toastLength: Toast.LENGTH_SHORT,
      );
    }

    await controller.play();
    mark('play');
    startHideTimer();

    await loadDanmaku();
    unawaited(loadSubtitles());
  }

  /// 轉向番劇播放：以新的 PlayerScreen 取代目前頁面（尚未建立 videoController）。
  void _redirectToPgc(int seasonId, int epId) {
    debugPrint('🎬 [PGC] redirect to season=$seasonId ep=$epId');
    if (!mounted || upSpaceOpen) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          video: models.Video(
            bvid: '',
            title: widget.video.title,
            pic: widget.video.pic,
            seasonId: seasonId,
            epId: epId,
          ),
        ),
      ),
    );
  }

  /// 番劇：載入季資訊，設定集數、起始集與續播進度。失敗時顯示錯誤並回傳 false。
  Future<bool> _setupPgcSeason(({int cid, int progress})? cachedRecord) async {
    var season = await BilibiliApi.getPgcSeason(
      seasonId: widget.video.seasonId,
    );
    // seasonId 查不到（例如 kid 不是 season_id）時，以 epId 再查一次
    if (season['error'] != null && widget.video.epId > 0) {
      season = await BilibiliApi.getPgcSeason(epId: widget.video.epId);
    }
    if (!mounted) return false;
    final eps = (season['episodes'] as List?) ?? [];
    if (season['error'] != null || eps.isEmpty) {
      setState(() {
        errorMessage = season['error'] ?? '此番劇目前沒有可播放的集數';
        isLoading = false;
      });
      return false;
    }

    // 起始集：伺服器觀看紀錄 > 本地快取 > 列表帶入的 ep > 第一集
    final lastEpId = season['lastEpId'] as int? ?? 0;
    var startIdx = lastEpId > 0
        ? eps.indexWhere((e) => e['ep_id'] == lastEpId)
        : -1;
    var resume = startIdx != -1 ? (season['lastTime'] as int? ?? 0) : 0;
    if (startIdx == -1 && cachedRecord != null) {
      startIdx = eps.indexWhere((e) => e['cid'] == cachedRecord.cid);
      if (startIdx != -1) resume = cachedRecord.progress;
    }
    if (startIdx == -1 && widget.video.epId > 0) {
      startIdx = eps.indexWhere((e) => e['ep_id'] == widget.video.epId);
    }
    if (startIdx == -1) startIdx = 0;

    setState(() {
      episodes = List<dynamic>.from(eps);
      pgcSeasonTitle = season['title'] as String? ?? '';
      cid = eps[startIdx]['cid'] as int;
      pgcResumeProgress = resume;
      fullVideoInfo = {'title': pgcSeasonTitle};
    });
    _applyPgcEpisode(cid!);
    debugPrint(
      '🎬 [PGC] season=${widget.video.seasonId} ep=$currentEpId cid=$cid resume=$resume',
    );
    return true;
  }

  /// 載入 CC 字幕軌並依設定自動選軌（R-10：不阻塞播放，以 cid＋subtitleGen 作廢）。
  Future<void> loadSubtitles() async {
    final forCid = cid;
    if (forCid == null) return;
    // 同一部影片已載入（或載入中）就不重置，避免覆蓋使用者已選的軌
    if (subtitleCid == forCid) return;
    subtitleCid = forCid;
    subtitleUserPicked = false;
    final gen = ++subtitleGen;
    if (mounted &&
        (subtitleTracks.isNotEmpty ||
            subtitleLines.isNotEmpty ||
            subtitleIndex != -1)) {
      setState(() {
        subtitleTracks = [];
        subtitleLines = [];
        subtitleIndex = -1;
        _clampSettingsFocus();
      });
    }
    bool stale() => !mounted || gen != subtitleGen || forCid != cid;
    subtitleLoading = true;
    try {
      final tracks = await SubtitleApi.getSubtitles(
        aid: aid,
        cid: forCid,
        bvid: playingBvid,
        epId: isPgc ? currentEpId : null,
        seasonId: isPgc ? widget.video.seasonId : null,
      );
      if (stale()) return;
      if (tracks.isEmpty) {
        subtitleCid = null; // 允許之後重試
        return;
      }
      final english = ZhConvert.script == ZhScript.english;
      final machine = machineTrackAvailable(
        tracks,
        englishUi: english,
        translatorEnabled: ContentTranslator.instance.enabled,
      );
      final all = [...tracks, if (machine) SubtitleTrack.machineEnglish];
      setState(() {
        subtitleTracks = all;
        _clampSettingsFocus();
      });
      if (!SettingsService.subtitleEnabled) return;
      // 英文介面且有機器翻譯軌時，優先於中文軌
      var idx = pickDefaultSubtitle(tracks, english: english);
      if (machine && (idx < 0 || !tracks[idx].isEnglish)) {
        idx = all.length - 1;
      }
      if (idx >= 0) await _applySubtitleTrack(idx, gen);
    } catch (e) {
      debugPrint('Failed to load subtitles: $e');
    } finally {
      // 只有最新一次載入才能收旗標（舊的已被作廢，新的自己會管）
      if (gen == subtitleGen) subtitleLoading = false;
    }
  }

  /// 翻譯模型在播放中才就緒（enabled 變 true）：補上機器翻譯軌，使用者沒手選過
  /// 軌時自動改選它（預設選軌發生在 enabled 之前）。
  void onTranslatorChanged() {
    if (!mounted || subtitleTracks.isEmpty) return;
    if (subtitleTracks.any((t) => t.machine)) return;
    final real = subtitleTracks.where((t) => !t.machine).toList();
    final machine = machineTrackAvailable(
      real,
      englishUi: ZhConvert.script == ZhScript.english,
      translatorEnabled: ContentTranslator.instance.enabled,
    );
    if (!machine) return;
    setState(() {
      subtitleTracks = [...subtitleTracks, SubtitleTrack.machineEnglish];
      _clampSettingsFocus();
    });
    if (subtitleUserPicked || !SettingsService.subtitleEnabled) return;
    final idx = subtitleTracks.length - 1;
    unawaited(_applySubtitleTrack(idx, ++subtitleGen));
  }

  /// 目前字幕軌清單中的預設軌索引（含機器翻譯軌）；沒有可選的回 -1。
  int defaultSubtitleIndex() {
    final tracks = subtitleTracks.where((t) => !t.machine).toList();
    final english = ZhConvert.script == ZhScript.english;
    var idx = pickDefaultSubtitle(tracks, english: english);
    final machineIdx = subtitleTracks.indexWhere((t) => t.machine);
    if (machineIdx >= 0 && (idx < 0 || !tracks[idx].isEnglish)) {
      return machineIdx;
    }
    if (idx < 0 && subtitleTracks.isNotEmpty) return 0;
    return idx;
  }

  /// 控制列字幕按鈕短按：有字幕軌時開／關，沒有時依狀態 toast。
  void onSubtitleButton() {
    if (subtitleTracks.isEmpty) {
      showZhToast(
        msg: subtitleLoading
            ? '字幕載入中…'
            : AuthService.isLoggedIn
            ? '此影片沒有字幕'
            : '登入後才能取得字幕',
      );
      return;
    }
    if (subtitleIndex >= 0) {
      selectSubtitle(-1);
      showZhToast(msg: '字幕已關閉');
    } else {
      selectSubtitle(defaultSubtitleIndex());
      showZhToast(msg: '字幕已開啟');
    }
  }

  /// 使用者在字幕選單選定軌（-1 關閉）；記住開關狀態。
  Future<void> selectSubtitle(int index) async {
    if (index < -1 || index >= subtitleTracks.length) return;
    SettingsService.setSubtitleEnabled(index >= 0);
    subtitleUserPicked = true;
    final gen = ++subtitleGen;
    await _applySubtitleTrack(index, gen);
  }

  /// 字幕軌變動後修正設定面板焦點：軌道清空時子選單退回 main，焦點不超出範圍。
  void _clampSettingsFocus() {
    if (!showSettingsPanel) return;
    if (settingsMenuType == SettingsMenuType.subtitle &&
        subtitleTracks.isEmpty) {
      settingsMenuType = SettingsMenuType.main;
      focusedSettingIndex = 6;
    }
    final max = switch (settingsMenuType) {
      SettingsMenuType.main => subtitleTracks.isNotEmpty ? 7 : 6,
      SettingsMenuType.audio =>
        audioOptions.isEmpty ? 0 : audioOptions.length - 1,
      SettingsMenuType.subtitle => subtitleTracks.length,
      _ => focusedSettingIndex,
    };
    if (focusedSettingIndex > max) focusedSettingIndex = max;
  }

  Future<void> _applySubtitleTrack(int index, int gen) async {
    final forCid = cid;
    bool stale() => !mounted || gen != subtitleGen || forCid != cid;
    if (index < 0) {
      setState(() {
        subtitleIndex = -1;
        subtitleLines = [];
      });
      return;
    }
    final track = subtitleTracks[index];
    final prevIndex = subtitleIndex;
    final prevLines = subtitleLines;
    setState(() {
      subtitleIndex = index;
      subtitleLines = [];
    });
    var sourceUrl = track.url;
    if (track.machine) {
      final real = subtitleTracks.where((t) => !t.machine).toList();
      final zh = pickDefaultSubtitle(real, english: false);
      if (zh < 0) return;
      sourceUrl = real[zh].url;
    }
    final lines = List<SubtitleLine>.of(
      await SubtitleApi.getSubtitleBody(sourceUrl),
    );
    if (stale()) return;
    if (lines.isEmpty) {
      showZhToast(msg: '字幕載入失敗', toastLength: Toast.LENGTH_SHORT);
      setState(() {
        subtitleIndex = prevIndex;
        subtitleLines = prevLines;
      });
      return;
    }
    setState(() => subtitleLines = lines);
    if (!track.machine) return;
    // 機器翻譯：從目前播放位置開始環狀走訪；翻好前顯示原文，逐句替換
    final pos = (videoController?.value.position.inMilliseconds ?? 0) / 1000.0;
    var start = lines.indexWhere((l) => l.to > pos);
    if (start < 0) start = 0;
    final order = [
      for (int k = 0; k < lines.length; k++) (start + k) % lines.length,
    ];
    await ContentTranslator.instance.translateBatch(
      [for (final i in order) lines[i].content],
      isCancelled: stale,
      onLine: (k, text) {
        if (stale() || k < 0 || k >= order.length) return;
        final i = order[k];
        lines[i] = lines[i].withContent(text);
        // 播放中每個 tick 都會重建；只有暫停且被換的正是目前顯示的行才刷新
        if (videoController?.value.isPlaying ?? false) return;
        final now =
            (videoController?.value.position.inMilliseconds ?? 0) / 1000.0;
        if (identical(findSubtitleLine(lines, now), lines[i])) {
          setState(() {});
        }
      },
    );
  }

  Future<void> loadDanmaku() async {
    if (cid == null) return;
    try {
      final danmaku =
          PrefetchService.instance.takeDanmaku(cid!) ??
          await BilibiliApi.getDanmaku(cid!);
      if (!mounted) return;
      setState(() {
        danmakuList = danmaku;
        danmakuList.sort(
          (a, b) => (a['time'] as double).compareTo(b['time'] as double),
        );
        lastDanmakuIndex = 0;
      });
    } catch (e) {
      debugPrint('Failed to load danmaku: $e');
    }
  }

  /// 檢查錯誤是否為硬體解碼器失敗 (MediaCodec / Decoder)
  bool _isDecoderError(Object? error) {
    if (error == null) return false;
    final msg = error.toString().toLowerCase();
    return msg.contains('mediacodec') || msg.contains('decoder');
  }

  /// 目前串流為 HDR／10-bit 時，回傳可退回的較低非 HDR 畫質；否則回 null
  int? _hdrFallbackTarget() {
    final codecs = (currentStream?['codecs'] ?? '').toString();
    if (!isHdrStream(qn: currentQuality, codecs: codecs)) return null;
    return nonHdrFallbackQn(
      qualities.map((q) => (q['qn'] as num?)?.toInt() ?? 0).where((q) => q > 0),
      currentQuality,
    );
  }

  /// HDR 解碼失敗：以同編碼設定（不指定 codec）重新載入較低非 HDR 畫質，位置不變
  Future<void> _fallbackFromHdr(int target, {Duration? resume}) async {
    final from = currentQuality;
    PerfLog.add('事件 HDR 解碼失敗 $from->$target');
    showZhToast(msg: '此裝置無法播放 HDR，已改用較低畫質', toastLength: Toast.LENGTH_LONG);
    await _reloadWithCodec(null, qn: target, resume: resume);
  }

  /// 解碼失敗時自動降級改用 AVC (H.264)
  Future<void> _fallbackToAvc({
    Duration? resumePosition,
    String? originalError,
  }) async {
    if (isFallingBackToAvc) return;
    if (stallSwitching) {
      PerfLog.add('事件 解碼失敗回退略過：正在重新載入');
      return;
    }

    // HDR／10-bit 串流解碼失敗：只是此裝置不能播 HDR，改播較低非 HDR 畫質，
    // 不寫入永久的「僅用 AVC」設定。找不到更低畫質才沿用 AVC 退路。
    final hdrTarget = _hdrFallbackTarget();
    if (hdrTarget != null) {
      isFallingBackToAvc = true;
      try {
        await _fallbackFromHdr(
          hdrTarget,
          resume: resumePosition ?? lastPlaybackPosition,
        );
      } finally {
        isFallingBackToAvc = false;
      }
      return;
    }

    // 與 _reloadWithCodec 互斥
    stallSwitching = true;
    reloadGen++;
    try {
      await _fallbackToAvcCore(
        resumePosition: resumePosition,
        originalError: originalError,
      );
    } finally {
      stallSwitching = false;
    }
  }

  Future<void> _fallbackToAvcCore({
    Duration? resumePosition,
    String? originalError,
  }) async {
    isFallingBackToAvc = true;

    debugPrint(
      '🎬 [CodecFallback] Decoder error, falling back to AVC. pos=$resumePosition err=$originalError',
    );
    await SettingsService.setCodecFallbackAvc(true);
    showZhToast(
      msg: '此裝置無法解碼 H.265／AV1，已改用 H.264',
      toastLength: Toast.LENGTH_LONG,
    );

    final resume = resumePosition ?? lastPlaybackPosition;

    if (mounted) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    cancelPlayerListeners();
    await videoController?.dispose();
    videoController = null;
    LocalServer.instance.clearMpdContent();

    try {
      final playInfo = await BilibiliApi.getVideoPlayUrl(
        bvid: playingBvid,
        audioOverride: audioOverrideNow,
        cid: cid!,
        qn: currentQuality,
        forceCodec: VideoCodec.avc,
        epId: isPgc ? currentEpId : null,
      );

      if (playInfo == null || playInfo['error'] != null) {
        throw Exception(
          playInfo?['error'] ?? originalError ?? '無法取得播放網址，請稍後再試',
        );
      }

      if (!mounted) return;
      isPreview = playInfo['isPreview'] == true;
      if (isPreview) {
        showZhToast(msg: '此集為大會員專屬，目前僅提供試看', toastLength: Toast.LENGTH_LONG);
      }
      currentQuality = playInfo['currentQuality'] ?? currentQuality;
      currentCodec = playInfo['codec'] ?? 'avc';
      _recordStream(playInfo);
      currentAudioUrl = playInfo['audioUrl'];
      recordAudio(playInfo);
      previewFrameUrl = playInfo['previewUrl'] as String?;
      qualities = List<Map<String, dynamic>>.from(playInfo['qualities'] ?? []);

      String? playUrl;
      if (playInfo['dashData'] != null) {
        final mpdContent = await MpdGenerator.generate(playInfo['dashData']);
        LocalServer.instance.setMpdContent(mpdContent);
        playUrl = LocalServer.instance.mpdUrl;
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

      if (playUrl == null || playUrl.isEmpty) {
        throw Exception('無法取得播放網址，請稍後再試');
      }

      videoController = VideoPlayerController.networkUrl(
        Uri.parse(playUrl),
        httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
          'Referer': 'https://www.bilibili.com/',
          'Origin': 'https://www.bilibili.com',
          if (BaseApi.cookieHeader != null) 'Cookie': BaseApi.cookieHeader!,
        },
        viewType: SettingsService.playerTextureView
            ? VideoViewType.textureView
            : VideoViewType.platformView,
      );

      await videoController!.initialize();
      if (resume > Duration.zero) {
        await videoController!.seekTo(resume);
      }
      _setupPlayerListeners();
      await videoController!.play();
      videoController?.setPlaybackSpeed(playbackSpeed);

      if (mounted) {
        setState(() {
          isLoading = false;
          isFallingBackToAvc = false;
        });
      }
    } catch (e) {
      debugPrint('🎬 [CodecFallback] AVC playback also failed: $e');
      if (mounted) {
        setState(() {
          // AVC 也失敗時顯示原本的錯誤訊息 (AC-A3)
          errorMessage = originalError ?? '播放器初始化失敗: $e';
          isLoading = false;
          isFallingBackToAvc = false;
        });
      }
    }
  }

  /// 設定播放器監聽器
  void _setupPlayerListeners() {
    if (videoController == null) return;

    videoController!.addListener(_onPlayerStateChange);
    _startPlayerStatsTimer();
  }

  /// 記下選定的影片串流（DASH 只有一條），供效能記錄與掉幀率計算
  void _recordStream(Map playInfo) {
    final v = (playInfo['dashData'] as Map?)?['video'];
    currentStream = (v is List && v.isNotEmpty && v.first is Map)
        ? Map<String, dynamic>.from(v.first as Map)
        : null;
  }

  double get _currentStreamFps => CodecService.parseFps(
    currentStream?['frameRate'] ?? currentStream?['frame_rate'],
  );

  // 播放診斷：每次（重）建主播放器都呼叫一次。先取消舊計時器並讓舊的非同步結果作廢，
  // 再重新對齊 10 秒區間；同一個 cid 保留降級次數，換 cid 才整個重置。
  void _startPlayerStatsTimer() {
    playerStatsTimer?.cancel();
    final gen = ++perfGen;
    if (perfCid != cid) {
      perfTracker.resetForVideo();
      perfCid = cid;
      stallTriedCodecs.clear();
    } else {
      perfTracker.resetInterval();
    }
    // 新 decoder 的掉幀累計從 0 起算（原生端在 decoder 初始化時也會歸零）
    lastStatsDropped = 0;
    lastStatsDecoder = '';
    perfPrevJiffies = null;
    perfPrevElapsedMs = null;
    unawaited(_logPlaybackStart(gen));
    unawaited(_sampleCpu(gen));
    playerStatsTimer = Timer.periodic(
      const Duration(seconds: kPerfIntervalSeconds),
      (_) => _perfTick(gen),
    );
    stallTimer?.cancel();
    bufferingSince = null;
    stallTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_stallTick(gen)),
    );
  }

  /// 每 2 秒讀原生狀態判斷解碼卡住（不 drain，避免吃掉 _perfTick 的事件）
  Future<void> _stallTick(int gen) async {
    if (videoController == null || !mounted || gen != perfGen) return;
    final s = await CodecService.getPlayerStats(drain: false);
    if (s == null || !mounted || gen != perfGen) return;

    final state = (s['playbackState'] as num?)?.toInt();
    if (state == 2) {
      bufferingSince ??= DateTime.now();
    } else {
      bufferingSince = null;
    }
    final since = bufferingSince;
    if (since == null) return;
    final bufferingFor = DateTime.now().difference(since);
    final aheadMs = (s['bufferedAheadMs'] as num?)?.toInt();
    final stalled = isDecoderStall(
      playWhenReady: s['playWhenReady'] == true,
      playbackState: state,
      bufferingFor: bufferingFor,
      bufferedAheadMs: aheadMs,
    );
    if (!stalled ||
        isLoading ||
        stallSwitching ||
        isFallingBackToAvc ||
        perfDowngrading) {
      return;
    }

    final codecs = currentCodec.toLowerCase();
    final cur = codecs.startsWith('av01') || codecs.startsWith('av1')
        ? 'av01'
        : (codecs.startsWith('hev') || codecs.startsWith('hvc')
              ? 'hev'
              : 'avc');
    stallTriedCodecs.add(cur);
    final next = nextStallCodec(currentCodec, stallTriedCodecs);
    final bufSec = bufferingFor.inSeconds;
    final aheadSec = (aheadMs ?? 0) / 1000;
    if (next == null) {
      PerfLog.add(
        formatStallLog(
          from: cur,
          to: null,
          bufferingSec: bufSec,
          bufferedAheadSec: aheadSec,
        ),
      );
      // 避免重複記錄：重新起算緩衝時間
      bufferingSince = DateTime.now();
      return;
    }
    PerfLog.add(
      formatStallLog(
        from: cur,
        to: next.prefix,
        bufferingSec: bufSec,
        bufferedAheadSec: aheadSec,
      ),
    );
    showZhToast(
      msg: '播放卡住，改用 ${next == VideoCodec.hevc ? 'H.265' : 'H.264'} 重新載入',
      toastLength: Toast.LENGTH_LONG,
    );
    // 同時記下目標家族：forceCodec 找不到時 API 可能又回原編碼，避免重載迴圈
    stallTriedCodecs.add(next.prefix);
    await _reloadWithCodec(next, resume: lastPlaybackPosition);
  }

  /// 卡住時以指定編碼重新載入同一畫質與位置。不寫入任何永久設定。
  /// [codec] 為 null 時不指定編碼；[qn] 有值時改載入該畫質（HDR 解碼失敗退路）。
  Future<void> _reloadWithCodec(
    VideoCodec? codec, {
    int? qn,
    Duration? resume,
  }) async {
    if (stallSwitching) return;
    stallSwitching = true;
    final startCid = cid;
    final startQuality = qn ?? currentQuality;
    final token = ++reloadGen;
    final pos = resume ?? lastPlaybackPosition;
    try {
      try {
        await _reloadAttempt(codec, startCid, startQuality, token, pos, qn);
      } catch (e) {
        // 重載時又遇到解碼失敗且不是 AVC：以 AVC、同畫質、同位置再試一次（不寫永久設定）
        if (_isDecoderError(e) &&
            codec != VideoCodec.avc &&
            !isCurrentCodecAvc &&
            mounted &&
            cid == startCid &&
            reloadGen == token) {
          debugPrint('🎬 [StallReload] decoder error, retry with AVC: $e');
          await _reloadAttempt(
            VideoCodec.avc,
            startCid,
            startQuality,
            token,
            pos,
            qn,
          );
        } else {
          rethrow;
        }
      }
    } catch (e) {
      debugPrint('🎬 [StallReload] reload failed: $e');
      if (mounted && cid == startCid && reloadGen == token) {
        setState(() {
          errorMessage = '播放器初始化失敗: $e';
          isLoading = false;
        });
      }
    } finally {
      stallSwitching = false;
    }
    // 重載期間新播放器已出錯時，_fallbackToAvc 會因 stallSwitching 略過；
    // 這裡補做一次錯誤檢查，避免畫面停在錯誤狀態
    if (mounted &&
        cid == startCid &&
        reloadGen == token &&
        videoController?.value.hasError == true) {
      _onPlayerStateChange();
    }
  }

  /// 單次重載；失敗時清掉自己建立的 controller 後拋出例外
  Future<void> _reloadAttempt(
    VideoCodec? codec,
    int? startCid,
    int startQuality,
    int token,
    Duration pos,
    int? qn,
  ) async {
    bool alive() => mounted && cid == startCid && reloadGen == token;
    VideoPlayerController? created;
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
      cancelPlayerListeners();
      final old = videoController;
      videoController = null;
      await old?.dispose();
      LocalServer.instance.clearMpdContent();
      if (!alive()) return;

      final playInfo = await BilibiliApi.getVideoPlayUrl(
        bvid: playingBvid,
        audioOverride: audioOverrideNow,
        cid: startCid!,
        qn: startQuality,
        forceCodec: codec,
        epId: isPgc ? currentEpId : null,
      );
      if (!alive()) return;
      if (playInfo == null || playInfo['error'] != null) {
        throw Exception(playInfo?['error'] ?? '無法取得播放網址，請稍後再試');
      }

      isPreview = playInfo['isPreview'] == true;
      currentQuality = playInfo['currentQuality'] ?? currentQuality;
      currentCodec = playInfo['codec'] ?? currentCodec;
      if (qn == null && currentQuality != startQuality) {
        PerfLog.add('事件 解碼卡住換編碼後畫質 $startQuality->$currentQuality');
      }
      _recordStream(playInfo);
      currentAudioUrl = playInfo['audioUrl'];
      recordAudio(playInfo);
      previewFrameUrl = playInfo['previewUrl'] as String?;
      qualities = List<Map<String, dynamic>>.from(playInfo['qualities'] ?? []);

      String? playUrl;
      if (playInfo['dashData'] != null) {
        final mpdContent = await MpdGenerator.generate(playInfo['dashData']);
        if (!alive()) return;
        LocalServer.instance.setMpdContent(mpdContent);
        playUrl = LocalServer.instance.mpdUrl;
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
        if (!alive()) return;
      }
      if (playUrl == null || playUrl.isEmpty) {
        throw Exception('無法取得播放網址，請稍後再試');
      }

      created = VideoPlayerController.networkUrl(
        Uri.parse(playUrl),
        httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
          'Referer': 'https://www.bilibili.com/',
          'Origin': 'https://www.bilibili.com',
          if (BaseApi.cookieHeader != null) 'Cookie': BaseApi.cookieHeader!,
        },
        viewType: SettingsService.playerTextureView
            ? VideoViewType.textureView
            : VideoViewType.platformView,
      );
      await created.initialize();
      if (!alive()) {
        await created.dispose();
        created = null;
        return;
      }
      videoController = created;
      if (pos > Duration.zero) {
        await created.seekTo(pos);
        if (!alive()) return;
        resetDanmakuIndex(pos);
      }
      _setupPlayerListeners();
      await created.play();
      if (!alive()) return;
      created.setPlaybackSpeed(playbackSpeed);
      created = null; // 已交給 videoController，不再由失敗路徑釋放
      setState(() => isLoading = false);
    } catch (_) {
      // 失敗時不殘留沒有監聽的 controller
      if (created != null) await created.dispose();
      if (identical(videoController, created)) videoController = null;
      rethrow;
    }
  }

  Future<void> _logPlaybackStart(int gen) async {
    final info = await CodecService.getPerfDeviceInfo();
    final s = await CodecService.getPlayerStats(drain: false);
    if (gen != perfGen) return;
    if (info != null) {
      perfCores = (info['cores'] as num?)?.toInt() ?? 1;
    }
    final st = currentStream;
    final codec = st?['codecs'] ?? currentCodec;
    final btrUsed =
        BtrConfig.playback &&
        !shouldSkipBtr(
          is32Bit: isProcess32Bit(),
          qn: currentQuality,
          height: (st?['height'] as num?)?.toInt(),
        );
    PerfLog.add(
      '播放開始 abi=${Abi.current()} cores=${info?['cores']} '
      'memClass=${info?['memoryClass']}MB lowRam=${info?['isLowRam']} '
      'display=${info?['modeWidth']}x${info?['modeHeight']}@'
      '${((info?['modeRefresh'] as num?) ?? 0).toStringAsFixed(1)}Hz '
      'hdr=${info?['hdr']} '
      '視圖=${SettingsService.playerTextureView ? '相容' : '原生'} '
      'btr=${btrUsed ? '用' : '不用'} '
      '彈幕=${danmakuEnabled ? '開' : '關'} '
      '隧道=${SettingsService.playerTunneling ? '開' : '關'}',
    );
    final tunnelActive = s?['tunnelingActive'];
    if (SettingsService.playerTunneling && !SettingsService.playerTextureView) {
      PerfLog.add(
        '隧道播放 設定=開 實際=${tunnelActive == null ? '未知' : (tunnelActive == true ? '隧道模式' : '一般模式')}'
        '${tunnelActive == true ? '（隧道模式，掉幀統計可能不準）' : ''}',
      );
    } else if (SettingsService.playerTunneling) {
      PerfLog.add('隧道播放 設定=開，但畫面模式為相容，不會啟用');
    }
    final caps = await CodecService.getDecoderCaps(
      codec: CodecService.codecFamily(codec?.toString() ?? '') ?? '',
      width: 3840,
      height: 2160,
      fps: 60,
      decoderName: s?['decoderName']?.toString(),
    );
    if (gen != perfGen) return;
    if (caps != null) {
      PerfLog.add(
        '解碼器能力 name=${caps['name']} '
        '隧道支援=${caps['tunnel']} '
        '4K可達幀率=${caps['achievable']} '
        '4K60效能點=${caps['perfPointOk']}',
      );
    }
    final modes = info?['supportedModes'];
    if (modes is List && modes.isNotEmpty) {
      PerfLog.add('支援螢幕模式 ${modes.join(' ')}');
    }
    PerfLog.add(
      '串流 qn=$currentQuality codec=$codec '
      '${st?['width']}x${st?['height']}@${_currentStreamFps.toStringAsFixed(2)}fps '
      'bw=${(((st?['bandwidth'] as num?)?.toInt() ?? 0) ~/ 1000)}kbps '
      'decoder=${s?['decoderName']} hw=${s?['isHardware']}',
    );
  }

  /// 取一次 /proc/self/stat 樣本，與上一次比較得 CPU 百分比；第一次回 null
  Future<double?> _sampleCpu(int gen) async {
    final r = await CodecService.getProcessCpu();
    if (r == null || gen != perfGen) return null;
    final j = (r['jiffies'] as num?)?.toInt();
    final ms = (r['elapsedMs'] as num?)?.toInt();
    final hz = (r['hz'] as num?)?.toInt();
    if (j == null || ms == null) return null;
    if (hz != null && hz > 0) perfHz = hz;
    final pj = perfPrevJiffies;
    final pm = perfPrevElapsedMs;
    perfPrevJiffies = j;
    perfPrevElapsedMs = ms;
    if (pj == null || pm == null) return null;
    return cpuPercent(
      prevJiffies: pj,
      prevElapsedMs: pm,
      curJiffies: j,
      curElapsedMs: ms,
      hz: perfHz,
      cores: perfCores,
    );
  }

  Future<void> _perfTick(int gen) async {
    final c = videoController;
    if (c == null || !mounted || gen != perfGen) return;
    final s = await CodecService.getPlayerStats();
    if (s == null || gen != perfGen) return;

    final events = s['events'];
    if (events is List) {
      for (final e in events) {
        PerfLog.add('事件 $e');
      }
    }
    final dropped = (s['droppedTotal'] as num?)?.toInt() ?? 0;
    final value = c.value;
    final cpu = await _sampleCpu(gen);
    if (gen != perfGen) return;
    if (!value.isInitialized || !value.isPlaying || value.isBuffering) {
      // 暫停或緩衝中：這個區間不完整，不計入連續掉幀
      lastStatsDropped = dropped;
      perfTracker.resetInterval();
      return;
    }

    final decoder = (s['decoderName'] as String?) ?? '';
    final delta = dropped >= lastStatsDropped
        ? dropped - lastStatsDropped
        : dropped;
    lastStatsDropped = dropped;
    lastStatsDecoder = decoder;

    var fps = _currentStreamFps;
    if (fps <= 0) fps = (s['inputFps'] as num?)?.toDouble() ?? 0;
    final rate = dropRate(delta, fps * playbackSpeed, kPerfIntervalSeconds);

    var bufSec = 0.0;
    for (final r in value.buffered) {
      if (r.end >= value.position) {
        bufSec = (r.end - value.position).inMilliseconds / 1000;
      }
    }
    PerfLog.add(
      formatPerfLine(
        posSec: value.position.inSeconds,
        droppedInterval: delta,
        droppedTotal: dropped,
        rate: rate,
        offsetUs: (s['frameOffsetAvgUs'] as num?)?.toDouble() ?? 0,
        rendered: (s['renderedTotal'] as num?)?.toInt() ?? 0,
        bufSec: bufSec,
        bandwidthBps: (s['bandwidthBps'] as num?)?.toDouble() ?? 0,
        cpu: cpu,
      ),
    );

    final shouldDowngrade = perfTracker.record(
      rate,
      enabled: SettingsService.autoDowngradeOnDrops,
    );
    if (!shouldDowngrade || isLoading || perfDowngrading || stallSwitching) {
      return;
    }
    final target = nextLowerQn(
      qualities.map((q) => (q['qn'] as num?)?.toInt() ?? 0).where((q) => q > 0),
      currentQuality,
    );
    if (target == null) {
      perfTracker.noLowerLevel = true;
      PerfLog.add('自動降畫質略過：已是最低畫質');
      return;
    }
    final from = currentQuality;
    final prevRate = perfTracker.previousRate;
    perfTracker.commitDowngrade();
    PerfLog.add(
      '事件 自動降畫質 $from->$target '
      '區間掉幀率=${(prevRate * 100).toStringAsFixed(1)}%,'
      '${(rate * 100).toStringAsFixed(1)}%',
    );
    perfDowngrading = true;
    try {
      await switchQuality(target, auto: true);
    } finally {
      perfDowngrading = false;
    }
  }

  void _onPlayerStateChange() {
    if (videoController == null || !mounted) return;

    final value = videoController!.value;
    if (value.position > Duration.zero) {
      lastPlaybackPosition = value.position;
    }

    // 播放中解碼器錯誤 (AC-A1)
    if (value.hasError) {
      final err = value.errorDescription ?? '';
      // 杜比/Hi-Res 音軌播放失敗：先退回標準音質（本影片只試一次）。
      // 只有錯誤訊息與音訊有關才退回，避免把網路或視訊解碼錯誤誤判成音軌錯誤。
      final audioRelated = RegExp(
        r'audio|e-?ac-?3|flac|joc',
        caseSensitive: false,
      ).hasMatch(err);
      if (currentAudioKind != AudioKind.standard &&
          audioOverrideNow != AudioKind.standard &&
          !stallSwitching &&
          !isFallingBackToAvc &&
          audioRelated) {
        fallbackAudioToStandard();
        return;
      }
      if (!isFallingBackToAvc && _isDecoderError(err) && !isCurrentCodecAvc) {
        _fallbackToAvc(
          resumePosition: lastPlaybackPosition,
          originalError: err,
        );
        return;
      }
    }

    // 同步彈幕
    if (danmakuEnabled && danmakuController != null) {
      syncDanmaku(value.position.inSeconds.toDouble());
    }

    // 檢查是否需要預載入下一張雪碧圖
    _checkSpritePreload(value.position);

    // 使用者重播或跳轉離開結尾：重置完成標誌並取消倒數，之後播完才能再觸發
    if (hasHandledVideoComplete &&
        value.duration > Duration.zero &&
        value.position < value.duration - const Duration(seconds: 1)) {
      hasHandledVideoComplete = false;
      if (upNextSeconds != null) cancelUpNext();
    }

    // 檢查播放完成
    if (value.position >= value.duration &&
        value.duration > Duration.zero &&
        !value.isPlaying) {
      // 通過位置判斷播放結束
      onVideoComplete();
    }

    // 觸發重繪以更新 UI (進度條等)
    setState(() {});

    // 外掛處理 (Debounce logic internal to plugin, but we update UI here)
    _handlePlugins(value.position);
  }

  void _handlePlugins(Duration position) async {
    final plugins = PluginManager().getEnabledPlugins<PlayerPlugin>();
    if (plugins.isEmpty) return;

    final positionMs = position.inMilliseconds;
    SkipAction? newAction;

    for (var plugin in plugins) {
      final action = await plugin.onPositionUpdate(positionMs);
      if (action is SkipActionSkipTo) {
        if (!mounted) return;
        videoController?.seekTo(Duration(milliseconds: action.positionMs));
        resetDanmakuIndex(Duration(milliseconds: action.positionMs));
        showZhToast(msg: action.reason);
        // 跳過也可能需要清除之前的按鈕
        newAction = null;
        break; // 優先處理跳過
      } else if (action is SkipActionShowButton) {
        newAction = action;
      }
    }

    // 更新 UI 狀態
    if (mounted && currentSkipAction != newAction) {
      // 簡單的去重，如果是同一個片段ID則不更新
      if (currentSkipAction is SkipActionShowButton &&
          newAction is SkipActionShowButton) {
        if (currentSkipAction.segmentId == newAction.segmentId) {
          return;
        }
      }
      setState(() {
        currentSkipAction = newAction;
      });
    } else if (mounted && newAction == null && currentSkipAction != null) {
      setState(() {
        currentSkipAction = null;
      });
    }
  }

  /// 清理播放器監聽器
  void cancelPlayerListeners() {
    videoController?.removeListener(_onPlayerStateChange);
    // 播放器即將重建：讓舊計時器與進行中的取樣作廢，重建後 _setupPlayerListeners 會重新啟動
    playerStatsTimer?.cancel();
    playerStatsTimer = null;
    stallTimer?.cancel();
    stallTimer = null;
    bufferingSince = null;
    perfGen++;
  }

  Future<void> disposePlayer() async {
    // 退出前上報進度並儲存到本地快取
    await reportPlaybackProgress();

    // 🔥 儲存進度到本地快取（解決 B站 API history 欄位不可靠的問題）
    if (cid != null && videoController != null) {
      final currentPos = videoController!.value.position.inSeconds;
      if (currentPos > 5) {
        // 只有播放超過 5 秒才快取
        await PlaybackProgressCache.saveProgress(
          progressCacheKey,
          cid!,
          currentPos,
        );
        debugPrint(
          '🎬 [Cache] Saved progress: key=$progressCacheKey, cid=$cid, pos=$currentPos',
        );
      }
    }

    cancelPlayerListeners();
    seekIndicatorTimer?.cancel();
    autoSeekTimer?.cancel();
    onlineCountTimer?.cancel(); // 取消線上人數定時器
    playerStatsTimer?.cancel();
    playerStatsTimer = null;
    stallTimer?.cancel();
    stallTimer = null;
    _clearSpritesFromMemory(); // 清理雪碧圖記憶體快取
    previewFrameUrl = null;
    FrameService.release();

    // 通知外掛影片結束
    final plugins = PluginManager().getEnabledPlugins<PlayerPlugin>();
    for (var plugin in plugins) {
      plugin.onVideoEnd();
    }

    await videoController?.dispose();
    videoController = null;
    LocalServer.instance.clearMpdContent();
  }

  /// 獲取線上觀看人數
  Future<void> _fetchOnlineCount() async {
    if (aid == null || cid == null) return;

    final result = await BilibiliApi.getOnlineCount(aid: aid!, cid: cid!);
    if (mounted && result != null) {
      setState(() {
        onlineCount = result['total'] ?? result['count'];
      });
    }
  }

  /// 獲取用於顯示的影片資訊（優先使用 API 獲取的完整資訊）
  models.Video getDisplayVideo() {
    if (isPgc) {
      // 番劇：標題為「季名 - 第 N 話 標題」
      var title = pgcSeasonTitle.isNotEmpty
          ? pgcSeasonTitle
          : widget.video.title;
      final currentEp = episodes.firstWhere(
        (e) => e['cid'] == cid,
        orElse: () => {},
      );
      final part = currentEp['part'] as String? ?? '';
      if (part.isNotEmpty) title = '$title - $part';
      return models.Video(
        bvid: playingBvid,
        title: title,
        pic: widget.video.pic,
        progress: widget.video.progress,
        viewAt: widget.video.viewAt,
      );
    }
    if (fullVideoInfo == null) {
      return widget.video;
    }

    final info = fullVideoInfo!;
    final owner = info['owner'] ?? {};
    final stat = info['stat'] ?? {};

    var displayTitle = info['title'] ?? widget.video.title;

    // 多P影片，在標題後追加分P名稱
    if (episodes.length > 1 && cid != null) {
      final currentEp = episodes.firstWhere(
        (e) => e['cid'] == cid,
        orElse: () => {},
      );
      if (currentEp.isNotEmpty) {
        final partName = currentEp['part'] ?? currentEp['title'] ?? '';
        final pageIndex = currentEp['page'] ?? episodes.indexOf(currentEp) + 1;
        if (partName.isNotEmpty) {
          displayTitle = '$displayTitle - P$pageIndex $partName';
        }
      }
    }

    return models.Video(
      bvid: widget.video.bvid,
      title: displayTitle,
      pic: info['pic'] ?? widget.video.pic,
      ownerName: owner['name'] ?? widget.video.ownerName,
      ownerFace: owner['face'] ?? widget.video.ownerFace,
      ownerMid: owner['mid'] ?? widget.video.ownerMid,
      view: stat['view'] ?? widget.video.view,
      danmaku: stat['danmaku'] ?? widget.video.danmaku,
      pubdate: info['pubdate'] ?? widget.video.pubdate,
      duration: info['duration'] ?? widget.video.duration,
      // 關鍵：保留從列表傳入的播放進度和觀看時間，否則會丟失進度導致從頭播放
      progress: widget.video.progress,
      viewAt: widget.video.viewAt,
    );
  }

  /// 影片播放完成回撥
  void onVideoComplete() {
    // 防止重複觸發
    if (hasHandledVideoComplete) return;
    hasHandledVideoComplete = true;

    hideTimer?.cancel();

    // 試看片段播完不是真的看完：不連播、不回報完播
    if (isPreview) {
      setState(() => showControls = true);
      showZhToast(msg: '試看結束，此集為大會員專屬');
      return;
    }

    // UP主頁面開啟中不自動連播／跳轉
    if (upSpaceOpen) {
      setState(() => showControls = true);
      return;
    }

    final mode = SettingsService.playRepeat;

    switch (mode) {
      case PlayRepeat.pause:
        _stopAtEnd();
      case PlayRepeat.singleCycle:
        reportPlaybackProgress(overrideProgress: -1);
        _replayCurrent();
      case PlayRepeat.listCycle:
        final target = resolveNext(wrap: true);
        if (target == null) {
          // 沒有分P、集數或合集：重播目前影片
          reportPlaybackProgress(overrideProgress: -1);
          _replayCurrent();
        } else {
          _advanceTo(target, countdown: false);
        }
      case PlayRepeat.playNext:
      case PlayRepeat.countdownNext:
        final target = resolveNext();
        if (target == null) {
          _stopAtEnd(); // 沒有下一部：停住
        } else {
          _advanceTo(target, countdown: mode == PlayRepeat.countdownNext);
        }
    }
  }

  /// 停在結尾並顯示控制列
  void _stopAtEnd() {
    setState(() => showControls = true);
    reportPlaybackProgress(overrideProgress: -1);
  }

  /// 播完後前往 [target]；[countdown] 為 true 時先倒數。
  void _advanceTo(NavTarget target, {required bool countdown}) {
    // 暫停當前影片
    if (videoController != null && videoController!.value.isPlaying) {
      videoController!.pause();
    }

    if (target is RelatedFallback) {
      // 番劇最後一集：暫停、提示並打開相關影片，不自動播放
      reportPlaybackProgress(overrideProgress: -1);
      showZhToast(
        msg: '已播完最後一集',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.TOP,
      );
      openRelatedStrip(focusFirstCard: true);
      return;
    }

    // 切集不上報完播（避免多 P／番劇中途被標成看完）；其他一律上報
    if (target is! EpisodeTarget) reportPlaybackProgress(overrideProgress: -1);

    final info = _upNextInfoFor(target);
    if (countdown) {
      startUpNext(info, SettingsService.upNextCountdown);
    } else {
      showZhToast(
        msg: '自動播放下一部: ${info.title}',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.TOP,
      );
      info.play();
    }
  }

  /// 由導覽目標組出倒數卡片資訊
  UpNextInfo _upNextInfoFor(NavTarget target) {
    switch (target) {
      case EpisodeTarget(:final index):
        final ep = episodes[index];
        final newCid = ep['cid'] as int;
        final title = '${ep['title'] ?? ep['part'] ?? 'P${index + 1}'}';
        final cover = (ep['first_frame'] ?? ep['cover'] ?? '') as String;
        return UpNextInfo(
          title: title,
          cover: cover.isNotEmpty ? cover : getDisplayVideo().pic,
          play: () => switchEpisode(newCid),
        );
      case VideoTarget(:final video, :final fromHistory):
        return UpNextInfo(
          title: video.title,
          cover: video.pic,
          play: () =>
              navigateTo(video, record: !fromHistory, startCid: video.cid),
        );
      case RelatedFallback():
        return UpNextInfo(title: '', cover: '', play: () {});
    }
  }

  /// 從頭重播目前影片（單個循環）
  Future<void> _replayCurrent() async {
    final c = videoController;
    if (c == null) return;
    await c.seekTo(Duration.zero);
    resetDanmakuIndex(Duration.zero);
    await c.play();
    if (!mounted) return;
    hasHandledVideoComplete = false;
    startHideTimer();
  }

  // ───────────── 上一部／下一部 ─────────────

  // 合集攤平結果的快取：來源資料與 bvid 沒變時重用
  SeasonFlat _seasonCache = SeasonFlat.empty;
  Object? _seasonCacheSrc;
  String? _seasonCacheBvid;

  /// 目前影片所屬的合集（番劇不處理合集）
  SeasonFlat get _season {
    if (isPgc) return SeasonFlat.empty;
    final src = fullVideoInfo?['ugc_season'];
    if (src == null) return SeasonFlat.empty;
    if (!identical(src, _seasonCacheSrc) || _seasonCacheBvid != playingBvid) {
      _seasonCache = flattenUgcSeason(fullVideoInfo, playingBvid);
      _seasonCacheSrc = src;
      _seasonCacheBvid = playingBvid;
    }
    return _seasonCache;
  }

  int get _currentEpisodeIndex =>
      cid == null ? -1 : episodes.indexWhere((e) => e['cid'] == cid);

  /// 把相關影片（Map）轉成 Video
  models.Video _videoFromRelated(dynamic v) {
    return models.Video(
      bvid: v['bvid'] ?? '',
      title: v['title'] ?? '',
      pic: v['pic'] ?? '',
      ownerName: v['owner']?['name'] ?? '',
      ownerFace: v['owner']?['face'] ?? '',
      duration: v['duration'] ?? 0,
      pubdate: v['pubdate'] ?? 0,
      view: v['stat']?['view'] ?? 0,
    );
  }

  /// 下一部：下一個分P或集 → 合集下一部 → （[wrap]）回到第一個 →
  /// 第一個相關影片（非番劇）→ 番劇為 [RelatedFallback]；其他為 null。
  NavTarget? resolveNext({bool wrap = false}) {
    final epIdx = _currentEpisodeIndex;
    if (epIdx >= 0 && epIdx + 1 < episodes.length) {
      return EpisodeTarget(epIdx + 1);
    }

    final season = _season;
    if (season.index >= 0 && season.index + 1 < season.videos.length) {
      return VideoTarget(season.videos[season.index + 1]);
    }

    if (wrap) {
      if (season.videos.length > 1) return VideoTarget(season.videos.first);
      if (episodes.length > 1 && epIdx >= 0) return const EpisodeTarget(0);
      return null; // 呼叫端重播目前影片
    }

    if (!isPgc && relatedVideos.isNotEmpty) {
      return VideoTarget(_videoFromRelated(relatedVideos.first));
    }
    if (isPgc) return const RelatedFallback();
    return null;
  }

  /// 上一部：上一個分P或集 → 合集上一部 → 播放紀錄的前一部。
  NavTarget? resolvePrev() {
    final epIdx = _currentEpisodeIndex;
    if (epIdx > 0) return EpisodeTarget(epIdx - 1);

    final season = _season;
    if (season.index > 0) {
      return VideoTarget(season.videos[season.index - 1]);
    }

    // 跳過紀錄中「就是目前這部」的項目（例如返回後再開同一部）。
    // 這裡不能修改紀錄：hasPrev 會在 build 中呼叫，換片時舊頁面重建也會呼叫，
    // 若在這裡 pop，會把剛記下的上一部丟掉。
    final last = _historyPrevEntry();
    if (last != null) return VideoTarget(last, fromHistory: true);
    return null;
  }

  /// 播放紀錄中，從頂端往下第一筆不是目前影片的項目（不修改紀錄）
  models.Video? _historyPrevEntry() {
    final items = PlaySessionHistory.items;
    for (var i = items.length - 1; i >= 0; i--) {
      if (items[i].bvid != playingBvid) return items[i];
    }
    return null;
  }

  /// 有沒有上一部（每次重新計算，不快取）
  bool get hasPrev => resolvePrev() != null;

  /// 有沒有下一部。[RelatedFallback] 不算。
  bool get hasNext {
    final t = resolveNext();
    return t is EpisodeTarget || t is VideoTarget;
  }

  /// 立刻播上一部
  Future<void> playPrev() async {
    final target = resolvePrev();
    if (target == null) return;
    if (target is VideoTarget) {
      // 從播放紀錄回去，或合集上一部剛好就是紀錄頂端：先 pop，避免再往前時回到同一部
      if (target.fromHistory) {
        // 連同頂端「就是目前這部」的項目，一起取出到目標為止
        while (PlaySessionHistory.canPop) {
          final popped = PlaySessionHistory.pop();
          if (identical(popped, target.video)) break;
        }
      } else if (PlaySessionHistory.peek?.bvid == target.video.bvid) {
        PlaySessionHistory.pop();
      }
    }
    await _runTarget(target, record: false);
  }

  /// 立刻播下一部
  Future<void> playNext() async {
    final target = resolveNext();
    if (target == null) return;
    await _runTarget(target, record: true);
  }

  Future<void> _runTarget(NavTarget target, {required bool record}) async {
    switch (target) {
      case EpisodeTarget(:final index):
        await switchEpisode(episodes[index]['cid'] as int);
      case VideoTarget(:final video):
        await navigateTo(video, record: record, startCid: video.cid);
      case RelatedFallback():
        openRelatedStrip(focusFirstCard: true);
    }
  }

  /// 目前播放的影片（供播放紀錄使用）。不帶 cid，回去時依進度續播。
  models.Video _currentForHistory() {
    final d = getDisplayVideo();
    final infoTitle = '${fullVideoInfo?['title'] ?? ''}';
    return models.Video(
      bvid: playingBvid,
      title: isPgc
          ? d.title
          : (infoTitle.isNotEmpty ? infoTitle : widget.video.title),
      pic: d.pic,
      ownerName: d.ownerName,
      ownerFace: d.ownerFace,
      ownerMid: d.ownerMid,
      duration: d.duration,
      pubdate: d.pubdate,
      seasonId: isPgc ? widget.video.seasonId : 0,
      epId: isPgc ? currentEpId : 0,
      aid: aid ?? 0,
    );
  }

  /// 換到另一部影片的唯一入口。[record] 為 true 時，先把目前影片記進播放紀錄。
  /// 上一部從播放紀錄 pop 回去時用 `record: false`。
  /// [startCid] > 0 時，新頁面從該分P開始（只有合集換片使用）。
  bool _navigating = false;

  Future<void> navigateTo(
    models.Video video, {
    bool record = true,
    int startCid = 0,
  }) async {
    if (!mounted || _navigating) return; // 換片進行中，忽略重入
    _navigating = true;
    if (record && video.bvid != playingBvid) {
      PlaySessionHistory.push(_currentForHistory());
    }
    cancelUpNext();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(video: video, startCid: startCid),
      ),
    );
  }

  /// 控制列按鈕目前能不能用（沒有上一部／下一部時變暗）
  bool isCtrlBtnEnabled(int index) {
    if (index == CtrlBtn.prev) return hasPrev;
    if (index == CtrlBtn.next) return hasNext;
    // 設定中隱藏的讚／幣／藏按鈕不顯示，左右鍵要跳過
    if (index == CtrlBtn.like) return SettingsService.showLikeButton;
    if (index == CtrlBtn.coin) return SettingsService.showCoinButton;
    if (index == CtrlBtn.fav) return SettingsService.showFavButton;
    // 字幕按鈕沒有字幕軌時只是變暗，仍可聚焦（按下會 toast 原因）
    return true;
  }

  /// 打開底部相關影片（一排）。影片繼續播放，只取消倒數與自動隱藏。
  /// [focusFirstCard] 為 true（播完最後一集等自動開啟）時，收起後控制列的焦點回到播放/暫停。
  void openRelatedStrip({bool focusFirstCard = false}) {
    cancelUpNext();
    hideTimer?.cancel();
    setState(() {
      showControls = false;
      showRelatedPanel = true;
      relatedExpanded = false;
      if (focusFirstCard) focusedButtonIndex = CtrlBtn.playPause;
    });
  }

  /// 收起相關影片，回到控制列
  void closeRelatedStrip() {
    if (!mounted) return;
    setState(() {
      showRelatedPanel = false;
      relatedExpanded = false;
      showControls = true;
    });
    startHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) playerFocusNode.requestFocus();
    });
  }

  /// 開始倒數：隱藏控制列、顯示「接下來播放」卡片。
  void startUpNext(UpNextInfo info, int seconds) {
    hideTimer?.cancel();
    upNextTimer?.cancel();
    setState(() {
      showControls = false;
      upNextTotal = seconds;
      upNextSeconds = seconds;
      upNextInfo = info;
    });
    upNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final left = (upNextSeconds ?? 0) - 1;
      if (left <= 0) {
        final i = upNextInfo;
        cancelUpNext();
        if (mounted) i?.play();
        return;
      }
      setState(() => upNextSeconds = left);
    });
  }

  /// 取消倒數；[showControlsAfter] 為 true 時顯示控制列。
  void cancelUpNext({bool showControlsAfter = false}) {
    upNextTimer?.cancel();
    upNextTimer = null;
    final active = upNextSeconds != null || upNextInfo != null;
    if (!active && !showControlsAfter) return;
    upNextSeconds = null;
    upNextInfo = null;
    if (!mounted) return;
    setState(() {
      if (showControlsAfter) showControls = true;
    });
    if (showControlsAfter) startHideTimer();
  }

  /// 上報播放進度 (暫停/退出時呼叫)
  Future<void> reportPlaybackProgress({int? overrideProgress}) async {
    if (videoController == null ||
        cid == null ||
        (overrideProgress == null && !videoController!.value.isInitialized)) {
      return;
    }

    final progress =
        overrideProgress ?? videoController!.value.position.inSeconds;

    // 上報到B站
    await BilibiliApi.reportProgress(
      bvid: playingBvid,
      cid: cid!,
      progress: progress,
      epId: isPgc ? currentEpId : null,
      seasonId: isPgc ? widget.video.seasonId : null,
    );
  }

  void syncDanmaku(double currentTime) {
    if (danmakuController == null || !danmakuEnabled) return;

    if (lastDanmakuIndex < danmakuList.length) {
      final nextDmTime = danmakuList[lastDanmakuIndex]['time'] as double;
      // 檢測跳轉 (Seek)
      if (currentTime - nextDmTime > 5.0) {
        resetDanmakuIndex(Duration(seconds: currentTime.toInt()));
        return;
      }
    }

    // 獲取已啟用的彈幕外掛
    final plugins = PluginManager().getEnabledPlugins<DanmakuPlugin>();

    while (lastDanmakuIndex < danmakuList.length) {
      final dm = danmakuList[lastDanmakuIndex];
      final time = dm['time'] as double;

      if (time <= currentTime) {
        if (currentTime - time < 1.0) {
          // 構造外掛傳遞物件 (目前簡單用 Map 傳遞)
          // 真實專案中建議定義 DanmakuItem 模型
          Map<String, dynamic>? dmItem = {
            'content': dm['content'],
            'color': dm['color'],
          };

          DanmakuStyle? style;

          // 外掛過濾管道
          for (var plugin in plugins) {
            if (dmItem == null) break;
            dmItem = plugin.filterDanmaku(dmItem);
            if (dmItem != null) {
              final s = plugin.styleDanmaku(dmItem);
              if (s != null) style = s;
            }
          }

          if (dmItem != null) {
            Color color = Color(dmItem['color'] as int).withValues(alpha: 255);
            if (style != null && style.borderColor != null) {
              // 高亮樣式暫時用顏色替代，或如果庫支援邊框則設定
              // 這裡簡單將文字變色，並加粗（如果庫支援）
              color = style.borderColor!;
            }

            danmakuController!.addDanmaku(
              DanmakuContentItem(
                ZhConvert.convert(dmItem['content'] as String),
                color: color,
              ),
            );
          }
        }
        lastDanmakuIndex++;
      } else {
        break;
      }
    }
  }

  void resetDanmakuIndex(Duration position) {
    if (danmakuList.isEmpty) return;
    final seconds = position.inSeconds.toDouble();
    int index = danmakuList.indexWhere(
      (dm) => (dm['time'] as double) >= seconds,
    );
    if (index == -1) {
      index = danmakuList.length;
    }
    lastDanmakuIndex = index;
  }

  void toggleControls() {
    setState(() {
      showControls = true;
      // 焦點在不能用的按鈕（如換片後沒有上一部）時，改回播放/暫停
      if (!isCtrlBtnEnabled(focusedButtonIndex)) {
        focusedButtonIndex = CtrlBtn.playPause;
      }
    });
    if (!showSettingsPanel) {
      startHideTimer();
    }
  }

  void startHideTimer() {
    hideTimer?.cancel();
    if (showSettingsPanel) return;

    if (videoController?.value.isPlaying ?? false) {
      hideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() => showControls = false);
        }
      });
    }
  }

  void togglePlayPause() {
    if (videoController == null) return;

    if (videoController!.value.isPlaying) {
      videoController!.pause();
      hideTimer?.cancel();
      // 暫停時上報進度
      reportPlaybackProgress();
      // 暫停時只顯示暫停符號，不顯示控制欄
    } else {
      videoController!.play();
      startHideTimer();
    }
    setState(() {});
  }

  /// 放開方向鍵：結束按住快轉（預覽位置保留，由 1.5 秒計時器或確定鍵跳轉）
  void endSeekHold() {
    seekHoldStart = null;
    seekHoldLast = null;
    seekHoldDirection = null;
  }

  /// 執行快退/快進操作（Netflix 式進度預覽，不立即跳轉）
  ///
  /// [repeat] 為 false 是短按，預覽位置移動 10 秒；為 true 是按住，依按住時間計速。
  void _performSeek(bool forward, {bool repeat = false}) {
    if (videoController == null) return;

    if (!isSeekPreviewMode) {
      originalSeekPosition = videoController!.value.position;
      wasPlayingBeforeSeek = videoController!.value.isPlaying;
      videoController!.pause(); // 跳轉時影片暫停預覽 (AC-B4)
      previewPosition = originalSeekPosition;
      isSeekPreviewMode = true;
    }

    final currentPreview =
        previewPosition ?? originalSeekPosition ?? Duration.zero;
    final total = videoController!.value.duration;

    final now = DateTime.now();
    Duration delta;
    if (repeat && seekHoldStart != null && seekHoldDirection == forward) {
      // 按住：依經過時間推進，速度隨按住時間提高
      final held = now.difference(seekHoldStart!);
      var dt = now.difference(seekHoldLast ?? now);
      if (dt > const Duration(milliseconds: 250)) {
        dt = const Duration(milliseconds: 250);
      }
      seekHoldLast = now;
      final speed = holdSeekSpeed(held, total);
      delta = Duration(milliseconds: (speed * dt.inMilliseconds).round());
    } else {
      // 短按（或按住的第一個事件）：一步 10 秒，並開始計按住時間
      seekHoldStart = now;
      seekHoldLast = now;
      seekHoldDirection = forward;
      delta = const Duration(seconds: 10);
    }

    var target = forward ? currentPreview + delta : currentPreview - delta;
    if (target > total) target = total;
    if (target < Duration.zero) target = Duration.zero;

    setState(() {
      previewPosition = target;
    });

    _showSeekIndicator();

    // 1.5 秒內沒有再按方向鍵也自動跳轉 (AC-B3)
    autoSeekTimer?.cancel();
    autoSeekTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && isSeekPreviewMode) {
        confirmPreviewSeek();
      }
    });
  }

  void seekForward({bool repeat = false}) => _performSeek(true, repeat: repeat);

  void seekBackward({bool repeat = false}) =>
      _performSeek(false, repeat: repeat);

  /// 預覽模式下繼續快進/快退
  void seekPreviewForward({bool repeat = false}) =>
      _performSeek(true, repeat: repeat);

  void seekPreviewBackward({bool repeat = false}) =>
      _performSeek(false, repeat: repeat);

  /// 確認預覽跳轉 (AC-B3, AC-B4)
  void confirmPreviewSeek() {
    autoSeekTimer?.cancel();
    endSeekHold();
    if (previewPosition != null && videoController != null) {
      final target = previewPosition!;
      videoController!.seekTo(target);
      resetDanmakuIndex(target);
      if (wasPlayingBeforeSeek) {
        videoController!.play(); // 跳轉後恢復播放
      }
    }
    _endPreviewMode();
  }

  /// 取消預覽跳轉 (AC-B3, AC-B4)
  void cancelPreviewSeek() {
    autoSeekTimer?.cancel();
    endSeekHold();
    if (originalSeekPosition != null && videoController != null) {
      videoController!.seekTo(originalSeekPosition!);
      resetDanmakuIndex(originalSeekPosition!);
      if (wasPlayingBeforeSeek) {
        videoController!.play(); // 恢復播放
      }
    }
    _endPreviewMode();
  }

  void _endPreviewMode() {
    autoSeekTimer?.cancel();
    endSeekHold();
    setState(() {
      isSeekPreviewMode = false;
      previewPosition = null;
      showSeekIndicator = false;
    });
    seekIndicatorTimer?.cancel();
  }

  void _showSeekIndicator() {
    seekIndicatorTimer?.cancel();
    setState(() => showSeekIndicator = true);
    // 預覽模式下不自動隱藏
    if (!isSeekPreviewMode) {
      seekIndicatorTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => showSeekIndicator = false);
        }
      });
    }
  }

  /// 載入影片快照(雪碧圖)資料
  Future<void> loadVideoshot() async {
    // 始終嘗試載入資料，以便在使用者啟用設定時能夠立即使用
    try {
      final data = await BilibiliApi.getVideoshot(bvid: playingBvid, cid: cid);
      if (mounted && data != null) {
        setState(() => videoshotData = data);
        precachedSpriteIndex = -1;
        // 預快取第一張雪碧圖到 GPU
        _precacheNextSprite(0);
      }
    } catch (e) {
      debugPrint('Failed to load videoshot: $e');
    }
  }

  /// 預快取指定索引的雪碧圖 (滑動視窗: 只保留當前 + 下一張)
  void _precacheNextSprite(int index) {
    if (videoshotData == null || index >= videoshotData!.images.length) return;
    if (index <= precachedSpriteIndex) return; // 已快取

    // 清理更早的雪碧圖 (保留 index-1 和 index)
    if (index > 1) {
      VideoshotApi.evictSprite(videoshotData!.images[index - 2]);
    }

    // 預快取新的雪碧圖
    VideoshotApi.precacheSprite(context, videoshotData!.images[index]);
    precachedSpriteIndex = index;
  }

  /// 檢查是否需要預載入下一張雪碧圖 (播放過程中呼叫)
  void _checkSpritePreload(Duration position) {
    if (videoshotData == null) return;

    final l = videoshotData!.framesPerImage;
    final frame = videoshotData!.getIndex(position);
    final spriteIdx = frame ~/ l;

    // 如果當前幀已超過該雪碧圖的 80%，預載入下一張
    if (frame % l > l * 0.8 && spriteIdx + 1 < videoshotData!.images.length) {
      _precacheNextSprite(spriteIdx + 1);
    }
  }

  /// 清理所有雪碧圖的記憶體快取
  void _clearSpritesFromMemory() {
    if (videoshotData == null) return;
    for (final url in videoshotData!.images) {
      VideoshotApi.evictSprite(url);
    }
    videoshotData = null;
    precachedSpriteIndex = -1;
  }

  // ========== 進度條拖動控制 (Feature 4) ==========

  void enterProgressBarMode() {
    if (videoController == null) return;
    setState(() {
      isProgressBarFocused = true;
      previewPosition = null; // 初始無預覽，顯示當前位置
    });
    hideTimer?.cancel();
  }

  void exitProgressBarMode({bool commit = false}) {
    if (commit && previewPosition != null && videoController != null) {
      videoController!.seekTo(previewPosition!);
      resetDanmakuIndex(previewPosition!);
    }
    setState(() {
      isProgressBarFocused = false;
      previewPosition = null;
    });
    startHideTimer();
  }

  /// 開始調整進度 - 設定初始預覽位置
  void startAdjustProgress(int seconds) {
    if (videoController == null) return;
    previewPosition ??= videoController!.value.position;
    adjustProgress(seconds);
  }

  /// 結束調整進度 - 跳轉到預覽位置
  void commitProgress() {
    if (previewPosition != null && videoController != null) {
      videoController!.seekTo(previewPosition!);
      resetDanmakuIndex(previewPosition!);
      setState(() => previewPosition = null);
    }
  }

  void adjustProgress(int seconds) {
    if (videoController == null || previewPosition == null) return;
    final total = videoController!.value.duration;
    final newPos = previewPosition! + Duration(seconds: seconds);
    setState(() {
      if (newPos < Duration.zero) {
        previewPosition = Duration.zero;
      } else if (newPos > total) {
        previewPosition = total;
      } else {
        previewPosition = newPos;
      }
    });
  }

  void toggleDanmaku() {
    setState(() {
      danmakuEnabled = !danmakuEnabled;
    });
    showZhToast(msg: danmakuEnabled ? '彈幕已開啟' : '彈幕已關閉');
    toggleControls();
  }

  void updateDanmakuOption() {
    danmakuController?.updateOption(
      DanmakuOption(
        opacity: danmakuOpacity,
        fontSize: danmakuFontSize,
        // 彈幕飛行速度隨播放倍速同步調整
        duration: danmakuSpeed / playbackSpeed,
        area: danmakuArea,
        hideTop: hideTopDanmaku,
        hideBottom: hideBottomDanmaku,
      ),
    );
  }

  void adjustDanmakuSetting(int direction) {
    setState(() {
      switch (focusedSettingIndex) {
        case 0:
          danmakuEnabled = !danmakuEnabled;
          break;
        case 1:
          danmakuOpacity = (danmakuOpacity + 0.1 * direction).clamp(0.1, 1.0);
          break;
        case 2:
          danmakuFontSize = (danmakuFontSize + 2.0 * direction).clamp(
            10.0,
            50.0,
          );
          break;
        case 3:
          final areas = [0.25, 0.5, 0.75, 1.0];
          int currentIndex = areas.indexOf(danmakuArea);
          if (currentIndex == -1) currentIndex = 1;
          int newIndex = (currentIndex + direction).clamp(0, areas.length - 1);
          danmakuArea = areas[newIndex];
          break;
        case 4:
          danmakuSpeed = (danmakuSpeed + 1.0 * direction).clamp(4.0, 20.0);
          break;
        case 5:
          hideTopDanmaku = !hideTopDanmaku;
          break;
        case 6:
          hideBottomDanmaku = !hideBottomDanmaku;
          break;
      }
      updateDanmakuOption();
      saveSettings();
    });
  }

  /// 依 cid 更新番劇當前集的 ep_id / bvid / aid
  void _applyPgcEpisode(int forCid) {
    final idx = episodes.indexWhere((e) => e['cid'] == forCid);
    if (idx == -1) return;
    final ep = episodes[idx];
    currentEpId = ep['ep_id'] as int? ?? currentEpId;
    final epBvid = ep['bvid'] as String? ?? '';
    if (epBvid.isNotEmpty) currentBvid = epBvid;
    final epAid = ep['aid'] as int? ?? 0;
    if (epAid > 0) aid = epAid;
  }

  Future<void> switchEpisode(int newCid) async {
    if (newCid == cid) return;

    cancelUpNext();
    // 切集前先儲存目前這集的進度 (番劇以 season 為 key，只保留最後一集)
    if (isPgc) {
      await reportPlaybackProgress();
      _applyPgcEpisode(newCid);
    }

    subtitleGen++;
    subtitleCid = null;
    // 切集後重新判斷音軌，避免沿用上一集的杜比／Hi-Res 狀態
    currentAudioKind = AudioKind.standard;
    setState(() {
      cid = newCid;
      subtitleTracks = [];
      subtitleLines = [];
      subtitleIndex = -1;
      _clampSettingsFocus();
      isPreview = false;
      isLoading = true;
      errorMessage = null;
      showEpisodePanel = false;
      lastDanmakuIndex = 0;
      danmakuList = [];
      hasHandledVideoComplete = false; // 重置播放完成標誌，確保下一集播完後能繼續觸發自動播放
    });

    // 清理舊播放器
    cancelPlayerListeners();
    await videoController?.dispose();
    videoController = null;
    videoController = null;
    LocalServer.instance.clearMpdContent();

    try {
      final playInfo = await BilibiliApi.getVideoPlayUrl(
        bvid: playingBvid,
        audioOverride: audioOverrideNow,
        cid: cid!,
        qn: currentQuality,
        forceCodec: SettingsService.codecFallbackAvc ? VideoCodec.avc : null,
        epId: isPgc ? currentEpId : null,
      );

      if (playInfo == null) {
        if (mounted) {
          setState(() {
            errorMessage = '無法取得播放網址，請稍後再試';
            isLoading = false;
          });
          showZhToast(msg: '無法取得播放網址，請稍後再試');
        }
        return;
      }

      if (playInfo['error'] != null) {
        throw Exception(playInfo['error']);
      }

      if (!mounted) return;
      isPreview = playInfo['isPreview'] == true;
      if (isPreview) {
        showZhToast(msg: '此集為大會員專屬，目前僅提供試看', toastLength: Toast.LENGTH_LONG);
      }
      currentQuality = playInfo['currentQuality'] ?? 80;
      currentCodec = playInfo['codec'] ?? currentCodec;
      _recordStream(playInfo);
      currentAudioUrl = playInfo['audioUrl'];
      recordAudio(playInfo);
      previewFrameUrl = playInfo['previewUrl'] as String?;
      qualities = List<Map<String, dynamic>>.from(playInfo['qualities'] ?? []);

      String? playUrl;

      if (playInfo['dashData'] != null) {
        final mpdContent = await MpdGenerator.generate(playInfo['dashData']);

        LocalServer.instance.setMpdContent(mpdContent);
        playUrl = LocalServer.instance.mpdUrl;
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

      if (playUrl == null || playUrl.isEmpty) {
        throw Exception('無法取得播放網址，請稍後再試');
      }

      // 建立新播放器
      videoController = VideoPlayerController.networkUrl(
        Uri.parse(playUrl),
        httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
          'Referer': 'https://www.bilibili.com/',
          'Origin': 'https://www.bilibili.com',
          if (BaseApi.cookieHeader != null) 'Cookie': BaseApi.cookieHeader!,
        },
        viewType: SettingsService.playerTextureView
            ? VideoViewType.textureView
            : VideoViewType.platformView,
      );

      await videoController!.initialize();

      _setupPlayerListeners();
      await videoController!.play();

      setState(() => isLoading = false);

      startHideTimer();
      await loadDanmaku();
      unawaited(loadSubtitles());

      // 🔥 重新載入當前 P 的雪碧圖資料
      _clearSpritesFromMemory();
      loadVideoshot();

      final idx = episodes.indexWhere((e) => e['cid'] == cid);
      if (idx != -1) setState(() => focusedEpisodeIndex = idx);

      // 恢復倍速
      videoController?.setPlaybackSpeed(playbackSpeed);
    } catch (e) {
      if (_isDecoderError(e) && !isCurrentCodecAvc) {
        await _fallbackToAvc(originalError: e.toString());
        return;
      }
      if (mounted) {
        setState(() {
          final errStr = e.toString().replaceFirst('Exception: ', '');
          errorMessage = '切換失敗: $errStr';
          isLoading = false;
        });
      }
    }
  }

  void activateSetting() {
    if (settingsMenuType == SettingsMenuType.main) {
      switch (focusedSettingIndex) {
        case 0:
          showQualityPicker();
          break;
        case 1:
          setState(() {
            settingsMenuType = SettingsMenuType.audio;
            final i = audioOptions.indexWhere(
              (o) => o.kind == currentAudioKind,
            );
            focusedSettingIndex = i < 0 ? 0 : i;
          });
          break;
        case 2:
          setState(() {
            settingsMenuType = SettingsMenuType.danmaku;
            focusedSettingIndex = 0;
          });
          break;
        case 3:
          setState(() {
            settingsMenuType = SettingsMenuType.speed;
            focusedSettingIndex = 0;
          });
          break;
        case 4:
          setState(() {
            settingsMenuType = SettingsMenuType.cdn;
            focusedSettingIndex = 0;
          });
          break;
        case 5:
          // 收藏：開收藏夾選擇對話框（關閉後焦點回到播放器），套用後更新星星
          favoriteVideoFlow(context, aid, video: favVideo).then((faved) {
            if (mounted && faved != null) videoActions.setFavorited(faved);
          });
          break;
        case 6:
          setState(() {
            settingsMenuType = SettingsMenuType.playEnd;
            focusedSettingIndex = SettingsService.playRepeat.index;
          });
          break;
        case 7:
          if (subtitleTracks.isNotEmpty) {
            setState(() {
              settingsMenuType = SettingsMenuType.subtitle;
              focusedSettingIndex = subtitleIndex + 1;
            });
          }
          break;
      }
    } else if (settingsMenuType == SettingsMenuType.danmaku) {
      if (focusedSettingIndex == 0 ||
          focusedSettingIndex == 5 ||
          focusedSettingIndex == 6) {
        adjustDanmakuSetting(1);
      }
    } else if (settingsMenuType == SettingsMenuType.speed) {
      final speed = availableSpeeds[focusedSettingIndex];
      setState(() => playbackSpeed = speed);
      videoController?.setPlaybackSpeed(speed);
      showZhToast(msg: '倍速已設定為 ${speed}x');
    } else if (settingsMenuType == SettingsMenuType.playEnd) {
      final mode = PlayRepeat.values[focusedSettingIndex];
      SettingsService.setPlayRepeat(mode);
      setState(() {
        settingsMenuType = SettingsMenuType.main;
        focusedSettingIndex = 6;
      });
    } else if (settingsMenuType == SettingsMenuType.audio) {
      _activateAudio();
    } else if (settingsMenuType == SettingsMenuType.subtitle) {
      selectSubtitle(focusedSettingIndex - 1);
      setState(() {
        settingsMenuType = SettingsMenuType.main;
        focusedSettingIndex = subtitleTracks.isNotEmpty ? 7 : 6;
      });
    }
  }

  /// [auto] 為 true 表示由卡頓自動降畫質觸發；使用者手動選擇會停止該影片的自動降級
  Future<void> switchQuality(
    int qn, {
    bool auto = false,
    String? doneMsg, // 非 null 時改用此訊息（空字串表示不顯示）
    Duration? resumeAt,
  }) async {
    if (stallSwitching) return;
    if (!auto) perfTracker.userPicked = true;
    final position =
        resumeAt ?? videoController?.value.position ?? Duration.zero;

    setState(() => isLoading = true);

    try {
      var playInfo = await BilibiliApi.getVideoPlayUrl(
        bvid: playingBvid,
        audioOverride: audioOverrideNow,
        cid: cid!,
        qn: qn,
        forceCodec: SettingsService.codecFallbackAvc ? VideoCodec.avc : null,
        epId: isPgc ? currentEpId : null,
      );

      if (playInfo == null || playInfo['error'] != null) {
        final msg = playInfo == null
            ? '無法取得播放網址，請稍後再試'
            : '切換畫質失敗：${playInfo['error']}';
        showZhToast(msg: msg);
        setState(() => isLoading = false);
        return;
      }

      // 此裝置硬體解碼能力不足時，嘗試降到可解碼的最高畫質
      var chosenQn = qn;
      if (playInfo['hwDecodable'] == false) {
        String qnDesc(int q, Map<String, dynamic> info) {
          final list = (info['qualities'] as List?) ?? qualities;
          for (final item in list) {
            if (item is Map && item['qn'] == q && item['desc'] != null) {
              return item['desc'].toString();
            }
          }
          return '${q}P';
        }

        final cap = playInfo['maxDecodableQn'] as int?;
        String? toastMsg;
        if (cap != null && cap < qn) {
          final retry = await BilibiliApi.getVideoPlayUrl(
            bvid: playingBvid,
            audioOverride: audioOverrideNow,
            cid: cid!,
            qn: cap,
            forceCodec: SettingsService.codecFallbackAvc
                ? VideoCodec.avc
                : null,
            epId: isPgc ? currentEpId : null,
          );
          if (retry != null && retry['error'] == null) {
            toastMsg =
                '此電視無法順暢播放 ${qnDesc(qn, playInfo)}，已改用 ${qnDesc(cap, retry)}';
            playInfo = retry;
            chosenQn = cap;
          }
        }
        toastMsg ??= '此電視可能無法順暢播放 ${qnDesc(qn, playInfo)}';
        showZhToast(msg: toastMsg, toastLength: Toast.LENGTH_LONG);
      }

      // 清理舊播放器
      cancelPlayerListeners();
      await videoController?.dispose();
      LocalServer.instance.clearMpdContent();

      if (!mounted) return;
      isPreview = playInfo['isPreview'] == true;
      if (isPreview) {
        showZhToast(msg: '此集為大會員專屬，目前僅提供試看', toastLength: Toast.LENGTH_LONG);
      }
      currentQuality = playInfo['currentQuality'] ?? chosenQn;
      currentCodec = playInfo['codec'] ?? currentCodec;
      _recordStream(playInfo);
      currentAudioUrl = playInfo['audioUrl'];
      recordAudio(playInfo);
      previewFrameUrl = playInfo['previewUrl'] as String?;
      qualities = List<Map<String, dynamic>>.from(
        playInfo['qualities'] ?? qualities,
      );

      String? playUrl;

      if (playInfo['dashData'] != null) {
        final mpdContent = await MpdGenerator.generate(playInfo['dashData']);

        LocalServer.instance.setMpdContent(mpdContent);
        playUrl = LocalServer.instance.mpdUrl;
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

      if (playUrl == null || playUrl.isEmpty) {
        throw Exception('無法取得播放網址，請稍後再試');
      }

      // 建立新播放器
      videoController = VideoPlayerController.networkUrl(
        Uri.parse(playUrl),
        httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
          'Referer': 'https://www.bilibili.com/',
          'Origin': 'https://www.bilibili.com',
          if (BaseApi.cookieHeader != null) 'Cookie': BaseApi.cookieHeader!,
        },
        viewType: SettingsService.playerTextureView
            ? VideoViewType.textureView
            : VideoViewType.platformView,
      );

      await videoController!.initialize();
      await videoController!.seekTo(position);
      resetDanmakuIndex(position);

      _setupPlayerListeners();
      await videoController!.play();

      // 恢復倍速
      videoController?.setPlaybackSpeed(playbackSpeed);

      setState(() => isLoading = false);

      final msg =
          doneMsg ??
          (auto
              ? "播放不順，已自動降為 $currentQualityDesc"
              : "已切換到 $currentQualityDesc");
      if (msg.isNotEmpty) showZhToast(msg: msg);
    } catch (e) {
      if (_isDecoderError(e) && !isCurrentCodecAvc) {
        await _fallbackToAvc(
          resumePosition: position,
          originalError: e.toString(),
        );
        return;
      }
      setState(() {
        final errStr = e.toString().replaceFirst('Exception: ', '');
        errorMessage = '切換失敗: $errStr';
        isLoading = false;
      });
    }
  }

  /// 音質子選單確認：不支援的音軌不可選；選定後記住並從目前位置重新載入
  void _activateAudio() {
    if (audioOptions.isEmpty) return;
    final i = focusedSettingIndex.clamp(0, audioOptions.length - 1);
    final opt = audioOptions[i];
    if (!opt.supported) {
      showZhToast(msg: "此裝置不支援");
      return;
    }
    setState(() {
      settingsMenuType = SettingsMenuType.main;
      focusedSettingIndex = 1;
    });
    if (opt.kind == currentAudioKind) return;
    switchAudio(opt.kind);
  }

  Future<void> switchAudio(AudioKind kind) async {
    // 正在切換畫質／重載時 switchQuality 會直接返回，先擋下避免偏好與實際音軌不一致
    if (stallSwitching) return;
    await SettingsService.setPreferredAudio(kind);
    setAudioOverride(kind);
    await switchQuality(
      currentQuality,
      auto: true,
      doneMsg: "已切換到音質：${audioKindLabel(kind)}",
      resumeAt: lastPlaybackPosition,
    );
  }

  /// 杜比/Hi-Res 播放失敗：本影片改用標準音質重新載入（不改使用者偏好）
  Future<void> fallbackAudioToStandard() async {
    setAudioOverride(AudioKind.standard);
    showZhToast(msg: "此裝置無法播放杜比音軌，已改用標準音質", toastLength: Toast.LENGTH_LONG);
    await switchQuality(
      currentQuality,
      auto: true,
      doneMsg: "",
      resumeAt: lastPlaybackPosition,
    );
  }

  void showQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2D2D2D),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      builder: (context) {
        return QualityPickerSheet(
          qualities: qualities,
          currentQuality: currentQuality,
          onSelect: (qn) {
            Navigator.pop(context);
            if (qn != currentQuality) {
              switchQuality(qn);
            }
          },
        );
      },
    );
  }
}
