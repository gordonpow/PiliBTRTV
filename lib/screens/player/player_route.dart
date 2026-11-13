import 'package:flutter/widgets.dart';

import '../../models/video.dart';
import '../../utils/anim.dart';
import 'player_screen.dart';

/// 開啟播放頁的轉場：120ms 淡入。
///
/// 低記憶體裝置（[Anim.reduced]）時為 0ms，不做動畫。
class PlayerRoute extends PageRouteBuilder<void> {
  PlayerRoute({required Video video, int startCid = 0})
    : super(
        opaque: true,
        transitionDuration: Anim.of(const Duration(milliseconds: 120)),
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            PlayerScreen(video: video, startCid: startCid),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      );
}
