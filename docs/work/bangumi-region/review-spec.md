依據需求文檔（`1-requirements.md`）、技術規格（`2-spec.md`）、探索記錄（`explore.md`）及現有程式碼實作，檢視規格書中所存在的真實問題，依重要性排序如下（共 10 項）：

---

### 1. 設計錯誤與缺少邊界：部分番劇正片集數為空，單集位於 `sections` 結構中（empty episodes in sections）

* **規格章節**：`T-2 番劇 > 資料`、`T-2 番劇 > 播放器`
* **問題**：規格書假設番劇詳情的所有單集均存在於 `result.episodes[]` 中。然而在 B 站 PGC 介面中，多季番劇、劇場版、特別篇或部分分季動畫的正片 `result.episodes` 常為空陣列（`[]` 或 `null`），其單集實際存放於 `result.sections[].episodes[]`（如正片區塊、預告花絮區塊等）。若僅解析 `result.episodes`，播放器在初始化時將拿到空集數，導致 `cid` 為 `null`，直接觸發「獲取影片資訊失敗」而完全無法播放。
* **程式碼依據**：
  * [`docs/work/bangumi-region/2-spec.md:15`](file:///C:/presonal_project/PiliBTRTV/docs/work/bangumi-region/2-spec.md#L15)：`季資訊：/pgc/view/web/season?season_id=，result.episodes[] 含 id(ep_id)...`
  * [`docs/work/bangumi-region/explore.md:49`](file:///C:/presonal_project/PiliBTRTV/docs/work/bangumi-region/explore.md#L49)：`回傳 PgcInfoModel 包含 episodes/sections`
  * [`lib/screens/player/mixins/player_action_mixin.dart:74`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L74)：`episodes = videoInfo['pages'] ?? [];`
  * [`lib/screens/player/mixins/player_action_mixin.dart:108-114`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L108-L114)：`if (cid == null) { errorMessage = '獲取影片資訊失敗'; isLoading = false; return; }`
* **具體修正**：在 `PgcApi.getSeason` 解析時，若 `result['episodes']` 為空，必須降級遍歷 `result['sections']`（或 `result['section']`），提取第一個含有正片的 `section.episodes` 填入集數清單，並從中取得首集或上次觀看的 `ep_id` 與 `cid`。

---

### 2. 設計錯誤：假定 `bvid` 可由季資訊補回，忽略 `Video` 為不可變模型且本地歷史快取以 `bvid` 為 Key（bvid / history resume）

* **規格章節**：`T-2 番劇 > 資料`
* **問題**：規格書指出「`bvid` 仍必填（番劇卡片可先填空字串，進播放器後由季資訊補）」。然而 `Video` 類別的欄位皆為 `final`，且 `PlayerScreen.widget.video` 是不可變物件，進播放器後根本無法直接「補」回 `widget.video.bvid`。更嚴重的是，`PlayerActionMixin` 內部廣泛使用 `widget.video.bvid` 作為全域 Key（例如 `PlaybackProgressCache` 的進度儲存與讀取、心跳回報、外掛載入等）。若 `bvid` 為空字串，所有番劇將在本地快取共用同一個空鍵 `playback_progress_v3_`，導致不同番劇互相覆蓋觀看進度，且心跳 API 也會因 `bvid=''` 被 B 站伺服器拒絕。
* **程式碼依據**：
  * [`docs/work/bangumi-region/2-spec.md:15`](file:///C:/presonal_project/PiliBTRTV/docs/work/bangumi-region/2-spec.md#L15)：`bvid 仍必填（番劇卡片可先填空字串，進播放器後由季資訊補）。`
  * [`lib/models/video.dart:3`](file:///C:/presonal_project/PiliBTRTV/lib/models/video.dart#L3)：`final String bvid;`
  * [`lib/screens/player/mixins/player_action_mixin.dart:66-68`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L66-L68)：`final cachedRecord = await PlaybackProgressCache.getCachedRecord(widget.video.bvid);`
  * [`lib/screens/player/mixins/player_action_mixin.dart:504-508`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L504-L508)：`await PlaybackProgressCache.saveProgress(widget.video.bvid, cid!, currentPos);`
  * [`lib/services/playback_progress_cache.dart:26-27`](file:///C:/presonal_project/PiliBTRTV/lib/services/playback_progress_cache.dart#L26-L27)：`await _prefs?.setInt('$_progressPrefix$bvid', progress);`
* **具體修正**：
  1. 在 `PlayerStateMixin` 中宣告可變狀態變數 `currentBvid` 與 `currentEpId`，在解析完季資訊或切集時動態更新。
  2. 修改 `PlaybackProgressCache` 介面，支援以 `key`（PGC 使用 `season_id` 或 `ep_id`，UGC 使用 `bvid`）進行獨立快取隔離與讀取。
  3. 心跳上報與進度儲存時，改用 `currentBvid` 與單集實際帶有的 `bvid`。

---

### 3. 設計錯誤與缺少邊界：`switchEpisode` 與 `switchQuality` 缺少 `epId` 且未檢查 `error` 導致空解包崩潰（quality switch / -10403）

* **規格章節**：`T-2 番劇 > 資料`、`T-2 番劇 > 播放器`
* **問題**：
  1. 現有 `switchEpisode(int newCid)` 僅接收 `int newCid`，`switchQuality(int qn)` 僅接收 `int qn`。規格書雖寫「切畫質、切集同樣走 PGC 分支」，卻未說明 `epId` 從何而來。
  2. 規格書定義 `getPgcPlayUrl` 失敗時回傳 `{error: '<B站 message>（<code>）'}`（非 `null`）。但現有 `switchEpisode`（L1169）與 `switchQuality`（L1291）並未檢查 `playInfo['error']`，失敗時 `dashData` 與 `url` 均為 `null`，代碼直接強制執行 `Uri.parse(playUrl!)`，引發 `Null check operator used on a null value` 致命異常，完全無法按預期顯示錯誤訊息。
* **程式碼依據**：
  * [`docs/work/bangumi-region/2-spec.md:19`](file:///C:/presonal_project/PiliBTRTV/docs/work/bangumi-region/2-spec.md#L19)：`失敗時回傳 {error: '<B站 message>（<code>）'}`
  * [`docs/work/bangumi-region/2-spec.md:28`](file:///C:/presonal_project/PiliBTRTV/docs/work/bangumi-region/2-spec.md#L28)：`切畫質、切集同樣走 PGC 分支（switchEpisode、畫質切換的兩處 MpdGenerator.generate 呼叫點都要處理）。`
  * [`lib/screens/player/mixins/player_action_mixin.dart:1121`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L1121)：`Future<void> switchEpisode(int newCid) async`
  * [`lib/screens/player/mixins/player_action_mixin.dart:1169`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L1169)：`videoController = VideoPlayerController.networkUrl(Uri.parse(playUrl!), ...)`
  * [`lib/screens/player/mixins/player_action_mixin.dart:1252`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L1252)：`Future<void> switchQuality(int qn) async`
  * [`lib/screens/player/mixins/player_action_mixin.dart:1291`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L1291)：`videoController = VideoPlayerController.networkUrl(Uri.parse(playUrl!), ...)`
* **具體修正**：
  1. 在 `PlayerStateMixin` 中記錄 `currentEpId`；在 `switchEpisode(newCid)` 觸發時，由 `episodes.firstWhere((e) => e['cid'] == newCid)` 查出對應的 `ep_id` 並更新 `currentEpId`。
  2. 在 `switchEpisode` 與 `switchQuality` 呼叫 playurl 後，立即加入 `if (playInfo['error'] != null)` 檢查，若有錯誤則更新 `errorMessage` 或 Toast 並提早返回，不得對 `playUrl` 進行 `!` 強制解包。

---

### 4. 缺少邊界處理：編碼器回退迴圈遇到 -10403 地區限制等業務錯誤時重複請求 4 次（-10403）

* **規格章節**：`T-2 番劇 > 播放器`
* **問題**：規格書敘述「PGC playurl 失敗時 errorMessage 顯示 B站訊息（例如「抱歉您所在地區不可觀看！（-10403）」），不重試 3 次」。規格作者誤以為「重試 3 次」是 ExoPlayer 初始化的 `maxRetries = 3`（L258）。事實上，當 playurl 返回錯誤時根本走不到 L258，而是在外層 `for (final tryCodec in uniqueCodecs)` 迴圈（L175-234）中觸發 `continue codecLoop;`。由於 `uniqueCodecs` 最多有 4 種編碼器選項，遇到地區限制（-10403）或版權錯誤時，程式碼會連續對 B 站發送 4 次完全相同的 API 請求，導致電視介面嚴重卡頓轉圈數秒後才顯示錯誤。
* **程式碼依據**：
  * [`docs/work/bangumi-region/2-spec.md:32`](file:///C:/presonal_project/PiliBTRTV/docs/work/bangumi-region/2-spec.md#L32)：`PGC playurl 失敗時 errorMessage 顯示 B站訊息（例如「抱歉您所在地區不可觀看！（-10403）」），不重試 3 次。`
  * [`lib/screens/player/mixins/player_action_mixin.dart:174-175`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L174-L175)：`codecLoop: for (final tryCodec in uniqueCodecs) {`
  * [`lib/screens/player/mixins/player_action_mixin.dart:230-233`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L230-L233)：`if (playInfo['error'] != null) { lastError = playInfo['error']; continue codecLoop; }`
* **具體修正**：在 `initializePlayer` 的 `codecLoop` 內，檢查 `playInfo['error']`。若錯誤訊息中包含 `-10403`、權限錯誤或特定不可播錯誤碼，直接 `break codecLoop`，立即將錯誤訊息更新至 `errorMessage` 並終止初始化，避免無效輪詢多種編碼器。

---

### 5. 缺少邊界處理：大會員／試看單集（Preview）回傳 code:0 卻非正片，未判斷試看狀態導致完播連播錯亂（VIP/preview episodes）

* **規格章節**：`T-2 番劇 > 資料`、`風險`
* **問題**：規格書僅考慮 playurl 回傳非零錯誤碼的情況，但依 B 站 PGC 協議，非大會員請求大會員專屬集數時，playurl 回傳的 `code` 仍為 `0`，但回傳的是一段試看串流（帶有 `is_preview: 1` 或 `accept_description` 含有「试看」）。現有程式碼完全沒有試看標記判定，會直接播放該片段；當 2~6 分鐘試看結束觸發 `onVideoComplete()` 時，系統會誤以為影片已看完，自動觸發連播下一集，造成集數連續跳轉錯亂。
* **程式碼依據**：
  * [`docs/work/bangumi-region/2-spec.md:19`](file:///C:/presonal_project/PiliBTRTV/docs/work/bangumi-region/2-spec.md#L19)：`成功時 result.video_info 的結構與 UGC playurl 的 data 相同...`
  * [`docs/work/bangumi-region/explore.md:63`](file:///C:/presonal_project/PiliBTRTV/docs/work/bangumi-region/explore.md#L63)：`當 acceptDesc 含「试看」時彈出「該影片為專屬影片，僅提供試看」`
  * [`lib/screens/player/mixins/player_action_mixin.dart:604-620`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L604-L620)：播完直接呼叫 `switchEpisode(nextCid)`
* **具體修正**：在解析 PGC playurl 時檢測是否為試看（例如判斷 `video_info['is_preview'] == 1` 或 `accept_description` 含「试看」）。若為試看串流，於畫面提示「此為專屬影片，僅提供試看」，並在 `PlayerStateMixin` 設定 `isPreview = true`；當 `isPreview == true` 時，`onVideoComplete()` 禁止自動切換至下一集，亦不上報完播狀態。

---

### 6. 設計錯誤：`initializePlayer` 內的 VIP 智慧畫質升級寫死呼叫 UGC 介面（Design error）

* **規格章節**：`T-2 番劇 > 播放器`
* **問題**：規格書雖提及初始播放地址、切畫質與切集需走 PGC 分支，但完全遺漏了 `initializePlayer` 內部現有的「VIP 智慧升級」邏輯（L185-222）。在登入使用者為大會員時，代碼會自動請求最高可用畫質，此處寫死呼叫 `BilibiliApi.getVideoPlayUrl(bvid: widget.video.bvid, cid: cid!, qn: maxQn, forceCodec: tryCodec)`。當播放番劇時，因 `widget.video.bvid` 為空或為番劇專屬，此請求會呼叫 UGC 介面失敗，導致升級中斷或播放位址異常。
* **程式碼依據**：
  * [`docs/work/bangumi-region/2-spec.md:28`](file:///C:/presonal_project/PiliBTRTV/docs/work/bangumi-region/2-spec.md#L28)：`切畫質、切集同樣走 PGC 分支（switchEpisode、畫質切換的兩處 MpdGenerator.generate 呼叫點都要處理）。`
  * [`lib/screens/player/mixins/player_action_mixin.dart:208-213`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L208-L213)：
    ```dart
    final upgradePlayInfo = await BilibiliApi.getVideoPlayUrl(
      bvid: widget.video.bvid,
      cid: cid!,
      qn: maxQn, // 精確請求最高畫質
      forceCodec: tryCodec,
    );
    ```
* **具體修正**：在 VIP 智慧升級處加入 `widget.video.isPgc` 分支判斷，改呼叫 `PgcApi.getPgcPlayUrl`（傳入 `epId`），或透過統一入口方法獲取位址。

---

### 7. 更簡單的設計：統一 `PlaybackApi.getVideoPlayUrl` 內部端點，免除播放器層大量散落的分支（Simpler design）

* **規格章節**：`T-2 番劇 > 資料`、`T-2 番劇 > 播放器`
* **問題**：規格書要求在 `PgcApi` 內手動將 PGC 回傳的 `result.video_info` 轉換成與 `PlaybackApi.getVideoPlayUrl` 相同結構（包括 qualities、currentQuality、dashData 等 130+ 行的音訊軌排序、硬解 codec 匹配），並在播放器的初始化、VIP 升級、`switchEpisode`、`switchQuality` 各處遍布 `if (widget.video.isPgc)` 分支。實際上，B 站 PGC playurl 的 `result.video_info` 與 UGC playurl 的 `data` 內部 DASH 結構 100% 一致。
* **程式碼依據**：
  * [`docs/work/bangumi-region/2-spec.md:19, 28`](file:///C:/presonal_project/PiliBTRTV/docs/work/bangumi-region/2-spec.md#L19)：`轉成與 PlaybackApi.getVideoPlayUrl 相同的回傳格式（含 dashData、qualities、currentQuality、codec），讓 MPD／BTR 流程共用... 切畫質、切集同樣走 PGC 分支`
  * [`lib/services/api/playback_api.dart:62-245`](file:///C:/presonal_project/PiliBTRTV/lib/services/api/playback_api.dart#L62-L245)：現有完整的 DASH 解析、Codec 硬解優先序比對邏輯
* **具體修正**：不需在 `PgcApi` 重複實作整套 DASH 解析與轉換，直接在現有 `PlaybackApi.getVideoPlayUrl` 增加可選參數 `int? epId`。當 `epId != null` 時，改請求 PGC 端點 `/pgc/player/web/v2/playurl` 並將 `json['result']?['video_info']` 視為 `data` 傳入既有解析流程。如此一來，編碼器降級、VIP 畫質升級、`switchQuality`、`switchEpisode` 均無需改動多處分支，即可自動享有完整的 DASH 解析與 BTR 加速支援。

---

### 8. 驗收條件無法滿足：選集面板標題格式寫死 `'P${index + 1} $partName'`，無法達成 AC-3（AC-3）

* **規格章節**：`T-2 番劇 > 播放器`
* **問題**：需求 **AC-3** 明確要求「選集面板列出所有集數（「第 N 話 標題」），可切換」。規格書僅規定將單集轉換結構中的 `part` 設為「第 N 話 long_title」。但在現有 `EpisodePanel`（L113-114）中，項目標題一律格式化為 `final title = 'P${index + 1} $partName';`。這會導致介面上顯示為 `P1 第 1 話 標題`（產生多餘的 `P1 ` 前綴），違反驗收標準，且規格書漏掉了修改 `EpisodePanel` 的工作項目。
* **程式碼依據**：
  * [`docs/work/bangumi-region/1-requirements.md:22`](file:///C:/presonal_project/PiliBTRTV/docs/work/bangumi-region/1-requirements.md#L22)：`AC-3：...選集面板列出所有集數（「第 N 話 標題」），可切換。`
  * [`docs/work/bangumi-region/2-spec.md:27`](file:///C:/presonal_project/PiliBTRTV/docs/work/bangumi-region/2-spec.md#L27)：`part=「第 N 話 long_title」`
  * [`lib/screens/player/widgets/episode_panel.dart:113-114`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/widgets/episode_panel.dart#L113-L114)：
    ```dart
    final partName = episode['part'] ?? episode['page_part'] ?? '';
    final title = 'P${index + 1} $partName';
    ```
* **具體修正**：修改 `EpisodePanel`，在組裝 `title` 時增加判定：若單集資訊來自番劇（或 `partName` 已包含「第」字樣），直接顯示 `partName`，不再額外拼接 `P${index + 1}`。

---

### 9. 驗收條件與邊界缺失：最後一集播完仍會跳轉推薦影片，且測試未涵蓋自動連播開關（auto-play next / AC-5）

* **規格章節**：`T-2 番劇 > 播放器`、`驗證`
* **問題**：
  1. 需求 **AC-5** 規定「番劇播完自動播下一集（自動連播開啟時）；最後一集播完不跳到推薦影片」。現有 `onVideoComplete()` 在最後一集播完後，若 `relatedVideos` 非空，仍會無條件執行 `Navigator.pushReplacement` 跳轉推薦影片（L623-647）。雖然規格提及不請求相關影片，但若先前有快取或變數未清空，將引發非預期跳轉。
  2. 現有程式碼在 `onVideoComplete()` 連播下一集呼叫的是 `switchEpisode(nextCid)`，由於現有 `switchEpisode` 走 UGC 且缺 `epId`，番劇連播下一集會直接失敗中斷。
  3. 規格驗證清單中寫「模擬器播放番劇...播到下一集」，但未提及如何在單元測試或模擬器中驗證長達 24 分鐘的集數自然完播（未規範使用 seek 快進至最後數秒），亦未驗證 `SettingsService.autoPlay == false` 時的暫停表現。
* **程式碼依據**：
  * [`docs/work/bangumi-region/1-requirements.md:24`](file:///C:/presonal_project/PiliBTRTV/docs/work/bangumi-region/1-requirements.md#L24)：`AC-5：番劇播完自動播下一集（自動連播開啟時）；最後一集播完不跳到推薦影片。`
  * [`lib/screens/player/mixins/player_action_mixin.dart:623-647`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L623-L647)：
    ```dart
    if (relatedVideos.isNotEmpty) {
      final nextVideo = relatedVideos.first;
      // 導航到新影片
      Navigator.of(context).pushReplacement(...);
    }
    ```
* **具體修正**：
  1. 在 `onVideoComplete()` 增加 `isPgc` 判斷：當番劇達到最後一集時，強制阻斷並略過 `relatedVideos` 邏輯，僅執行完播進度回報並保持暫停。
  2. 在驗證清單中加入手動快進至片尾 5 秒內的驗收步驟，分別測試自動連播「開啟」與「關閉」兩種設定下的行為。

---

### 10. 缺少邊界處理：舊設定分類排序污染預載入資料，與控制列按鈕隱藏引發焦點脫靶（old saved category settings / remote focus）

* **規格章節**：`T-1 分區 API`、`T-2 番劇 > 播放器`
* **問題**：
  1. **舊設定污染**：`SplashScreen` 在啟動時會固定預載入「推薦」影片列表傳入 `HomeTab(preloadedVideos: ...)`。而在 `home_tab.dart:55-58` 中，程式碼直接無條件將其填入 `_categoryVideos[0]`。若舊使用者曾在介面設定中自訂分區排序，將「番劇」或「影視」排在第一位（即 `_categories[0] != HomeCategory.recommend`），則第一頁分類將直接被 UGC 推薦影片污染；點擊卡片時又會因被判定為 PGC 而誤入番劇播放流程引發崩潰。
  2. **遙控器焦點斷層**：規格書提出在 PGC 播放器時「隱藏或跳過」UP 主、相關影片、投幣等面板。但現有 `ControlsOverlay`（L196-228）與 `player_event_mixin.dart:216` 寫死了固定的控制項索引 0~4（0=選集, 1=UP主, 2=更多, 3=設定, 4=三連，`maxIndex: 4`）。若直接在 UI 隱藏 UP 主與相關影片按鈕，遙控器往右按時焦點索引仍會停在 1 或 2，導致畫面焦點框「憑空消失」，按下確定鍵還會開啟空白面板。
* **程式碼依據**：
  * [`lib/screens/home/home_tab.dart:55-58`](file:///C:/presonal_project/PiliBTRTV/lib/screens/home/home_tab.dart#L55-L58)：
    ```dart
    if (widget.preloadedVideos != null && widget.preloadedVideos!.isNotEmpty) {
      _categoryVideos[0] = widget.preloadedVideos!;
    ```
  * [`lib/screens/player/widgets/controls_overlay.dart:196-228`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/widgets/controls_overlay.dart#L196-L228)：固定按鈕索引 0~4
  * [`lib/screens/player/mixins/player_event_mixin.dart:216`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_event_mixin.dart#L216)：`maxIndex: 4`
* **具體修正**：
  1. 在 `home_tab.dart:initState` 填入預載入資料前，增加條件檢查 `_categories[0] == HomeCategory.recommend`；若不相符則不覆蓋 `_categoryVideos[0]`，改為按分類正常異步請求。
  2. 在 `ControlsOverlay` 與按鍵處理中，動態建立可用按鈕列表與索引對應（或在 PGC 模式下將 UP 主與更多影片按鈕以 `disabled` 樣式顯示而不直接從 DOM 移除），維持遙控器左右導航的連續性，避免焦點斷層。
