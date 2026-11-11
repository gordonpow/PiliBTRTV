import 'package:flutter/foundation.dart';
import '../../services/auth_service.dart';
import '../../services/bilibili_api.dart';
import '../../services/local_favorites_service.dart';
import '../../utils/zh_toast.dart';

/// 播放器控制列的點讚／投幣／收藏狀態與動作
class VideoActionsController extends ChangeNotifier {
  int _aid = 0;
  String _bvid = '';
  bool isLiked = false;
  int coinCount = 0;
  bool isFavorited = false;
  bool _busy = false;
  bool _disposed = false;

  /// 載入該影片的三項狀態；aid 相同時不重複載入
  Future<void> load(int aid, {String bvid = ''}) async {
    if (aid <= 0 || aid == _aid) return;
    _aid = aid;
    _bvid = bvid;
    isLiked = false;
    coinCount = 0;
    isFavorited = false;
    _notify();
    final results = await Future.wait([
      BilibiliApi.checkLikeStatus(aid),
      BilibiliApi.checkCoinStatus(aid),
      BilibiliApi.checkFavoriteStatus(aid),
    ]);
    if (_disposed || _aid != aid) return;
    isLiked = results[0] as bool;
    coinCount = results[1] as int;
    if (AuthService.isLoggedIn) {
      isFavorited = results[2] as bool;
    } else {
      // 未登入：以本機收藏判斷
      await LocalFavoritesService.instance.ensureLoaded();
      if (_disposed || _aid != aid) return;
      final local = LocalFavoritesService.instance;
      isFavorited = _bvid.isNotEmpty
          ? local.isFavorited(_bvid)
          : local.isFavoritedAid(aid);
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> toggleLike() async {
    if (_busy || _aid <= 0) return;
    _busy = true;
    final aid = _aid;
    final success = await BilibiliApi.likeVideo(aid: aid, like: !isLiked);
    if (success && aid == _aid) {
      isLiked = !isLiked;
      showZhToast(msg: isLiked ? '已點贊' : '已取消點贊');
    } else if (!success) {
      showZhToast(msg: '操作失敗');
    }
    _busy = false;
    _notify();
  }

  Future<void> addCoin() async {
    if (_busy || _aid <= 0) return;
    if (coinCount >= 2) {
      showZhToast(msg: '已投滿2個硬幣');
      return;
    }
    _busy = true;
    final aid = _aid;
    final error = await BilibiliApi.coinVideo(aid: aid, count: 1);
    if (error == null) {
      if (aid == _aid) coinCount += 1;
      showZhToast(msg: '投幣成功 ($coinCount/2)');
    } else {
      showZhToast(msg: error);
    }
    _busy = false;
    _notify();
  }

  /// 收藏夾選單套用後更新收藏狀態（星星圖示）
  void setFavorited(bool value) {
    isFavorited = value;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
