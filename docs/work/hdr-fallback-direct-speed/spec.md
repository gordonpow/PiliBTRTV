# 需求與規格：HDR 解碼失敗回退、直連顯示網速

## 背景
模擬器（hdr=false）手動選 qn=125 真彩 HDR（`hvc1.2.4`，HEVC Main10 PQ）：
- ExoPlayer `format_supported=NO_EXCEEDS_CAPABILITIES` → `_fallbackToAvc` → `setCodecFallbackAvc(true)`，之後所有影片永久只用 H.264。
- 改播 qn=120 AVC，但標籤仍顯示「真彩 HDR (H.264)」、PerfLog 寫 qn=125。
- 「CDN 狀態」在直連時只顯示「未使用 BTR（直連）」，沒有網速。

## 驗收條件
- AC-1：解碼失敗的串流是 HDR／10-bit（qn 125 或 126，或 codecs 為 `hvc1.2`／`hev1.2` 開頭，或 AV1 codecs 第 4 段位元深度為 `10`/`12`，如 `av01.0.13M.10`）時，**不**呼叫 `setCodecFallbackAvc(true)`，改以同編碼設定（forceCodec 不指定）重新載入「可用畫質中，比目前低且不是 125／126 的最高畫質」，位置不變，toast `此裝置無法播放 HDR，已改用較低畫質`，PerfLog 記 `事件 HDR 解碼失敗 125->120`。找不到更低畫質時沿用原本 `_fallbackToAvc` 行為。
- AC-2：非 HDR 串流的解碼失敗，維持原本永久改用 AVC 的行為。
- AC-3：AC-1 適用三個入口：播放中錯誤（`_onPlayerStateChange` → `_fallbackToAvc` 前判斷）、首次初始化失敗（`player_action_mixin.dart` 約 371 行 codecLoop）、`PlaybackPreparer.prepare` 非暖機初始化失敗（約 252 行）。實作者可視情況：初始化入口改成「不寫永久設定、以較低非 HDR 畫質重試」；若入口結構不便，至少確保 HDR 失敗不寫永久設定。
- AC-4：DASH 回傳的 `currentQuality` 改為實際選到的串流 `selectedVideo['id']`（`playback_api.dart` 約 384 行），讓畫質標籤、PerfLog 與實際一致。非 DASH 路徑（約 420 行）不動。
- AC-5：螢幕不支援 HDR（`CodecService.isHdrDisplay()` 為 false）時，`playback_api.dart` 回傳的 `qualities` 移除 qn 125、126，手動畫質選單不再列出。
- AC-6：「CDN 狀態」在沒有 BTR 資料（直連，含 32 位元 4K 略過 BTR）時，顯示
  - `直連速度 X MB/s`（最近 3 秒平均）
  - `估計頻寬 Y Mbps`（ExoPlayer bandwidth estimate）
  - 下方一行灰字 `未使用 BTR（直連）`
  無資料時顯示 `直連，等待資料…`。
- AC-7：`flutter analyze` 無問題、`flutter test` 通過、原生 Java 可編譯。

## 設計
- `lib/services/playback_perf.dart`：純函式 `bool isHdrStream({required int qn, required String codecs})`、`int? nonHdrFallbackQn(Iterable<int> available, int current)`；加單元測試。
- `player_action_mixin.dart`：`_fallbackToAvc` 呼叫前（或其開頭）判斷目前串流（`currentQuality`、`currentStream?['codecs']`）；HDR → 新函式 `_fallbackFromHdr(resume)`：用既有 `switchQuality(target, auto: true)` 或 `_reloadWithCodec` 類似流程重新載入目標畫質（不寫永久設定），防重入。
- `PlayerStats.java`：新增 `static long bytesLoadedTotal`，`onBandwidthEstimate` 累加 `totalBytesLoaded`；attach 新播放器時歸零；`snapshot()` 放入 `bytesLoadedTotal`。
- `cdn_status_view.dart`：`_hasData == false` 時每秒 `CodecService.getPlayerStats(drain: false)`，以 `bytesLoadedTotal` 差值算速度（負值或首次略過），保留最近 3 個樣本平均；`bandwidthBps` 顯示估計頻寬。**不得 drain**。

## 不做
- 不檢查解碼器 Main10／HDR profile（只用螢幕 HDR 判斷隱藏選項）。
- 不改 settings_panel 的「BTR／直連」標籤。

## 審查
使用者要求一起修；規格審查併入發布前的 diff 審查（與 av1-tunnel-stall 一起）。

## 實作偏差
- `_reloadWithCodec` 參數改為 `VideoCodec? codec, {int? qn, Duration? resume}`；HDR 退路直接重用它（codec 傳 null、qn 傳目標），不走 `switchQuality`，避免 `stallSwitching` 互卡且能保留續播位置。
- HDR 判斷放在 `_fallbackToAvc` 開頭，所以「播放中錯誤」與 `switchQuality`／`_fallbackToAvc` 其他呼叫處都涵蓋；以 `isFallingBackToAvc` 防重入。
- 初始化入口（mixin codecLoop、`PlaybackPreparer.prepare`）：不寫永久設定，將 qn 改為較低非 HDR 畫質後 `continue codecLoop`（下一輪為 AVC 等後續編碼，而非同編碼重試），因 for-in 結構不便重跑同一輪。`prepare` 新增選用 callback `onHdrFallback` 供呼叫端 toast。
- `playback_api.dart` 的 `currentQuality` 用 `selectedVideo['id'] ?? data['quality'] ?? qn`。
- CDN 狀態：無 BTR 資料時一律顯示直連速度與估計頻寬（涵蓋 32 位元 4K 略過 BTR）；直連也無資料時，BTR 開啟顯示「BTR 已開啟，等待資料…」，否則「直連，等待資料…」。
- `cdn_status_view.dart` 原有單行 `if` 補上大括號以通過 analyze。
