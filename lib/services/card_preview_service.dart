import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../models/video.dart';
import '../screens/player/player_screen.dart';
import 'api/base_api.dart';
import 'bilibili_api.dart';
import 'btr/btr_proxy.dart';
import 'play_params.dart';
import 'playback_preparer.dart';
import 'prefetch_service.dart';
import 'settings_service.dart';

/// 目前正在播放的卡片預覽
class CardPreviewState {
  final Object owner;
  final VideoPlayerController controller;

  const CardPreviewState(this.owner, this.controller);
}

/// 影片卡片焦點預覽服務（單例，同一時間最多一個預覽）
///
/// 兩種模式：
/// - 暖機（UGC 且沒有播放頁開著）：用 PlaybackPreparer 建立正式畫質的播放器，
///   靜音預覽，按 OK 時由播放頁 take 接手。會使用 LocalServer 的 MPD。
/// - 480P 預覽（番劇，或播放頁開著時）：不使用 LocalServer。
/// 預覽失敗一律靜默，保持封面；不得修改任何設定、不得 toast。
class CardPreviewService {
  CardPreviewService._();
  static final CardPreviewService instance = CardPreviewService._();

  static const Duration _previewDuration = Duration(seconds: 10);
  static const Duration _initTimeout = Duration(seconds: 8);
  static const Duration _cacheTtl = Duration(minutes: 3);
  static const int _cacheMax = 50;
  static const int _failLimit = 3;
  static const Duration _pauseDuration = Duration(seconds: 60);
  static const Duration _warmTimeout = Duration(seconds: 10);
  static const Duration _warmHold = Duration(seconds: 60);
  static const Duration _reserveTimeout = Duration(seconds: 5);

  /// 只有 initialize 成功並開始播放後才會有值
  final ValueNotifier<CardPreviewState?> current = ValueNotifier(null);

  int _generation = 0;
  Object? _owner; // 準備中或播放中的擁有者
  Timer? _stopTimer;
  VideoPlayerController? _controller;

  // ---- 暖機狀態 ----
  PreparedPlayback? _prepared; // 已就緒、尚未被 take 的暖機播放器
  Timer? _holdTimer; // 預覽暫停後保留上限
  Timer? _reserveTimer; // reserve 後未被 take 的自動釋放
  VoidCallback? _errorListener;
  bool _reserved = false;

  // 進行中的暖機（尚未就緒）。按 OK 時若暖機還在跑，播放頁等它完成，
  // 不要丟掉重來（兩個播放器同時載入反而更慢）。
  String? _pendingBvid;
  Completer<void>? _pendingDone;
  bool _pendingReserved = false;

  /// 此 bvid 的暖機是否仍在準備中且已保留給播放頁
  bool isPendingFor(String bvid) =>
      _pendingBvid == bvid && _pendingReserved && _pendingDone != null;

  /// 播放頁：等進行中的暖機完成後接手；最多等 [maxWait]。
  Future<PreparedPlayback?> waitAndTake(
    String bvid, {
    Duration maxWait = const Duration(seconds: 8),
  }) async {
    final ready = take(bvid);
    if (ready != null) return ready;
    final done = _pendingDone;
    if (!isPendingFor(bvid) || done == null) return null;
    await done.future.timeout(maxWait, onTimeout: () {});
    final p = take(bvid);
    if (p == null) {
      // 逾時或失敗：放棄這次暖機，讓播放頁自己準備
      _pendingReserved = false;
      stopAll();
    }
    return p;
  }

  /// 已保留給播放頁（或已被接手）的 controller；卡片不得再顯示它
  VideoPlayerController? _claimedController;

  bool isClaimed(VideoPlayerController controller) =>
      identical(_claimedController, controller);

  /// 此影片是否會走暖機（UGC、沒有播放頁開著）
  bool willWarm(Video video) =>
      !video.isLive &&
      !video.isPgc &&
      video.bvid.isNotEmpty &&
      PlayerScreen.activeCount == 0;

  final Map<String, ({String url, DateTime at})> _urlCache = {};
  int _failCount = 0;
  DateTime? _pausedUntil;

