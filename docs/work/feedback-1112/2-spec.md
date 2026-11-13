# 規格：2026-11-12 使用者回饋

需求見 `1-requirements.md`。四個任務改的檔案互不重疊，可平行。

## T-1 登入失效偵測與刷新（AC-1～4）

檔案：`lib/services/auth_service.dart`、`lib/services/api/auth_api.dart`、`lib/screens/splash_screen.dart`（`fetchAndSaveUserInfo` 呼叫處約 :99）。

- `AuthService`：新增 `refreshToken` getter（移除 `// ignore: unused_field`）；`logout()` 加 `_isVip = false` 並 remove `_keyIsVip`。
- `AuthApi.fetchNavData()` 改為能分辨結果：新增 `enum NavCheck { ok, invalid, unknown }` 或回傳 code。`-101` 為 invalid；HTTP 錯誤、例外、其他 code 為 unknown。保留既有呼叫端（`user_api.dart:147`、`fetchAndSaveUserInfo`）的行為。
- 新增 `AuthApi.refreshTvToken()`：
  - `POST ${BaseApi.passportBase}/x/passport-login/oauth2/refresh_token`，form/query 參數 `access_key`、`refresh_token`、`local_id=0`，用 `AppSign.appSign` 簽名（與 `pollTvLogin` 相同 appkey），標頭用 `_hdHeaders()`。
  - 成功（`code==0`）時從 `data.token_info`（`access_token`、`refresh_token`、`mid`）與 `data.cookie_info` 呼叫 `AuthService.saveLoginCredentials`。欄位缺漏視為失敗。
  - log 只記 code 與 message，不記任何 token 或 Cookie 值。
- 新增 `AuthApi.validateSession()`（啟動時呼叫一次）：
  1. nav 結果 ok → 照舊儲存使用者資訊。
  2. invalid → 有 access_token 與 refresh_token 時呼叫 `refreshTvToken()`，成功後再查一次 nav 並儲存使用者資訊。
  3. refresh 失敗或沒有 refresh_token → `AuthService.logout()`，回傳「已失效」。
  4. unknown → 不動登入狀態。
- `splash_screen.dart`：把原本的 `fetchAndSaveUserInfo()` 換成 `validateSession()`，`await` 並加 4 秒 timeout（timeout 視為 unknown），確保進首頁前登入狀態正確。已失效時用 `showZhToast` 顯示「登入已失效，請重新登入」。

## T-2 設定頁改用次級選單（AC-5、6）

檔案：`lib/screens/home/settings/tabs/playback_settings.dart`（:45、:62、:143、:169）、`btr_settings.dart`（:92、:121）、`about_settings.dart`（:115），`lib/screens/home/settings/widgets/setting_dropdown_row.dart`。

- 7 處 `SettingDropdownRow` 換成 `SettingPickerRow`（參考 `interface_settings.dart:280` 語言選項的用法）。保留原本的選項、標籤、副標題與 onChanged 行為（包含需要重啟提示等副作用）。
- 換完後 `SettingDropdownRow` 若已無引用，刪除該檔。
- 檢查設定搜尋結果（`settings_view.dart` 搜尋結果區）若有依類型建立這些 row，一併改用 picker。

## T-3 一般影片彈幕設定面板（AC-7、8）

檔案：`lib/screens/player/mixins/player_event_mixin.dart`（:103-184 長按、:618-700 設定面板按鍵、`adjustDanmakuSetting`）、`lib/screens/player/widgets/settings_panel.dart`，必要時 `player_state_mixin.dart`。

- 新增狀態 `danmakuPanelDirect`：由長按彈幕鍵（`_fireDanmakuHold`）開啟時為 true，由主選單進入時為 false。
- 彈幕選單按左鍵：direct 時關閉面板（同 main 左鍵行為）；否則回主選單、`focusedSettingIndex = 2`。不再 `adjustDanmakuSetting(-1)`。
- 彈幕選單按右鍵或 OK：開關項目切換；數值項目呼叫 `showTvMenuDialog`（`lib/screens/home/settings/widgets/tv_menu_dialog.dart`）列出可選值（依 `adjustDanmakuSetting` 現有的範圍與級距產生清單），選定後套用並儲存，與原本調值的副作用相同。
- 陷阱：播放器用全域按鍵處理（`handleGlobalKeyEvent`）。彈窗開著時，播放器的按鍵處理必須放行，按鍵要交給彈窗（例如用 `_dialogOpen` 旗標在 handler 開頭回傳 ignored，或確認 HardwareKeyboard handler 不會攔截）。彈窗關閉後焦點回播放器，控制列自動隱藏計時器不能在彈窗開著時把面板關掉。

