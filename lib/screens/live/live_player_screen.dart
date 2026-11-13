import 'package:bili_tv_app/widgets/content_text.dart';
import 'package:bili_tv_app/utils/format_count.dart';
import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:bili_tv_app/utils/zh_toast.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    show VideoPlayerPlatform;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api/live_api.dart';
import '../../services/api/base_api.dart';
import '../../services/device_profile.dart';
import '../../services/frame_service.dart';
import '../../utils/seek_speed.dart';
import '../../services/live/live_timeshift.dart';
import '../../services/live_socket_service.dart';
import '../../services/memory_budget.dart';
import '../../services/settings_service.dart';
import '../../widgets/time_display.dart';
import '../home/settings/widgets/tv_menu_dialog.dart';
import 'widgets/live_chat_panel.dart';
import 'widgets/live_settings_panel.dart';

class LivePlayerScreen extends StatefulWidget {
  final int roomId;
  final String title;
  final String? cover;
  final String? uname;
  final String? face;
  final int? online;

  const LivePlayerScreen({
    super.key,
    required this.roomId,
    required this.title,
    this.cover,
    this.uname,
    this.face,
    this.online,
  });

  @override
  State<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends State<LivePlayerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  final LiveSocketService _socketService = LiveSocketService();
  DanmakuController? _danmakuController;

  bool _isLoading = true;
  String? _errorMessage;
  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _popularityTimer;
  String _onlineCount = '0';

  /// 開播時間（room/v1/Room/get_info 的 live_time，北京時間）；未開播或取不到為 null
  DateTime? _liveStart;

  /// 控制列顯示時每秒更新「已開播」時間
  Timer? _liveClockTimer;

  // Settings State
  bool _showSettingsPanel = false;
  LiveSettingsMenuType _settingsMenuType = LiveSettingsMenuType.main;
  int _focusedSettingIndex = 0;
  // Controls: 0:播放/暫停, 1:彈幕, 2:留言, 3:畫質, 4:線路, 5:關注
  int _focusedControlIndex = 0;
  static const int _maxControlIndex = 5;
  final FocusNode _focusNode = FocusNode();

  // 彈窗（showTvMenuDialog）開著時，本畫面的按鍵處理放行
  bool _dialogOpen = false;

  // 彈幕按鈕長按（500ms 開啟彈幕設定面板），模式同一般影片
  static const Duration _danmakuHoldDelay = Duration(milliseconds: 500);
  Timer? _danmakuHoldTimer;
  bool _danmakuHolding = false;
  // 放開後 150ms 內沒有再按下才判定短按（容忍模擬器連發的按下／放開）
  static const Duration _danmakuUpDelay = Duration(milliseconds: 150);
  Timer? _danmakuUpTimer;
  // 長按觸發後吞掉確認鍵事件，直到安靜 200ms
  bool _danmakuSwallow = false;
  Timer? _danmakuSwallowTimer;

  // 播放器重連：generation token + 看門狗（唯一的重連觸發來源）
  int _playerGen = 0;
  bool _initializing = false;
  bool _userPaused = false;
  bool _appInBackground = false;
  Timer? _watchdog;
  Timer? _retryTimer;
  int _retryCount = 0;
  int _stallSeconds = 0;
  int _playingSeconds = 0;
  Duration? _lastPosition;
  bool _playerOutageToasted = false;
  static const int _stallLimitSeconds = 10;

  // 本機時移（#51）：_ts 非 null 即為時移模式
  LiveTimeshiftSession? _ts;
  StreamSubscription<LiveTimeshiftState>? _tsSub;
  // 本次畫面是否已因 fatal 而停用時移
  bool _tsDisabled = false;
  // 播放器位置（相對於播放清單視窗起點，不夾限），每秒輪詢一次
  Duration _tsPosition = Duration.zero;
  // 暫停當下的絕對位置，繼續時換算回播放器位置
  Duration? _pausedAbs;
  // 時移停住偵測（#56）
  Duration? _tsLastPos;
  int _tsStallSeconds = 0;
  int _tsStableSeconds = 0;
  DateTime? _tsLastKick;
  // 預覽快轉（#54）：_tsPreviewAbs 非 null 即在預覽中（絕對位置）
  Duration? _tsPreviewAbs;
  Duration _tsPreviewOrigin = Duration.zero;
  bool _tsPreviewWasPlaying = false;
  DateTime? _tsHoldStart;
  DateTime? _tsHoldLast;
  bool? _tsHoldForward;
  Timer? _tsPreviewTimer;
  Timer? _tsFrameTimer;
  // 預覽縮圖：key 為相對中心的卡片位置（-2..2），值為 JPEG；片段快取以檔案路徑為 key
  final Map<int, Uint8List?> _tsThumbs = {};
  // 以片段編號 n 為 key 的 LRU（最多 30 張）
  final Map<int, Uint8List> _tsThumbCache = {};
  static const int _tsThumbCacheMax = 30;
  int _tsFrameReq = 0;
  static const Duration _tsSeekStep = Duration(seconds: 10);
  static const Duration _tsLiveThreshold = Duration(seconds: 5);

  bool get _tsActive => _ts != null;

  // 彈幕 socket 重連
  StreamSubscription<Map<String, dynamic>>? _msgSub;
  Timer? _socketRetryTimer;
  Timer? _socketStableTimer;
  int _socketRetryCount = 0;
  bool _socketOutageToasted = false;

  // 聊天列表（留言）
  bool _showChat = false;
  bool _chatPopup = true; // 留言樣式：彈出式／列表
  bool _chatOnLeft = true; // 留言位置：左側／右側
  final List<LiveChatMessage> _chatMessages = [];
  int _chatSeq = 0;
  static const int _chatMaxCount = 100;

  // Danmaku Settings
  bool _danmakuEnabled = true;
  double _danmakuOpacity = 0.6;
  double _danmakuFontSize = 17.0;
  double _danmakuArea = 0.25;
  double _danmakuSpeed = 10.0;
  bool _hideTopDanmaku = false;
  bool _hideBottomDanmaku = false;

  // Line State
  final List<Map<String, dynamic>> _lines = [];
  int _currentLineIndex = 0;
  int _realRoomId = 0;

  // Quality State
  List<Map<String, dynamic>> _qualities = [];
  int _currentQuality = 10000;
  String _currentQualityDesc = '原畫';

  // Follow State
  bool _isFollowed = false;
  int _anchorUid = 0;

  // Double back to exit
  DateTime? _lastBackPressed;

  @override
  void initState() {
    super.initState();
    _realRoomId = widget.roomId; // Default
    // _danmakuController will be set by DanmakuScreen
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _showChat = SettingsService.liveChatVisible;
    _chatPopup = SettingsService.liveChatStyle != 'list';
    _chatOnLeft = SettingsService.liveChatSide != 'right';
    // 只訂閱一次；socket 重連沿用同一個 broadcast stream，不會重複訂閱
    _msgSub = _socketService.messageStream.listen(_onSocketMessage);
    _watchdog = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _watchdogTick(),
    );
    // Initialize online count from widget
    final initialOnline = widget.online ?? 0;
    _onlineCount = formatCount(initialOnline);

