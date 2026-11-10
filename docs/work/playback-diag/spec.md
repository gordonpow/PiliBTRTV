# 播放診斷記錄（精簡版工作流）

## 需求

起因：Sony BRAVIA 4K VH22（32 位元，報告 EHVM3R）與 SPPL4K 回報 4K 播放 FPS 很低，但錯誤報告看不出實際選了什麼串流、播放器是否掉幀。

- AC-1：每次選定影片串流後，log 一行：`🎬 [Stream] qn=.. codec=.. 1920x1080 @60.0fps bw=..kbps hw=true|false`。
- AC-2：播放中每 10 秒 log 一行：`🎬 [Stats] decoder=<名稱> 輸入=<寬>x<高>@<fps> 掉幀=<這段期間> 累計=<總數> 渲染=<已渲染幀數>`；只在有變化或掉幀 > 0 時記錄，暫停時不記錄。
- AC-3：錯誤報告「設定摘要」多一行 `畫面模式: platformView|textureView`。
- 不做：自動降畫質、自動關閉多執行緒（等診斷結果再決定）。

## 設計

不改 Pigeon 介面（重新產生成本高）。插件與 App 在同一個程序，App 直接讀插件的靜態統計：

1. `packages/video_player_android/android/src/main/java/io/flutter/plugins/videoplayer/PlayerStats.java`（新增，public final class）：
   - 靜態欄位：`decoderName`、`inputWidth`、`inputHeight`、`inputFps`、`droppedTotal`、`renderedTotal`（以 `synchronized` 或 `volatile` 保護）。
   - `static AnalyticsListener listener()` 回傳一個 `AnalyticsListener`：
     - `onVideoDecoderInitialized(eventTime, decoderName, ...)` → 記 decoderName，並把 droppedTotal 歸零。
     - `onVideoInputFormatChanged(eventTime, format, ...)` → 記 width、height、frameRate。
     - `onDroppedVideoFrames(eventTime, droppedFrames, elapsedMs)` → droppedTotal += droppedFrames。
     - `onVideoDisabled(eventTime, counters)`／`onVideoEnabled` 可用 counters.renderedOutputBufferCount 更新 renderedTotal（或在 snapshot 時無法取得就省略 rendered）。
   - `static Map<String, Object> snapshot()` 回傳目前值。
   - 只保留「最近建立的播放器」的統計（同時只有一個主播放器；預覽／預熱播放器也會寫入，可接受，log 以 decoder 名稱區分）。
2. `PlatformViewVideoPlayer.java` 與 `TextureVideoPlayer.java`：`builder.build()` 後 `exoPlayer.addAnalyticsListener(PlayerStats.listener())`。
3. `android/app/src/main/kotlin/com/bili/tv/bili_tv_app/MainActivity.kt`：既有 `com.bili.tv/codec` channel 加 `getPlayerStats` → `io.flutter.plugins.videoplayer.PlayerStats.snapshot()`。
4. `lib/services/codec_service.dart`：`static Future<Map<String, dynamic>?> getPlayerStats()`，例外回 null。
5. `lib/services/api/playback_api.dart`：選定 `selectedVideo` 後（約 291～296 行）log AC-1 那行（用既有的 `hwOk(selectedVideo)` 結果；bandwidth 欄位 `bandwidth`，換算 kbps）。
6. 播放器：在主播放器開始播放後啟動 10 秒 `Timer.periodic`，`dispose`／換集時取消；與上次 snapshot 比較算出這段期間掉幀，符合 AC-2 才 log。放在 `lib/screens/player/mixins/` 既有管理播放器生命週期的 mixin 內。
7. `lib/services/error_report_service.dart`：設定摘要加 `畫面模式` 一行（`SettingsService.playerTextureView`）。

log 不得含網址、Cookie。

## 修正：硬解判斷高估 4K60（2026-11-10）

- 實測（電視模擬器、借用的大會員帳號、BV1R1e4zKEh1）：自動升到 `qn=120 hev1 3840x2160 @59.937fps`，`[Stats]` 顯示每 10 秒掉 140～180 幀。
- 原因：`MainActivity.canHwDecode` 用 `areSizeAndRateSupported`，只看區塊速率上限（模擬器 HEVC `blocks-per-second` 上限 2073600 = 4K×64fps），但同一解碼器宣告 `performance-point-3840x2160 value="30"`，實際只保證 4K30。
- 修正：新增 `canSustain`，API 29+ 有 performance point 時須有一個 `covers(寬, 高, 幀率)`；否則用 `getAchievableFrameRatesFor` 上限 ≥ 幀率 90%；都沒有才退回 `areSizeAndRateSupported`。
- 結果：同影片改選 1920x1080，前 10 秒掉 7 幀（起播），之後 30 秒 0 掉幀。
- 實機（Sony BRAVIA VH22、SPPL4K）是否同因未驗證，需新版報告的 `[Stream]`／`[Stats]` 確認。
- **已撤回（同日）**：使用者指出同一台 Sony 用官方 App 播 4K（含 HDR）很順，硬體做得到；performance point 常被廠商低報，這個判斷可能讓 Sony 被誤降到 1080p。模擬器的掉幀是模擬器解碼器（goldfish）本身的瓶頸，不能代表實機。改為先發布診斷記錄收集實機資料。
