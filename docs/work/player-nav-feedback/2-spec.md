# 播放器導覽與手機回報：規格

需求：[1-requirements.md](1-requirements.md)。

## 現況重點

以下 `檔案:行號` 以 2026-11-10 的 main 為準。

- **換片方式**：播放器沒有原地換片。換到另一部影片時，一律用 `Navigator.pushReplacement(PlayerScreen(video:))`，位置在：
  - `player_action_mixin.dart:692`、`:1432`
  - `player_event_mixin.dart:331`
  - `player_screen.dart:314`
- **換分P**：`switchEpisode(int newCid)`（action_mixin:1950）。番劇換集用 `_applyPgcEpisode(int)`（:1939）。
- **影片資料**：`PlaybackApi.getVideoInfo` 回傳整包 `data`，存在 `fullVideoInfo`（state:59）。裡面有 `ugc_season`，但目前沒有解析。分P清單是 `episodes`（state:124）。
- **播完處理**：`onVideoComplete`（action_mixin:1313-1375）和 `_peekNext`（:1390）。
- **控制列按鈕**：按鈕索引是寫死的 0–5，用在以下位置：
  - state:107
  - controls_overlay.dart:196-237
  - event_mixin:224、:232、:258-291、:384
- **設定面板**：
  - 子選單是 `SettingsMenuType`（settings_panel.dart:6）。
  - 主選單索引寫死為 0 畫質、1 彈幕、2 速度、3 CDN、4 收藏。
  - 處理位置：event_mixin:482-496、:534-536；action_mixin:2091-2125 的 `activateSetting`。
- **回報**：
  - 送出用 `ReportSendService.send({category, report, reportId})`（report_send_service.dart:214）。
  - 回報紀錄用 `ReportHistory.add`。
  - LocalServer 的路由在 `_handleRequest`（local_server.dart:136）。
  - 讀 JSON body 用 `_readLimitedJson`（:364，上限 8KB）。
  - 手機登入的 token 由 phone_login_service.dart:131-261 處理。

## 設計

### D-1 播完模式（AC-1.1–1.5）

- `lib/models/play_repeat.dart` 的 enum 改為：

  | 值 | 標籤 |
  |---|---|
  | `pause` | 播完暫停 |
  | `playNext` | 直接播下一部 |
  | `countdownNext` | 倒數後播下一部 |
  | `singleCycle` | 循環播放此影片 |
  | `listCycle` | 列表循環 |

- `SettingsService` 的讀寫：
  - 新的 key 是 `play_end_mode`，存 enum 的 `name` 字串。存名稱而不存 index，舊的 index 和新的值就不會混在一起。
  - 讀取順序：
    1. 先讀 `play_end_mode`。
    2. 沒有時，讀舊的 `play_repeat`（int，舊 enum 依序是 pause、listOrder、singleCycle、listCycle、autoPlayRelated），依 AC-1.5 轉換。舊值是 listOrder 或 autoPlayRelated 時，看 `upNextCountdown`：0 轉成 `playNext`，大於 0 轉成 `countdownNext`。
    3. 兩個都沒有時，看舊的 bool `auto_play`：值為 false 轉成 `pause`，其他情況轉成 `countdownNext`。
  - 第一次讀到舊值時，把轉換結果寫進 `play_end_mode`。
- 連播倒數：
  - `upNextCountdownOptions` 改成 `[3, 5, 10, 15]`。
  - 讀到 0 時，當作 5（「直接播下一部」已經涵蓋原本的 0 秒）。
- `playback_settings.dart`：「播放完畢後」的副標題改成列出新的 5 種模式，`settings_index.dart:41` 的副標題也一起改。
- 設定面板：
  - 主選單新增第 5 項「播放完畢後」，放在「收藏」之後。值顯示在右側，用左右鍵循環切換，並立刻存檔。
  - 新增這一項時，要一起更新主選單的項目數和上下鍵的範圍（event_mixin:482-496、:534-536、action_mixin:2091-2125）。

### D-2 上一部／下一部的判斷（名詞、AC-1.3、AC-2.2、AC-2.4、AC-1.6）

- 新檔 `lib/services/play_session_history.dart`：
  - 這次開 App 期間的播放紀錄堆疊，是 `static final List<Video>`，上限 50 筆，只存在記憶體。
  - 提供 `push(Video)`、`Video? pop()`、`bool get canPop`。
