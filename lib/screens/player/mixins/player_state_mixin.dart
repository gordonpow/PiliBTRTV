import 'dart:async';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:video_player/video_player.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import '../player_screen.dart';
import '../video_actions_controller.dart';
import '../widgets/settings_panel.dart';
import '../../../models/subtitle.dart';
import '../../../models/video.dart' as models;
import '../../../models/videoshot.dart';
import '../../../services/playback_preparer.dart';
import '../../../services/playback_perf.dart';

/// 倒數連播的下一部資訊
class UpNextInfo {
  final String title;
  final String cover;
  final VoidCallback play;
  const UpNextInfo({
    required this.title,
    required this.cover,
    required this.play,
  });
}

/// 控制列按鈕索引
abstract final class CtrlBtn {
  static const int prev = 0; // 上一部
  static const int playPause = 1; // 播放/暫停
  static const int next = 2; // 下一部
  static const int episodes = 3; // 選集
  static const int up = 4; // UP主
  static const int danmaku = 5; // 彈幕
  static const int subtitle = 6; // 字幕
  static const int settings = 7; // 設定
  static const int like = 8; // 點讚
  static const int coin = 9; // 投幣
  static const int fav = 10; // 收藏
  static const int count = 11;
}

/// 播放器狀態 Mixin
/// 包含所有 State 變數
mixin PlayerStateMixin on State<PlayerScreen> {
  // 從卡片暖機接手、尚未使用的播放資料（initState 同步 take）
  PreparedPlayback? warmPlayback;

  // 控制器
  VideoPlayerController? videoController;
  DanmakuController? danmakuController;

  // 外掛跳過動作 (如空降助手)
  dynamic currentSkipAction; // SkipActionShowButton?

  // 載入狀態
  bool isLoading = true;
  String? errorMessage;
  int? cid;
  int? _aid; // 影片 aid (用於點贊/投幣/收藏)
  int? get aid => _aid;
  set aid(int? v) {
    _aid = v;
    if (v != null && v > 0) {
      videoActions.load(v, bvid: playingBvid); // 換片時重新載入狀態
    }
  }

  /// 收藏用的影片資訊（未登入時存進本機；一律以當前播放的 bvid／cid／集為準）。
  /// 標題與封面只在資料確實屬於當前影片時才用 fullVideoInfo，否則退回 widget.video。
  models.Video get favVideo {
    final info = fullVideoInfo;
    final bvid = playingBvid;
    // UGC 的 view 資料帶 bvid，必須與當前 bvid 相同；番劇只有季名（屬於整季）
    final infoMatches =
        info != null && (isPgc || '${info['bvid'] ?? bvid}' == bvid);
    String pick(String key, String fallback) {
      final v = infoMatches ? '${info[key] ?? ''}' : '';
      return v.isNotEmpty ? v : fallback;
    }

    final owner = infoMatches ? info['owner'] : null;
    final dur = infoMatches ? info['duration'] : null;
    return models.Video(
      bvid: bvid,
      aid: _aid ?? 0,
      title: pick('title', widget.video.title),
      pic: pick('pic', widget.video.pic),
      ownerName: owner is Map && '${owner['name'] ?? ''}'.isNotEmpty
          ? '${owner['name']}'
          : widget.video.ownerName,
      duration: dur is int ? dur : widget.video.duration,
      cid: cid ?? 0,
      seasonId: isPgc ? widget.video.seasonId : 0,
      epId: isPgc ? currentEpId : 0,
    );
  }

  /// 控制列點讚／投幣／收藏的狀態與動作
  final VideoActionsController videoActions = VideoActionsController();

  // 番劇 (PGC) 狀態：Video 不可變，切集時更新這些可變欄位
  String? currentBvid; // 當前集的 bvid (番劇由季資訊取得)
  int currentEpId = 0; // 當前集的 ep_id
  int pgcResumeProgress = 0; // 季資訊提供的續播進度 (秒)
  bool isPreview = false; // 當前播放的是試看片段
  String pgcSeasonTitle = ''; // 番劇季名

  bool get isPgc => widget.video.isPgc;

  /// 當前實際播放的 bvid (UGC 為 widget.video.bvid)
  String get playingBvid => currentBvid ?? widget.video.bvid;

  /// 進度快取的 key：番劇用 season，UGC 用 bvid
  String get progressCacheKey =>
      isPgc ? 'pgc_${widget.video.seasonId}' : widget.video.bvid;

  // 完整影片資訊 (從 API 獲取，統一資料來源)
  Map<String, dynamic>? fullVideoInfo;

  // 線上觀看人數
  String? onlineCount;
  Timer? onlineCountTimer;

  // 播放診斷統計計時器（每 10 秒）與上次快照
  Timer? playerStatsTimer;
  int lastStatsDropped = 0;
  String lastStatsDecoder = '';
  int perfGen = 0; // 每次重建播放器遞增，讓舊計時器的非同步結果作廢
  int? perfCid; // 區間統計所屬的 cid，換片時重置
  final DowngradeTracker perfTracker = DowngradeTracker();
  bool perfDowngrading = false;

  // 解碼卡住偵測（每 2 秒讀原生狀態）：緩衝起點、已試過的編碼家族、重新載入防重入
  Timer? stallTimer;
  DateTime? bufferingSince;
  final Set<String> stallTriedCodecs = {};
  bool stallSwitching = false;
  int reloadGen = 0; // 每次 _reloadWithCodec 遞增，讓舊流程作廢
  Map<String, dynamic>? currentStream; // 選定的影片串流（DASH）
  int? perfPrevJiffies;
  int? perfPrevElapsedMs;
  int perfCores = 1;
  int perfHz = 100;

  // 當前播放的音訊 URL (DASH 模式)
  String? currentAudioUrl;

  // 當前抽幀預覽使用的影片 URL (480P AVC)
  String? previewFrameUrl;

  // 播放器流訂閱
  List<StreamSubscription> playerSubscriptions = [];

  // 彈幕設定
  bool danmakuEnabled = true;
  double danmakuOpacity = 0.6;
  double danmakuFontSize = 17.0;
  double danmakuArea = 0.25;
  double danmakuSpeed = 10.0;
  bool hideTopDanmaku = false;
  bool hideBottomDanmaku = false;

  // 播放設定
  double playbackSpeed = 1.0;
  final List<double> availableSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // UI 控制
  bool showControls = true;
  bool showSettingsPanel = false;
  SettingsMenuType settingsMenuType = SettingsMenuType.main;
  Timer? hideTimer;
  Timer? progressReportTimer;
  int focusedButtonIndex = CtrlBtn.playPause; // 見 CtrlBtn
  int focusedSettingIndex = 0;

  // 解析度
  List<Map<String, dynamic>> qualities = [];
  int currentQuality = 80;
  String currentCodec = ''; // 當前編解碼器 (avc/hev/av01)
  bool isFallingBackToAvc = false; // 是否正在自動降級為 AVC
  Duration lastPlaybackPosition = Duration.zero; // 記錄最近播放進度 (供解碼失敗回退使用)

  /// 當前編碼是否為 AVC
  bool get isCurrentCodecAvc => currentCodec.toLowerCase().startsWith('avc');

  // 雙擊返回
  DateTime? lastBackPressed;

  // 選集
  List<dynamic> episodes = [];
  bool showEpisodePanel = false;
  int focusedEpisodeIndex = 0;

  // 彈幕資料
  List<dynamic> danmakuList = [];
  int lastDanmakuIndex = 0;

  // CC 字幕（#17）：subtitleIndex -1 為關閉；subtitleGen 用於作廢舊的載入／翻譯
  List<SubtitleTrack> subtitleTracks = [];
  int subtitleIndex = -1;
  List<SubtitleLine> subtitleLines = [];
  int subtitleGen = 0;
  bool subtitleUserPicked = false; // 使用者手選過字幕軌（自動換軌不覆蓋）
  bool subtitleLoading = false; // loadSubtitles 進行中（字幕按鈕提示用）
  int? subtitleCid; // 已（或正在）載入字幕的 cid，避免同一部影片重複載入

  // 新面板
  bool upSpaceOpen = false; // UP主全螢幕頁面開啟中（禁止播放器自行導航、防重入）
  bool showRelatedPanel = false;
  bool relatedExpanded = false; // 相關影片：false = 一排，true = 展開

  // 進度條聚焦模式
  bool isProgressBarFocused = false;
  Duration? previewPosition; // 拖動預覽位置

  // 自動續播
  int? initialProgress; // 從歷史記錄恢復的進度

  // 相關影片 (用於自動連播)
  List<dynamic> relatedVideos = [];

  // 播完倒數連播
  int? upNextSeconds; // 剩餘秒數；null = 沒有在倒數
  int upNextTotal = 0; // 本次倒數總秒數（供卡片進度圈使用）
  Timer? upNextTimer;
  UpNextInfo? upNextInfo;

  // 播放器根 Focus 節點（從 UP主頁面返回後用來恢復焦點）
  final FocusNode playerFocusNode = FocusNode();

  // 返回鍵處理標誌 - 防止 handleGlobalKeyEvent 和 onPopInvoked 重複處理
  bool backKeyJustHandled = false;

  // 快進快退指示器
  bool showSeekIndicator = false;
  Timer? seekIndicatorTimer;

  // 快進預覽模式 (雪碧圖)
  VideoshotData? videoshotData;
  bool isSeekPreviewMode = false; // 當前是否處於預覽快進模式
  int precachedSpriteIndex = -1; // 已預快取的雪碧圖最大索引 (滑動視窗)
  bool hasShownVideoshotFailToast = false; // 是否已顯示過預覽圖失敗提示
  bool hasHandledVideoComplete = false; // 防止重複觸發影片完成回撥
  int seekPressCount = 0; // 連續快進/快退計數
  DateTime? lastSeekPressTime; // 上次按下快進/快退時間
  bool? lastSeekDirection; // 上次快進方向 (true: forward, false: backward)
  Timer? autoSeekTimer; // 1.5 秒無操作自動跳轉計時器
  Duration? originalSeekPosition; // 快進前原播放位置 (供取消預覽使用)
  bool wasPlayingBeforeSeek = false; // 快進前是否正在播放

  // 獲取編解碼器簡稱
  String get _codecLabel {
    if (currentCodec.startsWith('av01')) {
      return 'AV1';
    }
    if (currentCodec.startsWith('hev') ||
        currentCodec.startsWith('hvc') ||
        currentCodec.startsWith('dvh')) {
      return 'H.265';
    }
    if (currentCodec.startsWith('avc')) {
      return 'H.264';
    }
    return '';
  }

  // 獲取當前畫質描述 (含編解碼器)
  String get currentQualityDesc {
    String desc = '${currentQuality}P';
    for (var q in qualities) {
      if (q['qn'] == currentQuality) {
        desc = q['desc'] ?? desc;
        break;
      }
    }
    if (_codecLabel.isNotEmpty) {
      return '$desc ($_codecLabel)';
    }
    return desc;
  }
}
