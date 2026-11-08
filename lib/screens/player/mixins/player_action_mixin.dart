import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:bili_tv_app/utils/zh_toast.dart';
import 'dart:async';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:video_player/video_player.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/video.dart' as models;
import '../../../services/bilibili_api.dart';
import '../../../services/settings_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/mpd_generator.dart';
import '../../../services/local_server.dart';
import '../../../services/api/videoshot_api.dart';
import '../../../services/api/base_api.dart';
import '../widgets/settings_panel.dart';
import '../player_screen.dart';
import '../widgets/quality_picker_sheet.dart';
import 'player_state_mixin.dart';
import '../../../core/plugin/plugin_manager.dart';
import '../../../core/plugin/plugin_types.dart';
import '../../../services/playback_progress_cache.dart';
import '../../../services/btr/btr_proxy.dart';
import '../../../services/frame_service.dart';
import '../../../services/codec_service.dart';
import '../../../services/api/pgc_api.dart';

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

      // 番劇不走 UGC 的 view API，改由季資訊取得集數
      final videoInfo = isPgc
          ? null
          : await BilibiliApi.getVideoInfo(widget.video.bvid);

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

        // 1. 首次請求: 使用預設畫質(80)或當前設定畫質
        // 這樣可以獲取到影片實際支援的 accept_quality 列表，而不是盲猜
        var playInfo = await BilibiliApi.getVideoPlayUrl(
          bvid: playingBvid,
          cid: cid!,
          qn: currentQuality,
          forceCodec: tryCodec,
          epId: isPgc ? currentEpId : null,
        );

        // 2. 智慧升級 (僅針對 VIP)
        // 如果是 VIP 且首次請求成功，檢查是否有更高畫質可用
        if (AuthService.isVip &&
            playInfo != null &&
            playInfo['qualities'] != null) {
          final qualities = playInfo['qualities'] as List;
          if (qualities.isNotEmpty) {
            // 獲取該影片支援的最高畫質
            // qualities 是 List<Map<String, dynamic>>, 需提取 qn 並排序
            final supportedQns = qualities.map((e) => e['qn'] as int).toList();
            // 解碼上限（缺少時不限制）與 HDR 顯示限制
            final cap = playInfo['maxDecodableQn'] as int?;
            final hdrOk = await CodecService.isHdrDisplay();
            final allowedQns = supportedQns.where(
              (q) =>
                  (cap == null || q <= cap) &&
                  (hdrOk || (q != 125 && q != 126)),
            );
            if (allowedQns.isNotEmpty) {
              final maxQn = allowedQns.reduce(
                (curr, next) => curr > next ? curr : next,
              );
              final currentQn = playInfo['currentQuality'] as int? ?? 0;

              // 如果最高畫質 > 當前畫質 (且當前畫質只是預設的80，或者我們想強制升級)
              // 注意: 有時候 maxQn 可能高達 127/126，而 currentQn 只有 80
              if (maxQn > currentQn) {
                debugPrint(
                  '🎬 [SmartQuality] VIP detected. Upgrading from $currentQn to $maxQn',
                );

                final upgradePlayInfo = await BilibiliApi.getVideoPlayUrl(
                  bvid: playingBvid,
                  cid: cid!,
                  qn: maxQn, // 精確請求最高畫質
                  forceCodec: tryCodec,
                  epId: isPgc ? currentEpId : null,
                );

                // 如果升級請求成功，使用新資料（若指定 tryCodec 則升級結果不可偏離所要求編碼）
                if (upgradePlayInfo != null &&
                    upgradePlayInfo['hwDecodable'] == false) {
                  debugPrint('🎬 [SmartQuality] 升級後的串流無法硬體解碼，沿用 $currentQn');
                } else if (upgradePlayInfo != null &&
                    upgradePlayInfo['error'] == null &&
                    (tryCodec == null ||
                        (upgradePlayInfo['codec'] as String? ?? '')
                            .toLowerCase()
                            .startsWith(tryCodec.prefix))) {
                  playInfo = upgradePlayInfo;
                }
              }
            }
          }
        }

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
        currentAudioUrl = playInfo['audioUrl'];
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
              ? await BtrProxy.wrap(rawUrl, backups: backups)
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
              viewType: VideoViewType.platformView,
            );

            // 初始化
            await videoController!.initialize();
            break; // 成功，跳出迴圈
          } catch (e) {
            // 清理失敗的控制器
            await videoController?.dispose();
            videoController = null;

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
        startHideTimer();

        await loadDanmaku();
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

  /// 轉向番劇播放：以新的 PlayerScreen 取代目前頁面（尚未建立 videoController）。
  void _redirectToPgc(int seasonId, int epId) {
    debugPrint('🎬 [PGC] redirect to season=$seasonId ep=$epId');
    if (!mounted) return;
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

  Future<void> loadDanmaku() async {
    if (cid == null) return;
    try {
      final danmaku = await BilibiliApi.getDanmaku(cid!);
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

  /// 解碼失敗時自動降級改用 AVC (H.264)
  Future<void> _fallbackToAvc({
    Duration? resumePosition,
    String? originalError,
  }) async {
    if (isFallingBackToAvc) return;
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
      currentAudioUrl = playInfo['audioUrl'];
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
            ? await BtrProxy.wrap(rawUrl, backups: backups)
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
        viewType: VideoViewType.platformView,
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
    setState(() => showControls = true);

    // 試看片段播完不是真的看完：不連播、不回報完播
    if (isPreview) {
      showZhToast(msg: '試看結束，此集為大會員專屬');
      return;
    }

    // 檢查是否開啟自動連播
    if (!SettingsService.autoPlay) return;

    // 暫停當前影片
    if (videoController != null && videoController!.value.isPlaying) {
      videoController!.pause();
    }

    // 1. 檢查是否有下一集
    if (episodes.length > 1 && cid != null) {
      final currentIndex = episodes.indexWhere((ep) => ep['cid'] == cid);
      if (currentIndex >= 0 && currentIndex < episodes.length - 1) {
        // 有下一集，自動播放
        final nextEp = episodes[currentIndex + 1];
        final nextCid = nextEp['cid'] as int;
        showZhToast(
          msg:
              '自動播放下一集: ${nextEp['title'] ?? nextEp['part'] ?? 'P${currentIndex + 2}'}',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.TOP,
        );
        switchEpisode(nextCid);
        return;
      }
    }

    // 番劇最後一集播完：不跳推薦，只回報完播
    if (isPgc) {
      reportPlaybackProgress(overrideProgress: -1);
      return;
    }

    // 2. 所有集數播完，檢查相關影片
    if (relatedVideos.isNotEmpty) {
      final nextVideo = relatedVideos.first;
      showZhToast(
        msg: '自動播放推薦影片',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.TOP,
      );
      // 導航到新影片
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            video: models.Video(
              bvid: nextVideo['bvid'] ?? '',
              title: nextVideo['title'] ?? '',
              pic: nextVideo['pic'] ?? '',
              ownerName: nextVideo['owner']?['name'] ?? '',
              ownerFace: nextVideo['owner']?['face'] ?? '',
              duration: nextVideo['duration'] ?? 0,
              pubdate: nextVideo['pubdate'] ?? 0,
              view: nextVideo['stat']?['view'] ?? 0,
            ),
          ),
        ),
      );
    }

    // 🔥 3. 無論是否有後續動作，都強制上報一次"已看完"
    reportPlaybackProgress(overrideProgress: -1);
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
    setState(() => showControls = true);
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
          setState(() {
            showControls = false;
            showActionButtons = false;
          });
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

  /// 計算連按快進/快退每次移動秒數 (AC-B2)
  int _calculateSeekStep(bool forward) {
    final now = DateTime.now();
    if (lastSeekPressTime != null &&
        now.difference(lastSeekPressTime!) <
            const Duration(milliseconds: 800) &&
        lastSeekDirection == forward) {
      seekPressCount++;
    } else {
      seekPressCount = 1;
      lastSeekDirection = forward;
    }
    lastSeekPressTime = now;

    if (seekPressCount > 8) {
      return 60;
    } else if (seekPressCount > 3) {
      return 30;
    } else {
      return 10;
    }
  }

  /// 執行快退/快進操作（Netflix 式進度預覽，不立即跳轉）
  void _performSeek(bool forward) {
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

    Duration target;
    if (videoshotData != null && videoshotData!.frameCount > 1) {
      // 有縮圖資料：每次按鍵移動一幀 (AC-C5)
      final currentK = videoshotData!.indexAt(currentPreview, total);
      final nextK = forward ? currentK + 1 : currentK - 1;
      final clampedK = nextK.clamp(0, videoshotData!.frameCount - 1);
      target = videoshotData!.timeOfIndex(clampedK, total);
    } else {
      // 沒有縮圖資料：維持現有 10／30／60 秒加速 (AC-C6)
      final step = _calculateSeekStep(forward);
      target = forward
          ? currentPreview + Duration(seconds: step)
          : currentPreview - Duration(seconds: step);

      if (target < Duration.zero) target = Duration.zero;
      if (target > total) target = total;
    }

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

  void seekForward() => _performSeek(true);

  void seekBackward() => _performSeek(false);

  /// 預覽模式下繼續快進/快退
  void seekPreviewForward() => _performSeek(true);

  void seekPreviewBackward() => _performSeek(false);

  /// 確認預覽跳轉 (AC-B3, AC-B4)
  void confirmPreviewSeek() {
    autoSeekTimer?.cancel();
    seekPressCount = 0;
    lastSeekPressTime = null;
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
    seekPressCount = 0;
    lastSeekPressTime = null;
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
    seekPressCount = 0;
    lastSeekPressTime = null;
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

    // 切集前先儲存目前這集的進度 (番劇以 season 為 key，只保留最後一集)
    if (isPgc) {
      await reportPlaybackProgress();
      _applyPgcEpisode(newCid);
    }

    setState(() {
      cid = newCid;
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
      currentAudioUrl = playInfo['audioUrl'];
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
            ? await BtrProxy.wrap(rawUrl, backups: backups)
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
        viewType: VideoViewType.platformView,
      );

      await videoController!.initialize();

      _setupPlayerListeners();
      await videoController!.play();

      setState(() => isLoading = false);

      startHideTimer();
      await loadDanmaku();

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
            settingsMenuType = SettingsMenuType.danmaku;
            focusedSettingIndex = 0;
          });
          break;
        case 2:
          setState(() {
            settingsMenuType = SettingsMenuType.speed;
            focusedSettingIndex = 0;
          });
          break;
        case 3:
          setState(() {
            settingsMenuType = SettingsMenuType.cdn;
            focusedSettingIndex = 0;
          });
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
    }
  }

  Future<void> switchQuality(int qn) async {
    final position = videoController?.value.position ?? Duration.zero;

    setState(() => isLoading = true);

    try {
      var playInfo = await BilibiliApi.getVideoPlayUrl(
        bvid: playingBvid,
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
            cid: cid!,
            qn: cap,
            forceCodec:
                SettingsService.codecFallbackAvc ? VideoCodec.avc : null,
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
      currentAudioUrl = playInfo['audioUrl'];
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
            ? await BtrProxy.wrap(rawUrl, backups: backups)
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
        viewType: VideoViewType.platformView,
      );

      await videoController!.initialize();
      await videoController!.seekTo(position);
      resetDanmakuIndex(position);

      _setupPlayerListeners();
      await videoController!.play();

      // 恢復倍速
      videoController?.setPlaybackSpeed(playbackSpeed);

      setState(() => isLoading = false);

      showZhToast(msg: '已切換到 $currentQualityDesc');
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
