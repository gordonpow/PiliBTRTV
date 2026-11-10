# 播放效能：自動降畫質、32 位元略過 BTR、詳細效能記錄

延續 [spec.md](spec.md)。背景：Sony BRAVIA VH22（Android 12、32 位元 armeabi-v7a）播 4K 很卡，改 HEVC 仍卡；官方 App 同一台播 4K HDR 順。原因未定，先做可減輕的兩項，並把效能記錄做到足以判斷原因。

## 需求（AC）

- AC-1 自動降畫質：播放中以 10 秒為一個區間，計算掉幀率 = 區間掉幀 ÷（串流 fps × 區間秒數）。連續 2 個區間 > 15%，且還有更低的畫質可選時，自動切到下一級（優先保留幀率：120→116→112→80→64…，依該影片實際可用畫質清單），顯示提示「播放不順，已自動降為 <畫質名稱>」。每部影片（每個 cid）最多自動降 2 次；使用者手動選畫質後，該部影片不再自動降。
- AC-2 設定：播放設定新增開關「卡頓時自動降畫質」，預設開。
- AC-3 32 位元略過 BTR：行程 ABI 為 32 位元（`dart:ffi` 的 `Abi.current()` 為 `androidArm` 或 `androidIA32`）且選定串流為 4K（高 ≥ 2160 或 qn ≥ 120）時，不經 BTR 代理，播放器直接連原始網址（保留既有備援網址邏輯）。log 記錄「32 位元裝置 4K 略過 BTR」。
- AC-4 詳細效能記錄，獨立緩衝區，錯誤報告新增一節「== 播放效能 ==」（最近 200 行，不被一般 log 擠掉）。內容：
  - 播放開始（每次建立主播放器）：ABI、CPU 核心數、裝置記憶體等級（`ActivityManager.memoryClass`、`isLowRamDevice`）、螢幕目前模式（解析度、更新率）與支援的模式清單、HDR 支援、畫面模式（原生／相容）、BTR 是否使用、彈幕是否開啟、選定串流（qn、編碼字串、解析度、fps、位元率）、使用的解碼器名稱與是否硬體。
  - 每 10 秒（播放中，不論有無變化都記）：位置秒數、掉幀（區間／累計）、掉幀率、平均影格處理延遲（`onVideoFrameProcessingOffset` 的平均 µs；負數表示影格晚到）、已渲染影格數（`DecoderCounters.renderedOutputBufferCount`，用 `exoPlayer.getVideoDecoderCounters()` 在 snapshot 時讀，需在播放執行緒讀或用 `ensureUpdated()`）、緩衝秒數（buffered − position）、頻寬估計（`onBandwidthEstimate`）、App 行程 CPU 使用率（讀 `/proc/self/stat` 兩次取樣差 ÷ 時間 ÷ 核心數）。
  - 事件：開始緩衝／結束緩衝（含持續毫秒、累計次數）、解碼器初始化（名稱、耗時）、影片格式改變、自動降畫質（從哪級到哪級、觸發的兩個區間掉幀率）、BTR 略過、播放錯誤。
- AC-5 log 不得含網址、Cookie、token。

## 設計

- 原生統計：擴充 `packages/video_player_android/.../PlayerStats.java`：
  - 新增欄位：frameOffsetSumUs、frameOffsetCount、bandwidthBps、bufferingCount、bufferingStartMs、bufferingTotalMs、decoderInitMs、isHardware（依 decoderName 用 `MediaCodecList` 查 `isHardwareAccelerated`，API 29+）、lastEvent 佇列（最多 50 筆字串事件，snapshot 時取出並清空）。
  - `onVideoFrameProcessingOffset(eventTime, totalProcessingOffsetUs, frameCount)` 累加。
  - `onBandwidthEstimate`、`onPlaybackStateChanged`（BUFFERING 進出計時）、`onPlayerError`（只記錯誤代碼名稱 `error.getErrorCodeName()`，不記訊息中的網址）、`onVideoDecoderInitialized`（名稱與 initializationDurationMs）。
  - rendered frames：listener 持有 ExoPlayer 參考不方便；改在 `PlatformViewVideoPlayer`／`TextureVideoPlayer` 建立後把 player 以 WeakReference 註冊到 `PlayerStats.attach(player)`，snapshot 時若在主執行緒以外取 `player.getVideoDecoderCounters()` 可能不安全——改在 `onRenderedFirstFrame`／每次 `onDroppedVideoFrames` 與 `onVideoDisabled` 時更新；另外在 snapshot 時用 `new Handler(player.getApplicationLooper()).post` 不適合同步回傳。可接受做法：snapshot 由 MethodChannel 呼叫（主執行緒），ExoPlayer 的 application looper 即主執行緒，`getVideoDecoderCounters()` 可在主執行緒呼叫，呼叫 `counters.ensureUpdated()` 後讀取。
- App 原生（`MainActivity.kt` codec channel）：新增 `getDeviceInfo` → ABI 清單、`Build.SUPPORTED_ABIS`、`Runtime.availableProcessors()`、memoryClass、isLowRamDevice、Display 目前 mode（寬高、refreshRate）、supportedModes、HDR 能力；新增 `getProcessCpu` → 讀 `/proc/self/stat` 的 utime+stime（jiffies）與 `SystemClock.elapsedRealtime()`。
- Dart：
  - `lib/services/perf_log.dart`（新）：獨立環形緩衝 200 行，`PerfLog.add(String)` 同時 `debugPrint`（前綴 `📈 [Perf]`）。`error_report_service.dart` 新增「== 播放效能 ==」一節輸出 `PerfLog.lines`。
  - 既有 `_startPlayerStatsTimer`（`player_action_mixin.dart`）改為每 10 秒一定記錄（播放中），並做 AC-1 判斷。串流 fps 取自選定串流（`[Stream]` 那筆的 fps；需要把選定串流資訊存到播放狀態，例如 `PlayerStateMixin` 新欄位 `currentStreamFps`、`currentQn`、可用畫質清單）。
  - 自動降畫質：沿用播放器既有的切換畫質流程（找出使用者在畫質選單選擇時呼叫的方法，帶入目標 qn），並設旗標 `autoDowngradeCount`、`userPickedQuality`。
  - AC-3：在 `player_action_mixin.dart`（312、840、1849、2037 行）與 `playback_preparer.dart:203` 呼叫 `BtrProxy.wrap` 的條件加上「非 32 位元 4K」；抽成一個共用判斷函式避免五處重複。
  - 設定：`SettingsService` 新增 `autoDowngradeOnDrops`（預設 true）；`playback_settings.dart` 加開關。

## 不做

- 原生播放頁（第 4 項）。
- 彈幕優化（第 3 項）。

## 驗證

- `flutter analyze`、`flutter test`、`flutter build apk --release --split-per-abi`。
- 電視模擬器（4K60 會掉幀）播 BV1R1e4zKEh1：應在約 20 秒後自動降畫質並出現提示；錯誤報告「播放效能」一節有開始資訊、每 10 秒一行、事件。