- 播放器換到另一部影片時，依換片的原因處理紀錄：
  - 往前換（下一部、相關影片、合集的下一部、UpNextCard 等）：先 `push` 目前的影片，再 `pushReplacement`。要 push 的影片用目前的 bvid、標題、封面組出 `Video`，不要用 `widget.video`，因為切換分P後它可能已經過時。
  - 往回換（上一部用到播放紀錄）：`pop` 後換到那部影片，不再 push。
- 合集解析：
  - 從 `fullVideoInfo['ugc_season']` 取出 `sections[].episodes[]`，依序攤平成 `List<Video> seasonVideos`。
  - 每一筆的資料來源：bvid、aid、cid、title；pic、duration、owner 取自 `arc`。
  - 用 `currentBvid` 找出 `seasonIndex`。找不到，或沒有 `ugc_season` 時，`seasonVideos` 為空。
  - 合集影片的分P一樣由 `episodes` 處理：先播完目前影片的分P，再換合集的下一部。
- 在 player_action_mixin 新增 `NavTarget? resolveNext({bool wrap = false})` 和 `NavTarget? resolvePrev()`。`NavTarget` 是 sealed class，有 3 種：
  - `EpisodeTarget(index)`：換分P或番劇的集。
  - `VideoTarget(Video, {bool fromHistory})`：換到另一部影片。
  - `RelatedFallback`：番劇播完最後一集，要打開相關影片。
- `resolveNext` 依序檢查，第一個成立的就是結果：
  1. 有下一個分P或集：`EpisodeTarget`。
  2. `seasonVideos` 裡有下一部：`VideoTarget`。
  3. `wrap` 為 true（列表循環）時：
     - 有合集：回到合集第一部。
     - 只有分P或集：回到第一個分P或第一集。
     - 都沒有：回傳 null，由呼叫端重播目前影片。
  4. 不是番劇，而且 `relatedVideos` 不是空的：第一個相關影片（`VideoTarget`）。
  5. 番劇：`RelatedFallback`。
  6. 其他情況：null。
- `resolvePrev` 依序檢查：上一個分P或集；`seasonVideos` 的上一部；`PlaySessionHistory.canPop` 時為 `VideoTarget(fromHistory: true)`；其他情況為 null。
- 新增 `bool get hasPrev`、`bool get hasNext`，讓控制列判斷按鈕是否變暗。`hasNext` 遇到 `RelatedFallback` 時是 false。
- 新增 `Future<void> playPrev()`、`Future<void> playNext()`，執行上面的目標，並依規則處理播放紀錄。
- 改寫 `onVideoComplete`：保留試看與 UP 主頁開著時不連播的判斷（:1321、:1328），然後依模式處理：

  | 模式 | 行為 |
  |---|---|
  | `pause` | 原本的暫停行為 |
  | `singleCycle` | 從頭重播 |
  | `listCycle` | `resolveNext(wrap: true)`；結果是 null 時從頭重播 |
  | `playNext` | 有目標就立刻執行並顯示原本的 toast；沒有目標時暫停 |
  | `countdownNext` | 有目標就用 `startUpNext` 倒數，倒數結束後執行目標；沒有目標時暫停 |

  `playNext` 和 `countdownNext` 遇到 `RelatedFallback` 時，暫停、顯示「已播完最後一集」，並打開相關影片（D-4）。
- UpNextCard 要能顯示合集的下一部：倒數的目標改用 `NavTarget`，卡片顯示目標的標題和封面。
- 刪除舊的 `_peekNext`，由 `resolveNext` 取代。

### D-3 控制列（AC-2.1、AC-2.3、AC-3.x）

- 在 `player_state_mixin.dart` 新增按鈕索引常數 `abstract final class CtrlBtn`：

  | 常數 | 值 | 按鈕 |
  |---|---|---|
  | `prev` | 0 | 上一部 |
  | `playPause` | 1 | 播放/暫停 |
  | `next` | 2 | 下一部 |
  | `episodes` | 3 | 選集 |
  | `up` | 4 | UP主 |
  | `danmaku` | 5 | 彈幕 |
  | `settings` | 6 | 設定 |
  | `actions` | 7 | 點讚/投幣/收藏 |

  另外定義 `count = 8`。把所有寫死的數字換成這些常數，並移除「更多影片」按鈕（舊的 3）。