## T-4 直播播放器（AC-7～13）

檔案：`lib/screens/live/live_player_screen.dart`、`lib/screens/live/widgets/live_settings_panel.dart`、`lib/services/live_socket_service.dart`，新增 `lib/screens/live/widgets/live_chat_panel.dart`，`lib/services/settings_service.dart`（聊天列表開關）。

- 控制列（:934 `_buildControls`、:1009-1049、:504-584）：按鈕改為 0 播放/暫停、1 彈幕、2 留言、3 畫質、4 線路、5 關注；移除重新整理與彈幕設定按鈕；更新 maxIndex 與過時註解。
- 彈幕按鈕：短按切換彈幕顯示（沿用 `_toggleDanmakuSetting(0)` 的效果）；長按 500ms 開啟彈幕設定面板（`LiveSettingsMenuType.danmaku`）。實作照一般影片 `player_event_mixin.dart:103-184`：KeyDown 起 Timer，KeyUp 早於 500ms 為短按，觸發後吞掉 Repeat 與 KeyUp。注意目前 handler 只處理 KeyDown，要讓 KeyUp/Repeat 進得來。
- 彈幕設定面板（:586-693）：左鍵關閉面板；右鍵/OK 對開關項切換、數值項開 `showTvMenuDialog` 選值。彈窗開著時直播的按鍵 handler 要放行。
- 播放/暫停：按鈕與 `mediaPlayPause`、`mediaPlay`、`mediaPause` 鍵。暫停時 `controller.pause()` 並停止看門狗；繼續時呼叫 `_initializePlayer()` 重新連到最新畫面。按鈕圖示依狀態切換。
- 自動重連：
  - 對 controller `addListener`：`value.hasError` 或「正在緩衝」連續超過 10 秒（且非使用者暫停）時重建播放器。退避 2s、4s、8s… 上限 30s；成功播放 10 秒後重置退避。dispose 與重建時移除舊 listener、取消計時器。
  - 彈幕 socket：`onError`／`onDone` 後依同樣退避自動重連（畫面 dispose 後不重連）。
  - 修正重複訂閱：保存 `StreamSubscription`，重連前 cancel。移除重複的 `_startPopularityTimer` 呼叫。
- 聊天列表：
  - 新 widget `LiveChatPanel`：右側半透明面板，`ListView` 顯示「使用者名稱: 內容」，保留最近 100 則，新訊息自動捲到底。不搶焦點。
  - 「留言」按鈕切換顯示，狀態存在 `SettingsService`（新 key，預設 false）。
  - `DANMU_MSG` 已帶 `user`（`live_socket_service.dart:264-287`），同時送進彈幕層與聊天列表。彈幕關閉時聊天列表仍然更新。
- 返回鍵行為維持原樣（面板開著先關面板）。

## AC 驗證方式

| AC | 驗證 |
|---|---|
| 1～4 | 程式碼審查 + 使用者實機（需讓 Cookie 失效） |
| 5～13 | 程式碼審查 + 使用者實機操作 |
| 全部 | `flutter analyze` 無新增問題、`flutter build apk` 成功 |

## 風險與回退

- oauth2 refresh 端點欄位若與預期不同，refresh 失敗會退回 AC-2（登出提示），不會比現在更差。
- 彈窗與全域按鍵 handler 衝突是主要風險，審查時重點檢查。
- 回退：各任務獨立 commit，可單獨 revert。

## 審查紀錄（Sonnet 規格審查，全部採用，以下補充覆蓋上文）

