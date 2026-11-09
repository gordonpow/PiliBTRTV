# 規格：即時卡片預覽、播放中下鍵看相關影片、播完倒數連播

對應需求：[1-requirements.md](1-requirements.md)

## 設計

### A. 卡片預覽啟動時機（AC-1～3）

新增 `lib/utils/nav_settle.dart`：`NavSettle` 單例。

- 啟動時（`main.dart` 初始化處，或第一次使用時 lazy）註冊 `HardwareKeyboard.instance.addHandler`，記錄方向鍵最後一次 `KeyRepeatEvent` 的時間 `_lastRepeatAt`；handler 一律回傳 false（不吃按鍵）。
- `bool get isHeld`：上下左右任一方向鍵在 `HardwareKeyboard.instance.logicalKeysPressed` 中，且 `_lastRepeatAt` 在 150ms 內。
- `Duration onFocusArrived()`：卡片取得焦點時呼叫，回傳這張卡片要等多久再開始；並更新 `_lastFocusAt`。
  - 上一張卡片取得焦點距今 ≥ 300ms 且 `!isHeld`：回傳 150ms（單次移動）。
  - 否則回傳 250ms（快速移動）。
- 卡片計時到時呼叫 `bool canStartNow()`：`!isHeld` 且距 `_lastFocusAt` ≥ 已等待時間；`isHeld` 時卡片再等 250ms 重試（迴圈直到放開或失焦）。

`lib/widgets/base_tv_card.dart` `_onFocusChange`：

- 把目前的 300ms `_prefetchTimer` 與 1 秒 `_previewTimer` 合併為一個 `_startTimer`，延遲取自 `NavSettle.instance.onFocusArrived()`。
- 計時到時：`!mounted || !_isFocused` 就結束；`NavSettle.instance.isHeld` 就重新排 250ms；否則依原本邏輯 `PrefetchService.instance.schedule(this, video)`，並 `CardPreviewService.instance.start(this, video)`（暖機或 480P 預覽都在此時開始，條件同現在：`SettingsService.cardPreview`）。
- 失焦、dispose、`_handleSelect` 的取消邏輯照舊（改為取消 `_startTimer`）。`_keepPrefetch` 行為不變。
- `CardPreviewService` 不需修改（`start` 已有 generation 取消）。

### B. 控制列下鍵開相關影片（AC-4）

`lib/screens/player/mixins/player_event_mixin.dart` `_handleControlsVisibleKeyEvent`：在呼叫 `PlayerFocusHandler.handleControlsNavigation` 之前，`arrowDown` 的 KeyDownEvent 直接執行 `_activateControlButton(3)`（開「更多影片」面板）並回傳 handled。上鍵維持隱藏控制列。控制列隱藏時的處理不變。

### C. 播放完畢模式與倒數（AC-5～10）

**設定** `lib/services/settings_service.dart`：

- 新增 `enum PlayRepeat { pause, listOrder, singleCycle, listCycle, autoPlayRelated }`，各有 `label`：播完暫停、順序播放、單個循環、列表循環、自動連播。（可放在 `lib/models/play_repeat.dart`。）
- `static PlayRepeat get playRepeat`：讀 `play_repeat`（int index）；沒有值時，若舊的 `auto_play` 為 false 回傳 `pause`，否則 `autoPlayRelated`。`setPlayRepeat`。保留 `autoPlay` getter 但改為 `playRepeat != PlayRepeat.pause`（若仍有呼叫端），`setAutoPlay` 移除或保留但不用。
- `static int get upNextCountdown`：`up_next_countdown`，預設 5，只接受 0/3/5/10/15。`setUpNextCountdown`。

**設定介面** `lib/screens/home/settings/tabs/playback_settings.dart`：把「自動連播」toggle 換成兩個 `SettingDropdownRow`：「播放完畢後」（PlayRepeat）、「連播倒數」（0 顯示「立即播放」，其他顯示「N 秒」）。第一項保留 `isFirst`、`onMoveUp`、`sidebarFocusNode` 等原本參數。若設定項有 `SettingFocusTarget`／設定搜尋定位機制，比照其他項目接上。

