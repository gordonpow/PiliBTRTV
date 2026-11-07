import 'package:bili_tv_app/utils/zh_toast.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../services/bilibili_api.dart';
import '../../../models/video.dart';

/// 點贊/投幣/收藏 按鈕元件
class ActionButtons extends StatefulWidget {
  final Video video;
  final int aid;
  final bool isFocused; // 整個元件是否被聚焦
  final VoidCallback? onFocusExit; // 使用者退出時回撥
  final VoidCallback? onUserInteraction; // 使用者互動回撥 (用於重置定時器)

  const ActionButtons({
    super.key,
    required this.video,
    required this.aid,
    this.isFocused = false,
    this.onFocusExit,
    this.onUserInteraction,
  });

  @override
  State<ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends State<ActionButtons> {
  bool _isLiked = false;
  int _coinCount = 0;
  bool _isFavorited = false;
  int _focusedIndex = 0; // 0=點贊, 1=投幣, 2=收藏
  bool _isLoading = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadStatus();
    if (widget.isFocused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ActionButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aid != widget.aid) {
      _loadStatus();
    }
    // 當 isFocused 變為 true 時請求焦點
    if (widget.isFocused && !oldWidget.isFocused) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    if (widget.aid <= 0) return;

    final results = await Future.wait([
      BilibiliApi.checkLikeStatus(widget.aid),
      BilibiliApi.checkCoinStatus(widget.aid),
      BilibiliApi.checkFavoriteStatus(widget.aid),
    ]);

    if (mounted) {
      setState(() {
        _isLiked = results[0] as bool;
        _coinCount = results[1] as int;
        _isFavorited = results[2] as bool;
      });
    }
  }

  Future<void> _onLike() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final success = await BilibiliApi.likeVideo(
      aid: widget.aid,
      like: !_isLiked,
    );

    if (success) {
      setState(() => _isLiked = !_isLiked);
      showZhToast(msg: _isLiked ? '已點贊' : '已取消點贊');
    } else {
      showZhToast(msg: '操作失敗');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _onCoin() async {
    if (_isLoading || _coinCount >= 2) {
      if (_coinCount >= 2) {
        showZhToast(msg: '已投滿2個硬幣');
      }
      return;
    }
    setState(() => _isLoading = true);

    final error = await BilibiliApi.coinVideo(aid: widget.aid, count: 1);

    if (error == null) {
      setState(() => _coinCount = _coinCount + 1);
      showZhToast(msg: '投幣成功 ($_coinCount/2)');

      // 觸發互動回撥，重置隱藏定時器
      widget.onUserInteraction?.call();
    } else {
      showZhToast(msg: error);
    }
    setState(() => _isLoading = false);
  }

  Future<void> _onFavorite() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final success = await BilibiliApi.favoriteVideo(
      aid: widget.aid,
      favorite: !_isFavorited,
    );

    if (success) {
      setState(() => _isFavorited = !_isFavorited);
      showZhToast(msg: _isFavorited ? '已收藏' : '已取消收藏');
    } else {
      showZhToast(msg: '操作失敗');
    }
    setState(() => _isLoading = false);
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      setState(() => _focusedIndex = (_focusedIndex - 1).clamp(0, 2));
      widget.onUserInteraction?.call();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      setState(() => _focusedIndex = (_focusedIndex + 1).clamp(0, 2));
      widget.onUserInteraction?.call();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onFocusExit?.call();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      switch (_focusedIndex) {
        case 0:
          _onLike();
          break;
        case 1:
          _onCoin();
          break;
        case 2:
          _onFavorite();
          break;
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) =>
          widget.isFocused ? _handleKeyEvent(event) : KeyEventResult.ignored,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildButton(
              index: 0,
              svgPath: 'assets/icons/like.svg',
              label: _isLiked ? '已點贊' : '點贊',
              isActive: _isLiked,
            ),
            const SizedBox(width: 24),
            _buildButton(
              index: 1,
              svgPath: 'assets/icons/coin.svg',
              label: _coinCount > 0 ? '已投($_coinCount/2)個幣' : '投幣',
              isActive: _coinCount > 0,
            ),
            const SizedBox(width: 24),
            _buildButton(
              index: 2,
              svgPath: 'assets/icons/favorite.svg',
              label: _isFavorited ? '已收藏' : '收藏',
              isActive: _isFavorited,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required int index,
    required String svgPath,
    required String label,
    bool isActive = false,
  }) {
    final isFocused = widget.isFocused && _focusedIndex == index;
    final color = isActive ? const Color(0xFFfb7299) : Colors.white;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.all(isFocused ? 12 : 8),
      decoration: BoxDecoration(
        color: isFocused
            ? Colors.white.withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isFocused ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            svgPath,
            width: isFocused ? 32 : 28,
            height: isFocused ? 32 : 28,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: isFocused ? 14 : 12),
          ),
        ],
      ),
    );
  }
}