- 按鈕圖示：
  - 上一部：`Icons.skip_previous`
  - 下一部：`Icons.skip_next`
  - 彈幕：開啟時 `Icons.subtitles`，關閉時 `Icons.subtitles_off`
- 變暗的按鈕：
  - 沒有上一部或下一部時，按鈕的 opacity 設 0.35。
  - 左右鍵移動時跳過變暗的按鈕。目前焦點所在的按鈕變成不能用時（例如換片後），焦點移到「播放/暫停」。
  - 打開控制列時，預設焦點仍然是「播放/暫停」。
- 彈幕按鈕：
  - 長按偵測比照 `base_tv_card.dart:210-238`：
    1. 確認鍵 KeyDown 時開始 500ms 計時。
    2. KeyRepeat 事件吞掉。
    3. 計時到了：判定為長按，打開設定面板。
    4. 計時到之前 KeyUp：判定為短按，執行 `toggleDanmaku()`，並顯示「彈幕已開啟」或「彈幕已關閉」。
  - 長按打開設定面板的方式：在同一個 setState 裡設 `settingsMenuType = SettingsMenuType.danmaku`、`focusedSettingIndex = 0`、`showSettingsPanel = true`。
  - 長按後的 KeyUp 不能再觸發短按。
  - 其他按鈕的確認鍵行為不變。
- 下鍵：從控制列按下鍵時，打開 D-4 的相關影片（取代 `_activateControlButton(3)`）。

### D-4 相關影片底部橫排（AC-4.x、AC-1.6）

- 新檔 `lib/screens/player/widgets/related_strip.dart` 取代 `related_panel.dart`。舊檔刪除，`player_screen.dart:310-328` 改用新元件。
- 狀態：
  - 沿用 `showRelatedPanel`。
  - 新增 `bool relatedExpanded`，`false` 表示一排，`true` 表示展開成多排。
- 版面：
  - **一排**：貼齊畫面底部，高度約 260。背景是由下往上的漸層，從 `Colors.black` alpha 0.6 漸變到透明。卡片上方的影片畫面不加遮罩。
  - **展開**：佔畫面高度約 65%，從底部往上展開，背景是 `Colors.black` alpha 0.55。用 `GridView`，欄數 = `(可用寬度 / 280).floor()`。
  - 卡片用 `TvVideoCard`，寬 260、間距 20，設定 `showDanmaku: true`，和 UP 主頁相同（up_home_tab.dart:58-59、space_tab.dart:13）。
- 資料：
  - 一般影片：用 `relatedVideos`（已經載入的結果）。還沒載入時呼叫 `VideoApi.getRelatedVideos`。
  - 番劇：新增 `PgcApi.getSeasonRelated(int seasonId)`，打 `GET /pgc/season/web/related/recommend?season_id=`。
    - 把結果轉成卡片可以顯示的 `Video`。
    - 點下去時，用 App 現有的開啟番劇方式（比照首頁番劇卡片的 onTap）。
    - 實作時先確認回應格式。API 失敗時顯示「沒有相關推薦」。
- 按鍵操作：
  - 一排時：下鍵展開；上鍵或返回鍵收起，焦點回到控制列。
  - 展開時：在最下面一排按下鍵沒有動作。在第一排按上鍵或按返回鍵，收回成一排。
  - 收回成一排後，再按上鍵或返回鍵，關閉相關影片。
- 點卡片：依 D-2 的規則 push 播放紀錄，然後換到該影片。
- 打開相關影片時，影片繼續播放。AC-1.6 的情況除外，因為那時影片已經播完並暫停。

### D-5 手機回報（AC-5.x）

- 新檔 `lib/services/phone_feedback_service.dart`：
  - token 產生與驗證比照 `PhoneLoginService`：16 碼，15 分鐘到期，錯誤次數有上限。
  - 提供 `String? start()`（回傳完整網址）、`void stop()`、`checkToken`。
  - 提供 `ValueNotifier<FeedbackEvent?> lastSent`，讓電視端的對話框顯示結果。
- 新檔 `lib/services/phone_feedback_page.dart`：
  - `const phoneFeedbackPageHtml`，是 inline HTML。手機版面、繁體中文。
  - 頁面內容：「問題／建議」兩個 radio、textarea（`maxlength=2000`，附字數）、送出按鈕、結果區。
  - 送出失敗時保留輸入的文字。
