import 'package:bili_tv_app/utils/zh_toast.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../widgets/settings_panel.dart';
import '../focus/player_focus_handler.dart';
import 'player_action_mixin.dart';

/// 播放器按鍵事件 Mixin
mixin PlayerEventMixin on PlayerActionMixin {
  void onPopInvoked(bool didPop, dynamic result) {
    if (didPop) return;

    // 檢查是否返回鍵已經被 handleGlobalKeyEvent 處理過
    if (backKeyJustHandled) {
      backKeyJustHandled = false;
      return;
    }

    if (showSettingsPanel) {
      if (settingsMenuType != SettingsMenuType.main) {
        setState(() {
          focusedSettingIndex = settingsMenuType == SettingsMenuType.cdn
              ? 3
              : 0;
          settingsMenuType = SettingsMenuType.main;
        });
        return;
      }
      setState(() {
        showSettingsPanel = false;
        showControls = true;
      });
      startHideTimer();
      return;
    }

    if (showEpisodePanel) {
      setState(() {
        showEpisodePanel = false;
        showControls = true;
      });
      startHideTimer();
      return;
    }

    // 關閉 UP主面板
    if (showUpPanel) {
      setState(() {
        showUpPanel = false;
        showControls = true;
      });
      startHideTimer();
      return;
    }

    // 關閉更多影片面板
    if (showRelatedPanel) {
      setState(() {
        showRelatedPanel = false;
        showControls = true;
      });
      startHideTimer();
      return;
    }

    if (showActionButtons) {
      setState(() => showActionButtons = false);
      startHideTimer();
      return;
    }

    // 預覽模式下按返回鍵取消預覽
    if (isSeekPreviewMode) {
      cancelPreviewSeek();
      return;
    }

    // 控制欄顯示時按返回鍵隱藏控制欄
    if (showControls) {
      setState(() => showControls = false);
      return;
    }

    final now = DateTime.now();
    if (lastBackPressed == null ||
        now.difference(lastBackPressed!) > const Duration(seconds: 2)) {
      lastBackPressed = now;
      showZhToast(
        msg: '再按一次返回鍵退出播放',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.CENTER,
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        textColor: Colors.white,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  KeyEventResult handleGlobalKeyEvent(FocusNode node, KeyEvent event) {
    // 處理 KeyUpEvent - 鬆開左右鍵時提交進度
    if (event is KeyUpEvent) {
      if (isProgressBarFocused && previewPosition != null) {
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          commitProgress();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }

    // 只處理 KeyDownEvent 和 KeyRepeatEvent
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // 設定面板
    if (showSettingsPanel) {
      if (PlayerFocusHandler.isBackKey(event) && event is KeyDownEvent) {
        backKeyJustHandled = true;
        if (settingsMenuType != SettingsMenuType.main) {
          setState(() {
            focusedSettingIndex = settingsMenuType == SettingsMenuType.cdn
                ? 3
                : 0;
            settingsMenuType = SettingsMenuType.main;
          });
        } else {
          setState(() {
            showSettingsPanel = false;
            showControls = true;
          });
          startHideTimer();
        }
        return KeyEventResult.handled;
      }
      final result = handleSettingsKeyEvent(event);
      if (result == KeyEventResult.handled) {
        if (!showControls) setState(() => showControls = true);
        return KeyEventResult.handled;
      }
    }

    // 選集面板 - 使用 PlayerFocusHandler
    if (showEpisodePanel) {
      if (PlayerFocusHandler.isBackKey(event) && event is KeyDownEvent) {
        backKeyJustHandled = true;
        _closeEpisodePanel();
        return KeyEventResult.handled;
      }
      final result = handleEpisodeKeyEvent(event);
      if (result == KeyEventResult.handled) {
        if (!showControls) setState(() => showControls = true);
        return KeyEventResult.handled;
      }
    }

    // UP主面板返回處理
    if (showUpPanel) {
      if (PlayerFocusHandler.isBackKey(event) && event is KeyDownEvent) {
        backKeyJustHandled = true;
        setState(() {
          showUpPanel = false;
          showControls = true;
        });
        startHideTimer();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 相關影片面板返回處理
    if (showRelatedPanel) {
      if (PlayerFocusHandler.isBackKey(event) && event is KeyDownEvent) {
        backKeyJustHandled = true;
        setState(() {
          showRelatedPanel = false;
          showControls = true;
        });
        startHideTimer();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 點贊/投幣/收藏按鈕返回處理
    if (showActionButtons) {
      if (PlayerFocusHandler.isBackKey(event) && event is KeyDownEvent) {
        backKeyJustHandled = true;
        setState(() => showActionButtons = false);
        startHideTimer();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 控制欄顯示時
    if (showControls) {
      return _handleControlsVisibleKeyEvent(event);
    } else {
      // 控制欄隱藏時
      return _handleControlsHiddenKeyEvent(event);
    }
  }

  /// 控制欄顯示時的按鍵處理
  KeyEventResult _handleControlsVisibleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // 使用 PlayerFocusHandler 處理控制欄導航
    final nav = PlayerFocusHandler.handleControlsNavigation(
      event,
      currentIndex: focusedButtonIndex,
      maxIndex: 4,
      onSelect: _activateControlButton,
      onHide: () => setState(() => showControls = false),
    );

    if (nav.result == KeyEventResult.handled) {
      if (nav.newIndex != focusedButtonIndex) {
        setState(() => focusedButtonIndex = nav.newIndex);
        startHideTimer();
      }
      return KeyEventResult.handled;
    }

    // 返回鍵隱藏控制欄
    if (PlayerFocusHandler.isBackKey(event)) {
      if (event.logicalKey != LogicalKeyboardKey.escape) {
        backKeyJustHandled = true;
      }
      setState(() => showControls = false);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// 啟用控制欄按鈕
  void _activateControlButton(int index) {
    switch (index) {
      case 0: // 選集
        setState(() {
          showEpisodePanel = true;
          hideTimer?.cancel();
        });
        break;
      case 1: // UP主
        setState(() {
          showUpPanel = true;
          hideTimer?.cancel();
        });
        break;
      case 2: // 更多影片
        setState(() {
          showRelatedPanel = true;
          hideTimer?.cancel();
        });
        break;
      case 3: // 設定
        setState(() {
          showSettingsPanel = true;
          hideTimer?.cancel();
        });
        break;
      case 4: // 點贊/投幣/收藏
        setState(() {
          showActionButtons = !showActionButtons;
        });
        break;
    }
  }

  /// 控制欄隱藏時的按鍵處理
  KeyEventResult _handleControlsHiddenKeyEvent(KeyEvent event) {
    // 如果處於預覽模式，使用 PlayerFocusHandler 處理
    if (isSeekPreviewMode && previewPosition != null) {
      final result = PlayerFocusHandler.handleSeekPreviewNavigation(
        event,
        onSeekBackward: seekPreviewBackward,
        onSeekForward: seekPreviewForward,
        onConfirm: confirmPreviewSeek,
        onCancel: () {
          if (event.logicalKey == LogicalKeyboardKey.goBack ||
              event.logicalKey == LogicalKeyboardKey.browserBack) {
            backKeyJustHandled = true;
          }
          cancelPreviewSeek();
        },
      );
      if (result == KeyEventResult.handled) {
        return KeyEventResult.handled;
      }
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // 上下鍵顯示控制欄
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      toggleControls();
      return KeyEventResult.handled;
    }

    // 確認鍵播放/暫停
    if (PlayerFocusHandler.isSelectKey(event) && event is KeyDownEvent) {
      togglePlayPause();
      return KeyEventResult.handled;
    }

    // 左右鍵快退/快進 (支援按住重複觸發)
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      seekBackward();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      seekForward();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// 關閉選集面板
  void _closeEpisodePanel() {
    setState(() {
      showEpisodePanel = false;
      showControls = true;
    });
    startHideTimer();
  }

  /// 選集面板按鍵處理 - 使用 PlayerFocusHandler
  KeyEventResult handleEpisodeKeyEvent(KeyEvent event) {
    // 支援長按連續移動 (KeyRepeatEvent)
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final nav = PlayerFocusHandler.handleEpisodePanelNavigation(
      event,
      currentIndex: focusedEpisodeIndex,
      maxIndex: episodes.length - 1,
      onSelect: () {
        if (episodes.isNotEmpty) {
          switchEpisode(episodes[focusedEpisodeIndex]['cid']);
        }
      },
      onClose: _closeEpisodePanel,
    );

    if (nav.result == KeyEventResult.handled) {
      if (nav.newIndex != focusedEpisodeIndex) {
        setState(() => focusedEpisodeIndex = nav.newIndex);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// 設定面板按鍵處理 - 保持原有邏輯（有子選單特殊處理）
  KeyEventResult handleSettingsKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    int maxIndex = _getSettingsMaxIndex();

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        focusedSettingIndex = (focusedSettingIndex - 1).clamp(0, maxIndex);
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        focusedSettingIndex = (focusedSettingIndex + 1).clamp(0, maxIndex);
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (settingsMenuType == SettingsMenuType.main) {
        setState(() {
          showSettingsPanel = false;
          showControls = true;
        });
        startHideTimer();
      } else if (settingsMenuType == SettingsMenuType.danmaku) {
        adjustDanmakuSetting(-1);
      } else if (settingsMenuType == SettingsMenuType.speed) {
        setState(() => settingsMenuType = SettingsMenuType.main);
      } else if (settingsMenuType == SettingsMenuType.cdn) {
        setState(() {
          settingsMenuType = SettingsMenuType.main;
          focusedSettingIndex = 3;
        });
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (settingsMenuType == SettingsMenuType.main) {
        if (focusedSettingIndex == 1) {
          setState(() {
            settingsMenuType = SettingsMenuType.danmaku;
            focusedSettingIndex = 0;
          });
        } else if (focusedSettingIndex == 2) {
          setState(() {
            settingsMenuType = SettingsMenuType.speed;
            focusedSettingIndex = 0;
          });
        } else if (focusedSettingIndex == 3) {
          setState(() {
            settingsMenuType = SettingsMenuType.cdn;
            focusedSettingIndex = 0;
          });
        }
      } else if (settingsMenuType == SettingsMenuType.danmaku) {
        adjustDanmakuSetting(1);
      }
      return KeyEventResult.handled;
    }

    if (PlayerFocusHandler.isSelectKey(event)) {
      activateSetting();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (settingsMenuType == SettingsMenuType.main) {
        setState(() {
          showSettingsPanel = false;
          showControls = true;
        });
        startHideTimer();
      } else {
        setState(() {
          focusedSettingIndex = settingsMenuType == SettingsMenuType.cdn
              ? 3
              : 0;
          settingsMenuType = SettingsMenuType.main;
        });
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// 獲取當前設定選單的最大索引
  int _getSettingsMaxIndex() {
    switch (settingsMenuType) {
      case SettingsMenuType.main:
        return 3;
      case SettingsMenuType.danmaku:
        return 6;
      case SettingsMenuType.speed:
        return availableSpeeds.length - 1;
      default:
        return 0;
    }
  }
}
