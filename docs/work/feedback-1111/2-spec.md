# 規格：#27–#30

需求：[1-requirements.md](1-requirements.md)

## T-1 續播進度（#30）

### 根因（已在模擬器確認）
`x/web-interface/view` 不回傳 `history` 欄位。已登入的模擬器 log 一律是 `🎬 [Resume] No API history available`，接著 `Using LOCAL CACHE: ... progress=250` → `Video was completed (progress 250 >= duration 250 - 5), starting from beginning`。也就是說續播永遠用電視本地快取（`PlaybackProgressCache`，沒有時間戳），手機的進度只在本地沒有快取時才會被用到（列表 `video.progress`，`lib/services/playback_preparer.dart:341`）。

### 設計
- `lib/services/api/playback_api.dart`：新增 `static Future<({int cid, int seconds})?> getPlayerProgress({required String bvid, int? aid, required int cid})`。
  - 呼叫 `https://api.bilibili.com/x/player/wbi/v2`，WBI 簽名與 header 照 `lib/services/api/subtitle_api.dart:83-118` 的寫法（`BaseApi.ensureWbiKeys`、`SignUtils.signWithWbi`、`BaseApi.getHeaders(withCookie: true)`），逾時 5 秒。
  - 未登入（沒有 cookie／`AuthService` 判斷未登入）直接回 null，不發請求。
  - 解析 `data.last_play_time`（**毫秒**）與 `data.last_play_cid`。`code != 0` 或欄位不存在回 null。回傳秒數 = `last_play_time ~/ 1000`（可能為 0）。
  - 為了可測試，解析抽成 `static ({int cid, int seconds})? parsePlayerProgress(Map json)`。
- `lib/services/playback_progress_cache.dart`：新增儲存時間 key `playback_saved_v3_<bvid>`（epoch 秒），`saveProgress` 一起寫；`getCachedRecord` 回傳 `({int cid, int progress, int savedAt})`（舊資料沒有時間 → 0）。`clearProgress` 一起刪。更新所有呼叫端。
- `lib/services/playback_preparer.dart`：
  - 取得 `videoInfo` 後、決定 cid **之前**，呼叫 `getPlayerProgress`（用 `videoInfo['aid']` 與 `videoInfo['cid']` 當請求參數，逾時 3 秒），await 結果。只在已登入時發請求，未登入不增加延遲。
  - cid 優先序改為：呼叫端明確指定的 cid > 伺服器 `last_play_cid`（必須在 `videoInfo['pages']` 中） > 本地快取 cid > `videoInfo['cid']` > 第一個分 P。避免本地快取先鎖定舊分 P（審查 #1）。
  - 續播來源優先序改為：
    1. 伺服器進度（請求成功且 `last_play_cid` 等於最後採用的 cid 即採用，包含 0 秒）。
    2. 本地快取與列表進度比新舊：本地 `savedAt` 與列表 `video.viewAt` 比較，取較新的那一筆；只有其中一個 > 0 時用那一個。列表 progress `-1` 視為已看完 → 0。
  - log：`🎬 [Resume] source=server|cache|list|none progress=...`。
  - 「接近片尾視為看完」的判斷（`>= duration - 5`）保留。
- 舊流程 `lib/screens/player/mixins/player_action_mixin.dart:435-504`：確認它是否只處理 PGC／特殊情況。若也處理 UGC，套用同樣的優先序（可抽共用函式 `ResumeResolver`）；若只處理 PGC，不改。
- 測試：`test/resume_progress_test.dart`：`parsePlayerProgress`（毫秒轉秒、code 非 0、缺欄位）與優先序函式（純函式，輸入伺服器結果、快取、列表 → 輸出秒數與來源）。

## T-2 記憶體分級（#27）