- `local_server.dart`：
  - `GET /feedback?t=` 回傳頁面。token 錯誤時回 403。
  - `POST /api/feedback?t=` 讀 body `{type: "issue"|"suggestion", text}`：
    - 用 `_readLimitedJson` 讀取，上限 8KB。
    - text 去掉頭尾空白後，必須是 1 到 2000 字。
  - 收到後在電視端組報告：
    - `issue`：`使用者描述：\n<text>\n\n` 加上 `ErrorReportService.buildReport()` 的完整內容。
    - `suggestion`：`使用者建議：\n<text>\n\n版本：…\n裝置：…`。不附 log、設定、效能資料。
  - 用 `ReportSendService.send` 送出。分類：
    - `issue` 用新的 `ReportCategory.phoneIssue('問題（手機輸入）')`。
    - `suggestion` 用新的 `ReportCategory.suggestion('建議')`。
  - 成功時寫入 `ReportHistory.add`，回應 `{ok: true, id}`。失敗時回應 `{ok: false, error}`。
  - 同一個 token 送出成功後失效。手機要再送一次，需要電視重新產生 QR 碼。
- `error_report_dialog.dart`：
  - 分類選單之後加一個「用手機輸入」按鈕。
  - 按下後顯示 QR 碼、網址和說明「用同一個 Wi-Fi 的手機掃描」。
  - 送出成功時，電視顯示「已收到回報（編號 XXXXXX）」並刷新回報紀錄。
  - 關閉對話框時呼叫 `stop()`。
- `about_settings.dart:125` 和 `settings_index.dart:101` 的說明文字改成「送出錯誤報告或功能建議給開發者」。
- Apps Script：
  - 確認 `docs/report-gmail/` 裡的腳本是否接受新的 category 字串。
  - 如果腳本會擋未知的 category，在驗證時回報，不要修改腳本（需求的「不做」）。

## 任務

| 任務 | 內容 | 相依 |
|---|---|---|
| T-1 | D-1 與 D-2：播完模式、資料轉換、設定頁、設定面板項目、`PlaySessionHistory`、合集解析、`resolveNext`/`resolvePrev`、`playPrev`/`playNext`、改寫 `onVideoComplete`、UpNextCard 的目標 | — |
| T-2 | D-3 與 D-4：控制列按鈕常數、上一部/下一部/彈幕按鈕、長按、related_strip、PGC 推薦 API、下鍵、AC-1.6 打開相關影片 | T-1 |
| T-3 | D-5：手機回報 | —（可以和 T-1 同時做） |

## 驗證方式

- **全部**：`flutter analyze` 沒有問題，`flutter test` 全部通過。
- **單元測試**：
  - D-1 的資料轉換：`test/` 新增 PlayRepeat 轉換測試，用 SharedPreferences mock 測每一列轉換表。
  - D-2 的合集攤平：`ugc_season` 的 sections 攤平寫成純函式，加單元測試。
- **AC-1.x、2.x、3.x、4.x**：用模擬器操作，等使用者要求時再做。
- **AC-5.x**：
  - 用 `curl` 打 `/feedback` 和 `/api/feedback`：沒有 token 或 token 錯誤時要回 403；字數超過要回 400。
  - 實際送出一筆「建議」，確認 Gmail 收到（需要使用者確認收信）。

## 風險與回退

- 舊的播放模式轉換錯誤會改變使用者的播放行為：用單元測試涵蓋每一列轉換表。
- 按鈕索引全部重新編號，容易漏改：改用常數後，搜尋 `focusedButtonIndex` 的所有使用處逐一確認。
- PGC 推薦 API 的格式還沒確認：API 失敗時顯示「沒有相關推薦」，不影響播放。
- 回退：每個任務分開 commit，可以個別 revert。

## 審查紀錄與修正（2026-11-10，Sonnet 規格審查）

以下修正**優先於**上方設計內容。審查意見的編號是審查報告裡的編號。

### 採用

- **#1 安全**：
  - `/feedback` 和 `/api/feedback` 的判斷要放在 CORS 區塊之前，照 `/login`、`/report` 的做法（local_server.dart:143-153）：不加 CORS、不放行 OPTIONS。
  - 回應加 `Cache-Control: no-store` 和 `Referrer-Policy: no-referrer`。
  - POST 的 Content-Type 必須是 `application/json`，否則回 415。
  - token 錯誤次數有上限，比照 `PhoneLoginService.checkToken`。
