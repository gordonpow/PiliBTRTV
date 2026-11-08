# 規格：搜尋鍵盤殘留、閃退回報、Netflix 式縮圖列

需求：`1-requirements.md`。調查：`research.md`（B 站雪碧圖最大 160x90，沒有更高解析度端點；pvdata 前兩個值都是 0，所以「索引減 1」是正確的）。

使用者決定（2026-11-08）：縮圖畫質用**混合式**：縮圖列用雪碧圖，停在某張約 0.4 秒後，中間那張換成從影片串流解出的真實畫面。

## A. 搜尋後系統鍵盤殘留

原因推測：在系統鍵盤按「搜尋」時，`onSubmitted` → `_submit()` → `SearchTab._onSearch` 直接把 `SearchKeyboardView` 換成 `SearchResultsView`。隱藏的 `TextField` 被 dispose，但沒有呼叫 `TextInput.hide`，Android TV 的 IME 視窗留在畫面上。Activity 是 `adjustResize`，進播放器時畫面被鍵盤擠壓，播放器的 surface 尺寸一直變動，容易當機。

T-1（`lib/screens/home/search/search_keyboard_view.dart`、`lib/screens/player/player_screen.dart`）：
- 新增 `_closeIme()`：`_textFocus.unfocus()`、`SystemChannels.textInput.invokeMethod('TextInput.hide')`、`SearchImeBackGuard.markClosed()`。
- `_submit()` 一開始呼叫 `_closeIme()`，再呼叫 `widget.onSearch`。
- `dispose()`：`_textFocus.hasFocus` 或 `_imeVisible` 時呼叫 `TextInput.hide`。
- 播放器 `initState`：呼叫 `SystemChannels.textInput.invokeMethod('TextInput.hide')` 並讓播放器的 `Scaffold`（若有）設 `resizeToAvoidBottomInset: false`，避免被鍵盤擠壓。
- 回到鍵盤頁時 `SearchKeyboardView` 會重新建立，`_imeVisible` 初始為 `false`；`_openIme()` 照舊可用（AC-A3）。

## B. 閃退後詢問是否上傳錯誤報告

T-2 原生（新檔 `android/app/src/main/kotlin/com/bili/tv/bili_tv_app/CrashChannel.kt`）：
- `object CrashChannel { fun register(engine: FlutterEngine, context: Context) }`，MethodChannel `com.bili.tv/crash`。
- `installHandler(context)`：`Thread.setDefaultUncaughtExceptionHandler`，把時間（epoch ms）與堆疊寫到 `filesDir/last_crash.txt`（第一行為時間），再交給原本的 handler。
- `getLastCrash` → `Map?`：
  - API 30 以上：`ActivityManager.getHistoricalProcessExitReasons(packageName, 0, 5)`，取第一筆 `reason` 為 `REASON_CRASH`、`REASON_CRASH_NATIVE`、`REASON_ANR` 且 `timestamp` 大於已確認時間的紀錄。回傳 `reason`（字串 `crash`／`native`／`anr`）、`timestamp`、`description`、`trace`（`traceInputStream` 前 150 行，可能為 null）。
  - 同時讀 `last_crash.txt`；時間大於已確認時間時附上 `stack`。API 30 以下只靠這個檔案。
  - 都沒有就回傳 null。
- `ackCrash(timestamp)`：把已確認時間存到 SharedPreferences（`crash_prefs`、key `acked_ts`），並刪除 `last_crash.txt`。
- `MainActivity`：`onCreate` 呼叫 `CrashChannel.installHandler(this)`；`configureFlutterEngine` 呼叫 `CrashChannel.register(...)`（由 Opus 加）。