  Future<void> start(Object owner, Video video) async {
    stopAll();
    if (!SettingsService.cardPreview) return;
    if (video.isLive || video.bvid.isEmpty) return;
    if (video.isPgc && video.epId <= 0) return;
    final pausedUntil = _pausedUntil;
    if (pausedUntil != null && DateTime.now().isBefore(pausedUntil)) return;

    final gen = ++_generation;
    _owner = owner;
    _claimedController = null;
    if (willWarm(video)) return _startWarm(owner, video, gen);
    VideoPlayerController? controller;

    try {
      final rawUrl = await _resolveUrl(video);
      if (gen != _generation) return;
      if (rawUrl == null) return;
      // 經 BtrProxy 走多節點備援：部分 CDN 節點直連會回 HTTP 567，
      // 播放器能播是因為走 BtrProxy。只登記來源，不動 LocalServer 的 MPD。
      final url = await BtrProxy.wrap(rawUrl);
      if (gen != _generation) return;

      controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
          'Referer': 'https://www.bilibili.com/',
          'Origin': 'https://www.bilibili.com',
          if (BaseApi.cookieHeader != null) 'Cookie': BaseApi.cookieHeader!,
        },
        viewType: VideoViewType.textureView,
      );
      await controller.setVolume(0);
      await controller.setLooping(false);
      await controller.initialize().timeout(_initTimeout);
      if (gen != _generation) {
        _disposeController(controller);
        return;
      }
      await controller.play();
      if (gen != _generation) {
        _disposeController(controller);
        return;
      }