- **#2、#3 播放紀錄**：
  - 播放紀錄存的 `Video` 要帶 `seasonId` 和 `epId`（`Video` 已經有這兩個欄位，models/video.dart:24-25）。這樣番劇從紀錄 pop 回去時，才能開對影片。
  - 新增唯一的換片入口 `navigateTo(Video, {bool record = true})`。只有以下 4 處會用它並記錄：
    - `playNext`
    - 相關影片的 onTap
    - UpNextCard 的 play
    - UP 主頁選片（event_mixin:331）
  - `_redirectToPgc`（action_mixin:692）不走 `navigateTo`，也不記錄。
  - 「上一部」從播放紀錄 pop 時，用 `record: false`。
- **#4 回報分類**：不新增 `ReportCategory` 的 enum 值，因為對話框（error_report_dialog.dart:220、:227）會用 `values` 列出全部分類。改為：
  - `ReportSendService.send` 加選填參數 `String? categoryLabel`，有值時取代 `category.label`，寫進 payload 的 category。
  - 手機回報「問題」時用 `category: other`、`categoryLabel: '問題（手機輸入）'`。
  - 手機回報「建議」時用 `category: other`、`categoryLabel: '建議'`。
  - 寫進 `ReportHistory` 的分類也用 `categoryLabel`。需要時擴充 `ReportHistory.add` 的參數。
- **#5 長按**：
  - 在 `handleGlobalKeyEvent` 最前面處理長按，比 :101-110 的 KeyUp 早退更早。條件是 `showControls && focusedButtonIndex == CtrlBtn.danmaku`，而且按的是確認鍵（select、enter、gameButtonA）。
  - KeyDown：開始計時，回傳 handled。
  - KeyRepeat：吞掉，回傳 handled。
  - KeyUp：計時還沒到就判定為短按，執行切換。
  - 以下情況要取消計時器：控制列隱藏、焦點離開彈幕按鈕、dispose。
- **#6 UpNextCard**：`UpNextInfo` 和 `startUpNext` 不改。由 `resolveNext` 的結果組出 `UpNextInfo{title, cover, play}`。D-2 裡「UpNextCard 改用 NavTarget」作廢。
- **#7 倒數中的下鍵**：倒數中按下鍵（event_mixin:130-136）也改成打開底部相關影片，並保留 `cancelUpNext()`。`_activateControlButton` 要補上 `CtrlBtn.prev` 和 `CtrlBtn.next`。
- **#8 相關影片**：
  - 新元件用 `currentBvid`，不用 `widget.video.bvid`。
  - 一排／展開／收起的按鍵由 `related_strip.dart` 自己的 Focus 處理。
  - 打開相關影片期間，全域的控制列處理不攔截方向鍵。照現有 RelatedPanel 打開時的處理方式，確認 `showRelatedPanel` 為 true 時全域處理會放行。
- **#9 合集資料不足**：
  - 合集 `Video` 的 owner 先從 `arc.owner` 取（如果有），沒有時從目前影片的 `fullVideoInfo['owner']` 取，因為合集通常是同一個 UP 主。
  - 實作前先用一部合集影片實測 `fullVideoInfo` 有沒有 `ugc_season`。
- **#10 合集與分P**：
  - 換到合集的另一部影片時，從它的第 1 個分P開始，也就是用 episode 的 `cid`，它對應第 1P。
  - 列表循環回到合集第一部時，同樣從第 1P 開始。
- **#11 設定面板**：
  - 主選單的最大索引從 4 改成 5（event_mixin `_getSettingsMaxIndex`）。
  - 從「彈幕設定」子選單返回主選單時，焦點落在「彈幕」（index 1），不是 0。CDN 返回落在 3 的行為保留。
- **#12 舊設定轉換**：先轉換 `play_end_mode`，再把倒數秒數正規化。單元測試要包含「舊 listOrder ＋ 倒數 0 → playNext」。
- **#13 Apps Script**：腳本只截斷 category、不擋未知值（apps_script.gs:40-44），所以不用修改。
  - 送出被限流（每個安裝每小時 5 筆）時，`send` 的失敗訊息要原樣回給手機頁顯示。
- **#14 字數與上限**：`/api/feedback` 讀 body 的上限放寬到 16KB。`_readLimitedJson` 加 `maxBytes` 參數，預設 8KB 不變。字數上限維持 2000。
- **#15、#16 檔案衝突**：
  - 「回報問題/建議」標籤，以及 settings_index.dart:101、about_settings.dart:125 的說明文字，Opus 已經先改好。T-3 不再修改 settings_index.dart。
  - T-1 結束時，`resolveNext`、`resolvePrev`、`hasPrev`、`hasNext`、`playPrev`、`playNext`、`navigateTo` 和 `NavTarget` 的介面固定，T-2 直接使用。
