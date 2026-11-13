# 規格：直播時移預覽快轉（#54）、長按判定修正（#55）

日期：2026-11-13

## 需求（AC）

- AC-1：直播時移開啟時，時移進度條只顯示，不再是焦點選項（移除 `_barFocused`）；按鈕列按上鍵直接隱藏控制列。
- AC-2：控制列隱藏時按左／右鍵（或任何時候按 mediaRewind／mediaFastForward，設定面板開著時除外）進入預覽模式：播放器暫停，預覽位置從目前位置開始，短按每次 ±10 秒，按住依 `holdSeekSpeed`（`lib/utils/seek_speed.dart`）加速，行為比照一般影片 `_performSeek`（`lib/screens/player/mixins/player_action_mixin.dart:2614`）。
- AC-3：預覽範圍夾在 `[ts.droppedDuration, ts.liveAbsolute - ts.liveEdgeOffset]`（絕對位置）。
- AC-4：預覽中 1.5 秒沒有再按方向鍵，或按 OK，跳到預覽位置（`_tsSeekToAbs`），預覽前在播放就恢復播放；上／下／返回／Escape 取消，回原位置並恢復播放。返回鍵取消預覽時不得離開直播頁。
- AC-5：預覽畫面：中央一張 16:9 縮圖卡（寬約螢幕 24%），下方一條進度條標出預覽位置，顯示「-MM:SS」（落後最新位置）或預覽到最新位置時顯示「LIVE」。外觀參考 `lib/screens/player/widgets/seek_thumbnail_strip.dart`。
- AC-6：縮圖從本機時移暫存擷取：找出預覽位置所在的本機片段，把 init 檔＋片段檔串成 `pv_<n>.mp4` 放在 session 目錄，呼叫 `FrameService.getFrame(path, Duration.zero)` 取 JPEG。請求 debounce 250ms；載入中保留上一張；沒有圖時顯示深色空卡。最多保留 3 個 `pv_*.mp4`，舊的刪除。
- AC-7：控制列沒開時移時，行為不變（左右鍵只顯示控制列）。
- AC-8（#55）：彈幕／留言鈕的長按判定能容忍「按下／放開」連發（模擬器主機鍵盤自動重複）：
  - KeyUp 後不立刻判定短按，啟動 150ms 計時；期間同一確認鍵再 KeyDown 視為持續按住（不重設 500ms 長按計時），回 handled。
  - 150ms 到期且長按尚未觸發 → 取消長按計時，執行短按動作。
  - 長按觸發後進入「吞鍵」狀態：之後每個確認鍵事件（down／up／repeat）都 handled 並重設 200ms 安靜計時，計時到期才解除，避免面板一開就被連發的 Enter 切換項目。
  - 套用到直播（`lib/screens/live/live_player_screen.dart` 的 `_handleDanmakuHold` 等）與一般影片（`lib/screens/player/mixins/player_event_mixin.dart` 的 `_handleDanmakuHold`）。真實遙控器（down＋repeat＋up）行為不變，短按只多 150ms 延遲。所有新 Timer 在 dispose 取消。

## 設計

### `lib/services/live/live_timeshift.dart`

新增 `Future<String?> previewFile(Duration absolute)`：
- `offset = absolute - droppedDuration`；依 `_local.segments` 累加 duration 找到包含 offset 的片段（超出則取最後一個）。
- 路徑 `_dir/pv_<n>.mp4`；已存在直接回傳。否則讀 `liveInitFileName(seg.initIndex)`（initIndex < 0 則不加 init）與 `seg.fileName`，串接寫入。檔案讀取失敗（已被刪）回 null。
- 記錄已產生的 pv 檔名（佇列），超過 3 個刪最舊的。disposed 時回 null。

### `android/app/src/main/kotlin/com/bili/tv/bili_tv_app/FrameChannel.kt`

`url` 以 `/` 開頭時用 `r.setDataSource(url)`（本機檔），否則維持帶 headers 的版本。

### `lib/screens/live/live_player_screen.dart`

