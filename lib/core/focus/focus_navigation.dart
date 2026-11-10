import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';

/// TV 焦點導航模式
enum FocusPattern {
  /// 垂直列表：↑↓ 移動，←→ 是退出/動作
  vertical,

  /// 水平列表：←→ 移動，↑↓ 是退出
  horizontal,

  /// 網格：四方向移動
  grid,
}

/// 統一的 TV 按鍵處理工具類
class TvKeyHandler {
  /// 處理方向鍵和確認鍵事件
  ///
  /// [event] - 鍵盤事件
  /// [onUp/Down/Left/Right] - 方向鍵回撥
  /// [onSelect] - 確認鍵回撥 (Enter/Select)
  /// [blockUp/Down/Left/Right] - 是否阻止該方向的預設行為
  ///
  /// 返回 [KeyEventResult.handled] 如果按鍵被處理
  static KeyEventResult handleNavigation(
    KeyEvent event, {
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onLeft,
    VoidCallback? onRight,
    VoidCallback? onSelect,
    bool blockUp = false,
    bool blockDown = false,
    bool blockLeft = false,
    bool blockRight = false,
  }) {
    // 只處理 KeyDownEvent，避免重複觸發
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        if (onUp != null) {
          onUp();
          return KeyEventResult.handled;
        }
        return blockUp ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.arrowDown:
        if (onDown != null) {
          onDown();
          return KeyEventResult.handled;
        }
        return blockDown ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.arrowLeft:
        if (onLeft != null) {
          onLeft();
          return KeyEventResult.handled;
        }
        return blockLeft ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.arrowRight:
        if (onRight != null) {
          onRight();
          return KeyEventResult.handled;
        }
        return blockRight ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
        if (onSelect != null) {
          onSelect();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;

      default:
        return KeyEventResult.ignored;
    }
  }

  /// 處理支援 KeyRepeat 的方向鍵（如在網格中按住快速移動）
  static KeyEventResult handleNavigationWithRepeat(
    KeyEvent event, {
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onLeft,
    VoidCallback? onRight,
    VoidCallback? onSelect,
    bool blockUp = false,
    bool blockDown = false,
    bool blockLeft = false,
    bool blockRight = false,
  }) {
    // 處理 KeyDownEvent 和 KeyRepeatEvent
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        if (onUp != null) {
          onUp();
          return KeyEventResult.handled;
        }
        return blockUp ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.arrowDown:
        if (onDown != null) {
          onDown();
          return KeyEventResult.handled;
        }
        return blockDown ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.arrowLeft:
        if (onLeft != null) {
          onLeft();
          return KeyEventResult.handled;
        }
        return blockLeft ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.arrowRight:
        if (onRight != null) {
          onRight();
          return KeyEventResult.handled;
        }
        return blockRight ? KeyEventResult.handled : KeyEventResult.ignored;

      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
        // 確認鍵不支援重複
        if (event is KeyDownEvent && onSelect != null) {
          onSelect();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;

      default:
        return KeyEventResult.ignored;
    }
  }
}

/// 通用的 TV 焦點容器
///
/// 自動處理邊界導航邏輯，減少重複程式碼
class TvFocusScope extends StatelessWidget {
  /// 焦點模式
  final FocusPattern pattern;

  /// 子元件
  final Widget child;

  /// 焦點節點
  final FocusNode? focusNode;

  /// 是否自動獲取焦點
  final bool autofocus;

  /// 焦點變化回撥
  final ValueChanged<bool>? onFocusChange;

  /// 確認鍵回撥
  final VoidCallback? onSelect;

  /// 退出方向的目標焦點節點
  final FocusNode? exitUp;
  final FocusNode? exitDown;
  final FocusNode? exitLeft;
  final FocusNode? exitRight;

  /// 退出方向的回撥（優先順序高於 exitXxx FocusNode）
  final VoidCallback? onExitUp;
  final VoidCallback? onExitDown;
  final VoidCallback? onExitLeft;
  final VoidCallback? onExitRight;

  /// 是否是列表中的第一項（垂直模式阻止向上，水平模式阻止向左）
  final bool isFirst;

  /// 是否是列表中的最後一項（垂直模式阻止向下，水平模式阻止向右）
  final bool isLast;

  /// 是否支援按鍵重複（適用於快速滾動場景）
  final bool enableKeyRepeat;

  /// 先於一般導航處理的按鍵攔截；回傳 handled 表示事件已消化（例如確認鍵長按偵測）
  final KeyEventResult Function(KeyEvent event)? preKeyHandler;