**設定搜尋** `lib/screens/home/settings/settings_index.dart`：「自動連播」改為「播放完畢後」（subtitle：播完暫停、順序播放、單個循環、列表循環、自動連播），新增「連播倒數」（影片播完後倒數幾秒再播下一部）。標題必須與介面 label 相同（搜尋定位依 label，先讀現有機制確認）。`test/settings_index_test.dart` 若有固定數量或名稱斷言要更新。

**播放器狀態** `player_state_mixin.dart`：新增 `int? upNextSeconds`、`Timer? upNextTimer`、`UpNextInfo? upNextInfo`（`title`、`cover`、`VoidCallback play`）。dispose 時取消 timer（找到現有 dispose／disposePlayer 位置）。

**播完處理** `player_action_mixin.dart` `onVideoComplete`：

1. 保留：防重複、試看 toast 後 return、`upSpaceOpen` return。
2. 依 `SettingsService.playRepeat`：
   - `pause`：`showControls = true`，上報 -1，結束。
   - `singleCycle`：`hasHandledVideoComplete = false`、`seekTo(Duration.zero)`、`play()`，上報 -1，結束（不倒數）。
   - 其他：用 `_peekNext(mode)` 決定下一部：
     - 有下一集（`episodes` 中目前 cid 之後一筆）：下一集（title 同現在的 toast 文字；cover 用 episode 的 `first_frame`／`cover`，沒有就用目前影片封面）。動作＝`switchEpisode(nextCid)`（PGC 原本用的切集方法照舊，先讀現有程式確認 UGC／PGC 下一集是否都走 `switchEpisode`）。
     - 最後一集且 `listCycle`：`episodes.length > 1` 回到第一集；否則（單一影片）重播，同 singleCycle。
     - 最後一集且 `autoPlayRelated` 且非番劇且 `relatedVideos` 不空：第一個推薦影片（title、pic），動作＝原本的 `pushReplacement` 到新 `PlayerScreen`。
     - 其他（`listOrder` 最後一集、番劇最後一集、沒有推薦）：同 `pause`。
   - 有下一部時：暫停目前影片；上報 -1（原本最後一律上報，保持）；`upNextCountdown == 0` 直接執行動作（保留原本 toast）；否則 `startUpNext(info)`。
3. `startUpNext`：`showControls = false`、`hideTimer?.cancel()`、`upNextSeconds = N`、`upNextInfo = info`，每秒遞減；到 0 時 `cancelUpNext()` 後執行 `info.play`。
4. `cancelUpNext({bool showControlsAfter = false})`：取消 timer、清空 `upNextSeconds`／`upNextInfo`；需要時顯示控制列並 `startHideTimer()`。
5. 其他要取消倒數的時機：`switchEpisode`、開 UP主頁、開相關影片面板、`initializePlayer` 開頭、video listener 偵測到使用者重播或跳轉（`position < duration - 1s` 且正在倒數）。

**按鍵** `player_event_mixin.dart` `handleGlobalKeyEvent`：最前面（KeyUp 處理之後、各面板之前）加入：`upNextSeconds != null` 且 KeyDownEvent 時：
- OK（`PlayerFocusHandler.isSelectKey`）：`final info = upNextInfo; cancelUpNext(); info?.play();` handled。
- 返回：`backKeyJustHandled = true`（比照現有返回鍵處理；escape 例外同現有規則），`cancelUpNext(showControlsAfter: true)`，handled。返回鍵也走 `onPopInvoked`／`handleBack` 類路徑時要同樣先處理倒數（讀現有 `backKeyJustHandled` 機制，避免返回同時觸發「再按一次退出」）。
- 下鍵：`cancelUpNext()`，開相關影片面板（同 `_activateControlButton(3)`），handled。
- 左右鍵：`cancelUpNext()`，然後讓原本流程處理（不 return）。
- 上鍵：handled，不動作。