      _controller = controller;
      controller.addListener(() {
        if (gen == _generation && controller!.value.hasError) {
          stop(owner);
        }
      });
      current.value = CardPreviewState(owner, controller);
      _stopTimer?.cancel();
      _stopTimer = Timer(_previewDuration, () => stop(owner));
    } catch (_) {
      // 預覽失敗：靜默保持封面
      if (controller != null) _disposeController(controller);
      if (gen == _generation) {
        _generation++;
        _owner = null;
      }
    }
  }

  // ===================== 暖機 =====================

  Future<void> _startWarm(Object owner, Video video, int gen) async {
    bool cancelled() => gen != _generation;
    final watch = Stopwatch()..start();
    final done = Completer<void>();
    _pendingBvid = video.bvid;
    _pendingDone = done;
    _pendingReserved = false;
    debugPrint('🔥 [Warm] start ${video.bvid}');
    try {
      final outcome =
          await PlaybackPreparer.prepare(
            video,
            qn: PlayParams.initialQn,
            warm: true,
            videoInfo: PrefetchService.instance.peekVideoInfo(video.bvid),
            isCancelled: cancelled,
            onStep: (s) => debugPrint(
              '🔥 [Warm] $s ${watch.elapsedMilliseconds}ms ${video.bvid}',
            ),
          ).timeout(
            _warmTimeout,
            onTimeout: () {
              // 逾時：取消準備，晚到的 controller 會由 prepare 自行釋放
              if (!cancelled()) {
                _generation++;
                _owner = null;
              }
              _recordFailure();
              return const PrepareOutcome(cancelled: true);
            },
          );
      final prepared = outcome.playback;
      if (prepared == null) {
        if (!outcome.cancelled && !outcome.redirect && outcome.error != null) {
          _recordFailure();
        }
        if (!cancelled()) {
          _generation++;
          _owner = null;
        }
        return;
      }
      if (cancelled()) {
        _disposeController(prepared.controller);
        return;
      }
      _failCount = 0;
      final controller = prepared.controller;
      await controller.setVolume(0);
      await controller.setLooping(false);
      if (cancelled()) {
        _disposeController(controller);
        return;
      }
      await controller.play();
      if (cancelled()) {
        _disposeController(controller);
        return;
      }

      _prepared = prepared;
      debugPrint(
        '🔥 [Warm] ready ${watch.elapsedMilliseconds}ms ${video.bvid}',
      );
      if (_pendingReserved) {
        // 準備期間已按 OK：直接保留給播放頁，不在卡片上預覽
        _pendingReserved = false;
        _reserveFor(prepared);
        return;
      }
      void onChange() {
        if (gen == _generation && controller.value.hasError) stop(owner);
      }

      _errorListener = onChange;
      controller.addListener(onChange);
      current.value = CardPreviewState(owner, controller);
      _stopTimer?.cancel();
      _stopTimer = Timer(_previewDuration, () => _pauseWarm(gen));
    } catch (e) {
      debugPrint('🔥 [Warm] failed: $e');
      if (gen == _generation) _pendingReserved = false;
      if (gen == _generation) {
        _generation++;
        _owner = null;
      }
    } finally {
      if (identical(_pendingDone, done)) {
        _pendingBvid = null;
        _pendingDone = null;
      }
      if (!done.isCompleted) done.complete();
    }
  }

  /// 預覽時間到：暫停並恢復封面，但保留已緩衝的播放器
  void _pauseWarm(int gen) {
    if (gen != _generation) return;
    final p = _prepared;
    if (p == null) return;
    p.controller.pause();
    _clearCurrentDeferred();
    _holdTimer?.cancel();
    _holdTimer = Timer(_warmHold, () {
      if (gen == _generation) stopAll();
    });
  }

  /// 按 OK：把暖機結果保留給播放頁。尚未就緒則取消準備，改走播放頁自己的流程。
  void reserve(String bvid) {
    final p = _prepared;
    if (p != null && p.bvid == bvid) {
      _reserveFor(p);
    } else if (_pendingBvid == bvid && _pendingDone != null) {
      // 還在準備：保留給播放頁，卡片失焦不取消，完成後由 waitAndTake 接手
      _pendingReserved = true;
      _owner = null;
      _clearCurrentDeferred();
    } else {
      stopAll();
    }
  }

  void _reserveFor(PreparedPlayback p) {
    {
      _reserved = true;
      _owner = null; // 之後卡片失焦、dispose 的 stop(this) 不會釋放它
      _claimedController = p.controller;
      _stopTimer?.cancel();
      _stopTimer = null;
      _holdTimer?.cancel();
      _holdTimer = null;
      _reserveTimer?.cancel();
      _reserveTimer = Timer(_reserveTimeout, () {
        if (_reserved && identical(_prepared, p)) stopAll();
      });
      _clearCurrentDeferred();
    }
  }

  /// 播放頁接手：bvid 相符就交出並清空自身引用
  PreparedPlayback? take(String bvid) {
    final p = _prepared;
    if (p == null || p.bvid != bvid) return null;
    _prepared = null;
    _reserved = false;
    _claimedController = p.controller;
    _generation++;
    _owner = null;
    _cancelTimers();
    final l = _errorListener;
    if (l != null) p.controller.removeListener(l);
    _errorListener = null;
    _clearCurrentDeferred();
    return p;
  }

  void _cancelTimers() {
    _stopTimer?.cancel();
    _stopTimer = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    _reserveTimer?.cancel();
    _reserveTimer = null;
  }

  /// 不在 build 期間通知：延到畫面之後再清掉 current
  void _clearCurrentDeferred() {
    final snapshot = current.value;
    if (snapshot == null) return;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (identical(current.value, snapshot)) current.value = null;
    });
    binding.scheduleFrame();
  }

  // ===================== 480P 預覽 =====================

  /// 取得預覽串流網址；失敗回傳 null
  Future<String?> _resolveUrl(Video video) async {
    final cached = _urlCache[video.bvid];
    if (cached != null && DateTime.now().difference(cached.at) < _cacheTtl) {
      return cached.url;
    }
    _urlCache.remove(video.bvid);

    // 先用焦點預載的結果，省一次 playurl 請求
    final prefetched = await PrefetchService.instance.takePreviewUrl(
      video.bvid,
    );
    if (prefetched != null) {
      _failCount = 0;
      if (_urlCache.length >= _cacheMax) {
        _urlCache.remove(_urlCache.keys.first);
      }
      _urlCache[video.bvid] = (url: prefetched, at: DateTime.now());
      return prefetched;
    }

    int cid = video.cid;
    if (video.isPgc) {
      if (cid <= 0) return null; // 避免取到別集
    } else if (cid <= 0) {
      cid =
          PrefetchService.instance.peekInfoCid(video.bvid) ??
          await BilibiliApi.getVideoCid(video.bvid) ??
          0;
      if (cid <= 0) {
        _recordFailure();
        return null;
      }
    }

    final info = await BilibiliApi.getVideoPlayUrl(
      bvid: video.bvid,
      cid: cid,
      qn: 32,
      epId: video.isPgc ? video.epId : null,
    );
    final previewUrl = info?['previewUrl'];
    if (info == null ||
        info['error'] != null ||
        info['isPreview'] == true ||
        info['previewIsAvc'] != true ||
        previewUrl is! String ||
        previewUrl.isEmpty) {
      _recordFailure();
      return null;
    }

    _failCount = 0;
    if (_urlCache.length >= _cacheMax) {
      _urlCache.remove(_urlCache.keys.first);
    }
    _urlCache[video.bvid] = (url: previewUrl, at: DateTime.now());
    return previewUrl;
  }

  void _recordFailure() {
    _failCount++;
    if (_failCount >= _failLimit) {
      _failCount = 0;
      _pausedUntil = DateTime.now().add(_pauseDuration);
    }
  }

  /// owner 相同（含準備中）才停止
  void stop(Object owner) {
    if (!identical(_owner, owner)) return;
    stopAll();
  }

  /// 無條件停止（含已保留未接手的暖機播放器）
  void stopAll() {
    _generation++;
    _owner = null;
    _reserved = false;
    _pendingReserved = false;
    _cancelTimers();
    final controller = _controller;
    _controller = null;
    final prepared = _prepared;
    _prepared = null;
    _errorListener = null;
    // 先讓畫面移除 VideoPlayer（下一個 frame 後通知），再釋放 controller
    _clearCurrentDeferred();
    if (controller != null) _disposeController(controller);
    if (prepared != null) _disposeController(prepared.controller);
  }

  /// 等畫面不再使用 controller 後才釋放（兩個 frame：先通知卡片移除，再 dispose）
  void _disposeController(VideoPlayerController controller) {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      binding.addPostFrameCallback((_) => controller.dispose());
      binding.scheduleFrame();
    });
    binding.scheduleFrame();
  }
}
