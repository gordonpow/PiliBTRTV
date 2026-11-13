# 規格：點影片秒開與播放掉幀

## T-1 秒開（#58，AC-1～AC-4）

檔案：`lib/screens/player/player_screen.dart`、`lib/screens/player/mixins/player_action_mixin.dart`（`_initializeUgc`、`_adoptPlayback`，約 528～730 行）、`lib/services/card_preview_service.dart`、`lib/services/prefetch_service.dart`、`lib/services/playback_preparer.dart`、推 PlayerScreen 的各處。

1. 接手條件：新增 `CardPreviewService`（或 PlayerScreen）判斷 `canAdoptWarm(PreparedPlayback p)`：相容模式一律 true；原生模式在 `p.playInfo['currentQuality']` 為 ≥120、125、126，或 `p.controller.value.size` 高 > 寬（直式）時 false。`initState` 不再以 `playerTextureView` 決定是否 take；take 之後不可接手就把它的 videoInfo／playInfo 留給冷啟動用，並 dispose 其 controller。`_initializeUgc` 等待暖機（`isPendingFor` → `waitAndTake`）也不再限相容模式，等到後同樣檢查。
2. 冷啟動沿用資料：不可接手或沒有暖機時，`PlaybackPreparer.prepare` 優先使用：暖機留下的 videoInfo／playInfo（同 cid、同 qn 才用）、`PrefetchService.peekVideoInfo`、預載 playurl。暖機取用預載 playurl 時改為不消耗（peek），或在暖機結果中保留 playInfo 給播放頁。
3. 並行：`prepare` 中 `getPlayerProgress` 與以 `info.cid` 發出的 playurl 同時進行；最後選定的 cid 與 info.cid 相同就用該結果，不同再重抓。
4. 轉場：新增 `PlayerRoute`（PageRouteBuilder，淡入 120ms；`Anim` 低記憶體時為 0），所有 `MaterialPageRoute(builder: ... PlayerScreen(...))` 改用它。
5. 保留計時 log：`⏱ [E2E] open`（PlayerScreen.initState）、`PiliStartup firstFrame`（ExoPlayerEventListener）、`⏱ [Startup] shown`。

## T-2 掉幀（#59，AC-5～AC-7）

檔案：`lib/screens/player/mixins/player_action_mixin.dart`（`_onPlayerStateChange` 約 1800～1890 行、`syncDanmaku` 約 2489～2549 行）、`lib/screens/player/player_screen.dart`（build）、`lib/screens/player/widgets/` 的進度條與 `related_strip.dart`、`lib/widgets/conditional_marquee.dart`。

1. 位置更新：`_onPlayerStateChange` 不再無條件 `setState`。改為只在需要時重建：控制列顯示中、或狀態旗標（isPlaying、isBuffering、錯誤、完成）改變、或控制列隱藏時的迷你進度條每整秒一次。或改用 `ValueListenableBuilder`／`ValueNotifier<Duration>` 只重建進度元件。
2. 彈幕：`syncDanmaku` 改用毫秒位置（`value.position.inMilliseconds / 1000`），每次只加入「上次位置 < t ≤ 目前位置」的彈幕；跳轉時重設索引。
3. RelatedStrip：callback 改為穩定參照（方法 tear-off 或在 initState 建立），讓 `ListView.builder` 不因父層重建而重建卡片；或用 `RepaintBoundary` 隔開。
4. `DanmakuOption` 只在設定改變時建立，不在每次 build 新建。
5. 新增 `lib/utils/frame_monitor.dart`（已建立）：每 5 秒 log `⏱ [Jank]` 慢幀數與最慢 build／raster。

## 驗證

- `flutter analyze`、`flutter test`。
- TV 模擬器量測：冷／暖各兩次，記錄 open → shown／firstFrame。掉幀看 `⏱ [Jank]` 的 maxBuild（模擬器為軟體 GPU，raster 數值不具代表性）。

## 風險

- 原生模式接手 textureView：該次播放無法隧道播放；直式影片綠塊問題出現在部分裝置的 textureView？（原註解）——4K/HDR 例外已排除主要風險，綠塊需使用者實機觀察。
- 位置更新減少重建：要確認進度條、時間文字、SponsorBlock 外掛、播完判斷仍正常。
