# 規格：直播上鍵隱藏控制列、彈出式留言

## 設計

### 設定（`lib/services/settings_service.dart`）

在 `liveChatVisible` 後新增：

- `liveChatStyle`（key `live_chat_style`，字串 `popup`／`list`，預設 `popup`）＋ `setLiveChatStyle`。
- `liveChatSide`（key `live_chat_side`，字串 `left`／`right`，預設 `left`）＋ `setLiveChatSide`。

寫法比照 `liveChatVisible`／`setLiveChatVisible`。

### 留言層（`lib/screens/live/widgets/live_chat_panel.dart`）

- `LiveChatPanel` 新增參數 `bool popup`、`bool onLeft`。
- 列表樣式：沿用現有 `Positioned`（top 96、bottom 120、寬 320），`onLeft` 時改 `left: 0`，圓角改右側。
- 彈出式：新的 `_LiveChatPopup`（StatefulWidget），`Positioned` 在 `bottom: 140`、`left: 24` 或 `right: 24`、`width: 420`；`IgnorePointer` + `ExcludeFocus`。
  - State 保存 `_PopupItem(msg, addedAt)` 清單；`initState` 時記下目前最後一則 id，不顯示舊留言（避免重開時一次湧出）。
  - `didUpdateWidget`：把 id 大於上次記錄的訊息加入；超過 6 則時移除最舊的。
  - `Timer.periodic(500ms)`：移除超過 8 秒的項目；有變化才 `setState`；`dispose` 取消。
  - 每個氣泡：`Column(mainAxisSize: min, crossAxisAlignment: start/end 依左右)`，新的在最下方；`Container` 底色 `Colors.black` alpha 0.55、圓角 14、padding 水平 12 垂直 6、間距 6；`Text.rich` 名稱（`0xFFfb7299`，13）＋內容（白，15），`maxLines: 2`。
  - 浮現：`TweenAnimationBuilder` opacity 0→1 + 往上位移 200ms。淡出：age ≥ 7.5 秒時 `AnimatedOpacity` 到 0（500ms），8 秒移除。氣泡以 msg.id 為 `ValueKey`。
- 兩種樣式切換或左右切換時，外層用不同 widget 即可（不需保留狀態）。

### 直播畫面（`lib/screens/live/live_player_screen.dart`）

1. 狀態：新增 `_chatPopup`、`_chatOnLeft`，`initState` 從 SettingsService 讀取（位置在 `_showChat = SettingsService.liveChatVisible;` 附近）。
2. 繪製：`LiveChatPanel(messages: ..., popup: _chatPopup, onLeft: _chatOnLeft)`。
3. 上鍵（AC-1、AC-2），在 `_onKeyEvent` 的 KeyDown 區段：
   - `_barFocused` 區塊內：新增 `arrowUp` → `_hideControls()`。
   - `_tsActive && arrowUp` 那行之後：新增 `arrowUp` → `_hideControls()`（未開時移時）。
4. 長按留言鈕（AC-5）：把現有彈幕長按邏輯泛化：
   - `_canHoldDanmaku` 改為焦點在 1 或 2；`_fireDanmakuHold` 依焦點開 `danmaku` 或新的 `chat` 選單；短按（KeyUp）依焦點呼叫 `_toggleDanmakuSetting(0)` 或切換留言（抽出 `_toggleChatVisible()`，`_handleControlSelect` case 2 也改用它）。
   - 變數可保留原名或改名為 `_hold*`，註解更新。
5. 留言選單：`LiveSettingsMenuType` 新增 `chat`；`_getSettingsItemCount` 回傳 3；右鍵／確認鍵呼叫 `_activateChatItem(index)`：0 切換顯示、1 切換樣式、2 切換左右，各自寫入 SettingsService 並 `setState`；左鍵沿用關閉面板。`_handleSettingsSelection` 也處理 chat。
6. `LiveSettingsPanel`（`lib/screens/live/widgets/live_settings_panel.dart`）新增參數 `chatVisible`、`chatPopup`、`chatOnLeft`；`chat` 選單標題「留言設定」，3 項用既有 `_buildSettingItem` 樣式：
   - 顯示留言：開／關（icon `chat_bubble`）
   - 樣式：彈出式／列表（icon `view_agenda` 或類似）
   - 位置：左側／右側（icon `swap_horiz`）
   - 所有 `switch (menuType)` 補上 `chat` 分支（含捲動、標題判斷）。

## 任務

- T-1：以上全部（同一組檔案，不拆）。

## AC 驗證方式

- 全部：`flutter analyze` 無新錯誤；建置成功。功能面待使用者在電視上測試。

## 邊界與風險

- 留言關閉時 `_chatMessages` 仍累積，但畫面只在 `_showChat` 時 setState；彈出層重建時只顯示新留言。
- 留言很多時（每秒數則）6 則上限會快速輪替，屬預期。
- 回退：還原這 4 個檔案即可；新設定 key 不影響舊資料。

## 審查紀錄

- 範圍明確（使用者已確認做法），未另派規格審查。
