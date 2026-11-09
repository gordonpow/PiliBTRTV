# 規格：按下影片到開始播放約 0.5 秒

## 需求

使用者要求（2026-11-09）：從點選影片到開始播放保持在 0.5 秒左右。使用者選「兩項都做」。

實測（Android TV API 36 模擬器，改動前）：
- 焦點停 3 秒再按 OK（暖機已就緒）：`adopted 0ms`、`play 135ms`。
- 移到卡片馬上按 OK：`play 2774ms`；暖機 videoInfo 664ms、playInfo +418ms、initialize +1550ms。

- **AC-1**：ExoPlayer 起播緩衝改為 0.5 秒（原預設 2.5 秒），重新緩衝門檻 2 秒。
- **AC-2**：焦點停住後，背景預先解析鄰近最多 4 張影片卡片的影片資訊與播放網址（不抓 2MB 開頭），移到這些卡片後暖機直接用快取，略過 videoInfo 與 playurl 請求。
- **AC-3**：預先解析一次只跑一個請求鏈（序列），不中斷焦點卡片自己的預載，失敗靜默；已有新鮮快取（2 分鐘內）不重抓。

## 設計

### T-A（已完成，Opus）起播緩衝

- `packages/video_player_android`：複製 `video_player_android` 2.9.1，新增 `FastStartLoadControl.java`（`DefaultLoadControl` bufferForPlayback 500ms、afterRebuffer 2000ms），`TextureVideoPlayer`／`PlatformViewVideoPlayer` 的 `ExoPlayer.Builder` 加 `.setLoadControl(...)`。
- `pubspec.yaml` 用 `dependency_overrides` 指向 path；`analysis_options.yaml` 排除 `packages/**`。

### T-B（Sonnet）鄰近卡片預先解析

1. `lib/services/prefetch_service.dart`：
   - 新增 `void preResolve(List<Video> videos)`：過濾 `_eligible`、已有新鮮 entry 的略過；放入背景佇列（新的呼叫取代尚未開始的舊佇列，最多 4 筆）；序列執行：`BilibiliApi.getVideoInfo` → 決定 cid（沿用 `_run` 的 cid 邏輯）→ playurl（沿用 `_run` 的 playurl 部分，**不做** `_warm` 2MB 開頭、**不抓**彈幕）。結果存入 `_entries`（同一份快取，`takePlayUrl`、`takeVideoInfo`、`peekInfoCid` 都能用）。
   - 背景佇列使用自己的 CancelToken／generation，不受 `_abortActive` 影響，也不影響 `_active`；`schedule()` 對同一 bvid 若已有背景 entry 正在跑或已完成，視同快取（`skip (cached)` 或接手等待），不要重複請求。
   - 若 `_run` 抽共用函式較乾淨可以重構，但 `schedule` 原本行為（含 2MB 開頭與彈幕）不能改變。
   - 新增 `Map<String, dynamic>? peekVideoInfo(String bvid)`：不消耗地回傳新鮮 entry 的 info（若 `takeVideoInfo` 是消耗型，播放頁仍用 take）。
   - log：`⚡ [PreResolve] start/done/fail bvid`。
2. `lib/services/card_preview_service.dart` `_startWarm`：呼叫 `PlaybackPreparer.prepare` 時傳 `videoInfo: PrefetchService.instance.peekVideoInfo(video.bvid)`。注意 `prepare` 中 `fetchedHere` 為 false 時會略過 redirect_url 轉番劇檢查——快取的 info 若含 `redirect_url` 指向番劇，暖機要直接放棄（回傳不暖機），讓播放頁走原流程。cid 決定邏輯要確認傳入 info 時仍正確（播放歷史 `history` 欄位：`_run` 會 remove('history')，prepare 的 cid 優先序可能用到 API history——讀程式確認；若因此改變續播 cid，則改為傳入前不 remove，或在 preResolve 保留 history）。
3. `lib/widgets/base_tv_card.dart`：
   - 新增 static 註冊表 `static final Set<_BaseTvCardState> _mounted`（initState 加、dispose 移除）。
   - 焦點停住、`_startTimer` 觸發並開始預覽時，找出其他已掛載、`previewVideo != null`、render box 已 attach 且在畫面內（與螢幕矩形相交）的卡片，依卡片中心到目前卡片中心的距離排序，取最近 4 張，呼叫 `PrefetchService.instance.preResolve(...)`。
   - 只在 `SettingsService.cardPreview` 開啟時做（關閉預覽的使用者不增加請求）。

## 驗證

