import 'package:bili_tv_app/services/device_profile.dart';
import 'package:flutter/widgets.dart';

/// 共用的介面動畫時長（#41）。
///
/// 低記憶體或記憶體不足（[MemoryTier.low]／[MemoryTier.critical]）的裝置
/// 回傳 [Duration.zero]，關閉動畫以免拖慢焦點移動。
abstract final class Anim {
  /// 焦點樣式、分頁切換。
  static const Duration fast = Duration(milliseconds: 150);

  /// 面板、彈出元件進場。
  static const Duration normal = Duration(milliseconds: 200);

  static const Curve curve = Curves.easeOutCubic;

  /// 依裝置等級調整後的時長。
  static Duration of(Duration d) => reduced ? Duration.zero : d;

  /// 是否關閉動畫。
  static bool get reduced {
    final tier = DeviceProfile.currentTier;
    return tier == MemoryTier.low || tier == MemoryTier.critical;
  }
}

/// 掛上時淡入並從 [offset]（以自身大小為單位）滑入；離場不做動畫。
///
/// 用在以 `if (flag)` 直接加入 Stack 的面板。離場不做動畫，避免已關閉的
/// 面板還留在樹上搶焦點或吃按鍵。
class EnterTransition extends StatelessWidget {
  const EnterTransition({
    super.key,
    required this.child,
    this.offset = const Offset(0.15, 0),
    this.duration = Anim.normal,
  });

  final Widget child;
  final Offset offset;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final d = Anim.of(duration);
    if (d == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: d,
      curve: Anim.curve,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: FractionalTranslation(
          translation: offset * (1 - t),
          child: child,
        ),
      ),
    );
  }
}
