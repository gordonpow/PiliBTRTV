經審查 [`docs/work/search-crash-seek/2-spec.md`](file:///C:/presonal_project/PiliBTRTV/docs/work/search-crash-seek/2-spec.md) 與現有程式碼，發現以下 5 個問題：

### 1. 縮圖列索引邊界越界與除零例外
- **嚴重度**：高
- **問題**：AC-C1 規定中間為選中縮圖，左右各顯示 3 張（共 7 張）。在影片頭尾時，索引會出現負數或 $\ge \text{frameCount}$。規格中的 [`frameAtIndex`](file:///C:/presonal_project/PiliBTRTV/docs/work/search-crash-seek/2-spec.md#L44) 與 [`timeOfIndex`](file:///C:/presonal_project/PiliBTRTV/docs/work/search-crash-seek/2-spec.md#L43) 未定義邊界防護，取 `ts[k+1]` 會拋出 `RangeError`；且無時間戳時若影片長度為 0 會產生除以零例外。
- **依據**：[`docs/work/search-crash-seek/2-spec.md:40-44, 64`](file:///C:/presonal_project/PiliBTRTV/docs/work/search-crash-seek/2-spec.md#L40-L44)、[`lib/models/videoshot.dart:50-104`](file:///C:/presonal_project/PiliBTRTV/lib/models/videoshot.dart#L50-L104)
- **建議修法**：`frameAtIndex(k)` 在 $k < 0$ 或 $k \ge \text{frameCount}$ 時回傳 `null`（UI 顯示空白/佔位）；`timeOfIndex` 先將 $k$ clamp 至合法區間，並對除以零做防護。

### 2. ApplicationExitInfo 首次啟動誤報與資源洩漏
- **嚴重度**：高
- **問題**：初次安裝或清除資料時 `acked_ts` 為空，`getHistoricalProcessExitReasons` 會取得過去系統留存的紀錄而誤跳對話框（違反 AC-B4）。且 Java 閃退的 `last_crash.txt` 與系統記錄時間有微小秒差，分開比對會重複詢問；`traceInputStream` 亦未保證關閉。
- **依據**：[`docs/work/search-crash-seek/2-spec.md:23-27`](file:///C:/presonal_project/PiliBTRTV/docs/work/search-crash-seek/2-spec.md#L23-L27)、[`MainActivity.kt:52-64`](file:///C:/presonal_project/PiliBTRTV/android/app/src/main/kotlin/com/bili/tv/bili_tv_app/MainActivity.kt#L52-L64)
- **建議修法**：初次啟動無 `acked_ts` 時預設寫入當前時間；比對時 5 秒內視為同一次崩潰；`traceInputStream` 務必使用 `.use { ... }` 讀取並關閉。

### 3. MediaMetadataRetriever 阻塞與 release 崩潰風險
- **嚴重度**：高
- **問題**：原生單一背景執行緒若因網路或 DASH fMP4 延遲，`setDataSource` 會阻塞數十秒，導致抽幀請求堆積。此時若退出播放器由主執行緒呼叫 native `release()`，底層會引發 `IllegalStateException` 或崩潰。
- **依據**：[`docs/work/search-crash-seek/2-spec.md:54-58`](file:///C:/presonal_project/PiliBTRTV/docs/work/search-crash-seek/2-spec.md#L54-L58)
- **建議修法**：抽幀應具備 timeout 機制（如 1.5 秒）；`release()` 需排入同一個 background executor 排程執行以確保執行緒安全。

### 4. 點選搜尋建議漏關 IME
- **嚴重度**：中
- **問題**：開啟系統鍵盤輸入時，若以方向鍵選取右側「搜尋建議」（[`_selectSuggestion`](file:///C:/presonal_project/PiliBTRTV/lib/screens/home/search/search_keyboard_view.dart#L257)），不會走 `_submit()`。而 `dispose()` 僅在 `hasFocus || _imeVisible` 時才關閉，焦點轉移時可能誤判導致鍵盤殘留（違反 AC-A1/AC-A2）。
- **依據**：[`docs/work/search-crash-seek/2-spec.md:11-15`](file:///C:/presonal_project/PiliBTRTV/docs/work/search-crash-seek/2-spec.md#L11-L15)、[`search_keyboard_view.dart:257-261`](file:///C:/presonal_project/PiliBTRTV/lib/screens/home/search/search_keyboard_view.dart#L257-L261)
- **建議修法**：`_selectSuggestion` 開頭呼叫 `_closeIme()`；`dispose()` 內無條件呼叫 `TextInput.hide`。

### 5. 解碼失敗降級遺漏 previewFrameUrl
- **嚴重度**：低
- **問題**：規格只在 `initializePlayer/switchEpisode/switchQuality` 取得 `playInfo` 處更新 `previewFrameUrl`，遺漏了硬體解碼失敗自動降級至 AVC 的 [`_fallbackToAvc`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L527) 流程。
- **依據**：[`docs/work/search-crash-seek/2-spec.md:60-61`](file:///C:/presonal_project/PiliBTRTV/docs/work/search-crash-seek/2-spec.md#L60-L61)、[`player_action_mixin.dart:558-580`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L558-L580)
- **建議修法**：在 `_fallbackToAvc` 取得 `playInfo` 處同步更新 `previewFrameUrl`。
