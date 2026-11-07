import 'package:bili_tv_app/widgets/zh_material.dart';
import 'plugin.dart';

// 這裡的 VideoItem 和 DanmakuItem 需要根據實際專案中的模型進行調整
// 暫時使用 dynamic 或者定義簡單的介面，後續整合時替換為真實型別

/// 首頁/推薦流過濾外掛介面
abstract class FeedPlugin extends Plugin {
  /// 是否顯示該影片/動態
  /// 返回 false 表示過濾掉
  bool shouldShowItem(dynamic item);
}

/// 彈幕外掛介面
abstract class DanmakuPlugin extends Plugin {
  /// 過濾彈幕
  /// 返回 null 表示過濾掉，否則返回處理後的彈幕（或原彈幕）
  dynamic filterDanmaku(dynamic item);

  /// 彈幕樣式自定義
  /// 返回自定義樣式，null 表示使用預設樣式
  DanmakuStyle? styleDanmaku(dynamic item);
}

/// 播放器外掛介面
abstract class PlayerPlugin extends Plugin {
  /// 影片載入時呼叫
  Future<void> onVideoLoad(String bvid, int cid);

  /// 播放進度更新時呼叫 (單位: 毫秒)
  /// 返回 SkipAction 決定是否跳過或顯示按鈕
  Future<SkipAction> onPositionUpdate(int positionMs);

  /// 影片結束時呼叫
  void onVideoEnd();
}

/// 彈幕樣式定義
class DanmakuStyle {
  final Color? borderColor;
  final Color? backgroundColor;
  final bool bold;

  const DanmakuStyle({
    this.borderColor,
    this.backgroundColor,
    this.bold = false,
  });
}

/// 跳過動作定義
abstract class SkipAction {}

class SkipActionNone extends SkipAction {}

class SkipActionSkipTo extends SkipAction {
  final int positionMs;
  final String reason;

  SkipActionSkipTo(this.positionMs, this.reason);
}

class SkipActionShowButton extends SkipAction {
  final int skipToMs;
  final String label;
  final String segmentId;

  SkipActionShowButton(this.skipToMs, this.label, this.segmentId);
}
