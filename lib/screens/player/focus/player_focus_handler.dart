import 'package:bili_tv_app/widgets/zh_widgets.dart';
import 'package:flutter/services.dart';

/// 播放器內部焦點導航工具
///
/// 提供播放器面板內的焦點導航邏輯，可被 player_event_mixin 使用
class PlayerFocusHandler {
  /// 處理控制欄按鈕導航（水平模式）
  ///
  /// [event] - 鍵盤事件
  /// [currentIndex] - 當前聚焦按鈕索引
  /// [maxIndex] - 最大按鈕索引
  /// [onIndexChange] - 索引變化回撥
  /// [onSelect] - 確認鍵回撥
  /// [onHide] - 隱藏控制欄回撥（上下鍵觸發）
  ///
  /// 返回事件處理結果和新的索引
  static ({KeyEventResult result, int newIndex}) handleControlsNavigation(
    KeyEvent event, {
    required int currentIndex,
    required int maxIndex,
    required Function(int) onSelect,
    VoidCallback? onHide,
  }) {
    if (event is! KeyDownEvent) {
      return (result: KeyEventResult.ignored, newIndex: currentIndex);
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        final newIndex = (currentIndex - 1).clamp(0, maxIndex);
        return (result: KeyEventResult.handled, newIndex: newIndex);

      case LogicalKeyboardKey.arrowRight:
        final newIndex = (currentIndex + 1).clamp(0, maxIndex);
        return (result: KeyEventResult.handled, newIndex: newIndex);

      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.arrowDown:
        onHide?.call();
        return (result: KeyEventResult.handled, newIndex: currentIndex);

      default:
        if (isSelectKey(event)) {
          onSelect(currentIndex);
          return (result: KeyEventResult.handled, newIndex: currentIndex);
        }
        return (result: KeyEventResult.ignored, newIndex: currentIndex);
    }
  }

  /// 處理設定面板導航（垂直模式，帶子選單）
  ///
  /// [event] - 鍵盤事件
  /// [currentIndex] - 當前聚焦項索引
  /// [maxIndex] - 最大項索引
  /// [isSubMenu] - 是否在子選單中
  /// [onActivate] - 啟用當前項回撥
  /// [onBack] - 返回上級選單回撥
  /// [onAdjust] - 調整值回撥（用於彈幕設定等，傳入 -1 或 1）
  ///
  /// 返回事件處理結果和新的索引
  static ({KeyEventResult result, int newIndex}) handleSettingsPanelNavigation(
    KeyEvent event, {
    required int currentIndex,
    required int maxIndex,
    required bool isSubMenu,
    VoidCallback? onActivate,
    VoidCallback? onBack,
    Function(int)? onAdjust,
  }) {
    if (event is! KeyDownEvent) {
      return (result: KeyEventResult.ignored, newIndex: currentIndex);
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        final newIndex = (currentIndex - 1).clamp(0, maxIndex);
        return (result: KeyEventResult.handled, newIndex: newIndex);

      case LogicalKeyboardKey.arrowDown:
        final newIndex = (currentIndex + 1).clamp(0, maxIndex);
        return (result: KeyEventResult.handled, newIndex: newIndex);

      case LogicalKeyboardKey.arrowLeft:
        if (isSubMenu && onAdjust != null) {
          onAdjust(-1);
        } else {
          onBack?.call();
        }
        return (result: KeyEventResult.handled, newIndex: currentIndex);

      case LogicalKeyboardKey.arrowRight:
        if (isSubMenu && onAdjust != null) {
          onAdjust(1);
        } else {
          onActivate?.call();
        }
        return (result: KeyEventResult.handled, newIndex: currentIndex);

      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
        onActivate?.call();
        return (result: KeyEventResult.handled, newIndex: currentIndex);

      case LogicalKeyboardKey.escape:
        onBack?.call();
        return (result: KeyEventResult.handled, newIndex: currentIndex);

      default:
        return (result: KeyEventResult.ignored, newIndex: currentIndex);
    }
  }

  /// 處理選集面板導航（垂直/水平模式）
  ///
  /// [event] - 鍵盤事件
  /// [currentIndex] - 當前選中索引
  /// [maxIndex] - 最大索引
  /// [onSelect] - 選中回撥
  /// [onClose] - 關閉面板回撥
  static ({KeyEventResult result, int newIndex}) handleEpisodePanelNavigation(
    KeyEvent event, {
    required int currentIndex,
    required int maxIndex,
    VoidCallback? onSelect,
    VoidCallback? onClose,
  }) {
    // 支援長按連續移動 (KeyRepeatEvent)
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return (result: KeyEventResult.ignored, newIndex: currentIndex);
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        final newIndex = (currentIndex - 1).clamp(0, maxIndex);
        return (result: KeyEventResult.handled, newIndex: newIndex);

      case LogicalKeyboardKey.arrowDown:
        final newIndex = (currentIndex + 1).clamp(0, maxIndex);
        return (result: KeyEventResult.handled, newIndex: newIndex);

      case LogicalKeyboardKey.arrowLeft:
        onClose?.call();
        return (result: KeyEventResult.handled, newIndex: currentIndex);

      case LogicalKeyboardKey.arrowRight:
        // 右鍵在選集面板為無效操作
        return (result: KeyEventResult.handled, newIndex: currentIndex);

      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
        onSelect?.call();
        return (result: KeyEventResult.handled, newIndex: currentIndex);

      case LogicalKeyboardKey.escape:
        onClose?.call();
        return (result: KeyEventResult.handled, newIndex: currentIndex);

      default:
        return (result: KeyEventResult.ignored, newIndex: currentIndex);
    }
  }

  /// 處理快進快退指示器導航（特殊預覽模式）
  ///
  /// [event] - 鍵盤事件
  /// [onSeekBackward] - 後退回撥
  /// [onSeekForward] - 前進回撥
  /// [onConfirm] - 確認跳轉回調
  /// [onCancel] - 取消預覽回撥
  static KeyEventResult handleSeekPreviewNavigation(
    KeyEvent event, {
    VoidCallback? onSeekBackward,
    VoidCallback? onSeekForward,
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
  }) {
    // 支援 KeyRepeat 用於快速拖動
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        onSeekBackward?.call();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
        onSeekForward?.call();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
        if (event is KeyDownEvent) {
          onConfirm?.call();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.goBack:
      case LogicalKeyboardKey.browserBack:
        if (event is KeyDownEvent) {
          onCancel?.call();
        }
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }

  /// 檢查是否是返回鍵
  static bool isBackKey(KeyEvent event) {
    return event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.browserBack ||
        event.logicalKey == LogicalKeyboardKey.escape;
  }

  /// 檢查是否是確認鍵
  static bool isSelectKey(KeyEvent event) {
    return event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA;
  }
}
