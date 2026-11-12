import 'dart:async';

import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../core/focus/focus_navigation.dart';
import '../models/video.dart';
import '../services/card_preview_service.dart';
import '../services/prefetch_service.dart';
import '../services/settings_service.dart';
import '../utils/nav_settle.dart';

/// TV 影片卡片基類
///
/// 使用統一的焦點管理系統，支援網格導航模式
class BaseTvCard extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onBack;
  final bool autofocus;
  final FocusNode? focusNode;

  /// 長按確認鍵（約 0.5 秒）或觸控長按的動作；null 表示不啟用，行為與原本相同。
  /// 動作結束後焦點會還給長按前的元件。
  final Future<void> Function()? onLongPress;

  /// 焦點預覽用的影片（null 表示此卡片不預覽，如直播、合集）
  final Video? previewVideo;

  /// The main image content (usually CachedNetworkImage)
  /// This will be wrapped in AspectRatio and Stack for glow/border
  final Widget imageContent;

  /// The information content below the image, aware of focus state
  final Widget Function(BuildContext context, bool isFocused)
  infoContentBuilder;

  /// Grid boundary flags
  final bool isFirst;
  final bool isLast;

  const BaseTvCard({
    super.key,
    required this.onTap,
    required this.onFocus,
    required this.imageContent,
    required this.infoContentBuilder,
    this.onMoveLeft,
    this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
    this.onBack,
    this.autofocus = false,
    this.focusNode,
    this.previewVideo,
    this.onLongPress,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  State<BaseTvCard> createState() => _BaseTvCardState();
}

class _BaseTvCardState extends State<BaseTvCard>
    with SingleTickerProviderStateMixin {
  /// 已掛載的卡片（供焦點停住時挑鄰近卡片預先解析）
  static final Set<_BaseTvCardState> _mounted = {};

  bool _isFocused = false;
  Timer? _startTimer;

  /// 長按偵測：確認鍵按住的門檻
  static const Duration _longPressDelay = Duration(milliseconds: 500);
  Timer? _longPressTimer;
  bool _selectDown = false; // 確認鍵目前處於按下（尚未放開、尚未觸發長按）
  bool _longPressRunning = false;

  /// 已按下確認鍵進入播放：之後的失焦不取消預載，讓播放器能用到結果
  bool _keepPrefetch = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _mounted.add(this);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _glowAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _mounted.remove(this);
    _startTimer?.cancel();
    _startTimer = null;
    _longPressTimer?.cancel();
    if (!_keepPrefetch) PrefetchService.instance.cancel(this);
    // 避免在 widget 樹卸載期間通知監聽者，延後到 microtask
    Future.microtask(() => CardPreviewService.instance.stop(this));
    _animController.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    setState(() => _isFocused = focused);
    if (focused) {
      widget.onFocus();
      _animController.forward();
      _keepPrefetch = false;
      final video = widget.previewVideo;
      // 焦點停穩後才預載並開始預覽（單次移動約 150ms，快速移動 250ms）
      _startTimer?.cancel();
      _startTimer = null;
      if (video != null) {
        _scheduleStart(video, NavSettle.instance.onFocusArrived());
      }
    } else {
      _longPressTimer?.cancel();
      _selectDown = false;
      _animController.reverse();
      _startTimer?.cancel();
      _startTimer = null;
      if (!_keepPrefetch) PrefetchService.instance.cancel(this);
      CardPreviewService.instance.stop(this);
    }
  }

  void _scheduleStart(Video video, Duration delay) {
    _startTimer = Timer(delay, () {
      if (!mounted || !_isFocused) {
        debugPrint(
          '⚡ [PreResolve] skip: timer fired mounted=$mounted focused=$_isFocused',
        );
        return;
      }
      // 長按移動中：等放開再啟動
      if (NavSettle.instance.isHeld) {
        _scheduleStart(video, const Duration(milliseconds: 250));
        return;
      }
      PrefetchService.instance.schedule(this, video);
      if (SettingsService.cardPreview) {
        CardPreviewService.instance.start(this, video);
        _preResolveNeighbors();
      } else {
        debugPrint('⚡ [PreResolve] skip: cardPreview off');
      }
    });
  }

  /// 挑最近 4 張在畫面內的其他卡片，背景預先解析影片資訊與播放網址
  void _preResolveNeighbors() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) {
      debugPrint('⚡ [PreResolve] skip: render box not attached');
      return;
    }
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    final origin = box.localToGlobal(box.size.center(Offset.zero));
    final found = <({double dist, Video video})>[];
    for (final s in _mounted) {
      if (identical(s, this)) continue;
      final v = s.widget.previewVideo;
      final b = s.context.findRenderObject();
      if (v == null || b is! RenderBox || !b.attached || !b.hasSize) continue;
      final rect = b.localToGlobal(Offset.zero) & b.size;
      if (!rect.overlaps(screen)) continue;
      // 同一排的左右鄰居優先（使用者多半左右移動），垂直距離加權 1.5 倍
      final d = rect.center - origin;
      found.add((dist: Offset(d.dx, d.dy * 1.5).distance, video: v));
    }
    if (found.isEmpty) {
      debugPrint(
        '⚡ [PreResolve] skip: no visible candidates (mounted=${_mounted.length})',
      );
      return;
    }
    found.sort((a, b) => a.dist.compareTo(b.dist));
    // 多給幾張候選，已快取的由 preResolve 跳過後再取 4 張
    PrefetchService.instance.preResolve([
      for (final f in found.take(8)) f.video,
    ]);
  }

  static bool _isSelectKey(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA;

  /// 確認鍵長按偵測：按下開始計時，≥500ms 觸發長按；
  /// 放開時若尚未觸發長按才當作短按。重複事件一律吞掉。
  KeyEventResult _preKey(KeyEvent event) {
    if (widget.onLongPress == null || !_isSelectKey(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _selectDown = true;
      _longPressTimer?.cancel();
      _longPressTimer = Timer(_longPressDelay, _fireLongPress);
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      // 長按觸發後殘留的重複事件不應再落到短按邏輯
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      if (!_selectDown) return KeyEventResult.handled; // 長按已觸發，放開不做事
      _selectDown = false;
      _longPressTimer?.cancel();
      _handleSelect();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _fireLongPress() {
    if (!mounted || !_selectDown) return;
    _selectDown = false;
    _runLongPress();
  }

  Future<void> _runLongPress() async {
    final action = widget.onLongPress;
    if (action == null || _longPressRunning) return;
    _longPressRunning = true;
    // 記住原本的焦點，動作（對話框）結束後還回去
    final previous = FocusManager.instance.primaryFocus;
    try {
      await action();
    } finally {
      _longPressRunning = false;
      if (previous != null &&
          previous.context != null &&
          previous.canRequestFocus &&
          !previous.hasPrimaryFocus) {
        previous.requestFocus();
      }
    }
  }

  void _handleSelect() {
    // 只取消尚未觸發的計時器；已開始的預載保留給播放器
    _startTimer?.cancel();
    _startTimer = null;
    _keepPrefetch = true;
    // 保留暖機播放器給播放頁接手（尚未就緒則取消準備）
    final video = widget.previewVideo;
    if (video != null && !video.isPgc) {
      CardPreviewService.instance.reserve(video.bvid);
    } else {
      CardPreviewService.instance.stopAll();
    }
    // 卡片立即不再顯示預覽畫面，避免同一個 controller 掛在兩個視圖
    if (mounted) setState(() {});
    widget.onTap();
  }

  Widget _buildCover() {
    return ValueListenableBuilder<CardPreviewState?>(
      valueListenable: CardPreviewService.instance.current,
      builder: (context, state, _) {
        final controller = state?.controller;
        final showVideo =
            state != null &&
            identical(state.owner, this) &&
            controller != null &&
            !CardPreviewService.instance.isClaimed(controller) &&
            controller.value.isInitialized &&
            !controller.value.hasError;
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.imageContent,
            if (showVideo)
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = _buildScope();
    if (widget.onLongPress == null) return scope;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: _runLongPress,
      child: scope,
    );
  }

  Widget _buildScope() {
    return TvFocusScope(
      pattern: FocusPattern.grid,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChange,
      onExitLeft: widget.onMoveLeft,
      onExitRight: widget.onMoveRight,
      onExitUp: widget.onMoveUp,
      onExitDown: widget.onMoveDown,
      onSelect: _handleSelect,
      preKeyHandler: widget.onLongPress == null ? null : _preKey,
      isFirst: widget.isFirst,
      isLast: widget.isLast,
      enableKeyRepeat: true, // 網格導航支援按住快速移動
      child: ScaleTransition(
        scale: _scaleAnim,
        child: RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面區域
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 陰影層
                    Positioned.fill(
                      top: 10,
                      child: FadeTransition(
                        opacity: _glowAnim,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFfb7299,
                                ).withValues(alpha: 0.4),
                                blurRadius: 20,
                                spreadRadius: 2,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 圖片與內容層
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: widget.previewVideo == null
                              ? widget.imageContent
                              : _buildCover(),
                        ),
                        // 聚焦時的邊框
                        IgnorePointer(
                          child: FadeTransition(
                            opacity: _glowAnim,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                  strokeAlign: BorderSide.strokeAlignOutside,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // 底部資訊區域
              widget.infoContentBuilder(context, _isFocused),
            ],
          ),
        ),
      ),
    );
  }
}
