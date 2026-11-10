# 4K60 卡頓：記住裝置＋隧道播放實驗（需求與規格）

使用者請求（2026-11-10）：做「第 1 步：記住這台電視」和「第 2 步：隧道播放實驗開關＋診斷資料」。使用者回報，官方 App 播放同一部 4K60 影片很順。

## 背景

- 報告：2K4EBR、GCBB9P、BVESCZ、HXUSJ7。裝置是 Sony BRAVIA VH22，Android 12，32 位元，使用 MTK 解碼器。
- 4K60 的 AV1 和 HEVC 都掉幀 86–91%，「原生」和「相容」兩種模式都一樣。1080p60 掉幀 0%。CPU 只用 11–16%，緩衝充足。
- 推測：在非隧道路徑上，4K60 的輸出跟不上。

## 驗收條件

- AC-1：同一台裝置上，4K 高幀率影片（qn ≥ 120，fps > 30）一旦觸發「自動降畫質」，就把這件事記下來（SharedPreferences）。之後播放 4K 高幀率影片時，直接從 116（1080P60）開始，並且：
  - 效能紀錄寫一行「已知此裝置 4K60 不順，改從 1080P60 開始」。
  - 顯示一次提示「此裝置播放 4K 60 幀不順，已改用 1080P 60 幀」。
- AC-2：4K 30 幀以下的影片不受 AC-1 影響。使用者在播放中手動選 4K 時，照使用者的選擇播放，不再強制降級，也不清除記錄。
- AC-3：「設定 → 播放設定」新增：
  - 「隧道播放（實驗）」開關。預設關閉。副標題：「4K 60 幀不順時可試試，只在『原生』畫面模式有效；黑畫面或沒聲音請關閉」。
  - 「重設 4K 60 幀偵測」動作。按下後清除 AC-1 的記錄，並顯示提示。
- AC-4：隧道播放開啟，而且畫面模式是「原生」時，播放器的 `DefaultTrackSelector` 設定 `setTunnelingEnabled(true)`。開啟之後，播放器實際有沒有進入隧道模式，要寫進效能紀錄。
- AC-5：效能紀錄的「播放開始」，以及錯誤報告的設定摘要，新增以下資料：
  - `隧道=開/關`（設定值）
  - 實際是否在隧道模式（可以取得時才寫）
  - 目前影片解碼器的 `FEATURE_TunneledPlayback` 支援情況
  - `getAchievableFrameRatesFor(3840,2160)` 的結果，沒有資料時寫 `null`
  - API 29 以上時，`PerformancePoint` 是否涵蓋 3840x2160@60
- AC-6：隧道播放開啟時，播放、暫停、快轉、換畫質、換片都不會閃退。拿不到掉幀統計時，效能紀錄寫「隧道模式，掉幀統計可能不準」。
- AC-7：設定說明與提示只用繁體中文。

不做：

- 繞過 Flutter，把原生 SurfaceView 放在 Flutter 畫面後面（第 3 步）。
- 修改「自動」編碼的選擇順序。

## 設計

1. **AC-1、AC-2：記住這台裝置**
   - `SettingsService` 新增 `bool known4k60Bad`（key `known_4k60_bad`），附 getter、setter、清除方法。
   - 觸發「自動降畫質」時（player_action_mixin.dart:1076-1095 附近），如果降級前的畫質是 120 以上，而且 fps 大於 30，就設為 true。
   - 選畫質時套用：
     - 位置：首次選畫質的地方，也就是 SmartQuality 升級，或 `play_params.dart`／`playback_api.dart` 決定 qn 的地方。實作時找到「升級到 120」的位置。
     - 規則：`known4k60Bad` 為 true，而且候選畫質是 4K 高幀率時，把上限限制在 116。只有自動選畫質會套用；使用者手動選 4K 不套用。
2. **AC-3、AC-4：隧道播放開關**
   - `SettingsService` 新增 `bool playerTunneling`（key `player_tunneling`）。
   - 原生端 `PlatformViewVideoPlayer.java:59-62` 建立 `DefaultTrackSelector` 之後：
     - 讀 `context.getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).getBoolean("flutter.player_tunneling", false)`，key 的前綴以 shared_preferences 套件的實際格式為準。
     - 值為 true 時，設定 `trackSelector.setParameters(trackSelector.buildUponParameters().setTunnelingEnabled(true))`。
   - `TextureVideoPlayer` 不改，因為隧道播放需要 SurfaceView。
3. **AC-5：診斷資料**
   - `MainActivity.kt` 的 CODEC_CHANNEL 新增方法 `decoderCaps(codec, w, h, fps)`，回傳以下欄位：
     - `name`
     - `tunnel`（`isFeatureSupported(FEATURE_TunneledPlayback)`）
     - `achievable`（`getAchievableFrameRatesFor` 的 lower/upper，或 null）
     - `perfPointOk`（API 29 以上，`supportedPerformancePoints` 有沒有涵蓋；否則 null）
   - `PlayerStats` 或 player 端，在播放開始時加入這些欄位，寫進效能紀錄。
   - 實際是否在隧道模式：可以用 `ExoPlayer` 的 `isTunnelingEnabled()`（media3 1.x 的 `ExoPlayer` 有提供，實作時確認）。
   - 錯誤報告的設定摘要（`error_report_service.dart`）加一行「隧道播放：開/關」，以及「4K60 已知不順：是/否」。

## 驗證

- `flutter analyze`、`flutter test` 全部通過。
- 單元測試：AC-1 的判斷函式寫成純函式（輸入 qn、fps、旗標、是否手動，輸出上限 qn），並測試。
- 模擬器：
  - 開啟隧道播放後，播放 1080p 影片不閃退。模擬器的解碼器多半不支援隧道播放，所以只確認會降回一般模式。
  - 效能紀錄有新欄位。
- 實機：交給使用者在 Sony 電視上測。

## 審查紀錄

- 範圍小，而且大多是新增程式，所以省略規格審查，改在實作完成後做 diff 審查（2026-11-10）。

## 實作偏差

- AC-1 選畫質套用點：fps 要等請求回來才知道，所以在 `PlayParams.resolvePlayInfo` 的 SmartQuality 升級成功後檢查；若升級結果是 4K 高幀率而且 `known4k60Bad` 為 true，再多請求一次 116（1080P60），並在 playInfo 加 `known4k60Capped: true`。播放器看到這個旗標才寫效能紀錄與顯示提示。只有 VIP 的智慧升級路徑會觸發；使用者手動選畫質（switchQuality）不經過此處。
- AC-1 判斷寫成純函式 `autoQnCap` 與 `is4kHighFps`（lib/services/playback_perf.dart），測試在 test/playback_perf_test.dart。
- 原生端 `PlayerStats.snapshot` 新增 `tunnelingActive`（`ExoPlayer.isTunnelingEnabled()`，media3 1.8.0 確認存在），取不到時為 null，效能紀錄寫「未知」。
- 播放開始新增兩行效能紀錄：「隧道播放 設定=… 實際=…」與「解碼器能力 …」，不併入原本「播放開始」那一行（只加 `隧道=開/關`）。
- 掉幀統計不準的提示，條件是實際為隧道模式；沒有另外偵測「拿不到統計」的情況。
- shared_preferences 2.5.4（android 2.4.18）舊式 API：檔名 `FlutterSharedPreferences`，key 前綴 `flutter.`。
