import '../../main.dart' show appNavigatorKey;
import '../../models/video.dart';
import '../../screens/player/player_route.dart';
import '../../screens/player/player_screen.dart';

/// 手機投放過來的播放請求
class CastRequest {
  final String? bvid;
  final int? aid;
  final int? cid;
  final int? epId;
  final int? seasonId;
  final int positionMs;
  final String title;

  const CastRequest({
    this.bvid,
    this.aid,
    this.cid,
    this.epId,
    this.seasonId,
    required this.positionMs,
    this.title = '',
  });
}

/// 依投放請求開啟播放頁
abstract final class CastPlayback {
  static bool _opening = false;
  static CastRequest? _pending;

  static Future<void> open(CastRequest r) async {
    if (_opening) {
      _pending = r; // 開頁進行中：記下最新的請求，結束後執行（最後一筆為準）
      return;
    }
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    _opening = true;
    try {
      final epId = r.epId ?? 0;
      final isPgc = epId > 0;
      final positionMs = r.positionMs < 0 ? 0 : r.positionMs;
      final video = isPgc
          ? Video(
              bvid: '',
              title: r.title,
              pic: '',
              seasonId: r.seasonId ?? 0,
              epId: epId,
              forceEpId: epId,
              forceStartMs: positionMs,
            )
          : Video(
              bvid: r.bvid ?? '',
              title: r.title,
              pic: '',
              aid: r.aid ?? 0,
              forceStartMs: positionMs,
            );
      final route = PlayerRoute(video: video, startCid: isPgc ? 0 : (r.cid ?? 0));

      if (PlayerScreen.activeCount > 0) {
        // 先退回最上層的播放頁（關掉其上的選單、面板），再整頁換掉
        nav.popUntil((x) => x is PlayerRoute || x.isFirst);
        nav.pushReplacement(route);
      } else {
        nav.push(route);
      }
    } finally {
      // 轉場結束前維持旗標，避免連續投放造成重複進頁
      Future.delayed(const Duration(milliseconds: 800), () {
        _opening = false;
        final next = _pending;
        _pending = null;
        if (next != null) open(next);
      });
    }
  }
}