**倒數卡片** 新增 `lib/screens/player/widgets/up_next_card.dart`：`UpNextCard(info, seconds)`，`player_screen.dart` 的 Stack 中、相關影片面板之前，`upNextSeconds != null && upNextInfo != null` 時以 `Positioned(right: 32, bottom: 48)` 顯示。內容：「接下來播放」、封面（16:9，寬約 320，`CachedNetworkImage` 或專案現有的圖片元件）、標題（最多 2 行）、右上角圓形倒數（`CircularProgressIndicator` value = seconds / total，中間數字）、底部提示「OK 立即播放 · ↓ 更多影片 · 返回 取消」。黑色半透明背景、圓角 12。

## 任務

| ID | 範圍 | 檔案 |
|---|---|---|
| T-1 | A | `lib/utils/nav_settle.dart`（新）、`lib/widgets/base_tv_card.dart` |
| T-2 | B、C | `settings_service.dart`、`play_repeat.dart`（新）、`playback_settings.dart`、`settings_index.dart`、`test/settings_index_test.dart`、`player_state_mixin.dart`、`player_action_mixin.dart`、`player_event_mixin.dart`、`player_screen.dart`、`up_next_card.dart`（新） |

T-1、T-2 無共用檔案，可平行。

## 驗證

| AC | 方式 |
|---|---|
| AC-1～3 | 程式碼審查；模擬器長按方向鍵時 log 不出現多次暖機（使用者測試） |
| AC-4、AC-7～9 | 程式碼審查；功能待使用者測試 |
| AC-5、AC-6、AC-10 | 程式碼審查、`flutter test` |
| 全部 | `flutter analyze`、`flutter test`、debug APK 建置 |

## 風險

- `HardwareKeyboard` 在 Android TV 遙控器上的 `KeyRepeatEvent`：Flutter 會把 Android repeatCount > 0 轉成 KeyRepeatEvent；若某些遙控器沒有 repeat，仍有 AC-3 的 300ms 間隔判斷兜底。
- 倒數期間返回鍵的雙重處理（`onPopInvoked` 與 key handler）。

## 審查紀錄

Sonnet 規格審查 11 條全部採用（以下優先於上文）：

1. **重播後能再觸發**：video listener 偵測 `position < duration - 1s` 時，`hasHandledVideoComplete = false`，正在倒數就 `cancelUpNext()`。所有模式都適用。
2. **singleCycle**：`await seekTo(Duration.zero); await play();` 完成後才設 `hasHandledVideoComplete = false`（或交給第 1 條的 listener 重置）。
3. **返回鍵**：`onPopInvoked`（player_event_mixin.dart 約 14-21 行）在 `backKeyJustHandled` 檢查之後、`showSettingsPanel` 之前加入 `if (upNextSeconds != null) { cancelUpNext(showControlsAfter: true); return; }`。key handler 中 escape 不設 `backKeyJustHandled`（比照現有規則）。
4. **計時器**：`PlayerScreen.dispose` 同步取消 `upNextTimer`（與 hideTimer 同處）；timer 每次 tick 先檢查 `mounted`；執行 `info.play` 前檢查 `mounted`。
5. **長按判斷**：`NavSettle` 用 `HardwareKeyboard` handler 記錄每個方向鍵的 KeyDown 時間；`isHeld` = 任一方向鍵目前在 `logicalKeysPressed` 中，且按下已超過 150ms（不依賴 KeyRepeat）。
6. **刪除 `canStartNow`**：卡片計時到時只檢查 `isHeld`。
7. **接受代價**：單次移動 150ms 後就暖機。非暖機的 480P 預覽（番劇、播放頁開著）也改為同一個計時（使用者要求馬上預覽）。
8. **KeyRepeat**：倒數中的按鍵處理同時涵蓋 KeyRepeatEvent：Repeat 的 OK、返回、上、下一律 handled 不動作；左右鍵的 KeyDown 先 `cancelUpNext()` 再走原本流程，Repeat 左右鍵在倒數已取消後才會進來（照原流程）。
9. **避免閃爍**：`onVideoComplete` 不再一開始就設 `showControls = true`；改由各分支決定（停住的分支顯示控制列，倒數分支隱藏）。
10. **移除 `autoPlay`／`setAutoPlay`**：只在 `play_repeat` 未寫入時讀舊的 `auto_play` 做遷移。
11. **測試**：`test/settings_index_test.dart` 新增 `search('連播倒數')` 斷言。