T-3 Dart：
- 新檔 `lib/services/crash_report_service.dart`：`static Future<Map?> lastCrash()`、`static Future<void> ack(int ts)`、`static String format(Map crash)`（每行經 `sanitizeLogLine`，標題 `== 上次閃退 ==`，含原因、時間、description、stack／trace）。
- `ErrorReportService.buildReport({String? crashSection})`：有值時放在 `== App ==` 之前。
- `showErrorReportDialog(context, {String? crashSection})`：有 `crashSection` 時標題改為「上次 App 異常結束，是否上傳錯誤報告？」，說明多一行「・上次閃退的原因與堆疊」；預覽與上傳都帶 `crashSection`。預設焦點維持「取消」。
- `HomeScreen.initState` 的 post-frame callback：延遲 2 秒後呼叫 `CrashReportService.lastCrash()`，有結果且 `mounted` 時顯示對話框；對話框關閉後（不論結果）呼叫 `ack(timestamp)`（AC-B4）。

## C. Netflix 式縮圖列

### 幀索引與時間（`lib/models/videoshot.dart`）

pvdata 時間戳 `ts`：第 k 幀涵蓋 `[ts[k+1], ts[k+2])`。新增：
- `int get frameCount`：有時間戳時 `ts.length - 1`，否則 `images.length * framesPerImage`，再以影片長度限制（無時間戳時由呼叫端提供長度）。
- `int indexAt(Duration pos)`：等同現有 `getIndex`。
- `Duration timeOfIndex(int k, Duration total)`：有時間戳時 `ts[k+1]` 秒；否則 `total * k / frameCount`。
- `FrameInfo? frameAtIndex(int k)`：依索引計算雪碧圖位置（現有 `getFrameAt` 改為呼叫它）。

### 切換邏輯（`player_action_mixin.dart` `_performSeek`）

- 有 `videoshotData` 且 `frameCount > 1`：每次按鍵（含按住的 repeat）移動一幀：`k = indexAt(current) ± 1`，夾在 `[0, frameCount-1]`，`previewPosition = timeOfIndex(k)`（最後一幀之後不再前進；k=0 對應 0 秒）。
- 沒有縮圖資料：維持現有 10／30／60 秒加速。
- 1.5 秒自動確認、確認鍵、返回鍵取消不變（AC-C5）。

### 真實畫面來源

T-4 原生（新檔 `FrameChannel.kt`）：MethodChannel `com.bili.tv/frame`。
- `getFrame(url, timeMs, width)` → JPEG `ByteArray`（品質 85）或 null。用單一背景執行緒（`Executors.newSingleThreadExecutor`）；同一個 `url` 重用 `MediaMetadataRetriever`（`setDataSource(url, headers)`，headers：`Referer: https://www.bilibili.com/`、`User-Agent` 同 App）；`url` 改變時 release 舊的。API 27 以上用 `getScaledFrameAtTime(us, OPTION_CLOSEST_SYNC, width, width*9/16)`，否則 `getFrameAtTime` 再 `Bitmap.createScaledBitmap`。任何例外回傳 null 並 `Log.w`。結果用 `Handler(Looper.getMainLooper())` 回傳。
- `release`：釋放 retriever。
- `MainActivity.configureFlutterEngine` 註冊（Opus 加）。