### 設計
- `android/app/src/main/kotlin/com/bili/tv/bili_tv_app/MainActivity.kt`：codec channel 新增 method `getMemoryState`，回傳 `availMemMb`、`thresholdMb`、`lowMemory`（`ActivityManager.MemoryInfo`）。不改 update channel 的 `getDeviceInfo`。
- `lib/services/device_profile.dart`：
  - `enum MemoryTier { critical, low, mid, high }`。
  - 靜態分級 `staticTier`：`isLowRam` 或 total ≤ 2304 → low；≤ 4096 → mid；其他 high；查詢失敗 → mid。保留既有 `lowMemory` getter（= staticTier 為 low），NavSettle 等既有呼叫端不改。
  - `currentTier`：critical 或 staticTier。`ValueNotifier<MemoryTier> tierNotifier` 給其他服務監聽。
  - `startMonitor()`：每 15 秒呼叫 `getMemoryState`。進入 critical 條件：`lowMemory == true`，或 `availMemMb < max(thresholdMb * 1.5, 300)`。離開條件：連續兩次查詢都不符合。`onMemoryPressure()`（由 `main.dart` 的 `didHaveMemoryPressure` 呼叫）立即進入 critical 並重置離開計數。切換時 log `🧠 [Memory] tier=... avail=...MB reason=...`。App 進入背景時停止計時器、回前景恢復：`main.dart` 既有的 `_MemoryPressureObserver` 只處理記憶體壓力，要補 `didChangeAppLifecycleState`（審查 #4）。
  - 可測試的純函式：`static MemoryTier tierFor({required int totalMemMb, required bool isLowRam})`、`static bool isCritical({required int availMb, required int thresholdMb, required bool lowMemory})`，以及離開 critical 的計數邏輯（可注入查詢結果）。
- 預算表（集中定義在 `DeviceProfile` 或新檔 `lib/services/memory_budget.dart`）：

  | tier | 圖片快取張數 / MB | 鄰近預解析 `_bgMax` | prefetch `_cacheMax` | 暖機播放器 | 鄰近預解析 |
  |---|---|---|---|---|---|
  | high | 500 / 200 | 4 | 30 | 開 | 開 |
  | mid | 300 / 120 | 3 | 20 | 開 | 開 |
  | low | 150 / 64 | 2 | 10 | 開 | 開 |
  | critical | 80 / 32 | 0 | 5 | 關 | 關 |

- 套用：
  - `lib/main.dart`：圖片快取改依 tier 設定，tier 改變時更新 `PaintingBinding.instance.imageCache.maximumSize/maximumSizeBytes`；啟動 `DeviceProfile.startMonitor()`；`didHaveMemoryPressure` 呼叫 `DeviceProfile.onMemoryPressure()`（既有的 stopAll／trim／清圖片快取保留）。
  - `lib/services/prefetch_service.dart`：`_bgMax`、`_cacheMax` 改讀預算；`_bgMax == 0`（critical）時 `preResolve` 直接略過（鄰近預解析在這裡，不在 CardPreviewService，審查 #3）；cache 超過新上限時淘汰最舊的。
  - `lib/services/card_preview_service.dart`：`willWarm` 在 critical 時回 false；進入 critical 時呼叫既有的 `stopAll` 類方法（不必再暫停 60 秒，已有的 `onMemoryPressure` 照舊）；
- 測試：`test/device_profile_test.dart` 補 tier 與 critical 判斷、離開計數。

## T-3 快轉（#28）與隱藏按鈕（#29）

### #28 設計（`lib/screens/player/mixins/player_action_mixin.dart`、`player_event_mixin.dart`、`focus/player_focus_handler.dart`）
- 區分短按與按住：`KeyDownEvent` = 短按一步；`KeyRepeatEvent` = 按住。`KeyUpEvent` 結束按住。
- 短按：預覽位置 ±10 秒（不論有無縮圖），不再用 `_calculateSeekStep` 的 30／60 秒加速（刪除或停用該函式與相關欄位，注意不要留下未使用欄位造成 analyze 警告）。縮圖條顯示最接近的一幀（`videoshotData.indexAt`）。
- 按住：記錄按住開始時間 `seekHoldStart` 與上次更新時間。每個 repeat 事件依經過時間 `dt`（上限 0.25 秒）推進：速度（秒/秒）前 1 秒 30、1～3 秒 90、3 秒後 `max(180, 片長秒數 / 20)`。位置夾在 0～片長。
- 放開後：既有 1.5 秒自動跳轉計時器從放開時開始（按住期間每個事件都重設計時器即可）。確定立即跳轉、返回取消，維持。
- 控制列隱藏時的入口（`player_event_mixin.dart:500-508`）與預覽模式中的入口（`handleSeekPreviewNavigation`）都要傳入「是否為 repeat」。KeyUp 事件要能到達處理函式以結束按住（檢查 `player_event_mixin.dart:184-191` 附近的 KeyUp 分支，不要破壞既有行為）。
- 速度計算抽純函式 `static double holdSeekSpeed(Duration held, Duration total)`，放可測試的位置（例如 `lib/utils/seek_speed.dart`），加 `test/seek_speed_test.dart`。

