import 'dart:async';

import 'package:bili_tv_app/utils/zh_toast.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../../models/play_repeat.dart';
import '../../../core/plugin/plugin_types.dart';
import '../../../models/video.dart';
import '../../../services/settings_service.dart';
import '../../../widgets/video_action_dialogs.dart';
import '../../up_space/up_space_screen.dart';
import '../widgets/settings_panel.dart';
import '../focus/player_focus_handler.dart';
import 'player_action_mixin.dart';
import 'player_state_mixin.dart';

/// 播放器按鍵事件 Mixin
mixin PlayerEventMixin on PlayerActionMixin {
  void onPopInvoked(bool didPop, dynamic result) {
    if (didPop) return;

    // 檢查是否返回鍵已經被 handleGlobalKeyEvent 處理過
    if (backKeyJustHandled) {
      backKeyJustHandled = false;
      return;
    }

    // 倒數連播中：返回 = 取消倒數並顯示控制列
    if (upNextSeconds != null) {
      cancelUpNext(showControlsAfter: true);
      return;
    }

    if (showSettingsPanel) {
      if (settingsMenuType != SettingsMenuType.main) {
        setState(() {
          focusedSettingIndex = _mainIndexAfterBack;
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

    // 相關影片：展開時先收回一排，再返回就關閉
    if (showRelatedPanel) {
      if (relatedExpanded) {
        setState(() => relatedExpanded = false);
      } else {
        closeRelatedStrip();
      }
      return;
    }

    if (showInfoPanel) {
      closeInfoPanel();
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

  // ───────────── 彈幕按鈕長按 ─────────────

  static const Duration _danmakuHoldDelay = Duration(milliseconds: 500);
  Timer? _danmakuHoldTimer;
  bool _danmakuHolding = false; // 確認鍵按下中，尚未判定短按或長按
  bool _danmakuHoldFired = false; // 長按已觸發，後續的 Repeat 與 KeyUp 要吞掉

  /// 取消彈幕按鈕的長按計時（控制列隱藏、焦點離開、dispose 時呼叫）
  void cancelDanmakuHold() {
    _danmakuHoldTimer?.cancel();
    _danmakuHoldTimer = null;
    _danmakuHolding = false;
  }

  /// 長按有作用的按鈕：彈幕；字幕（有字幕軌時，沒有軌時走短按 toast）
  bool get _canHoldDanmaku =>
      showControls &&
      (focusedButtonIndex == CtrlBtn.danmaku ||
          (focusedButtonIndex == CtrlBtn.subtitle &&
              subtitleTracks.isNotEmpty)) &&
      !showSettingsPanel &&
      !showEpisodePanel &&
      !showRelatedPanel &&
      !showInfoPanel &&
      upNextSeconds == null;

  void _fireDanmakuHold() {
    _danmakuHoldTimer = null;
    if (!mounted || !_danmakuHolding) return;
    _danmakuHolding = false;
    if (!_canHoldDanmaku) return;
    _danmakuHoldFired = true;
    hideTimer?.cancel();
    final subtitle = focusedButtonIndex == CtrlBtn.subtitle;
    setState(() {
      settingsMenuType = subtitle
          ? SettingsMenuType.subtitle
          : SettingsMenuType.danmaku;
      focusedSettingIndex = subtitle ? subtitleIndex + 1 : 0;
      showSettingsPanel = true;
    });
  }

  /// 彈幕／字幕按鈕的確認鍵：短按切換，按住 500ms 打開對應的設定次級選單。
  /// 回傳 null 表示這個事件與彈幕長按無關。
  KeyEventResult? _handleDanmakuHold(KeyEvent event) {
    if (!PlayerFocusHandler.isSelectKey(event)) {
      // 按住時按了其他鍵（如左右鍵移開焦點）：取消，不判定短按
      if (_danmakuHolding && event is KeyDownEvent) cancelDanmakuHold();
      return null;
    }
    if (_danmakuHoldFired) {
      if (event is KeyUpEvent) {
        _danmakuHoldFired = false;
        return KeyEventResult.handled;
      }
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      _danmakuHoldFired = false; // 新的 KeyDown
    }
    if (event is KeyDownEvent) {
      if (!_canHoldDanmaku) return null;
      _danmakuHolding = true;
      _danmakuHoldTimer?.cancel();
      _danmakuHoldTimer = Timer(_danmakuHoldDelay, _fireDanmakuHold);
      return KeyEventResult.handled;
    }
    if (!_danmakuHolding) return null;
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is KeyUpEvent) {
      cancelDanmakuHold();
      if (_canHoldDanmaku) {
        if (focusedButtonIndex == CtrlBtn.subtitle) {
          onSubtitleButton(); // 內含 toast
        } else {
          toggleDanmaku(); // toggleDanmaku 內含 toast
        }
        startHideTimer();
      }
      return KeyEventResult.handled;
    }
    return null;
  }

  KeyEventResult handleGlobalKeyEvent(FocusNode node, KeyEvent event) {
    final holdResult = _handleDanmakuHold(event);
    if (holdResult != null) return holdResult;

    // 處理 KeyUpEvent - 鬆開左右鍵時提交進度
    if (event is KeyUpEvent) {
      // 放開左右鍵：結束按住快轉計速（不吃掉事件，後續行為不變）
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        endSeekHold();
      }
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

    // 跳過按鈕顯示中、沒有開著面板時：確認鍵直接跳過
    // （按鈕的焦點常被播放器焦點搶走，不能只靠按鈕自己接收按鍵）
    if (currentSkipAction is SkipActionShowButton &&
        upNextSeconds == null &&
        !showSettingsPanel &&
        !showEpisodePanel &&
        !showInfoPanel &&
        !showRelatedPanel &&
        event is KeyDownEvent &&
        PlayerFocusHandler.isSelectKey(event)) {
      executeSkipAction();
      return KeyEventResult.handled;
    }

    // 倒數連播中的按鍵（含 KeyRepeat）
    if (upNextSeconds != null) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        // 取消倒數後照原流程（快退／快進）；Repeat 事件在已取消後才會進來
        if (event is KeyDownEvent) cancelUpNext();
        if (upNextSeconds != null) return KeyEventResult.handled;
      } else {
        if (event is KeyDownEvent) {
          if (PlayerFocusHandler.isSelectKey(event)) {
            final info = upNextInfo;
            cancelUpNext();
            info?.play();
          } else if (PlayerFocusHandler.isBackKey(event)) {
            if (key != LogicalKeyboardKey.escape) backKeyJustHandled = true;
            cancelUpNext(showControlsAfter: true);
          } else if (key == LogicalKeyboardKey.arrowDown) {
            openRelatedStrip(); // 內含 cancelUpNext()
          }
        }
        return KeyEventResult.handled;
      }
    }

    // 設定面板
    if (showSettingsPanel) {
      if (PlayerFocusHandler.isBackKey(event) && event is KeyDownEvent) {
        backKeyJustHandled = true;
        if (settingsMenuType != SettingsMenuType.main) {
          setState(() {
            focusedSettingIndex = _mainIndexAfterBack;
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

    // 相關影片返回處理（方向鍵由 RelatedStrip 自己處理）：
    // 展開時先收回一排，再返回就關閉
    if (showRelatedPanel) {
      if (PlayerFocusHandler.isBackKey(event) && event is KeyDownEvent) {
        if (event.logicalKey != LogicalKeyboardKey.escape) {
          backKeyJustHandled = true;
        }
        if (relatedExpanded) {
          setState(() => relatedExpanded = false);
        } else {
          closeRelatedStrip();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 簡介／留言面板：自管焦點，只處理返回鍵（其餘交給面板）
    if (showInfoPanel) {
      if (PlayerFocusHandler.isBackKey(event) && event is KeyDownEvent) {
        if (event.logicalKey != LogicalKeyboardKey.escape) {
          backKeyJustHandled = true;
        }
        closeInfoPanel();
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

    // 下鍵打開相關影片底部橫排
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      openRelatedStrip();
      return KeyEventResult.handled;
    }

    // 焦點在不能用的按鈕上時，改回播放/暫停
    if (!isCtrlBtnEnabled(focusedButtonIndex)) {
      focusedButtonIndex = CtrlBtn.playPause;
    }

    // 左右鍵：跳過變暗（不能用）的按鈕
    final isLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft;
    if (isLeft || event.logicalKey == LogicalKeyboardKey.arrowRight) {
      final step = isLeft ? -1 : 1;
      var i = focusedButtonIndex + step;
      while (i >= 0 && i < CtrlBtn.count && !isCtrlBtnEnabled(i)) {
        i += step;
      }
      if (i >= 0 && i < CtrlBtn.count && i != focusedButtonIndex) {
        setState(() => focusedButtonIndex = i);
        startHideTimer();
      }
      return KeyEventResult.handled;
    }

    // 使用 PlayerFocusHandler 處理控制欄導航
    final nav = PlayerFocusHandler.handleControlsNavigation(
      event,
      currentIndex: focusedButtonIndex,
      maxIndex: CtrlBtn.count - 1,
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

  /// 開收藏夾選單；選單開著時不自動隱藏控制列，套用後更新星星狀態
  Future<void> _openFavoritePicker() async {
    hideTimer?.cancel();
    final faved = await favoriteVideoFlow(context, aid, video: favVideo);
    if (!mounted) return;
    if (faved != null) videoActions.setFavorited(faved);
    startHideTimer();
  }

  /// 啟用控制欄按鈕
  void _activateControlButton(int index) {
    switch (index) {
      case CtrlBtn.prev: // 上一部
        if (hasPrev) playPrev();
        break;
      case CtrlBtn.playPause: // 播放/暫停（保持控制欄顯示）
        togglePlayPause();
        startHideTimer();
        break;
      case CtrlBtn.next: // 下一部
        if (hasNext) playNext();
        break;
      case CtrlBtn.episodes: // 選集
        setState(() {
          showEpisodePanel = true;
          hideTimer?.cancel();
        });
        break;
      case CtrlBtn.up: // UP主
        _openUpSpace();
        break;
      case CtrlBtn.danmaku: // 彈幕（短按；長按由 _handleDanmakuHold 處理）
        toggleDanmaku();
        break;
      case CtrlBtn.subtitle: // 字幕（短按；長按由 _handleDanmakuHold 處理）
        onSubtitleButton();
        startHideTimer();
        break;
      case CtrlBtn.settings: // 設定
        setState(() {
          showSettingsPanel = true;
          hideTimer?.cancel();
        });
        break;
      case CtrlBtn.info: // 簡介／留言
        setState(() {
          showInfoPanel = true;
          hideTimer?.cancel();
        });
        break;
      case CtrlBtn.like: // 點讚
        videoActions.toggleLike();
        startHideTimer();
        break;
      case CtrlBtn.coin: // 投幣
        videoActions.addCoin();
        startHideTimer();
        break;
      case CtrlBtn.fav: // 收藏：開收藏夾選單，顯示收藏到哪個資料夾
        _openFavoritePicker();
        break;
    }
  }

  /// 開啟 UP主全螢幕頁面：暫停影片，返回後依原狀態恢復；選了影片則改播該影片。
  Future<void> _openUpSpace() async {
    if (upSpaceOpen) return;
    final mid = widget.video.ownerMid;
    if (mid == 0) {
      showZhToast(msg: '此影片沒有 UP主資訊');
      return;
    }
    upSpaceOpen = true;
    hideTimer?.cancel();
    cancelUpNext();

    final controller = videoController;
    final wasPlaying =
        controller != null &&
        !isLoading &&
        controller.value.isInitialized &&
        controller.value.isPlaying;
    if (wasPlaying) controller.pause();

    Video? picked;
    try {
      picked = await Navigator.of(context).push<Video>(
        MaterialPageRoute(
          builder: (_) => UpSpaceScreen(
            mid: mid,
            name: widget.video.ownerName,
            face: widget.video.ownerFace,
            returnSelection: true,
          ),
        ),
      );
    } finally {
      upSpaceOpen = false;
    }
    if (!mounted) return;

    if (picked != null) {
      navigateTo(picked);
      return;
    }

    final current = videoController;
    if (wasPlaying && current != null && current.value.isInitialized) {
      current.play();
    }
    backKeyJustHandled = false;
    setState(() => showControls = true);
    startHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) playerFocusNode.requestFocus();
    });
  }

  /// 控制欄隱藏時的按鍵處理
  KeyEventResult _handleControlsHiddenKeyEvent(KeyEvent event) {
    // 如果處於預覽模式，使用 PlayerFocusHandler 處理
    if (isSeekPreviewMode && previewPosition != null) {
      final result = PlayerFocusHandler.handleSeekPreviewNavigation(
        event,
        onSeekBackward: () =>
            seekPreviewBackward(repeat: event is KeyRepeatEvent),
        onSeekForward: () =>
            seekPreviewForward(repeat: event is KeyRepeatEvent),
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

    // 確認鍵顯示控制欄，焦點回到播放/暫停鈕（再按一次才暫停）
    if (PlayerFocusHandler.isSelectKey(event) && event is KeyDownEvent) {
      setState(() => focusedButtonIndex = CtrlBtn.playPause);
      toggleControls();
      return KeyEventResult.handled;
    }

    // 左右鍵快退/快進 (支援按住重複觸發)
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      seekBackward(repeat: event is KeyRepeatEvent);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      seekForward(repeat: event is KeyRepeatEvent);
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
        setState(() {
          settingsMenuType = SettingsMenuType.main;
          focusedSettingIndex = 3;
        });
      } else if (settingsMenuType == SettingsMenuType.cdn) {
        setState(() {
          settingsMenuType = SettingsMenuType.main;
          focusedSettingIndex = 4;
        });
      } else if (settingsMenuType == SettingsMenuType.playEnd) {
        setState(() {
          settingsMenuType = SettingsMenuType.main;
          focusedSettingIndex = 6;
        });
      } else if (settingsMenuType == SettingsMenuType.subtitle) {
        setState(() {
          settingsMenuType = SettingsMenuType.main;
          focusedSettingIndex = 7;
        });
      } else if (settingsMenuType == SettingsMenuType.audio) {
        setState(() {
          settingsMenuType = SettingsMenuType.main;
          focusedSettingIndex = 1;
        });
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (settingsMenuType == SettingsMenuType.main) {
        if (focusedSettingIndex == 1) {
          setState(() {
            settingsMenuType = SettingsMenuType.audio;
            final i = audioOptions.indexWhere(
              (o) => o.kind == currentAudioKind,
            );
            focusedSettingIndex = i < 0 ? 0 : i;
          });
        } else if (focusedSettingIndex == 2) {
          setState(() {
            settingsMenuType = SettingsMenuType.danmaku;
            focusedSettingIndex = 0;
          });
        } else if (focusedSettingIndex == 3) {
          setState(() {
            settingsMenuType = SettingsMenuType.speed;
            focusedSettingIndex = 0;
          });
        } else if (focusedSettingIndex == 4) {
          setState(() {
            settingsMenuType = SettingsMenuType.cdn;
            focusedSettingIndex = 0;
          });
        } else if (focusedSettingIndex == 6) {
          setState(() {
            settingsMenuType = SettingsMenuType.playEnd;
            focusedSettingIndex = SettingsService.playRepeat.index;
          });
        } else if (focusedSettingIndex == 7 && subtitleTracks.isNotEmpty) {
          setState(() {
            settingsMenuType = SettingsMenuType.subtitle;
            focusedSettingIndex = subtitleIndex + 1;
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
          focusedSettingIndex = _mainIndexAfterBack;
          settingsMenuType = SettingsMenuType.main;
        });
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// 從子選單返回主選單時，焦點回到進入的項目（音質 1、彈幕 2、速度 3、CDN 4）
  int get _mainIndexAfterBack => switch (settingsMenuType) {
    SettingsMenuType.audio => 1,
    SettingsMenuType.danmaku => 2,
    SettingsMenuType.speed => 3,
    SettingsMenuType.cdn => 4,
    SettingsMenuType.playEnd => 6,
    SettingsMenuType.subtitle => 7,
    _ => 0,
  };

  /// 獲取當前設定選單的最大索引
  int _getSettingsMaxIndex() {
    switch (settingsMenuType) {
      case SettingsMenuType.main:
        return subtitleTracks.isNotEmpty ? 7 : 6;
      case SettingsMenuType.danmaku:
        return 6;
      case SettingsMenuType.speed:
        return availableSpeeds.length - 1;
      case SettingsMenuType.playEnd:
        return PlayRepeat.values.length - 1;
      case SettingsMenuType.audio:
        return audioOptions.isEmpty ? 0 : audioOptions.length - 1;
      case SettingsMenuType.subtitle:
        return subtitleTracks.length; // 「關閉」＋各軌
      default:
        return 0;
    }
  }
}