- 移除 `_barFocused` 及相關分支（按鍵、`_canHoldDanmaku`、`_hideControls`、進度條的粉紅焦點框與圓點顏色）。
- 新增預覽狀態：`_tsPreviewAbs`（null = 不在預覽）、`_tsPreviewOrigin`、`_tsPreviewWasPlaying`、按住計速欄位、`_tsPreviewTimer`（1.5 秒自動確認）、縮圖 `Uint8List? _tsPreviewImage`、debounce timer。
- 進入預覽：`_controller?.pause()`（不要走 `_pausePlayback`，不改 `_userPaused`）；`_userPaused` 時起點用 `_pausedAbs`。
- 確認：`_tsSeekToAbs(target)`；若 `_tsPreviewWasPlaying` 則 `_controller?.play()`。若 `_userPaused`，`_tsSeekToAbs` 已會更新 `_pausedAbs`，維持暫停。
- 預覽中的按鍵在 `_onKeyEvent` 最前面處理（`_dialogOpen` 之後、長按判定之前）。返回鍵：直播頁用 PopScope 處理返回（約 1569 行），預覽中按返回要先取消預覽，不離開頁面。
- 預覽 overlay 放在 build 的 Stack 中控制列之上；預覽期間不顯示控制列。
- 移除時移的立即 seek 區塊（原 `barSeek` 那段），以預覽取代。

### 測試

`test/` 中若有 `LiveTimeshiftSession` 測試（14 個），為 `previewFile` 補 1～2 個測試（找片段、串接 init、保留 3 個）。

## 驗證

- `flutter analyze` 無問題、`flutter test` 全過、建置成功。
- 功能面待使用者測試。

## 回退

還原上述檔案即可，無資料格式變動。

## 第二輪修正（2026-11-13，使用者回饋）

- R-1 進度條比例：時移進度條的全長 = 設定的時移長度（`ts.maxBuffer`，5／10／30 分鐘）。已暫存部分寬度 = `bufferedDuration / maxBuffer`（最多 100%），播放位置 = `(目前絕對位置 - droppedDuration) / maxBuffer`。暫存未滿時進度條隨時間按比例前進（30 分鐘設定前進得比 5 分鐘慢；同一時間差，5 分鐘設定前進較快）；滿了就是 100%；倒退時依比例減少。預覽 overlay 的進度條用同一比例。
- R-2 綠色縮圖：
  - Kotlin `FrameChannel` 對本機檔（`/` 開頭）改用 `OPTION_NEXT_SYNC`；取到 bitmap 後抽樣（例如 8×8 格點）判斷是否幾乎全為綠色（R、B < 40 且 G > 60 的比例 > 90%），是的話回 null。
  - 使用者已在最新位置時按右鍵不進入預覽；預覽位置在最新位置（落後 < 5 秒）時不顯示縮圖卡，只顯示「LIVE」。
- R-3 多張縮圖：比照一般影片 `SeekThumbnailStrip` 的版面，中央大卡＋左右各 2 張小卡，間隔 10 秒（中心 ±10、±20 秒），超出暫存範圍或在最新位置以後的不顯示。先擷取中央，再擷取兩側；各卡依所在片段快取（同片段共用一張圖）。
- R-4 動態位置：暫停中或預覽中，直播持續寫入暫存，`droppedDuration`／`bufferedDuration` 會變。預覽與暫停期間每秒 `setState` 重算進度條與節點位置；預覽位置與 `_pausedAbs` 為絕對時間，若小於 `droppedDuration`（片段已被刪除）就夾到 `droppedDuration`。

## 第三輪修正（2026-11-13，使用者回饋：快進／倒退卡頓、縮圖慢、版面不對）