    _loadSettings().then((_) {
      if (!mounted) return;
      _initializePlayer();
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _danmakuEnabled = prefs.getBool('danmaku_enabled') ?? true;
      _danmakuOpacity = prefs.getDouble('danmaku_opacity') ?? 0.6;
      _danmakuFontSize = prefs.getDouble('danmaku_font_size') ?? 17.0;
      _danmakuArea = prefs.getDouble('danmaku_area') ?? 0.25;
      _danmakuSpeed = prefs.getDouble('danmaku_speed') ?? 10.0;
      _hideTopDanmaku = prefs.getBool('hide_top_danmaku') ?? false;
      _hideBottomDanmaku = prefs.getBool('hide_bottom_danmaku') ?? false;

      // Live specific control bar setting
      if (SettingsService.hideLiveControlsOnStart) {
        _showControls = false;
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('danmaku_enabled', _danmakuEnabled);
    await prefs.setDouble('danmaku_opacity', _danmakuOpacity);
    await prefs.setDouble('danmaku_font_size', _danmakuFontSize);
    await prefs.setDouble('danmaku_area', _danmakuArea);
    await prefs.setDouble('danmaku_speed', _danmakuSpeed);
    await prefs.setBool('hide_top_danmaku', _hideTopDanmaku);
    await prefs.setBool('hide_bottom_danmaku', _hideBottomDanmaku);
    if (!mounted) return;
    _updateDanmakuOption();
  }

  void _updateDanmakuOption() {
    if (_danmakuController != null) {
      _danmakuController!.updateOption(
        DanmakuOption(
          opacity: _danmakuOpacity,
          fontSize: _danmakuFontSize,
          area: _danmakuArea,
          duration: _danmakuSpeed / 1.0, // Live is always 1x speed
          hideTop: _hideTopDanmaku,
          hideBottom: _hideBottomDanmaku,
        ),
      );
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    _playerGen++; // 讓進行中的初始化失效
    _msgSub?.cancel();
    _msgSub = null;
    // _danmakuController is disposed by its widget usually, or doesn't need disposal
    _socketService.dispose();
    _hideTimer?.cancel();
    _popularityTimer?.cancel();
    _liveClockTimer?.cancel();
    _watchdog?.cancel();
    _retryTimer?.cancel();
    _socketRetryTimer?.cancel();
    _socketStableTimer?.cancel();
    _danmakuHoldTimer?.cancel();
    _danmakuUpTimer?.cancel();
    _danmakuSwallowTimer?.cancel();
    _tsPreviewTimer?.cancel();
    _tsFrameTimer?.cancel();
    _controller?.dispose();
    _controller = null;
    _disposeTs();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused) {
      _appInBackground = true;
      if (_tsActive && !_userPaused) _tsCapturePause();
      _controller?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
      if (_tsActive) {
        // 時移模式：只在未暫停時從原位置繼續，不重新連線
        if (!_userPaused) _tsResumePlay();
      } else if (!_userPaused) {
        // 使用者沒有暫停：重新連到最新畫面，而不是單純 play()
        _initializePlayer(lineIndex: _currentLineIndex, auto: true);
      }
    }
  }

  // ───────────── 播放器重連 ─────────────

  /// 退避：2s、4s、8s… 上限 30s
  Duration _backoff(int count) {
    final secs = math.min(30, 2 * (1 << math.min(count, 4)));
    return Duration(seconds: secs);
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _scheduleRetry() {
    if (!mounted || _userPaused || _retryTimer != null) return;
    final delay = _backoff(_retryCount);
    _retryCount++;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!mounted || _userPaused) return;
      _initializePlayer(lineIndex: _currentLineIndex, auto: true);
    });
  }

  void _toastPlayerOutage() {
    if (_playerOutageToasted) return;
    _playerOutageToasted = true;
    showZhToast(msg: '直播連線中斷，正在重新連線...');
  }

  /// 每秒檢查一次：hasError，或緩衝／位置未前進連續 10 秒時重連
  void _watchdogTick() {
    if (!mounted) return;
    if (_tsActive) {
      _pollTsPosition();
      _tsTickDynamic();
      // 暫停、初始化、背景、預覽中：不做停住偵測，背景縮圖也先停
      if (_userPaused ||
          _initializing ||
          _appInBackground ||
          _tsPreviewAbs != null) {
        _ts?.thumbnailsEnabled = false;
        _tsStallSeconds = 0;
        _tsStableSeconds = 0;
        _tsLastPos = null;
      }
    }
    if (_userPaused || _initializing || _appInBackground) return;
    if (_retryTimer != null) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final v = c.value;
    if (v.hasError) {
      _toastPlayerOutage();
      _scheduleRetry();
      return;
    }
    // 時移模式：只有 hasError 才重建播放器；緩衝或落後直播很近時是在等新片段，
    // 錄製端會自己重新取流，不在這裡重連
    if (_tsActive) {
      _tsStallCheck(c);
      return;
    }
    final pos = v.position;
    final stalled = v.isBuffering || pos == _lastPosition;
    _lastPosition = pos;
    if (stalled) {
      _playingSeconds = 0;
      _stallSeconds++;
      if (_stallSeconds >= _stallLimitSeconds) {
        _stallSeconds = 0;
        _toastPlayerOutage();
        _scheduleRetry();
      }
    } else {
      _stallSeconds = 0;
      _playingSeconds++;
      if (_playingSeconds >= 10) {
        // 穩定播放 10 秒：重置退避與提示
        _retryCount = 0;
        _playerOutageToasted = false;
      }
    }
  }

  /// 時移模式停住偵測：位置（原生未夾限）連續 8 秒未前進且有新資料可播時，
  /// 先跳到最新位置；30 秒內再停住就重建播放器。同時控制背景縮圖開關（穩定 10 秒後才開）。
  void _tsStallCheck(VideoPlayerController c) {
    if (_tsPreviewAbs != null) return;
    final ts = _ts;
    if (ts == null) return;
    final pos = _tsPosition;
    final last = _tsLastPos;
    _tsLastPos = pos;
    if (last != null && pos > last && !c.value.isBuffering) {
      _tsStallSeconds = 0;
      if (++_tsStableSeconds >= 10) ts.thumbnailsEnabled = true;
      return;
    }
    _tsStableSeconds = 0;
    ts.thumbnailsEnabled = false;
    if (last == null) return; // 剛開始計時，沒有比較基準
    if (++_tsStallSeconds < 8) return;
    // 有新資料可播（暫存尾端比目前位置多 3 秒以上）才算卡住；否則是在等新片段
    final ahead = ts.bufferedDuration - ts.liveEdgeOffset - pos;
    if (ahead < const Duration(seconds: 3)) return;
    _tsStallSeconds = 0;
    final now = DateTime.now();
    final kick = _tsLastKick;
    if (kick != null && now.difference(kick) < const Duration(seconds: 30)) {
      _tsLastKick = null;
      _toastPlayerOutage();
      _initializePlayer(lineIndex: _currentLineIndex, auto: true);
      return;
    }
    _tsLastKick = now;
    _tsSeekToAbs(ts.liveAbsolute).whenComplete(() {
      if (mounted && c == _controller) c.play();
    });
  }

  void _pausePlayback() {
    if (_userPaused) return;
    _playerGen++; // 取消進行中的初始化
    _cancelRetry();
    _controller?.pause();
    if (_tsActive && _controller?.value.isInitialized == true) {
      _tsCapturePause();
    }
    setState(() {
      _userPaused = true;
      _initializing = false;
      if (_controller != null && _controller!.value.isInitialized) {
        _isLoading = false;
      }
    });
  }

  void _resumePlayback() {
    if (!_userPaused) return;
    if (_tsActive && _controller?.value.isInitialized == true) {
      // 時移：從暫停的位置接著播，不重新連線
      _tsResumePlay();
      return;
    }
    // 重新連到最新畫面（_initializePlayer 會清除暫停狀態）
    _initializePlayer(lineIndex: _currentLineIndex);
  }

  void _togglePlayPause() {
    if (_userPaused) {
      _resumePlayback();
    } else {
      _pausePlayback();
    }
  }

