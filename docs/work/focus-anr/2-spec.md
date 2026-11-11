# 規格：快速移動焦點後無回應（ANR）（#21）

## 設計

### T-1 裝置記憶體資訊
- `android/app/src/main/kotlin/com/bili/tv/bili_tv_app/MainActivity.kt` 的 `perfDeviceInfo()` 加上 `"totalMemMb"`（`ActivityManager.MemoryInfo.totalMem / 1048576`，Int）。
- 新增 `lib/services/device_profile.dart`：
  - `static bool isLowMemory({bool? isLowRam, int? totalMemMb})`：`isLowRam == true`，或 `totalMemMb` 在 1 到 2304 之間回 true。
  - `static bool lowMemory = false;`
  - `static Future<void> init()`：用既有的 `getDeviceInfo` channel（與 `lib/services/codec_service.dart` 相同的 channel）取得資訊並設定 `lowMemory`。失敗時維持 false，不丟例外。
- `lib/main.dart`：`SettingsService.init()` 之後 `await DeviceProfile.init()`；圖片快取上限依 `DeviceProfile.lowMemory` 設為 150／64MB 或 500／200MB。

### T-2 播放器名額（序列化）
- 新增 `lib/services/player_slot.dart`，類別 `PlayerSlot`（不依賴 Flutter）：
  - `Future<Object?> acquire({required bool Function() cancelled, Duration maxWait = const Duration(seconds: 12)})`：名額被占用時等待；每次被喚醒都檢查 `cancelled()`，為 true 回 null。等待超過 `maxWait` 時強制取得（避免漏釋放後永遠卡住）。成功回傳 token。
  - `void release(Object? token)`：可重複呼叫；只有目前持有者的 token 會釋放名額並喚醒等待者。
  - `bool get busy`。
- `lib/services/card_preview_service.dart`：
  - `start()` 的 480P 流程與 `_startWarm()` 在發出任何網路請求前先 `acquire`；回 null 就直接結束。
  - token 與 controller 的對應用 `Expando<Object>` 記錄。
  - 釋放時機：
    1. 這次嘗試結束且沒有留下 controller（取消、失敗、redirect）。
    2. `_disposeController` 內 `controller.dispose()` 完成之後（dispose 丟例外也要釋放）。
    3. `take()` 交給播放頁時。
  - 暖機逾時（`_warmTimeout`）後 `PlaybackPreparer.prepare` 仍在背景執行：名額要等底層的 prepare future 完成才釋放（prepare 被取消時會自行 dispose controller）。做法：保留未加 `.timeout` 的原始 future，在它完成時若這次嘗試沒有把 controller 交給 `_prepared`，就釋放。
  - `_startWarm` 的 `Stopwatch` 與 `_warmTimeout` 從取得名額之後才開始算，等待名額不算失敗。
  - 480P 流程中 `gen != _generation` 的每個提早 return 都要釋放名額。

### T-3 連續移動時延長等待
- `lib/utils/nav_settle.dart`（實際路徑以 `class NavSettle` 所在檔案為準）：
  - `onFocusArrived({DateTime? now})`：記錄最近的取得焦點時間。包含這一次在內，2 秒內達 3 次時回傳連續移動的等待時間。
  - 等待時間：一般裝置 150／250／500ms（單次／快速／連續）；`DeviceProfile.lowMemory` 時 300／300／600ms。
  - `now` 參數只給測試用。

### T-4 低記憶體裝置減少預先解析
- `lib/services/prefetch_service.dart`：`_bgMax` 改為 getter，`DeviceProfile.lowMemory` 時 2，否則 4。

### T-5 記憶體不足時釋放
- `CardPreviewService` 新增 `void onMemoryPressure()`：`stopAll()`，並把 `_pausedUntil` 設為現在加 60 秒。
- `PrefetchService` 新增 `void trimMemory()`：清空彈幕快取 `_danmaku`。
- `lib/main.dart`：註冊一個 `WidgetsBindingObserver`，`didHaveMemoryPressure()` 時呼叫上面兩個方法，並 `imageCache.clear()`、`imageCache.clearLiveImages()`。用 `debugPrint` 記一行 `🧹 [Memory] pressure`。

### T-6 測試
- `test/device_profile_test.dart`：`isLowMemory` 的邊界（null、0、2304、2305、isLowRam）。
- `test/player_slot_test.dart`：序列取得、等待中取消回 null、重複 release 無副作用、非持有者 release 無效、`maxWait` 逾時強制取得。
- `test/nav_settle_test.dart`：單次、快速、連續三種等待時間（用 `now` 參數）。

## AC 對應的驗證方式
| AC | 方式 |
|---|---|
| AC-1、AC-2 | `player_slot_test` 與 diff 審查；模擬器快速移動焦點看 log（`[Warm] start` 不重疊） |
| AC-3 | `nav_settle_test` |
| AC-4、AC-5 | `device_profile_test` 與 diff 審查 |
| AC-6 | diff 審查；模擬器 `adb shell am send-trim-memory <pkg> RUNNING_CRITICAL` 看 log |
| AC-7 | diff 審查；模擬器按 OK 播放 |

## 邊界情況與風險
- 漏釋放名額：`maxWait` 12 秒後強制取得，最多延遲一次暖機。
- 名額等待讓第二張卡片的預覽較晚出現：只有上一個播放器還在初始化或釋放時才會發生。
- 回退方式：還原本次 commit。

## 審查紀錄
- 規格未另外送審；實作完成後由全新的審查子代理審查 diff（使用者指定用 Fable）。

## 實作偏差
- `_startWarm` catch：prepare 已交出 controller 但尚未存進 `_prepared` 就丟例外時，新增 `_disposeController` 清理（原本會洩漏），名額隨之釋放。
- `PlayerSlot` 用 FIFO 等待者；取消的等待者被喚醒或 `acquire` 開頭偵測到取消時會喚醒下一位。
- `NavSettle` 新增 `@visibleForTesting resetForTest()`。
- `isLowMemory` 的 `totalMemMb` 條件為 1 到 2304（含）。

## diff 審查紀錄（agy Gemini 3.8 Flash，2026-11-11）
原始輸出：`docs/work/focus-anr/diff-review.md`。四項發現都不採用：
1. `_prepared` 設定後才丟例外時名額未釋放（低）：`_prepared` 仍持有該播放器，下一次 `start()` 的 `stopAll()` 會釋放它並釋放名額，不會洩漏。
2. `waitAndTake` 的 8 秒上限包含等待名額的時間（中）：逾時後 `stopAll()` 讓播放頁自行準備，是既有的回退行為。
3. `release()` 後新的 `acquire()` 可能插隊（低）：仍只有一個持有者，不違反 AC-1。
4. `base_tv_card.dart` 長按時重新排程固定 250ms（低）：那是按住方向鍵期間的輪詢間隔，不是停穩後的等待時間。