- R-5 版面與樣式完全比照一般影片 `lib/screens/player/widgets/seek_thumbnail_strip.dart`：卡片列的 Y 位置、中央／兩側卡片尺寸、圓角與白框、底部漸層、進度條位置與粗細、兩端文字樣式都用同樣的數值。最好的做法是把該檔的版面抽成可共用的 widget（例如輸入「卡片圖片清單＋中心索引＋進度比例＋左右文字」），一般影片與直播共用；若抽取會改到一般影片行為就複製數值。直播的左側文字為「-MM:SS」（落後最新位置，最新時為「LIVE」），右側文字為設定的時移長度（如 `05:00`）。進度條比例照 R-1。
- R-6 卡頓與縮圖慢：
  - 不在 Dart 讀檔串接：Kotlin `FrameChannel` 新增方法（例如 `getLocalFrame`，參數 `paths: List<String>`、`width`），用自訂 `MediaDataSource` 把 init 檔與片段檔虛擬串接（`RandomAccessFile` 依 offset 讀），不複製位元組。`LiveTimeshiftSession.previewFile` 改為回傳 `(initPath, segPath)`（或路徑清單）＋片段編號，不再寫 `pv_*.mp4`；移除相關刪除邏輯與測試改為新介面。
  - Kotlin 端以「請求序號」丟棄過時請求：Dart 每次預覽位置改變就送新的 generation；executor 開始處理時若 generation 已過時，直接回 null，不解碼。
  - Dart 端：按住（KeyRepeat）期間不擷取，只在方向鍵停止 200ms 後擷取；順序為中央 → 左右 1 → 左右 2，任一步發現預覽已移動就停止。
  - 縮圖以片段編號 n 快取（Dart 記憶體 LRU，最多 30 張），同片段直接使用。
  - 擷取寬度 320；`Image.memory` 設 `gaplessPlayback: true` 與 `cacheWidth`。
  - 預覽中的 `setState` 只在數值改變時呼叫；每秒動態重算（R-4）在預覽中仍保留。

## 第四輪修正（2026-11-13，縮圖仍很慢、中央卡空白）

觀察（模擬器 logcat）：每次擷取約 150～400ms，沒有錯誤 log；5 張依序擷取要 1～2 秒，與 1.5 秒自動確認相當，常常還沒載完預覽就結束。中央卡空白推測是該片段沒有關鍵幀（GOP 大於片段長度）或解出綠幀被過濾。

- R-7 錄製時預先擷取：`LiveTimeshiftSession` 每寫入一個本機片段（`_flush` 後），把該片段排入背景縮圖佇列，依序呼叫 `FrameService.getLocalFrame`（寬 320）。結果存在 session 內的 `Map<int, Uint8List>`（以片段編號 n 為 key），片段被 trim 移除時一併移除。佇列只保留最新 3 個待處理項目（太舊的丟掉），一次只處理一個；dispose 時停止。提供 `Uint8List? thumbnailFor(int n)`。
  - 預先擷取用的 generation 與預覽用的分開，不能互相讓對方的請求失效（Kotlin 的 gen 機制要支援「背景」請求不參與丟棄，例如 gen = 0 表示不檢查）。
- R-8 無關鍵幀的回退：擷取結果為 null 時，改用 `[init, 前一片段, 本片段]` 再試一次（前一片段需同一個 init）；仍失敗就用前一片段已有的縮圖。
- R-9 預覽端：先查 `thumbnailFor(n)`，有就直接顯示，不必等 200ms；沒有才走現有的按需擷取。按需擷取順序維持中央 → 兩側。
- 預覽時第一次進入（短按）中央卡立即嘗試讀快取。

## 第五輪修正（#56，時移模式畫面偶爾卡住）

證據（模擬器 logcat 2026-11-13 01:55 台灣時間）：ExoPlayer 開播後約 4 秒（17:55:20 UTC）解碼器重設 surface，之後不再輸出畫格，沒有錯誤；同時 pid 597 的 MPEG4Extractor（縮圖擷取）連續解碼。時移模式看門狗只看 hasError。

- R-10 時移停住偵測（`_watchdogTick`）：時移模式、未暫停、不在預覽、未在初始化時，若播放器位置（`_tsPosition`，原生未夾限）連續 8 秒未前進，且 `ts.bufferedDuration - liveEdgeOffset` 比目前位置多 3 秒以上（代表有新資料可播）：
  - 第一次：`_tsSeekToAbs(ts.liveAbsolute)` 跳到最新位置並 `play()`，記下時間。
  - 30 秒內再次停住：`_toastPlayerOutage()` 後 `_initializePlayer(lineIndex: _currentLineIndex, auto: true)` 重建。
  - 位置有前進就重置計數。
- R-11 背景縮圖節流（`LiveTimeshiftSession`）：新增 `bool thumbnailsEnabled`（預設 false）。直播頁在播放器穩定播放（位置前進）累計 10 秒後設為 true；播放器 `isBuffering` 或停住偵測觸發時設為 false，恢復播放 10 秒後再開。關閉期間新片段仍入佇列（只保留最新 3 個），只是不處理。