  /// [auto] 為 true 表示由重連機制呼叫（保留退避計數）；
  /// 使用者操作（換畫質、換線路、繼續播放）會重置退避並清除暫停狀態。
  /// 每次呼叫遞增 generation，await 後與當前世代不符就放棄（並釋放新建的 controller）。
  Future<void> _initializePlayer({
    int? qn,
    int? lineIndex,
    bool auto = false,
  }) async {
    if (!mounted) return;
    final gen = ++_playerGen;
    _cancelRetry();
    if (!auto) {
      _userPaused = false;
      _retryCount = 0;
      _playerOutageToasted = false;
    }
    _initializing = true;
    _stallSeconds = 0;
    _playingSeconds = 0;
    _lastPosition = null;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    VideoPlayerController? newController;
    LiveTimeshiftSession? newTs;
    // 換畫質、換線路、重連都先丟掉舊暫存（AC-13）
    _disposeTs();
    _tsPosition = Duration.zero;
    _pausedAbs = null;
    _tsLastPos = null;
    _tsStallSeconds = 0;
    _tsStableSeconds = 0;
    _tsResetPreview(clearCache: true);
    try {
      // 0. Resolve Real Room ID (only once)
      Map<String, dynamic>? roomInfo;
      if (_realRoomId == widget.roomId) {
        roomInfo = await LiveApi.getRoomInfo(widget.roomId);
        if (!mounted || gen != _playerGen) return;
        if (roomInfo != null && roomInfo['room_id'] != null) {
          _realRoomId = roomInfo['room_id'];
        }
        _updateLiveStart(roomInfo);
      }

      // 1. 獲取播放地址：優先 v2（多線路、HLS），失敗退回 v1
      final reqQn = qn ?? _currentQuality;
      final tsMinutes = _tsDisabled
          ? 0
          : MemoryBudget.liveTimeshiftMinutes(
              DeviceProfile.currentTier,
              SettingsService.liveTimeshiftMinutes,
            );
      var useTs = tsMinutes > 0;
      final v2 = await LiveApi.getRoomPlayInfo(_realRoomId, qn: reqQn);
      if (!mounted || gen != _playerGen) return;
      _ParsedPlay? parsed = v2 == null
          ? null
          : _parseV2(v2, timeshift: useTs);
      if (parsed != null && useTs && !parsed.tsOk) {
        // 此直播沒有 HLS fmp4 + avc：關閉時移，照一般流程播放
        useTs = false;
        showZhToast(msg: '此直播不支援時移');
        parsed = _parseV2(v2!, timeshift: false);
      }
      if (parsed == null || parsed.lines.isEmpty) {
        useTs = false;
        final playInfo = await LiveApi.getPlayUrl(_realRoomId, qn: reqQn);
        if (!mounted || gen != _playerGen) return;
        if (playInfo == null) {
          throw Exception('獲取直播地址失敗');
        }
        parsed = _parseV1(playInfo, qn);
      }

      _lines
        ..clear()
        ..addAll(parsed.lines);
      if (parsed.qualities.isNotEmpty) _qualities = parsed.qualities;
      _currentQuality = parsed.currentQn ?? reqQn;

      // Select Line
      int targetLineIndex = lineIndex ?? 0;
      if (targetLineIndex >= _lines.length) targetLineIndex = 0;
      _currentLineIndex = targetLineIndex;

      if (_lines.isEmpty) {
        throw Exception('無法獲取有效播放地址');
      }
      String url = _lines[_currentLineIndex]['url'] as String;

      final q = _qualities.firstWhere(
        (e) => e['qn'] == _currentQuality,
        orElse: () => {'desc': '未知($_currentQuality)'},
      );
      _currentQualityDesc = q['desc'] ?? '未知';

      // 時移：建立本機錄製 session，改播本機網址
      if (useTs) {
        final curQn = _currentQuality;
        final lineIdx = _currentLineIndex;
        final session = LiveTimeshiftSession(
          resolveUrl: () async {
            final d = await LiveApi.getRoomPlayInfo(_realRoomId, qn: curQn);
            if (d == null) return null;
            final p = _parseV2(d, timeshift: true);
            if (!p.tsOk || p.lines.isEmpty) return null;
            final i = lineIdx < p.lines.length ? lineIdx : 0;
            return p.lines[i]['url'] as String;
          },
          maxBuffer: Duration(minutes: tsMinutes),
          headers: _liveHeaders(),
        );
        newTs = session;
        try {
          url = await session.start();
        } catch (e) {
          debugPrint('LivePlayer: timeshift start failed: $e');
          await session.dispose();
          newTs = null;
          if (!mounted || gen != _playerGen) return;
          useTs = false;
          showZhToast(msg: '直播時移啟動失敗，改為一般播放');
          final plain = _parseV2(v2!, timeshift: false);
          if (plain.lines.isEmpty) throw Exception('無法獲取有效播放地址');
          _lines
            ..clear()
            ..addAll(plain.lines);
          if (_currentLineIndex >= _lines.length) _currentLineIndex = 0;
          url = _lines[_currentLineIndex]['url'] as String;
        }
        if (!mounted || gen != _playerGen) {
          await newTs?.dispose();
          return;
        }
      }

      // 3. Get Anchor Info & Relationship
      if (_anchorUid == 0 && roomInfo != null) {
        _anchorUid = roomInfo['uid'] ?? 0;
      }
      if (_anchorUid > 0) {
        LiveApi.getRelation(_anchorUid).then((relation) {
          if (mounted && relation != null) {
            setState(() {
              // attribute: 1=悄悄關注, 2=關注, 6=互粉, 128=拉黑
              // simpler check: just check if attribute is not 0 (no relation)
              // But standard API returns specific fields usually.
              // Let's assume relation map has 'attribute'
              final attr = relation['attribute'] as int? ?? 0;
              _isFollowed = attr == 2 || attr == 6;
            });
          }
        });
      }

      // 4. 初始化播放器
      newController = useTs
          ? VideoPlayerController.networkUrl(
              Uri.parse(url),
              formatHint: VideoFormat.hls,
              viewType: VideoViewType.platformView,
            )
          : VideoPlayerController.networkUrl(
              Uri.parse(url),
              httpHeaders: _liveHeaders(),
              viewType: VideoViewType.platformView,
            );

      await newController.initialize();
      if (!mounted || gen != _playerGen) {
        await newController.dispose();
        await newTs?.dispose();
        return;
      }
      final oldController = _controller;
      _controller = newController;
      newController = null; // 所有權交給 _controller
      if (newTs != null) {
        final session = newTs;
        newTs = null;
        _ts = session;
        _tsSub = session.states.listen((st) {
          if (st == LiveTimeshiftState.fatal && mounted && _ts == session) {
            _onTsFatal();
          }
        });
      }
      oldController?.dispose();
      if (_tsActive) await _controller!.setPlaybackSpeed(1.0);
      await _controller!.play();
      if (!mounted || gen != _playerGen) return;

      _initializing = false;
      setState(() {
        _isLoading = false;
      });

      if (!SettingsService.hideLiveControlsOnStart) {
        _startHideTimer();
      }

      // 3. 連線彈幕 (Use Real ID)；已連線、連線中或等待重連時不重複連線
      if (!_socketService.isConnected && _socketRetryTimer == null) {
        _socketService.connect(_realRoomId);
      }

      // 4. Start API polling for popularity (fallback for socket)
      _startPopularityTimer();
    } catch (e) {
      await newController?.dispose();
      await newTs?.dispose();
      if (!mounted || gen != _playerGen) return;
      _initializing = false;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
      // 取得網址或初始化失敗：退避重試
      _toastPlayerOutage();
      _scheduleRetry();
    }
  }