- **#17 AC-1.6**：
  - 發生 AC-1.6 時，控制列隱藏，相關影片以一排打開，焦點在第一張卡片。
  - 收起相關影片後，顯示控制列，焦點在「播放/暫停」。
  - `hasHandledVideoComplete` 維持原本的行為。
  - 打開控制列時，如果 `focusedButtonIndex` 指到不能用的按鈕，就改成 `playPause`。
- **#18 PGC 推薦 API**：T-2 的第一步是確認 PGC 推薦 API 的回應格式。如果 API 不能用，番劇改成只顯示「沒有相關推薦」，並記在「實作偏差」。
- **#19 上一部的判斷**：`hasPrev` 和 `hasNext` 是 getter，每次重新計算，不要快取。

### 不採用

無。

## 實作偏差（T-1）

- **ugc_season 未實測**：沙箱連不到 B 站 API（回傳網頁而不是 JSON）。依 API 文件推斷：`view` 回傳的 `data.ugc_season.sections[].episodes[]` 有 `bvid`、`aid`、`cid`、`title`、`arc{pic,duration,pubdate,author{mid,name,face},stat}`。`arc` 的 owner 欄位文件寫的是 `author`，所以攤平函式同時接受 `arc.owner` 與 `arc.author`，都沒有時用目前影片的 `owner`。`fullVideoInfo` 存的是整包 `data`，所以 `ugc_season` 一定在裡面。需要在真機確認。
- **解析放在純函式**：`lib/utils/ugc_season_utils.dart` 的 `flattenUgcSeason`，回傳 `SeasonFlat(videos, index)`；`NavTarget` 放在 `lib/models/nav_target.dart`。
- **舊設定轉換**：轉換寫成純函式 `PlayRepeat.resolve`，`SettingsService.playRepeat` 呼叫它；由舊 `play_repeat` 轉換時才寫回 `play_end_mode`。`SettingsService.debugSetPrefs` 供測試注入。
- **列表循環不倒數**：舊版列表循環會套用連播倒數；AC-1.3 只有「倒數後播下一部」提到倒數，所以列表循環改為直接換（顯示 toast）。
- **合集從第 1P 開始（#10）**：播放器原本不使用 `widget.video.cid`。在 `init` 的 cid 決定之後加一段：`widget.video.cid > 0` 且 `episodes` 有這個 cid 時，使用它。合集的 `Video` 帶 episode 的 cid（第 1P）。播放紀錄的 `Video` 不帶 cid，回去時依進度續播。
- **`PlaySessionHistory.peek`**：新增，`resolvePrev` 不取出就能得到目標；實際 `pop` 在 `playPrev`。
- **上一部經合集不記錄**：`playPrev` 一律 `record: false`，包含合集上一部。
- **`navigateTo` 會 `cancelUpNext()`**。
- **設定面板第 5 項**：`SettingsPanel` 新增必填參數 `playEndLabel`；確認鍵、右鍵往後循環，左鍵往前循環（原本主選單左鍵是關閉面板，只有第 5 項例外）。三處「子選單返回」（含 `onPopInvoked`、全域返回鍵）都改用 `_mainIndexAfterBack`（CDN 3、彈幕 1）。
- **審查修正**：`resolvePrev` 會丟掉播放紀錄頂端與目前 bvid 相同的項目；合集上一部若等於紀錄頂端先 pop；`navigateTo` 目標與目前同 bvid 不 push，並以 `_navigating` 擋重入；`init` 改讀新的 `PlayerScreen.startCid`（只有合集 `VideoTarget` 帶 `video.cid`），其他入口維持原本續播；彈幕短按後 `startHideTimer()`。
- **`RelatedFallback` 的 hook**：`openRelatedStrip` 目前設 `showControls = false`、`showRelatedPanel = true`（仍是舊的右側面板），T-2 取代。

## 實作偏差（T-3）

