import 'package:bili_tv_app/widgets/zh_material.dart';
import '../core/focus/focus_navigation.dart';

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
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  State<BaseTvCard> createState() => _BaseTvCardState();
}

class _BaseTvCardState extends State<BaseTvCard>
    with SingleTickerProviderStateMixin {
  bool _isFocused = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
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
    _animController.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    setState(() => _isFocused = focused);
    if (focused) {
      widget.onFocus();
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TvFocusScope(
      pattern: FocusPattern.grid,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChange,
      onExitLeft: widget.onMoveLeft,
      onExitRight: widget.onMoveRight,
      onExitUp: widget.onMoveUp,
      onExitDown: widget.onMoveDown,
      onSelect: widget.onTap,
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
                          child: widget.imageContent,
                        ),
                        // 聚焦時的邊框
                        if (_isFocused)
                          IgnorePointer(
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
