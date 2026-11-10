# 規格：AV1 4K60 隧道模式卡住

## 設計

### A：隧道模式 4K 高幀率優先 HEVC（AC-1～3）
- `lib/services/playback_perf.dart`：新增純函式
  `List<String> autoCodecOrder({required bool tunnelActive, required bool fallbackToAvc, required int height, required double fps})`
  - `fallbackToAvc` → `['avc']`
  - `tunnelActive && height >= 2160 && fps > 30` → `['hevc', 'av1', 'avc']`
  - 其餘 → `['av1', 'hevc', 'avc']`
- `lib/services/settings_service.dart`：新增 `static bool get tunnelWillBeActive => playerTunneling && !playerTextureView;`（只是設定推論，不保證裝置真的進隧道）。
- `lib/services/api/playback_api.dart` 約 263 行 auto 分支：`order` 改用 `autoCodecOrder(...)`。候選串流高度、幀率取 `candidateVideos` 中最大高度那條（同一畫質解析度相同；用 `CodecService.parseFps`）。
- 因為只依設定判斷，預載（Prefetch）取得的 playurl 與正式播放選到的編碼一致。

### B：解碼卡住偵測與換編碼（AC-4～8）
- `lib/services/playback_perf.dart`：新增純函式
  - `bool isDecoderStall({required bool wantsPlay, required bool isBuffering, required Duration bufferingFor, required double bufferedAheadSec})`：`wantsPlay && isBuffering && bufferingFor >= 8s && bufferedAheadSec >= 10`。常數 `kStallBufferingSeconds = 8`、`kStallBufferedAheadSeconds = 10`。
  - `VideoCodec? nextStallCodec(String currentCodec, Set<String> tried)`：current 為 av01 → hevc；hev → avc；avc → null；跳過已在 `tried` 的家族。
- `lib/screens/player/mixins/player_state_mixin.dart`：新增狀態
  - `DateTime? bufferingSince;`、`Timer? stallTimer;`、`final Set<String> stallTriedCodecs = {};`、`int? stallCid;`、`bool stallSwitching = false;`
- `lib/screens/player/mixins/player_action_mixin.dart`：
  - `_startPlayerStatsTimer()` 同時啟動 `stallTimer = Timer.periodic(2s, (_) => _stallTick(gen))`；`cancelPlayerListeners()` 一併取消 `stallTimer` 並清 `bufferingSince`。換 cid 時清空 `stallTriedCodecs`（比照 `perfCid` 作法）。
  - `_stallTick(gen)`：讀 `videoController.value`；`isBuffering` 時若 `bufferingSince == null` 設為現在，否則清為 null。已緩衝秒數算法同 `_perfTick` 的 bufSec。`isDecoderStall(...)` 成立、`!isLoading && !stallSwitching && !isFallingBackToAvc && !perfDowngrading` 時：
    - 家族 key：`currentCodec` 轉 av01／hev／avc，加入 `stallTriedCodecs`。
    - `next = nextStallCodec(...)`；null → PerfLog `解碼卡住偵測 已是 AVC，不再切換 ...`，並把 avc 加入 tried 避免重複記錄，結束。
    - 否則 PerfLog `事件 解碼卡住 <cur>-><next> 緩衝=<n>s 已緩衝=<m>s`，toast `播放卡住，改用 <H.265|H.264> 重新載入`，呼叫 `_reloadWithCodec(next, resume: lastPlaybackPosition)`。
  - 新增 `_reloadWithCodec(VideoCodec codec, {Duration? resume})`：由 `_fallbackToAvc` 抽出共用流程（dispose → getVideoPlayUrl(forceCodec: codec, qn: currentQuality) → MPD／BtrProxy → 建 controller（viewType 依設定）→ initialize → seek → `_setupPlayerListeners` → play → 設速度）。用 `stallSwitching` 防重入。**不呼叫** `setCodecFallbackAvc`。失敗時顯示錯誤訊息（同 `_fallbackToAvc` 的 catch）。
  - `_fallbackToAvc` 改為：設定 `setCodecFallbackAvc(true)`、toast 後呼叫共用流程（行為不變）。實作者可選擇抽出共用 private 函式，兩者都呼叫。

## 任務
- T-1（無相依）：`playback_perf.dart` 新增 `autoCodecOrder`、`isDecoderStall`、`nextStallCodec` 與常數；`test/playback_perf_test.dart` 加單元測試（AC-1/2/5/8 的邏輯）。
- T-2（相依 T-1）：`settings_service.dart` 的 `tunnelWillBeActive`；`playback_api.dart` auto 分支改用 `autoCodecOrder`。
- T-3（相依 T-1）：state／action mixin 的卡住偵測、`_reloadWithCodec`、`_fallbackToAvc` 改用共用流程。

## 驗證對應
| AC | 方式 |
|---|---|
| AC-1/2/3 | 單元測試 `autoCodecOrder`；讀 diff 確認手動編碼分支未動 |
| AC-4/5/8 | 單元測試 `isDecoderStall`、`nextStallCodec`；diff 審查計時器生命週期 |
| AC-6/7 | diff 審查 |
| 實機 | 待使用者（BRAVIA）測試 |