  const TvFocusScope({
    super.key,
    required this.pattern,
    required this.child,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.onSelect,
    this.exitUp,
    this.exitDown,
    this.exitLeft,
    this.exitRight,
    this.onExitUp,
    this.onExitDown,
    this.onExitLeft,
    this.onExitRight,
    this.isFirst = false,
    this.isLast = false,
    this.enableKeyRepeat = false,
    this.preKeyHandler,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: autofocus,
      onFocusChange: onFocusChange,
      onKeyEvent: _handleKeyEvent,
      child: child,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (preKeyHandler != null) {
      final pre = preKeyHandler!(event);
      if (pre == KeyEventResult.handled) return pre;
    }
    final handler = enableKeyRepeat
        ? TvKeyHandler.handleNavigationWithRepeat
        : TvKeyHandler.handleNavigation;

    switch (pattern) {
      case FocusPattern.vertical:
        return handler(
          event,
          // 垂直模式：上下移動由 Flutter 預設處理，除非是邊界
          onUp: isFirst ? _getExitUpHandler() : null,
          onDown: isLast ? _getExitDownHandler() : null,
          onLeft: _getExitLeftHandler(),
          onRight: _getExitRightHandler(),
          onSelect: onSelect,
          blockUp: isFirst && exitUp == null && onExitUp == null,
          blockDown: isLast && exitDown == null && onExitDown == null,
        );

      case FocusPattern.horizontal:
        return handler(
          event,
          onUp: _getExitUpHandler(),
          onDown: _getExitDownHandler(),
          // 水平模式：左右移動由 Flutter 預設處理，除非是邊界
          onLeft: isFirst ? _getExitLeftHandler() : null,
          onRight: isLast ? _getExitRightHandler() : null,
          onSelect: onSelect,
          blockLeft: isFirst && exitLeft == null && onExitLeft == null,
          blockRight: isLast && exitRight == null && onExitRight == null,
        );

      case FocusPattern.grid:
        // 網格模式：如果提供了回撥則強制使用回撥（適用於明確指定導航目標的情況）
        // 這樣可以實現嚴格的 4x4 網格導航
        return handler(
          event,
          onUp: _getExitUpHandler(),
          onDown: _getExitDownHandler(),
          onLeft: _getExitLeftHandler(),
          onRight: _getExitRightHandler(),
          onSelect: onSelect,
        );
    }
  }

  /// 獲取退出處理函式，如果沒有配置則返回 null
  VoidCallback? _getExitUpHandler() {
    if (onExitUp != null) return _handleExitUp;
    if (exitUp != null) return _handleExitUp;
    return null;
  }

  VoidCallback? _getExitDownHandler() {
    if (onExitDown != null) return _handleExitDown;
    if (exitDown != null) return _handleExitDown;
    return null;
  }

  VoidCallback? _getExitLeftHandler() {
    if (onExitLeft != null) return _handleExitLeft;
    if (exitLeft != null) return _handleExitLeft;
    return null;
  }

  VoidCallback? _getExitRightHandler() {
    if (onExitRight != null) return _handleExitRight;
    if (exitRight != null) return _handleExitRight;
    return null;
  }

  void _handleExitUp() {
    if (onExitUp != null) {
      onExitUp!();
    } else {
      exitUp?.requestFocus();
    }
  }

  void _handleExitDown() {
    if (onExitDown != null) {
      onExitDown!();
    } else {
      exitDown?.requestFocus();
    }
  }

  void _handleExitLeft() {
    if (onExitLeft != null) {
      onExitLeft!();
    } else {
      exitLeft?.requestFocus();
    }
  }

  void _handleExitRight() {
    if (onExitRight != null) {
      onExitRight!();
    } else {
      exitRight?.requestFocus();
    }
  }
}

/// 簡化版的垂直焦點列表項
///
/// 專為設定頁面等垂直列表設計
class TvVerticalListItem extends StatelessWidget {
  final Widget child;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback? onSelect;
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool isFirst;
  final bool isLast;

  const TvVerticalListItem({
    super.key,
    required this.child,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.onSelect,
    this.sidebarFocusNode,
    this.onMoveUp,
    this.onMoveDown,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusScope(
      pattern: FocusPattern.vertical,
      focusNode: focusNode,
      autofocus: autofocus,
      onFocusChange: onFocusChange,
      onSelect: onSelect,
      exitLeft: sidebarFocusNode,
      onExitUp: isFirst ? onMoveUp : null,
      onExitDown: isLast ? onMoveDown : null,
      isFirst: isFirst,
      isLast: isLast,
      child: child,
    );
  }
}