T-1：
- `refreshTvToken()` 回傳三態 `ok / rejected / unknown`。只有伺服器回 `code != 0` 且非限流（-412、-509、-799 等視為 unknown）才算 rejected；網路錯誤、HTTP 非 200、例外都是 unknown，不登出（AC-4）。新的 token 與 Cookie 寫入完成才算 ok。
- 參數補 `mobi_app=android_hd`、`platform=android`、`build=2001100`，appkey 與 `pollTvLogin` 同一組。實際回應待實機確認。
- splash 不擋啟動：在 splash 一開始就啟動 `validateSession()`（不 await），進首頁前才 `await` 剩餘時間，上限 4 秒。timeout 後背景結果仍會生效：若之後判定失效，照樣登出並 toast。
- 呼叫端有三個：`user_api.dart:147`、`login_view.dart:139`（經 `BilibiliApi.fetchAndSaveUserInfo`，`bilibili_api.dart:39`）、splash。前兩者行為不變；splash 改呼叫新的 `BilibiliApi.validateSession` 包裝。
- `auth_api.dart` 工作樹已有一處純格式修改（`final where = ...` 合成一行），保留即可。
- 執行中途的 -101 不處理（不在範圍，另記）。

T-2：
- 搜尋結果走 `SettingsIndex.search`，不建立 row，不用改。
- `SettingPickerRow.onChanged` 是非 null 的 `ValueChanged<T>`，移除原本 `if (v != null)` 判斷。選到與目前相同的值時不呼叫 onChanged（在 `SettingPickerRow._openMenu` 統一判斷），避免 CDN 模式與重啟提示誤觸發。

T-3：
- `adjustDanmakuSetting`（`player_action_mixin.dart:2866`）與 `activateSetting`（:3063）在 `player_action_mixin.dart`，檔案清單加入此檔。
- 長按彈幕與長按字幕共用 `_fireDanmakuHold`（`player_event_mixin.dart:136`）。`danmakuPanelDirect` 只影響彈幕選單；字幕選單左鍵維持原行為。
- 數值選項清單依一般影片現有範圍產生（字級 10–50 步進 2、速度 4–20 等，以程式碼為準），寫在 player 自己的檔案，不與直播共用。
- 彈窗衝突：兩個播放器都是 `Focus.onKeyEvent`，`showDialog` 會把焦點移到彈窗路由，不需要旗標。要確認：彈窗關閉後焦點回到播放器的 FocusNode（必要時 `requestFocus`）；開窗的 OK KeyDown 之後的 KeyUp/Repeat 不會在彈窗中誤選（彈窗項目只對 KeyDown 反應即可）；控制列自動隱藏計時器在彈窗開著時暫停。

T-4：
- `_initializePlayer` 加 generation token：每次呼叫遞增，每個 await 後比對，不符就 dispose 新建的 controller 並返回。`initialize()` 失敗時 dispose 該 controller。`getPlayUrl` 為 null 或初始化失敗也進入退避重試。
- 看門狗用 1 秒週期 Timer：`hasError`，或 `isBuffering`／position 未前進連續 10 秒（非使用者暫停、非初始化中）時重連。只由看門狗觸發重連，listener 不另外觸發，避免重複。
- `didChangeAppLifecycleState`：resumed 時依 `_userPaused` 決定；未暫停時重新連線到最新畫面（不是單純 `play()`）。
- `LiveSocketService`：加 generation／channel 身分比對，舊 channel 的 onDone/onError 不影響新連線；區分主動 `disconnect()` 與意外斷線，只有意外斷線才發出斷線事件給畫面重連；`connect()` 進行中不重複連線；`_msgController` 關閉後不再 add。
- 重連時的錯誤 toast 限流：同一段斷線只提示一次，恢復後再重置。
- 按鍵：播放/暫停鍵處理放在 `!_showControls` 吞鍵判斷之前。`_onKeyEvent` 要讓彈幕按鈕的 KeyUp／Repeat 進得來（長按判定）。
- `dispose` 取消所有新增計時器與訂閱；每個 await 後檢查 `mounted`。
- 直播彈幕數值選項依直播現有範圍（字級 10–30 步進 1、速度 5–20 等，以程式碼為準），寫在直播自己的檔案。