## 邊界與風險
- 使用者暫停中緩衝：`wantsPlay` 用 `value.isPlaying`（video_player 的 isPlaying 是播放意圖），暫停不觸發。
- seek 後緩衝：已緩衝 ≥ 10 秒仍緩衝 8 秒，同樣視為卡住，可接受。
- 重新載入期間 `isLoading` 為 true，計時器不會重複觸發；舊 gen 的 tick 用 `gen != perfGen` 作廢。
- 換編碼後畫質可能不同（該畫質沒有目標編碼時 API 會往下找），可接受。
- 回退：revert 本次 commit。

## 審查後修訂（覆蓋上文相衝突的部分）

### R-1：卡住判斷改用原生狀態（審查 #1）
Dart 的 `value.isPlaying` 在 ExoPlayer 緩衝時為 false（`ExoPlayerEventListener.java:91` 轉發 `onIsPlayingChanged`），不能當播放意圖。
- `packages/video_player_android/.../PlayerStats.java` `snapshot()`：`p != null` 時多放
  - `playWhenReady`（`p.getPlayWhenReady()`）
  - `playbackState`（`p.getPlaybackState()`，int；2 = STATE_BUFFERING）
  - `bufferedAheadMs`（`p.getTotalBufferedDuration()`）
  各自 try/catch，取不到放 null。
- `_stallTick` 呼叫 `CodecService.getPlayerStats(drain: false)`，**不得 drain**（否則會吃掉 `_perfTick` 要寫的事件）。
- `isDecoderStall({required bool playWhenReady, required int? playbackState, required Duration bufferingFor, required int? bufferedAheadMs})`：`playWhenReady && playbackState == 2 && bufferingFor >= 8s && bufferedAheadMs != null && bufferedAheadMs >= 10000`。
- `bufferingSince`：tick 看到 `playbackState == 2` 且為 null 時設為現在；不是 2 時清為 null。

### R-2：重新載入的競態（審查 #2）
- `_reloadWithCodec` 進入時記下 `startCid = cid` 與 `token = ++reloadGen`（state mixin 新增 `int reloadGen = 0`）。每個 await 之後檢查 `mounted && cid == startCid && reloadGen == token`，不符時 dispose 本次新建的 controller（若有）並 return。
- `stallSwitching` 在 `try/finally` 重置。
- `switchQuality` 開頭：`if (stallSwitching) return;`。
- `_fallbackToAvc` 行為維持不變（不強制套用 token，避免擴大範圍）；若抽共用函式，`_fallbackToAvc` 一樣受 token 保護也可以。

### R-3：A 的條件判斷（審查 #3）
- 在 auto 迴圈中逐條判斷：先算 `prefer = tunnelWillBeActive && candidateVideos.any(is4kHighFpsStream)`；`is4kHighFpsStream(v)` = 高 ≥ 2160 且（fps > 30 或 fps 解析不到＝0）。fps 解析不到視為高幀率（偏向 HEVC 無害）。
- `autoCodecOrder` 簽章改為 `autoCodecOrder({required bool fallbackToAvc, required bool preferHevc})`，單元測試覆蓋。
- `candidateVideos ??= videos` 只在 `videosByQuality` 為空時發生，不另外處理。

### R-4：換編碼後畫質變動（審查 #4）
reload 後若 `currentQuality` 和 reload 前不同，PerfLog 補記 `畫質 a->b`。

### R-5：狀態與已知限制（審查 #5、#8）
- 不新增 `stallCid`，用既有 `perfCid` 判斷換片：`_startPlayerStatsTimer` 中 `perfCid != cid` 分支同時清空 `stallTriedCodecs`。
- 已知限制：使用者之後手動或自動 `switchQuality`，auto 仍可能選回 AV1；再卡時 `nextStallCodec` 會跳過已試過的 AV1 直接往下。可接受。
- 預載 playurl 在使用者改設定之後可能與正式播放不一致，可接受。
- A 的條件要求原生視圖，暖機只在相容視圖接手，兩者互斥。

### R-6：可測試性（審查 #6）
- `formatStallLog({required String from, required String? to, required int bufferingSec, required double bufferedAheadSec})` 純函式，回傳 `事件 解碼卡住 av01->hev 緩衝=8s 已緩衝=12.3s`；`to == null` 回 `事件 解碼卡住 已是 AVC，不再切換 緩衝=…`。加單元測試。

## 審查紀錄
- Sonnet 規格審查 8 條：#1～#6、#8 採用（見 R-1～R-6）；#7（改用邊緣觸發代替 2 秒輪詢）不採用：改用原生狀態後需要輪詢讀取 `playbackState`，2 秒一次 MethodChannel 成本低。

## 實作偏差
- `_reloadWithCodec` 另寫一份，沒有從 `_fallbackToAvc` 抽共用流程：`_fallbackToAvc` 保持原狀（對外行為不變），避免擴大範圍。兩者流程相近，日後可合併。
- `nextStallCodec` 的 `tried` 存家族 key（av01／hev／avc，與 `VideoCodec.prefix` 一致）；新增 `is4kHighFps` 純函式與測試。
- `playback_perf.dart` 因回傳 `VideoCodec?` 而 import `settings_service.dart show VideoCodec`。
- 換編碼後畫質變動的 PerfLog 文字為 `事件 解碼卡住換編碼後畫質 a->b`。
- 已是 AVC 時記錄後將 `bufferingSince` 重設為現在，避免每 2 秒重複寫 log。
