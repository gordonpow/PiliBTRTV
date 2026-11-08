本次實作審查共找出 5 項與規格/AC 不符、會造成錯誤行為或資源洩漏的問題，依嚴重度條列如下：

---

### 1. 【嚴重度：高】
* **檔案:行號**：[videoshot.dart:77](file:///c:/presonal_project/PiliBTRTV/lib/models/videoshot.dart#L77)（連帶影響 [player_action_mixin.
經過審查實作 diff 與規格需求，共找出 5 項具體問題，依嚴重度條列如下：

---

### 1. 【嚴重度：高】
* **檔案:行號**：[videoshot.dart:77](file:///C:/presonal_project/PiliBTRTV/lib/models/videoshot.dart#L77)（連帶影響 [player_action_mixin.dart:586](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L586) 與 [seek_thumbnail_strip.dart:1051](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/widgets/seek_thumbnail_strip.dart#L1051)）
* **問題**：pvdata 為非同步載入，在載入完成前（或載入失敗時）`_frameTimestamps` 為 null，此時 `indexAt` 恆回傳 `0`。這會導致：
  1. 快進時 `currentK` 恆為 0、`nextK` 恆為 1，播放器快進快退卡死在第 1 幀無法前進。
  2. 縮圖列永遠將選中卡片鎖定在第 0 幀，無法隨進度切換。
* **建議修法**：無時間戳時，`indexAt` 應支援傳入影片長度並以均勻比例計算索引；或在 `_frameTimestamps == null` 時回退至原本 10/30/60 秒按鍵行為（AC-C6）。

---

### 2. 【嚴重度：高】
* **檔案:行號**：[CrashChannel.kt:77-87](file:///C:/presonal_project/PiliBTRTV/android/app/src/main/kotlin/com/bili/tv/bili_tv_app/CrashChannel.kt#L77-L87)
* **問題**：首開標記邏輯寫在 `getLastCrash` 中，若 App 於首次安裝啟動期間發生閃退，此時尚未寫入 `KEY_ACKED_TS`；下次重啟呼叫 `getLastCrash` 時仍會觸發「首次安裝」判斷，直接把剛產生的 `last_crash.txt` 刪除並回傳 null，導致首次閃退記錄永久丟失（AC-B1）。
* **建議修法**：將 `KEY_ACKED_TS` 的初始寫入移至 `CrashChannel.installHandler(context)`，只要 App 初次成功建立 handler 就記錄當前時間，後續崩潰時間必定大於基準時間。

---

### 3. 【嚴重度：中】
* **檔案:行號**：[FrameChannel.kt:249-256](file:///C:/presonal_project/PiliBTRTV/android/app/src/main/kotlin/com/bili/tv/bili_tv_app/FrameChannel.kt#L249-L256)
* **問題**：`val r = MediaMetadataRetriever()` 實例化後，若 `r.setDataSource(url, headers)` 拋出例外（如 403、網路中斷、無效串流），執行流程直接跳到 catch，此新建的 `r` 既未賦值給 `retriever` 也未呼叫 `release()`，造成 Android 原生 Binder 與解碼資源洩漏。
* **建議修法**：以 `try-catch` 包裹 `setDataSource`，失敗時在 catch 區塊內立即呼叫 `r.release()`。

---

### 4. 【嚴重度：中】
* **檔案:行號**：[search_keyboard_view.dart:144-149](file:///C:/presonal_project/PiliBTRTV/lib/screens/home/search/search_keyboard_view.dart#L144-L149)
* **問題**：在文字輸入狀態按返回鍵（`_isBackKey`）或點擊返回主頁時，僅呼叫 `SearchImeBackGuard.markClosed()` 與轉移焦點，未呼叫 `_closeIme()`。因主頁採 `IndexedStack` 保持子頁狀態，元件不會被 dispose，系統鍵盤（IME）仍殘留在畫面上，違反 AC-A1。
* **建議修法**：在 `_onTextKey` 處理 `_isBackKey` 處與 `onBackToHome` 回呼中補上 `_closeIme()`。

---

### 5. 【嚴重度：低】
* **檔案:行號**：[seek_thumbnail_strip.dart:928-932](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/widgets/seek_thumbnail_strip.dart#L928-L932)
* **問題**：在 `didUpdateWidget` 中同步呼叫了 `setState(() => _realFrameBytes = null)`。Flutter 生命週期中 `didUpdateWidget` 後會立即觸發 `build`，在此階段呼叫 `setState` 不僅多餘，亦可能在特定框架版本引發警告。
* **建議修法**：直接將變數賦值 `_realFrameBytes = null`，移除外層的 `setState`。