- `PhoneFeedbackService.start()` 是同步的；網址的區網位址由對話框先呼叫 `LocalServer.refreshAddress()` 取得。
- 送出失敗（含限流）時，`/api/feedback` 回 HTTP 200 加 `{ok:false,error}`，代碼保留，手機可以再送；只有送出成功才讓代碼失效。
- 「刷新回報紀錄」：紀錄由 service 送出成功後直接寫入 `ReportHistory`，歷史對話框每次開啟都重新載入，所以不需要另外刷新。
- 「用手機輸入」按鈕只放在選擇分類的畫面（select stage）。
- 另外有 `/api/feedback` 同時送出的保護（送出中再送會回「正在送出，請稍候」）；`type` 不是 issue／suggestion 時回 400。

## 實作偏差（T-2）

- **PGC 推薦 API 已確認可用**：`GET /pgc/season/web/related/recommend?season_id=33378` 不需登入就回 `code:0`，`data.season[]`（番劇）與 `data.relates[]`（漫畫等，不使用）。season 項目有 `season_id`、`title`、`cover`、`badge`、`stat{view,danmaku}`、`new_ep.index_show`、`styles[].name`。轉換放在 `Video.fromSeasonRelated`，`PgcApi.getSeasonRelated(seasonId)` 失敗回空清單，元件顯示「沒有相關推薦」。點卡片走 `navigateTo`（`PlayerScreen(video)`，`seasonId > 0` 即番劇，與首頁卡片相同）。
- **返回鍵不在 RelatedStrip 內處理**：返回鍵要設 `backKeyJustHandled`（避免 PopScope 重複處理），所以由 `handleGlobalKeyEvent` 與 `onPopInvoked` 處理（展開時先收回一排，再關閉）；上下左右鍵與一排／展開切換仍由 RelatedStrip 自己處理。
- **`TvVideoCard` 新增 `enablePreview`（預設 true）**：播放器內關閉，避免焦點預覽與預載同時啟動第二個解碼器。
- **相關影片資料由元件自己載入**：`relatedVideos` 是 Map 且沒有彈幕數，不能顯示 `showDanmaku`，所以元件用 `bvid` 重新呼叫 `getRelatedVideos`（番劇用 `getSeasonRelated`）。
- **`openRelatedStrip(focusFirstCard)`**：元件開啟時一律把焦點放在第一張卡片；參數為 true（AC-1.6）時，另外把控制列焦點重設為 playPause。從控制列按下鍵打開時保留原焦點按鈕，收起後回到該按鈕。
- 無相關推薦（載入中或空清單）時，元件用後備 Focus 接收按鍵：上鍵收起或關閉，其餘方向鍵吞掉。
- **彈幕短按的 toast** 沿用 `toggleDanmaku()` 內建的 toast（未重複顯示）。
- 按下不能用的上一部／下一部（理論上焦點不會落在上面）時不動作。

## 除錯紀錄（上一部）

- 回報：A 播完、倒數換到 B 後，按「上一部」第 1 次 B 從頭重播，第 2 次跳到無關影片，疑似 A 沒被記進播放紀錄。
- 做法：在 `navigateTo`、`playPrev`、`_runTarget` 加暫時的 `[NavHist]` log（印堆疊、`playingBvid`、target 類型），以 release x86_64 APK 在模擬器重現，驗證後已移除。
- 結果：目前工作樹的程式碼無法重現。log 證據：
  - A（`BV1aExF6nEYU`）倒數換到 B 時 `navigateTo ... record=true playing=A stack=[]`，之後堆疊為 `[A]`，A 有被記進去，`playingBvid` 沒有被暖機／預載改成 B（非番劇時 `currentBvid` 只有 `_applyPgcEpisode` 會設）。
  - B 按上一部：`playPrev target=V:A hist=true stack=[A]`，pop 後 `navigateTo A record=false stack=[]`，回到 A。
  - A→下一部→B→下一部→C：`stack=[A,B]`，上一部回 B（stack=[A]），再上一部回 A（stack=[]），不會換到自己。
  - 相關影片點卡片換片後上一部：`stack=[A]`，回到 A。
  - 合集影片（A→B 走 season）也正常：`target=V:A hist=false`，頂端相同時 pop。
- 根本原因：推測回報的現象來自 `resolvePrev` 先前會在 build 中 pop 紀錄的舊版本（見「實作偏差（T-1）」的審查修正，現已改為不修改紀錄、只在 `playPrev` pop）。目前版本未發現其他問題，因此沒有再改程式碼。
- 若仍能重現，請提供當時的 `[NavHist]` log（需重新加上），重點看 `navigateTo` 當下的 `stack`。