### #29 設計
- `lib/services/settings_service.dart`：新增 `showLikeButton`（key `show_like_button`）、`showCoinButton`（`show_coin_button`）、`showFavButton`（`show_fav_button`），預設 true，寫法照 `_showMiniProgressKey`（`:319-331`）。
- `lib/screens/home/settings/tabs/playback_settings.dart`：在「迷你進度條」附近新增三個 `SettingToggleRow`：「顯示按讚按鈕」「顯示投幣按鈕」「顯示收藏按鈕」，副標「關閉後播放器控制列不顯示此按鈕」。`lib/screens/home/settings/settings_index.dart` 加對應搜尋條目。
- `lib/screens/player/widgets/controls_overlay.dart:295-321`：依設定不建立被隱藏的按鈕；按鈕與間距由過濾後的清單動態組合，部分或全部隱藏都不殘留間距（審查 #5）。
- `lib/screens/player/mixins/player_action_mixin.dart` `isCtrlBtnEnabled`（`:2198`）：被隱藏的按鈕回 false，讓左右鍵跳過。確認焦點起始位置或其他直接指定 `CtrlBtn.like/coin/fav` 的地方不會落在隱藏按鈕上。
- `i18n/en.json`：在 `strings` 中加入新字串的英文：「顯示按讚按鈕」→ "Show like button"、「顯示投幣按鈕」→ "Show coin button"、「顯示收藏按鈕」→ "Show favorite button"、「關閉後播放器控制列不顯示此按鈕」→ "Hide this button from the player control bar"。

## AC 驗證方式
| AC | 方式 |
|---|---|
| AC-1～4 | 單元測試；模擬器 log `🧠 [Memory]`；`am send-trim-memory` 觸發 critical |
| AC-5 | 既有測試全過 |
| AC-6～8 | 單元測試（速度函式）；模擬器按鍵（`adb shell input keyevent` 短按、`--longpress`／`sendevent` 按住） |
| AC-9～11 | 模擬器切換設定後截圖控制列 |
| AC-12～14 | 單元測試；模擬器 log `source=server` |

## 風險
- `x/player/wbi/v2` 多一次請求；並行執行、5 秒逾時，失敗退回舊邏輯。
- tier 切換縮小圖片快取會立刻淘汰圖片，畫面可能重新載入縮圖；只在 critical 進出時發生。
- KeyRepeat 頻率依裝置不同，速度用經過時間計算，不依事件數。

## 實作偏差
- 實作者：T-2 由 agy Sonnet（accept-edits）完成；T-1、T-3 的 agy Sonnet 兩次都在讀檔後結束，第二次撞到 agy 用量上限（429），改由 Claude Sonnet 子代理完成。
- T-1：`prepare()` 沒有「呼叫端指定 cid」參數（UGC 路徑原本就不使用 `startCid`），該優先序略過。移除不存在的 `videoInfo['history']` 讀取。快取與列表時間相同時取快取。
- T-1：舊流程 `player_action_mixin.dart:435-504` 只處理 PGC（UGC 在 `:105` 進入 `_initializeUgc`），不改。
- T-3：`holdSeekSpeed` 為頂層函式；KeyUp 在 `handleGlobalKeyEvent` 的 KeyUp 分支呼叫 `endSeekHold()`，不吃掉事件。

## 審查紀錄
- 規格審查（agy Gemini 3.8 Flash，`spec-review.md`）：5 條全部採用，已改入上文。
- 實作審查 A（T-1／T-2，agy Gemini 3.8 Flash，`review-a.md`）：
  - #1 採用：critical 時 `willWarm` 為 false 會落到 480P 預覽仍建立播放器 → `CardPreviewService.start` 在 critical 直接 return。
  - #2 不採用：要求 `prepare` 支援指定 cid。UGC 路徑原本就不使用 `startCid`，非本次退化；歷史卡片傳入的 cid 與伺服器 `last_play_cid` 一致。
  - #3 採用：列表 progress `-1`（他處看完）且有 `view_at` 時以 0 秒參與比新舊，補測試。
- 實作審查 B（T-3，`review-b.md`）：沒有發現。