  Map<String, String> _liveHeaders() => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
    'Referer': 'https://live.bilibili.com/',
    if (BaseApi.cookieHeader != null) 'Cookie': BaseApi.cookieHeader!,
  };

  /// 解析 v2 回應。時移開啟時只取 http_hls + fmp4 + avc（[_ParsedPlay.tsOk]）；
  /// 否則 http_hls 優先、其次 http_stream，codec 選 avc。
  _ParsedPlay _parseV2(Map<String, dynamic> data, {required bool timeshift}) {
    final playurl = (data['playurl_info'] as Map?)?['playurl'] as Map?;
    final streams = (playurl?['stream'] as List?) ?? const [];

    Map? findCodec(String protocol, String? format) {
      for (final st in streams) {
        if (st['protocol_name'] != protocol) continue;
        for (final f in (st['format'] as List?) ?? const []) {
          if (format != null && f['format_name'] != format) continue;
          for (final c in (f['codec'] as List?) ?? const []) {
            if (c['codec_name'] == 'avc') return c as Map;
          }
        }
      }
      return null;
    }

    Map? codec;
    var tsOk = false;
    if (timeshift) {
      codec = findCodec('http_hls', 'fmp4');
      tsOk = codec != null;
    }
    codec ??= findCodec('http_hls', null) ?? findCodec('http_stream', null);

    final lines = <Map<String, dynamic>>[];
    int? currentQn;
    var qualities = <Map<String, dynamic>>[];
    if (codec != null) {
      final baseUrl = codec['base_url'] as String? ?? '';
      var i = 1;
      for (final info in (codec['url_info'] as List?) ?? const []) {
        lines.add({
          'name': '線路 $i',
          'url': '${info['host']}$baseUrl${info['extra']}',
        });
        i++;
      }
      currentQn = codec['current_qn'] as int?;
      final desc = <int, String>{
        for (final d in (playurl?['g_qn_desc'] as List?) ?? const [])
          if (d['qn'] is int) d['qn'] as int: (d['desc'] as String? ?? ''),
      };
      qualities = [
        for (final q in (codec['accept_qn'] as List?) ?? const [])
          if (q is int)
            {
              'qn': q,
              'desc': ZhConvert.convert(
                (desc[q] ?? '').isEmpty ? '$q' : desc[q]!,
              ),
            },
      ];
    }
    return _ParsedPlay(lines, qualities, currentQn, tsOk);
  }

  /// v1 後備：沿用原本的攤平邏輯
  _ParsedPlay _parseV1(Map<String, dynamic> playInfo, int? qn) {
    final lines = <Map<String, dynamic>>[];
    final playurlInfo = playInfo['playurl_info'];
    if (playurlInfo != null) {
      final streams = playurlInfo['playurl']['stream'] as List?;
      if (streams != null) {
        var counter = 1;
        void addLinesFromProtocol(String protocol) {
          final stream = streams.firstWhere(
            (s) => s['protocol_name'] == protocol,
            orElse: () => null,
          );
          if (stream == null) return;
          for (final format in (stream['format'] as List?) ?? const []) {
            for (final codec in (format['codec'] as List?) ?? const []) {
              final baseUrl = codec['base_url'] as String;
              for (final info in (codec['url_info'] as List?) ?? const []) {
                lines.add({
                  'name': '線路$counter',
                  'url': '${info['host']}$baseUrl${info['extra']}',
                });
                counter++;
              }
            }
          }
        }

        addLinesFromProtocol('http_hls');
        addLinesFromProtocol('http_stream');
      }
    }
    if (lines.isEmpty) {
      final durl = playInfo['durl'] as List?;
      if (durl != null && durl.isNotEmpty) {
        lines.add({'name': '預設線路', 'url': durl[0]['url'] as String});
      }
    }
    var qualities = <Map<String, dynamic>>[];
    if (playInfo['quality_description'] != null) {
      final list = List<Map<String, dynamic>>.from(
        playInfo['quality_description'],
      );
      qualities = list.where((q) {
        final desc = q['desc'] as String?;
        // 與伺服器回傳的簡體文字比對，保留原文
        return desc != null && desc != '默认' && desc.isNotEmpty;
      }).toList();
    }
    final cur = qn ?? (playInfo['current_quality'] as int?);
    return _ParsedPlay(lines, qualities, cur, false);
  }

  // ───────────── 本機時移 ─────────────

  void _disposeTs() {
    _tsSub?.cancel();
    _tsSub = null;
    final ts = _ts;
    _ts = null;
    ts?.dispose();
  }

  void _onTsFatal() {
    if (_tsDisabled) return;
    _tsDisabled = true;
    showZhToast(msg: '直播時移已停止，改為一般播放');
    _initializePlayer(lineIndex: _currentLineIndex, auto: true);
  }

  /// 每秒取一次未夾限的原生位置（controller.value.position 會夾在舊 duration）
  Future<void> _pollTsPosition() async {
    final c = _controller;
    final ts = _ts;
    if (c == null || ts == null || !c.value.isInitialized) return;
    try {
      final p = await c.position;
      if (!mounted || p == null || c != _controller || ts != _ts) return;
      _tsPosition = p;
      if (_showControls) setState(() {});
    } catch (_) {}
  }

  /// 暫停或預覽中，暫存持續變動：每秒重算並把絕對位置夾到 droppedDuration 以上
  void _tsTickDynamic() {
    final ts = _ts;
    if (ts == null) return;
    final dropped = ts.droppedDuration;
    final p = _pausedAbs;
    if (_userPaused && p != null && p < dropped) _pausedAbs = dropped;
    final v = _tsPreviewAbs;
    if (v != null && v < dropped) _tsPreviewAbs = dropped;
    if (mounted && (_userPaused || _tsPreviewAbs != null)) setState(() {});
  }

  /// 暫停時記下絕對位置
  Future<void> _tsCapturePause() async {
    final c = _controller;
    final ts = _ts;
    if (c == null || ts == null) return;
    Duration pos = _tsPosition;
    try {
      pos = (await c.position) ?? _tsPosition;
    } catch (_) {}
    if (!mounted || ts != _ts) return;
    _tsPosition = pos;
    _pausedAbs = ts.absoluteOf(pos);
  }

  /// 從暫停位置繼續；暫存已被刪掉時 playerPosFor 會夾到最舊位置
  Future<void> _tsResumePlay() async {
    final c = _controller;
    final ts = _ts;
    if (c == null || ts == null) return;
    final abs = _pausedAbs;
    _pausedAbs = null;
    setState(() {
      _userPaused = false;
      _isLoading = false;
    });
    try {
      if (abs != null) {
        final target = ts.playerPosFor(abs);
        // ignore: invalid_use_of_visible_for_testing_member
        await VideoPlayerPlatform.instance.seekTo(c.playerId, target);
        _tsPosition = target;
      }
      await c.play();
    } catch (e) {
      debugPrint('LivePlayer: timeshift resume failed: $e');
    }
  }

  Future<void> _tsSeekToAbs(Duration abs) async {
    final c = _controller;
    final ts = _ts;
    if (c == null || ts == null || !c.value.isInitialized) return;
    final target = ts.playerPosFor(abs);
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      await VideoPlayerPlatform.instance.seekTo(c.playerId, target);
    } catch (e) {
      debugPrint('LivePlayer: timeshift seek failed: $e');
      return;
    }
    if (!mounted || ts != _ts) return;
    _tsPosition = target;
    if (_userPaused) _pausedAbs = ts.absoluteOf(target);
    setState(() {});
  }

  // ───────────── 時移預覽快轉 ─────────────

  /// 清掉預覽狀態（不 setState、不恢復播放）
  void _tsResetPreview({bool clearCache = false}) {
    _tsPreviewTimer?.cancel();
    _tsPreviewTimer = null;
    _tsFrameTimer?.cancel();
    _tsFrameTimer = null;
    _tsFrameReq++;
    _tsPreviewAbs = null;
    _tsThumbs.clear();
    // 片段編號只在同一個 session 內有意義，換 session 才清快取
    if (clearCache) _tsThumbCache.clear();
    _tsHoldStart = null;
    _tsHoldLast = null;
    _tsHoldForward = null;
  }

  /// 預覽位置的可用範圍（絕對位置）
  (Duration, Duration) _tsPreviewRange(LiveTimeshiftSession ts) {
    final min = ts.droppedDuration;
    var max = ts.liveAbsolute - ts.liveEdgeOffset;
    if (max < min) max = min;
    return (min, max);
  }

  /// 預覽快轉一步：短按 10 秒，按住依 [holdSeekSpeed] 計速（比照一般影片）
  void _tsPreviewStep(bool forward, {required bool repeat}) {
    final ts = _ts;
    final c = _controller;
    if (ts == null || c == null || !c.value.isInitialized || !mounted) return;
    if (_tsPreviewAbs == null) {
      final (_, liveMax) = _tsPreviewRange(ts);
      final startAbs =
          (_userPaused ? _pausedAbs : null) ?? ts.absoluteOf(_tsPosition);
      // 已在最新位置時按右鍵不進入預覽
      if (forward && liveMax - startAbs < _tsLiveThreshold) return;
      _tsPreviewWasPlaying = !_userPaused && c.value.isPlaying;
      _tsPreviewOrigin =
          (_userPaused ? _pausedAbs : null) ?? ts.absoluteOf(_tsPosition);
      // 不走 _pausePlayback：它會 _playerGen++ 並改 _userPaused
      c.pause();
      _hideTimer?.cancel();
      _tsPreviewAbs = _tsPreviewOrigin;
      _showControls = false;
    }
    var cur = _tsPreviewAbs ?? _tsPreviewOrigin;
    if (cur < ts.droppedDuration) cur = ts.droppedDuration;
    final now = DateTime.now();
    Duration delta;
    if (repeat && _tsHoldStart != null && _tsHoldForward == forward) {
      final held = now.difference(_tsHoldStart!);
      var dt = now.difference(_tsHoldLast ?? now);
      if (dt > const Duration(milliseconds: 250)) {
        dt = const Duration(milliseconds: 250);
      }
      _tsHoldLast = now;
      final speed = holdSeekSpeed(held, ts.bufferedDuration);
      delta = Duration(milliseconds: (speed * dt.inMilliseconds).round());
    } else {
      _tsHoldStart = now;
      _tsHoldLast = now;
      _tsHoldForward = forward;
      delta = _tsSeekStep;
    }
    final (min, max) = _tsPreviewRange(ts);
    var target = forward ? cur + delta : cur - delta;
    if (target > max) target = max;
    if (target < min) target = min;
    if (target != _tsPreviewAbs) setState(() => _tsPreviewAbs = target);
    _tsPreviewTimer?.cancel();
    _tsPreviewTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && _tsPreviewAbs != null) _tsConfirmPreview();
    });
    if (repeat) {
      // 按住期間不擷取，並讓原生端丟棄排隊中的舊請求；放開 200ms 後才擷取
      _tsFrameTimer?.cancel();
      _tsFrameReq++;
    } else {
      _tsScheduleFrame();
    }
  }

  /// 250ms debounce 後從本機暫存擷取預覽縮圖：先中央再兩側（間隔 10 秒），
  /// 同片段共用一張圖；載入中保留上一張
  void _tsScheduleFrame() {
    _tsFrameTimer?.cancel();
    final ts = _ts;
    final center = _tsPreviewAbs;
    if (ts == null || center == null) return;
    final req = ++_tsFrameReq;
    _tsFrameTimer = Timer(const Duration(milliseconds: 200), () async {
      for (final k in const [0, -1, 1, -2, 2]) {
        // 預覽已移動（序號改變或位置不同）就停止
        if (!mounted || req != _tsFrameReq || _tsPreviewAbs != center) return;
        final abs = center + _tsSeekStep * k;
        if (!_tsThumbVisible(ts, abs)) continue;
        final src = ts.previewSource(abs);
        if (src == null) continue;
        // 錄製時已預先擷取：build 會直接讀 session 快取，不必再擷取
        if (ts.thumbnailFor(src.n) != null) continue;
        final cached = _tsThumbCache.remove(src.n);
        if (cached != null) {
          _tsThumbCache[src.n] = cached; // LRU：移到最新
          if (!identical(_tsThumbs[k], cached)) {
            setState(() => _tsThumbs[k] = cached);
          }
          continue;
        }
        Uint8List? bytes;
        try {
          bytes = await FrameService.getLocalFrame(src.paths, gen: req);
        } catch (_) {}
        if (!mounted || req != _tsFrameReq || _tsPreviewAbs != center) return;
        if (bytes != null) {
          _tsThumbCache[src.n] = bytes;
          while (_tsThumbCache.length > _tsThumbCacheMax) {
            _tsThumbCache.remove(_tsThumbCache.keys.first);
          }
        }
        setState(() => _tsThumbs[k] = bytes);
      }
    });
  }

  /// 該位置是否可顯示縮圖：在暫存範圍內，且落後最新位置至少 5 秒
  bool _tsThumbVisible(LiveTimeshiftSession ts, Duration abs) {
    final (min, max) = _tsPreviewRange(ts);
    return abs >= min && max - abs >= _tsLiveThreshold;
  }

  /// 確認：跳到預覽位置，預覽前在播放就恢復播放
  void _tsConfirmPreview() {
    final abs = _tsPreviewAbs;
    if (abs == null) return;
    final wasPlaying = _tsPreviewWasPlaying;
    final c = _controller;
    _tsResetPreview();
    setState(() {});
    _tsSeekToAbs(abs).whenComplete(() {
      if (mounted && wasPlaying && c == _controller) c?.play();
    });
  }

  /// 取消：回原位置並恢復播放
  void _tsCancelPreview() {
    if (_tsPreviewAbs == null) return;
    final wasPlaying = _tsPreviewWasPlaying;
    _tsResetPreview();
    setState(() {});
    if (wasPlaying) _controller?.play();
  }

  KeyEventResult _handleTsPreviewKey(KeyEvent event) {
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.goBack) {
      // 交給 PopScope：預覽中先取消預覽，不離開頁面
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight ||
          k == LogicalKeyboardKey.mediaRewind ||
          k == LogicalKeyboardKey.mediaFastForward) {
        final wasHold = _tsHoldStart != null;
        _tsHoldStart = null;
        _tsHoldLast = null;
        _tsHoldForward = null;
        // 方向鍵放開：200ms 後擷取新位置的縮圖
        if (wasHold) _tsScheduleFrame();
      }
      return KeyEventResult.handled;
    }
    final repeat = event is KeyRepeatEvent;
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.mediaRewind) {
      _tsPreviewStep(false, repeat: repeat);
    } else if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.mediaFastForward) {
      _tsPreviewStep(true, repeat: repeat);
    } else if (event is KeyDownEvent) {
      if (_isSelectKey(event)) {
        _tsConfirmPreview();
      } else if (k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.arrowDown ||
          k == LogicalKeyboardKey.escape) {
        _tsCancelPreview();
      }
    }
    return KeyEventResult.handled;
  }

  /// 預覽畫面：版面數值與一般影片的 SeekThumbnailStrip 一致
  /// （底部 55% 高度的漸層、卡片列中心在畫面 60% 處、進度條 left/right 80、bottom 36）。
  /// 中央大卡加左右各 2 張小卡，間隔 10 秒。
  Widget _buildTsPreview() {
    final ts = _ts!;
    final abs = _tsPreviewAbs!;
    final size = MediaQuery.of(context).size;
    final screenW = size.width;
    final screenH = size.height;
    final overlayH = screenH * 0.55;

    final centerW = screenW * 0.24;
    final centerH = centerW * 9 / 16;
    final sideW = screenW * 0.20;
    final sideH = sideW * 9 / 16;
    const spacing = 16.0;
    final cardCenterY = screenH * 0.15;
    final centerLeft = (screenW - centerW) / 2;

    final maxMs =
        ts.maxBuffer.inMilliseconds <= 0 ? 1 : ts.maxBuffer.inMilliseconds;
    final posMs = (abs - ts.droppedDuration).inMilliseconds;
    final frac = (posMs / maxMs).clamp(0.0, 1.0);
    final bufFrac =
        (ts.bufferedDuration.inMilliseconds / maxMs).clamp(0.0, 1.0);
    final (_, max) = _tsPreviewRange(ts);
    final atLive = max - abs < _tsLiveThreshold;
    final lag = ts.liveAbsolute - abs;
    final label = atLive ? 'LIVE' : '-${_formatLiveElapsed(lag)}';
    final totalLabel = _formatLiveElapsed(ts.maxBuffer);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    const barText = TextStyle(
      color: Colors.white,
      fontSize: 18,
      fontWeight: FontWeight.bold,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    Widget card(int k, double left, double w, double h, bool center) {
      final cabs = abs + _tsSeekStep * k;
      if (!_tsThumbVisible(ts, cabs)) return const SizedBox.shrink();
      final n = ts.previewSource(cabs)?.n;
      final img = (n == null ? null : (ts.thumbnailFor(n) ?? _tsThumbCache[n])) ??
          _tsThumbs[k];
      final inner = img == null
          ? const SizedBox.expand()
          : Image.memory(
              img,
              fit: BoxFit.cover,
              cacheWidth: (w * dpr).round(),
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            );
      if (!center) {
        return Positioned(
          left: left,
          top: cardCenterY - h / 2,
          width: w,
          height: h,
          child: Opacity(
            opacity: 0.85,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(color: const Color(0xFF1E1E1E), child: inner),
            ),
          ),
        );
      }
      return Positioned(
        left: left,
        top: cardCenterY - h / 2,
        width: w,
        height: h,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: ColoredBox(color: const Color(0xFF1E1E1E), child: inner),
          ),
        ),
      );
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: overlayH,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.95),
              Colors.black.withValues(alpha: 0.65),
              Colors.transparent,
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
        ),
        child: ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              card(-2, centerLeft - spacing * 2 - sideW * 2, sideW, sideH,
                  false),
              card(-1, centerLeft - spacing - sideW, sideW, sideH, false),
              card(1, centerLeft + centerW + spacing, sideW, sideH, false),
              card(2, centerLeft + centerW + spacing * 2 + sideW, sideW, sideH,
                  false),
              // 最新位置不顯示中央卡（只顯示 LIVE）
              if (!atLive) card(0, centerLeft, centerW, centerH, true),
              Positioned(
                left: 80,
                right: 80,
                bottom: 36,
                child: Row(
                  children: [
                    Text(
                      label,
                      style: atLive
                          ? barText.copyWith(color: const Color(0xFFff4d4f))
                          : barText,
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Stack(
                          children: [
                            // 已暫存範圍
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: bufFrac,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: frac,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFB7299),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Text(totalLabel, style: barText),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onSocketMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    switch (msg['type']) {
      case 'danmaku':
        final text = ZhConvert.convert(msg['content'] as String);
        final user = ZhConvert.convert((msg['user'] as String?) ?? '');
        // 聊天列表：不論彈幕顯示開關都更新
        _chatMessages.add(
          LiveChatMessage(id: ++_chatSeq, user: user, content: text),
        );
        if (_chatMessages.length > _chatMaxCount) {
          _chatMessages.removeRange(0, _chatMessages.length - _chatMaxCount);
        }
        if (_showChat) setState(() {});
        if (_danmakuController != null && _danmakuEnabled) {
          try {
            _danmakuController!.addDanmaku(
              DanmakuContentItem(
                text,
                color: Color(msg['color']).withValues(alpha: 255),
              ),
            );
          } catch (e) {
            debugPrint('Error adding danmaku: $e');
          }
        }
        break;
      case 'popularity':
        final count = msg['count'] as int;
        // Hotfix: Bilibili heartbeat sometimes returns 1 (invalid).
        // If we have a valid count, ignore 1 to avoid UI flicker.
        if (count <= 1) return;
        setState(() => _onlineCount = formatCount(count));
        break;
      case 'connected':
        // 穩定連線 10 秒後才重置退避與提示
        _socketStableTimer?.cancel();
        _socketStableTimer = Timer(const Duration(seconds: 10), () {
          _socketRetryCount = 0;
          _socketOutageToasted = false;
        });
        break;
      case 'error':
        debugPrint('LiveSocket Error: ${msg['msg']}');
        if (!_socketOutageToasted) {
          _socketOutageToasted = true;
          showZhToast(msg: '彈幕連線: ${msg['msg']}');
        }
        break;
      case 'disconnected':
        _socketStableTimer?.cancel();
        _scheduleSocketRetry();
        break;
    }
  }

  void _scheduleSocketRetry() {
    if (!mounted || _socketRetryTimer != null) return;
    final delay = _backoff(_socketRetryCount);
    _socketRetryCount++;
    _socketRetryTimer = Timer(delay, () {
      _socketRetryTimer = null;
      if (!mounted) return;
      _socketService.connect(_realRoomId);
    });
  }

  void _hideControls() {
    if (_showSettingsPanel) return;
    setState(() => _showControls = false);
  }

  void _startHideTimer() {
    // Cancel any existing timer
    _hideTimer?.cancel();
    // Start a new timer
    _hideTimer = Timer(const Duration(seconds: 5), _hideControls);
  }

  void _startPopularityTimer() {
    _popularityTimer?.cancel();
    // Poll API every 60 seconds as a fallback
    _popularityTimer = Timer.periodic(const Duration(seconds: 60), (
      timer,
    ) async {
      try {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final info = await LiveApi.getRoomInfo(_realRoomId);
        if (info != null && mounted) {
          _updateLiveStart(info);
          final online = info['online'] as int?;
          if (online != null && online > 1) {
            setState(() {
              _onlineCount = formatCount(online);
            });
          }
        }
      } catch (e) {
        debugPrint('Error polling popularity: $e');
      }
    });
  }

  /// 解析 get_info 的 live_time（"yyyy-MM-dd HH:mm:ss"，北京時間 UTC+8）。
  /// 未開播時 API 回 "0000-00-00 00:00:00"，視為 null。
  void _updateLiveStart(Map<String, dynamic>? info) {
    final raw = info?['live_time'];
    DateTime? start;
    if (raw is String && raw.isNotEmpty && !raw.startsWith('0000')) {
      start = DateTime.tryParse('${raw.replaceFirst(' ', 'T')}+08:00');
    }
    final status = info?['live_status'];
    if (status is int && status != 1) start = null;
    if (start == _liveStart || !mounted) return;
    setState(() => _liveStart = start);
    _liveClockTimer?.cancel();
    if (start != null) {
      _liveClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _showControls) setState(() {});
      });
    }
  }

  String _formatLiveElapsed(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// 時移進度條：範圍 = 暫存範圍，已播放部分填色，圓點為目前位置
  Widget _buildTimeshiftBar() {
    final ts = _ts!;
    final total = ts.bufferedDuration;
    var pos = _tsPosition;
    if (_userPaused && _pausedAbs != null) {
      pos = _pausedAbs! - ts.droppedDuration;
    }
    // 全長 = 設定的時移長度；已暫存部分與播放位置都以它為分母
    final totalMs =
        ts.maxBuffer.inMilliseconds <= 0 ? 1 : ts.maxBuffer.inMilliseconds;
    final frac = (pos.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final bufFrac = (total.inMilliseconds / totalMs).clamp(0.0, 1.0);
    // 以可到達的最新位置（暫存尾端 - liveEdgeOffset）為基準計算落後，
    // 否則播放器預設的 live edge 本身就落後約 3 個片段，會一直顯示為落後
    var lag = total - ts.liveEdgeOffset - pos;
    if (lag.isNegative) lag = Duration.zero;
    final atLive = lag < _tsLiveThreshold;
    final accent = atLive ? const Color(0xFFff4d4f) : Colors.white38;
    final elapsed = _liveStart == null
        ? null
        : _formatLiveElapsed(DateTime.now().difference(_liveStart!));
    final label = atLive
        ? (elapsed == null ? '直播中' : '已開播 $elapsed')
        : '-${_formatLiveElapsed(lag)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: Colors.white, size: 8),
                SizedBox(width: 4),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  return SizedBox(
                    height: 14,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Container(
                          width: w * bufFrac,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white38,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Container(
                          width: w * frac,
                          height: 4,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Positioned(
                          left: (w * frac - 7).clamp(0.0, w - 14),
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// 直播進度條（只顯示，不能拖動）：LIVE 標記、滿格進度、已開播時間
  Widget _buildLiveBar() {
    if (_tsActive) return _buildTimeshiftBar();
    final live = !_userPaused;
    final accent = live ? const Color(0xFFff4d4f) : Colors.white38;
    final elapsed = _liveStart == null
        ? null
        : _formatLiveElapsed(DateTime.now().difference(_liveStart!));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: Colors.white, size: 8),
                SizedBox(width: 4),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: 1,
                minHeight: 4,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            live
                ? (elapsed == null ? '直播中' : '已開播 $elapsed')
                : '已暫停 · 按播放回到最新畫面',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  bool _isSelectKey(KeyEvent event) =>
      event.logicalKey == LogicalKeyboardKey.select ||
      event.logicalKey == LogicalKeyboardKey.enter;

  void _cancelDanmakuHold() {
    _danmakuHoldTimer?.cancel();
    _danmakuHoldTimer = null;
    _danmakuUpTimer?.cancel();
    _danmakuUpTimer = null;
    _danmakuHolding = false;
  }

  bool get _canHoldDanmaku =>
      _showControls &&
      (_focusedControlIndex == 1 || _focusedControlIndex == 2) &&
      !_showSettingsPanel &&
      !_dialogOpen;

  void _fireDanmakuHold() {
    _danmakuHoldTimer = null;
    if (!mounted || !_danmakuHolding) return;
    _danmakuHolding = false;
    _danmakuUpTimer?.cancel();
    _danmakuUpTimer = null;
    if (!_canHoldDanmaku) return;
    _armDanmakuSwallow();
    _hideTimer?.cancel();
    setState(() {
      _showSettingsPanel = true;
      _settingsMenuType = _focusedControlIndex == 2
          ? LiveSettingsMenuType.chat
          : LiveSettingsMenuType.danmaku;
      _focusedSettingIndex = 0;
    });
  }

  /// 切換留言顯示並寫入設定
  void _toggleChatVisible() {
    final next = !_showChat;
    setState(() => _showChat = next);
    SettingsService.setLiveChatVisible(next);
  }

  /// 留言設定項目：0 顯示、1 樣式、2 位置
  void _activateChatItem(int index) {
    switch (index) {
      case 0:
        _toggleChatVisible();
        break;
      case 1:
        final next = !_chatPopup;
        setState(() => _chatPopup = next);
        SettingsService.setLiveChatStyle(next ? 'popup' : 'list');
        break;
      case 2:
        final next = !_chatOnLeft;
        setState(() => _chatOnLeft = next);
        SettingsService.setLiveChatSide(next ? 'left' : 'right');
        break;
    }
  }

  /// 彈幕(1)／留言(2)按鈕確認鍵：短按切換，按住 500ms 開啟對應設定面板。
  /// 回傳 null 表示事件與彈幕長按無關。
  KeyEventResult? _handleDanmakuHold(KeyEvent event) {
    if (!_isSelectKey(event)) {
      // 按住時按了其他鍵（如左右鍵移開焦點）：取消，不判定短按
      if (_danmakuHolding && event is KeyDownEvent) _cancelDanmakuHold();
      return null;
    }
    // 長按已觸發：吞掉之後所有確認鍵事件，安靜 200ms 才解除
    if (_danmakuSwallow) {
      _armDanmakuSwallow();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      if (_danmakuHolding && _danmakuUpTimer != null) {
        // 放開後 150ms 內再按下：視為持續按住（連發），不重設長按計時
        _danmakuUpTimer?.cancel();
        _danmakuUpTimer = null;
        return KeyEventResult.handled;
      }
      if (!_canHoldDanmaku) return null;
      _danmakuHolding = true;
      _danmakuHoldTimer?.cancel();
      _danmakuHoldTimer = Timer(_danmakuHoldDelay, _fireDanmakuHold);
      return KeyEventResult.handled;
    }
    if (!_danmakuHolding) return null;
    if (event is KeyRepeatEvent) {
      _danmakuUpTimer?.cancel();
      _danmakuUpTimer = null;
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      // 不立刻判定短按，等 150ms 看是否又被按下
      _danmakuUpTimer?.cancel();
      _danmakuUpTimer = Timer(_danmakuUpDelay, _finishDanmakuShortPress);
      return KeyEventResult.handled;
    }
    return null;
  }

  /// 長按觸發後進入吞鍵狀態，並（重新）啟動 200ms 安靜計時
  void _armDanmakuSwallow() {
    _danmakuSwallow = true;
    _danmakuSwallowTimer?.cancel();
    _danmakuSwallowTimer = Timer(const Duration(milliseconds: 200), () {
      _danmakuSwallowTimer = null;
      _danmakuSwallow = false;
    });
  }

  void _finishDanmakuShortPress() {
    _danmakuUpTimer = null;
    if (!mounted || !_danmakuHolding) return;
    _cancelDanmakuHold();
    if (_canHoldDanmaku) {
      if (_focusedControlIndex == 2) {
        _toggleChatVisible();
      } else {
        _toggleDanmakuSetting(0);
      }
      _startHideTimer();
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // 彈窗開著：焦點在彈窗路由，這裡直接放行
    if (_dialogOpen) return KeyEventResult.ignored;

    // 時移預覽中：所有按鍵由預覽處理
    if (_tsPreviewAbs != null) return _handleTsPreviewKey(event);

    final holdResult = _handleDanmakuHold(event);
    if (holdResult != null) return holdResult;

    // 時移模式進入預覽：媒體快轉鍵，或控制列隱藏時的左右鍵
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        _tsActive &&
        !_showSettingsPanel) {
      final k = event.logicalKey;
      final isLeft = k == LogicalKeyboardKey.arrowLeft;
      final isRight = k == LogicalKeyboardKey.arrowRight;
      final isRew = k == LogicalKeyboardKey.mediaRewind;
      final isFf = k == LogicalKeyboardKey.mediaFastForward;
      if (((isLeft || isRight) && !_showControls) || isRew || isFf) {
        _tsPreviewStep(isRight || isFf, repeat: false);
        return KeyEventResult.handled;
      }
    }

    if (event is KeyDownEvent) {
      _startHideTimer(); // Reset timer on input

      if (event.logicalKey == LogicalKeyboardKey.goBack) {
        return KeyEventResult.ignored;
      }

      // 播放/暫停鍵：在「控制列隱藏時吞鍵」之前處理
      if (event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
        _togglePlayPause();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.mediaPlay) {
        _resumePlayback();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.mediaPause) {
        _pausePlayback();
        return KeyEventResult.handled;
      }

      if (event.logicalKey == LogicalKeyboardKey.escape) {
        // 設定面板開著時，Escape 優先關閉設定面板
        if (_showSettingsPanel) {
          setState(() {
            _showSettingsPanel = false;
            _settingsMenuType = LiveSettingsMenuType.main;
          });
          return KeyEventResult.handled;
        }

        if (_showControls) {
          _hideControls();
          return KeyEventResult.handled;
        }
        // Let PopScope handle exit
        return KeyEventResult.ignored;
      }

      if (!_showControls) {
        // Show controls on any key press (except Back logic above)
        setState(() => _showControls = true);
        return KeyEventResult.handled;
      }

      if (_showSettingsPanel) {
        _handleSettingsKeyEvent(event);
        return KeyEventResult.handled;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _hideControls();
        return KeyEventResult.handled;
      }

      // Handle Control Bar Navigation
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        setState(() {
          _focusedControlIndex = (_focusedControlIndex - 1).clamp(
            0,
            _maxControlIndex,
          );
        });
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        setState(() {
          _focusedControlIndex = (_focusedControlIndex + 1).clamp(
            0,
            _maxControlIndex,
          );
        });
        return KeyEventResult.handled;
      } else if (_isSelectKey(event)) {
        // 彈幕鈕(1)的確認鍵由長按判定處理；走到這裡只會是其他按鈕
        _handleControlSelect();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _handleControlSelect() async {
    final hasLines = _lines.length > 1;
    // 0:播放/暫停, 1:彈幕, 2:留言, 3:畫質, 4:線路, 5:關注
    switch (_focusedControlIndex) {
      case 0:
        _togglePlayPause();
        break;
      case 1:
        // 正常由長按判定處理；保底行為為切換彈幕
        _toggleDanmakuSetting(0);
        break;
      case 2:
        _toggleChatVisible();
        break;
      case 3:
        setState(() {
          _showSettingsPanel = true;
          _settingsMenuType = LiveSettingsMenuType.quality;
          _focusedSettingIndex = 0;
          _hideTimer?.cancel();
        });
        break;
      case 4:
        if (hasLines) {
          setState(() {
            _showSettingsPanel = true;
            _settingsMenuType = LiveSettingsMenuType.line;
            _focusedSettingIndex = 0;
            _hideTimer?.cancel();
          });
        } else {
          showZhToast(msg: "當前只有預設線路");
        }
        break;
      case 5:
        if (_anchorUid == 0) {
          showZhToast(msg: "無法獲取主播資訊");
          return;
        }
        final act = _isFollowed ? 2 : 1; // 1=Follow, 2=Unfollow
        final success = await LiveApi.modifyRelation(_anchorUid, act);
        if (!mounted) return;
        if (success) {
          setState(() {
            _isFollowed = !_isFollowed;
          });
          showZhToast(msg: _isFollowed ? "已關注" : "已取消關注");
        } else {
          showZhToast(msg: "操作失敗");
        }
        break;
    }
  }

  void _closeSettingsPanel() {
    setState(() {
      _showSettingsPanel = false;
      _settingsMenuType = LiveSettingsMenuType.main;
    });
    _startHideTimer();
  }

  void _handleSettingsKeyEvent(KeyDownEvent event) {
    final count = _getSettingsItemCount();
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _focusedSettingIndex = (_focusedSettingIndex - 1).clamp(
          0,
          count > 0 ? count - 1 : 0,
        );
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _focusedSettingIndex = (_focusedSettingIndex + 1).clamp(
          0,
          count > 0 ? count - 1 : 0,
        );
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      // 直播一律關閉面板
      _closeSettingsPanel();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_settingsMenuType == LiveSettingsMenuType.danmaku) {
        _activateDanmakuItem(_focusedSettingIndex);
      } else if (_settingsMenuType == LiveSettingsMenuType.chat) {
        _activateChatItem(_focusedSettingIndex);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.escape) {
      _closeSettingsPanel();
    } else if (_isSelectKey(event)) {
      _handleSettingsSelection();
    }
  }

  /// 彈幕設定項目：開關項切換，數值項開次級選單選值
  void _activateDanmakuItem(int index) {
    if (index == 0 || index == 5 || index == 6) {
      _toggleDanmakuSetting(index);
    } else {
      _pickDanmakuValue(index);
    }
  }

  /// 在 [items] 中找最接近 [v] 的值，讓彈窗能標出目前選項
  double _nearest(List<double> items, double v) {
    var best = items.first;
    for (final i in items) {
      if ((i - v).abs() < (best - v).abs()) best = i;
    }
    return best;
  }

  Future<void> _pickDanmakuValue(int index) async {
    if (_dialogOpen || !mounted) return;
    final String title;
    final List<double> items;
    final double current;
    final String Function(double) label;
    switch (index) {
      case 1:
        title = '彈幕透明度';
        items = [for (var i = 1; i <= 10; i++) i / 10.0];
        current = _danmakuOpacity;
        label = (v) => '${(v * 100).round()}%';
        break;
      case 2:
        title = '彈幕字型大小';
        items = [for (var i = 10; i <= 30; i++) i.toDouble()];
        current = _danmakuFontSize;
        label = (v) => v.toInt().toString();
        break;
      case 3:
        title = '彈幕佔屏比';
        items = const [0.25, 0.5, 0.75, 1.0];
        current = _danmakuArea;
        label = (v) {
          if (v >= 1.0) return '滿屏';
          if (v >= 0.75) return '3/4屏';
          if (v >= 0.5) return '半屏';
          return '1/4屏';
        };
        break;
      case 4:
        title = '彈幕速度';
        items = [for (var i = 5; i <= 20; i++) i.toDouble()];
        current = _danmakuSpeed;
        label = (v) => v.toInt().toString();
        break;
      default:
        return;
    }

    _dialogOpen = true;
    _cancelDanmakuHold();
    _hideTimer?.cancel();
    double? picked;
    try {
      picked = await showTvMenuDialog<double>(
        context: context,
        title: title,
        items: items,
        current: _nearest(items, current),
        itemLabel: label,
      );
    } finally {
      _dialogOpen = false;
    }
    if (!mounted) return;
    _focusNode.requestFocus();
    if (picked == null) return;
    setState(() {
      switch (index) {
        case 1:
          _danmakuOpacity = picked!;
          break;
        case 2:
          _danmakuFontSize = picked!;
          break;
        case 3:
          _danmakuArea = picked!;
          break;
        case 4:
          _danmakuSpeed = picked!;
          break;
      }
    });
    await _saveSettings();
  }

  int _getSettingsItemCount() {
    switch (_settingsMenuType) {
      case LiveSettingsMenuType.main:
        return 0; // Deprecated
      case LiveSettingsMenuType.quality:
        return _qualities.length;
      case LiveSettingsMenuType.line:
        return _lines.length;
      case LiveSettingsMenuType.danmaku:
        return 7;
      case LiveSettingsMenuType.chat:
        return 3;
    }
  }

  void _handleSettingsSelection() {
    if (_settingsMenuType == LiveSettingsMenuType.quality) {
      if (_focusedSettingIndex < _qualities.length) {
        final qn = _qualities[_focusedSettingIndex]['qn'];
        _initializePlayer(qn: qn);
        setState(() {
          _showSettingsPanel = false;
        });
      }
    } else if (_settingsMenuType == LiveSettingsMenuType.line) {
      if (_focusedSettingIndex < _lines.length) {
        _changeLine(_focusedSettingIndex);
        setState(() {
          _showSettingsPanel = false;
        });
      }
    } else if (_settingsMenuType == LiveSettingsMenuType.danmaku) {
      _activateDanmakuItem(_focusedSettingIndex);
    } else if (_settingsMenuType == LiveSettingsMenuType.chat) {
      _activateChatItem(_focusedSettingIndex);
    }
  }

  /// 只處理開關項（0、5、6）；數值項改用 [_pickDanmakuValue]
  void _toggleDanmakuSetting(int index) {
    switch (index) {
      case 0: // Toggle danmaku enable/disable
        setState(() => _danmakuEnabled = !_danmakuEnabled);
        _saveSettings();
        break;
      case 5: // Toggle hide top danmaku
        setState(() => _hideTopDanmaku = !_hideTopDanmaku);
        _saveSettings();
        break;
      case 6: // Toggle hide bottom danmaku
        setState(() => _hideBottomDanmaku = !_hideBottomDanmaku);
        _saveSettings();
        break;
    }
  }

  void _changeLine(int index) {
    if (index == _currentLineIndex) return;
    _initializePlayer(lineIndex: index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 預覽中按返回：取消預覽，不離開頁面
        if (_tsPreviewAbs != null) {
          _tsCancelPreview();
          return;
        }

        if (_showSettingsPanel) {
          setState(() {
            _showSettingsPanel = false;
            _settingsMenuType = LiveSettingsMenuType.main;
          });
          return;
        }

        if (_showControls) {
          _hideControls();
          return;
        }

        final now = DateTime.now();
        if (_lastBackPressed == null ||
            now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
          _lastBackPressed = now;
          showZhToast(msg: "再按一次退出直播");
          return;
        }

        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          focusNode: _focusNode,
          onKeyEvent: _onKeyEvent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video Player
              Center(
                child: (_isLoading || _controller == null)
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            color: Color(0xFFfb7299),
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 20),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ],
                      )
                    : AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
              ),

              // Danmaku Layer
              if (_controller != null &&
                  _controller!.value.isInitialized &&
                  _danmakuEnabled)
                Positioned.fill(
                  child: DanmakuScreen(
                    createdController: (e) => _danmakuController = e,
                    option: DanmakuOption(
                      opacity: _danmakuOpacity,
                      fontSize: _danmakuFontSize,
                      area: _danmakuArea,
                      duration: _danmakuSpeed / 1.0,
                      hideTop: _hideTopDanmaku,
                      hideBottom: _hideBottomDanmaku,
                    ),
                  ),
                ),

              // 聊天列表（留言）
              if (_showChat)
                LiveChatPanel(
                  messages: List.of(_chatMessages),
                  popup: _chatPopup,
                  onLeft: _chatOnLeft,
                ),

              // Controls Layer
              if (_showControls && _tsPreviewAbs == null) _buildControls(),

              // 時移預覽快轉
              if (_tsPreviewAbs != null && _tsActive) _buildTsPreview(),

              // Settings Panel（進場動畫在 LiveSettingsPanel 內）
              if (_showSettingsPanel)
                LiveSettingsPanel(
                  menuType: _settingsMenuType,
                  focusedIndex: _focusedSettingIndex,
                  qualityDesc: _currentQualityDesc,
                  qualities: _qualities,
                  currentQuality: _currentQuality,
                  lines: _lines,
                  currentLineIndex: _currentLineIndex,
                  danmakuEnabled: _danmakuEnabled,
                  danmakuOpacity: _danmakuOpacity,
                  danmakuFontSize: _danmakuFontSize,
                  danmakuArea: _danmakuArea,
                  danmakuSpeed: _danmakuSpeed,
                  hideTopDanmaku: _hideTopDanmaku,
                  hideBottomDanmaku: _hideBottomDanmaku,
                  chatVisible: _showChat,
                  chatPopup: _chatPopup,
                  chatOnLeft: _chatOnLeft,
                  onChatItem: _activateChatItem,
                  onNavigate: (type, index) {
                    setState(() {
                      _settingsMenuType = type;
                      _focusedSettingIndex = index;
                    });
                  },
                  onQualitySelect: (qn) {
                    _initializePlayer(qn: qn);
                    setState(() {
                      _showSettingsPanel = false;
                      _settingsMenuType = LiveSettingsMenuType.main;
                    });
                  },
                  onLineSelect: (index) {
                    _changeLine(index);
                    setState(() {
                      _showSettingsPanel = false;
                      _settingsMenuType = LiveSettingsMenuType.main;
                    });
                  },
                  onDanmakuSettingChange: (key, value) async {
                    setState(() {
                      switch (key) {
                        case 'enabled':
                          _danmakuEnabled = value;
                          break;
                        case 'opacity':
                          _danmakuOpacity = value;
                          break;
                        case 'fontSize':
                          _danmakuFontSize = value;
                          break;
                        case 'area':
                          _danmakuArea = value;
                          break;
                        case 'speed':
                          _danmakuSpeed = value;
                          break;
                        case 'hideTop':
                          _hideTopDanmaku = value;
                          break;
                        case 'hideBottom':
                          _hideBottomDanmaku = value;
                          break;
                      }
                    });
                    await _saveSettings();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _showControls ? 1.0 : 0.0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.7),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.7),
            ],
          ),
        ),
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ContentText(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        // Online Count (Below Title)
                        Row(
                          children: [
                            const Icon(
                              Icons.people,
                              color: Colors.white70,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$_onlineCount人正在觀看',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const TimeDisplay(),
                ],
              ),
            ),

            const Spacer(),

            // 直播進度條
            _buildLiveBar(),

            // Bottom Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
              child: Row(
                children: [
                  // 播放/暫停 (0)
                  _buildControlButton(
                    index: 0,
                    icon: _userPaused ? Icons.play_arrow : Icons.pause,
                    label: _userPaused ? '播放' : '暫停',
                  ),
                  const SizedBox(width: 20),
                  // 彈幕 (1)：短按切換，長按開設定
                  _buildControlButton(
                    index: 1,
                    icon: _danmakuEnabled
                        ? Icons.subtitles
                        : Icons.subtitles_off,
                    label: '彈幕',
                  ),
                  const SizedBox(width: 20),
                  // 留言 (2)
                  _buildControlButton(
                    index: 2,
                    icon: _showChat
                        ? Icons.chat_bubble
                        : Icons.chat_bubble_outline,
                    label: '留言',
                  ),
                  const SizedBox(width: 20),
                  // 畫質 (3)
                  _buildControlButton(
                    index: 3,
                    icon: Icons.hd,
                    label: _currentQualityDesc,
                  ),
                  const SizedBox(width: 20),
                  // 線路 (4)
                  _buildControlButton(
                    index: 4,
                    icon: Icons.router,
                    label: _lines.isNotEmpty
                        ? _lines[_currentLineIndex]['name'] ?? '線路'
                        : '線路',
                  ),
                  const SizedBox(width: 20),
                  // 關注 (5)
                  _buildControlButton(
                    index: 5,
                    icon: _isFollowed ? Icons.favorite : Icons.favorite_border,
                    label: _isFollowed ? '已關注' : '關注',
                    iconColor: _isFollowed
                        ? const Color(0xFFfb7299)
                        : Colors.white,
                    textColor: _isFollowed
                        ? const Color(0xFFfb7299)
                        : Colors.white,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required int index,
    required IconData icon,
    required String label,
    Color? iconColor,
    Color? textColor,
  }) {
    final isFocused = _focusedControlIndex == index;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isFocused
            ? const Color(0xFFfb7299)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: isFocused
            ? Border.all(color: const Color(0xFFfb7299), width: 2)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isFocused ? Colors.white : (iconColor ?? Colors.white),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isFocused ? Colors.white : (textColor ?? Colors.white),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

/// v2／v1 解析結果：線路（name、url）、畫質（qn、desc）、目前畫質、是否可時移
class _ParsedPlay {
  final List<Map<String, dynamic>> lines;
  final List<Map<String, dynamic>> qualities;
  final int? currentQn;
  final bool tsOk;
  _ParsedPlay(this.lines, this.qualities, this.currentQn, this.tsOk);
}