- `flutter analyze`、`flutter test`、debug APK。
- 模擬器：焦點停在第一張 1 秒後右移一張馬上按 OK，log 中暖機不再出現 videoInfo／playInfo 網路耗時，`⏱ [Startup] play` 顯著下降；停 3 秒再按仍約 0.15 秒。

## 風險

- B 站 API 請求變多（每次停住最多 4 組 view + playurl），可能觸發 -352；失敗靜默，不影響播放。
- 起播緩衝 0.5 秒：網路差時開頭可能停頓一次。

## 第二輪：開頭連線選最快的 CDN 主機（T-C）

實測（T-A、T-B 後）：
- 暖機 `initialize` 仍要 1.8～2.6 秒；起播緩衝 0.5 秒沒有改善。
- curl 從同一台電腦：`upos-sz-mirrorcosov`（B 站回傳的主機）TLS 0.64～2.05 秒、TTFB 0.97～2.42 秒；`upos-sz-mirroraliov` TLS 0.13 秒、TTFB 0.16 秒；`upos-hz-mirrorakam.akamaized.net` TTFB 0.22 秒；`mirrorali`、`mirrorhw` 逾時 8 秒。
- BtrProxy 開播階段（`_startupPassBytes` 內）以 `_passthrough` 直接連原始網址，`prefetchHead` 也連原始網址，都受主機延遲影響。DASH 起播要循序取 MPD 後的 init／index／資料多個範圍，每個新連線都要付 TLS 成本。
- 第二次測試：從播放頁返回後，焦點停在第二排卡片，沒有出現任何 `⚡ [PreResolve]` log，右邊鄰居（`BV1iyn96eEL9`）沒有被預先解析。

- **AC-4**：App 啟動後背景測量候選 CDN 主機延遲；開播階段的 `_passthrough` 與 `prefetchHead` 改用測得最快且可換主機的網址，失敗時退回原始網址。
- **AC-5**：與 CDN 的連線保持可重用（idle 連線保留夠久），開播不必每次重新 TLS 握手。
- **AC-6**：從播放頁返回後，焦點停住仍會預先解析鄰近卡片；已快取的卡片不占用 4 個名額。

### T-C 設計

1. 新增 `lib/services/btr/btr_host_ranker.dart`：`BtrHostRanker.instance`
   - `warmUp()`：App 啟動時呼叫（main 初始化完成後，不阻塞啟動），之後每 10 分鐘可重測（在下次 `bestFor` 時發現過期就背景重測）。對 `BtrConfig` 的主機清單（排除 `akamai`，與 `BtrNodePool._build` 相同條件）加上近期看到的原始主機，平行以 `btrDio` 發 `GET https://host/`（任何 HTTP 狀態都算可連線）並記錄 TTFB，逾時 3 秒算失敗。
   - `String? bestFor(String url)`：URL 可換主機（條件與 `BtrNodePool._build` 相同：媒體主機、非 mcdn、路徑含 `/upgcxcode/`、不含 `/v1/resource/`、`os != mcdn`）時，回傳換成最快主機的 URL；最快主機必須比原始主機的已測延遲快 30% 以上（原始主機未測過時視為慢）；`BtrNodePool` 全域封鎖中的主機不選。否則回 null。
   - 記錄原始主機：`bestFor` 遇到沒測過的原始主機時加入下次測量。
2. `btr_proxy.dart`：
   - `_passthrough`（開播階段）與 `prefetchHead`：先用 `bestFor(url)` 的網址；連線失敗或回非 2xx 時改用原始網址重試一次，並把該主機告知 ranker 降級。log：`BTR: startup host <host>`。
   - 每個 `_BtrSource` 對開播主機只決定一次（同一來源的多個範圍請求走同一主機，連線可重用）。
3. `btr_cdn.dart`：`btrDio` 的 `IOHttpClientAdapter` 設 `createHttpClient: () => HttpClient()..idleTimeout = const Duration(seconds: 90)..maxConnectionsPerHost = 偏大值（例如 16，需不少於多執行緒下載的併發數）`；確認不影響既有 timeout 設定。
4. PreResolve 修正：
   - `base_tv_card.dart` `_preResolveNeighbors`：傳給 `preResolve` 的候選改為最近 8 張，由 `preResolve` 跳過已快取的後取 4 張。
   - 找出第二次測試沒有任何 PreResolve log 的原因（例如 `_bgRunning` 沒有在例外或提前 return 時歸位、`_mounted` 狀態、焦點恢復路徑沒觸發 `_startTimer`），修正並說明。
