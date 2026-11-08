import 'dart:async';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:video_player/video_player.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import '../player_screen.dart';
import '../widgets/settings_panel.dart';
import '../../../models/videoshot.dart';

/// 播放器狀態 Mixin
/// 包含所有 State 變數
mixin PlayerStateMixin on State<PlayerScreen> {
  // 控制器
  VideoPlayerController? videoController;
  DanmakuController? danmakuController;

  // 外掛跳過動作 (如空降助手)
  dynamic currentSkipAction; // SkipActionShowButton?

  // 載入狀態
  bool isLoading = true;
  String? errorMessage;
  int? cid;
  int? aid; // 影片 aid (用於點贊/投幣/收藏)

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

  // 當前播放的音訊 URL (DASH 模式)
  String? currentAudioUrl;

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
  int focusedButtonIndex = 0; // 0=Play, 1=Settings, 2=Playlist, 3=More
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

  // 新面板
  bool showUpPanel = false;
  bool showRelatedPanel = false;
  bool showActionButtons = false;

  // 進度條聚焦模式
  bool isProgressBarFocused = false;
  Duration? previewPosition; // 拖動預覽位置

  // 自動續播
  int? initialProgress; // 從歷史記錄恢復的進度

  // 相關影片 (用於自動連播)
  List<dynamic> relatedVideos = [];

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