T-5 Dart：
- `playback_api.dart` DASH 分支回傳多一個 `'previewUrl'`：從 `dash['video']` 選 `codecs` 以 `avc` 開頭、`id` 最小但 ≥ 32 的串流（沒有就最小 id 的 avc，再沒有就 `videoUrl`）。durl 分支 `'previewUrl'` 為 `videoUrl`。
- `player_state_mixin.dart` 新增 `String? previewFrameUrl;`，在 `initializePlayer`、`switchEpisode`、`switchQuality` 取得 playInfo 處設定。播放器 dispose 時呼叫 `FrameService.release()`。
- 新檔 `lib/services/frame_service.dart`：`static Future<Uint8List?> getFrame(String url, Duration t, {int width = 480})`，LRU 快取 30 張（key：url + 秒），同時只保留最新一個等待中的請求（較舊的結果回來後若已不是最新，只存快取不通知）。
- 新檔 `lib/screens/player/widgets/seek_thumbnail_strip.dart`（取代 `_buildNetflixSeekOverlay` 的內容，`SeekPreviewThumbnail` 可刪除或保留不用）：
  - 版面（參考使用者照片）：畫面下方約 45% 高度起，一列縮圖垂直置中於畫面 60% 處；中間卡片寬 = 螢幕寬 × 0.24、16:9、白色 3px 外框、圓角 8；兩側卡片寬 = 螢幕寬 × 0.2、無外框、略暗（不透明度 0.85）；間距 16；左右各顯示到超出畫面為止（各 3 張），超出部分被裁切。
  - 下方進度條：左邊預覽時間、右邊總長，軌道白色 30%、已播放部分粉色 `#fb7299`，水平留白 80。
  - 背景：由下往上的黑色漸層（覆蓋縮圖列與進度條區域）。
  - 每張縮圖用 `frameAtIndex` 從雪碧圖裁切，`FilterQuality.medium`；中間卡片在 `previewPosition` 停止變動 400ms 後呼叫 `FrameService.getFrame(previewFrameUrl, timeOfIndex(k))`，取得後以 `Image.memory`（`gaplessPlayback: true`）蓋在雪碧圖上；位置改變時先回到雪碧圖。
  - 切換時縮圖列以 `AnimatedSlide`／`TweenAnimationBuilder` 150ms 平移（可選，不影響 AC）。
  - 沒有縮圖資料：只顯示進度條與時間（AC-C6）。
- `videoshot_api.dart` 預載雪碧圖照舊；pvdata 尚未載入時 `frameCount` 用無時間戳的計算方式。

## AC 驗證方式

| AC | 驗證 |
|---|---|
| A1–A4 | 使用者實機測試；程式碼審查確認 `_submit` 先關 IME |
| B1–B4 | 使用者測試（可用 `adb shell am crash com.gordonpow.pilibtrtv` 模擬 crash）；審查 |
| C1–C6 | 使用者實機測試；`flutter analyze`；`test/videoshot_index_test.dart` 測 `indexAt`／`timeOfIndex`／`frameAtIndex` |

## 風險與回退

- `MediaMetadataRetriever` 對 HTTP 上的 fragmented MP4（DASH m4s）在某些裝置可能很慢或失敗：失敗時保留雪碧圖，不影響播放。
- 預覽用的請求會和播放搶頻寬；只在停 400ms 後抓一張，且選 480P AVC。
- 原生崩潰在 API 30 以下偵測不到（需求已列為限制）。
- 回退：各部分獨立，可分別 revert。

## 任務與分派

- T-1：搜尋 IME（agy 實作）
- T-2 + T-3：閃退回報（agy 實作）
- T-4 + T-5：縮圖列（agy 實作）
- MainActivity 註冊兩個 channel：Opus
- 三組改的檔案不重疊（`player_screen.dart` 的 IME 一行由 T-1 改在 `initState`，T-5 改 `_buildNetflixSeekOverlay`），可平行。

## 審查紀錄

agy（gemini-3.8-flash-high）審查，`spec-review.md`，5 條全部採用：

1. 邊界：`frameAtIndex(k)` 在 `k < 0` 或 `k >= frameCount` 回傳 null（縮圖列該位置不畫）；`timeOfIndex` 先把 k 夾在合法範圍，`frameCount` 或影片長度為 0 時回傳 `Duration.zero`。
2. 閃退誤報：沒有 `acked_ts` 時（首次安裝、清資料），先寫入目前時間，不詢問。`last_crash.txt` 與 `ApplicationExitInfo` 時間相差 5 秒內視為同一次，合併成一筆。`traceInputStream` 用 `.use {}` 讀取。
3. 抽幀阻塞：`release` 也排進同一個背景 executor 執行；Dart 端 `FrameService.getFrame` 加 3 秒 timeout（逾時回傳 null，結果晚到只存快取）。
4. 點搜尋建議（`_selectSuggestion`）也先呼叫 `_closeIme()`；`dispose()` 無條件呼叫 `TextInput.hide`。
5. 解碼失敗改用 AVC 的流程（`_fallbackToAvc`）取得 playInfo 時也更新 `previewFrameUrl`。
