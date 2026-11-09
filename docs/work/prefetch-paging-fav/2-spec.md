# 規格：焦點預載、首頁分頁修正、歷史頁收藏與稍後再看

需求見 `1-requirements.md`。三個任務改不同檔案，可平行實作。

## T-A 首頁分頁修正（只改 `lib/screens/home/home_tab.dart`）

根因：`SliverChildBuilderDelegate` builder 中 `index == length - 4` 時同步呼叫 `_loadMore()`（:264），`_loadVideosForCategory` 在第一個 await 前就 `setState`（:133），在 build 期間呼叫 setState。debug 模式丟例外後 `_categoryLoading` 留在 true，之後 `_loadMore` 永遠在 :203 return。

修改：
1. 移除 builder 裡的 `_loadMore()` 呼叫。改為在卡片 `onFocus` 中判斷 `index >= _currentVideos.length - 8` 時呼叫 `_loadMore()`（焦點事件不在 build 中）。另外在 builder 中若 `index == length - 1` 可用 `WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore())` 保底（避免短清單無法觸發），`_loadMore` 本身有 `_isLoading` 防重入。
2. `_loadVideosForCategory`：網路請求包在 try/finally，確保 `_categoryLoading[i]` 一定還原為 false（AC-7）。非 refresh 且取回 0 筆（失敗或空）時，把 `_loadMore` 先加上的 page 退回（推薦分類的 `_categoryRefreshIdx` 不退，因為 rcmd 每次都有新內容）。
3. `onMoveDown`：`index + 4 >= length` 但下一列存在（`(index ~/ 4 + 1) * 4 < length`）時，移到 `length - 1`（AC-8）；真正最後一列維持 null，並觸發 `_loadMore()`。
4. `_loadMore` 只在 `_categoryVideos` 非空時動作。

## T-B 焦點預載

### 新增 `lib/services/prefetch_service.dart`

單例 `PrefetchService.instance`：

- `void schedule(Object owner, Video video)` / `void cancel(Object owner)`：由卡片呼叫。只保留最新一個；用 generation 丟棄過期結果（AC-4）。
- `Future<void> _run(Video video, int gen)`，依序（每個 await 後檢查 gen）：
  1. `getVideoInfo(bvid)`（番劇／直播／bvid 空時整個略過）→ 存 `_infoCache[bvid]`，TTL 2 分鐘。
  2. cid：info 的 `cid`（或 `video.cid`）。
  3. 播放網址：用**與播放器相同的 qn 與 forceCodec 計算方式**呼叫 `BilibiliApi.getVideoPlayUrl`。把 player_action_mixin.dart 中決定初始 qn／forceCodec 的邏輯抽成可共用的靜態函式（例如 `PlaybackApi` 或新檔 `lib/services/play_params.dart`），播放器與預載都呼叫它，避免兩邊不一致。結果存 `_playUrlCache[(bvid,cid,qn,codec)]`，TTL 2 分鐘（CDN 簽名網址有期限）。
  4. 彈幕：`getDanmaku(cid)` 存 `_danmakuCache[cid]`，TTL 5 分鐘。
  5. 媒體暖機（只在 `BtrConfig.playback == true` 時，AC-5）：對 DASH 選定的 video 與 audio URL 呼叫新增的 `BtrProxy.prefetchHead(url, backups:, bytes: 2 * 1024 * 1024)`。
- 對外查詢：`takeVideoInfo(bvid)`、`takePlayUrl(bvid, cid, qn, codec)`、`takeDanmaku(cid)`，過期回 null。播放器拿到就用，並 `debugPrint('⚡ [Prefetch] hit ...')`（AC-2 可由 log 確認）。
- 快取上限：info／playurl／danmaku 各 30 筆，超過移除最舊。
- 風控：同 bvid 在 TTL 內不重抓；任一步失敗就停止本次預載，不重試。

### `BtrProxy.prefetchHead`（`lib/services/btr/btr_proxy.dart`）

- 用 `wrap` 相同的方式登記 source（同一個 URL 之後 `wrap` 會回傳同一個 source），並主動 `_probe()` 與下載 `[0, bytes)` 範圍，存在該 source 的開頭快取 `Uint8List? _head`。
- `serve` 處理 range 請求時，若請求範圍完全落在 `_head` 內，直接從記憶體回應，不打 CDN；部分重疊時先送 head 部分再接原本的抓取流程（若實作複雜，至少處理「完全落在 head 內」的情況）。
- 最多保留 2 支影片（4 個 source）的 head，超過時清掉最舊的 `_head`（記憶體上限，需求限制）。
- 需確認 `_maxSources` 淘汰不會在播放中移除正在使用的 source。

### 播放器使用預載（`lib/screens/player/mixins/player_action_mixin.dart`）

- `initializePlayer` 中：
  - `getVideoInfo` 前先 `PrefetchService.instance.takeVideoInfo(bvid)`；
  - `getVideoPlayUrl`（:234 初次請求）前先 `takePlayUrl(...)`，參數需與實際請求完全相同才使用；VIP 升級請求（:271）不使用快取；
  - `loadDanmaku` 中 `getDanmaku` 前先 `takeDanmaku(cid)`。
- 觀看進度（info 裡的 history）可能過期：使用快取 info 時，續播進度仍以 `PlaybackProgressCache` 與原本邏輯為準；若原本用 info 的 history 欄位，TTL 2 分鐘可接受。
- 拿到網址後的 `MpdGenerator.generate` → `BtrProxy.wrap` 流程不變（同 URL 會對應到已暖機的 source）。

### 卡片（`lib/widgets/base_tv_card.dart`）

- 聚焦且 `previewVideo != null` 時另開 `Timer(300ms)` → `PrefetchService.instance.schedule(this, video)`；失焦、dispose 時取消計時器並 `cancel(this)`。按確認鍵時**不**取消預載結果（只取消進行中的 0.3 秒計時器），讓播放器能用。
- `CardPreviewService` 取 cid 時先查 `PrefetchService` 的 info 快取（可選，減少請求）。

## T-C 歷史頁分頁

### API（新增 `lib/services/api/fav_api.dart`，並在 `bilibili_api.dart` 加轉接）

- `getFavFolders()`：`GET /x/v3/fav/folder/created/list-all?up_mid={mid}`（帶 cookie），回傳 `List<FavFolder{id, title, mediaCount}>`；API 回傳順序第一個即預設收藏夾，保持順序。
- `getFavVideos(mediaId, pn)`：`GET /x/v3/fav/resource/list?media_id=&pn=&ps=20&platform=web`，`data.medias` → `Video`（`bvid`、`title`、`cover`、`upper.name`/`upper.mid`、`duration`、`cnt_info.play`、`pubtime`）；`data.has_more` → hasMore。失效影片（`attr != 0` 或 title 為「已失效视频」）過濾掉。
- `getWatchLater()`：`GET /x/v2/history/toview`（帶 cookie），`data.list` → `Video`（`bvid`、`cid`、`title`、`pic`、`owner`、`duration`、`stat.view`、`pubdate`）。
- 在 `lib/models/video.dart` 新增 `Video.fromFav(Map)`、`Video.fromToView(Map)`。
- 與伺服器簡體字比對（如「已失效视频」）保留原文並加註解。

### 介面

- `lib/screens/home/history_tab.dart`：上方標題 `Text('觀看歷史')` 改為三個分頁標籤（觀看歷史／我的收藏／稍後再看），樣式參考 `home_tab.dart` 的 `_CategoryTab`（粉紅字＋底線，焦點時粉紅底）；**不要修改 home_tab.dart**，在 `lib/widgets/` 新增公用的 `TvTabBar` 或在 history 資料夾內自建。
  - 分頁標籤：左右鍵切換、聚焦即切換內容、下鍵進入內容第一張卡片、最左按左鍵到側邊欄。
  - 觀看歷史內容沿用現有程式（含 `refreshSilently`、載入更多），第一列按上鍵改為回到分頁標籤（原本是空操作 :264 附近）。
- 新增 `lib/screens/home/history/fav_view.dart`：上方一列收藏夾按鈕（標題＋數量），聚焦即載入該收藏夾；下方 4 欄影片格（`HistoryVideoCard` 或 `TvVideoCard`，與首頁相同尺寸），焦點接近底部時載入下一頁（不要在 build 中 setState，參考 T-A 的做法）。上下鍵在分頁標籤、收藏夾列、影片格之間移動。
- 新增 `lib/screens/home/history/watch_later_view.dart`：影片格，一次載入。
- 卡片點擊進入 `PlayerScreen(video: ...)`；卡片傳 `previewVideo`（`TvVideoCard` 已內建）。
- 未登入、空清單、載入中狀態（AC-13）。
- `HomeScreen` 對 `HistoryTab` 的 `refresh()`／`refreshSilently()` 只作用在觀看歷史分頁。

## 驗證方式

| AC | 方式 |
|---|---|
| AC-1～AC-5 | 程式碼審查＋模擬器 log（`⚡ [Prefetch] hit`）；開播速度待使用者實測 |
| AC-6～AC-8 | 模擬器：首頁往下移動超過兩列 |
| AC-9～AC-14 | 模擬器：歷史頁三個分頁（需登入帳號，待使用者測試收藏內容） |
| 全部 | `flutter analyze` 無問題、`flutter test` 通過、debug APK 建置成功 |

## 邊界與風險

- 預載請求量：0.3 秒門檻＋TTL 快取；連續快速瀏覽時舊預載以 generation 丟棄。
- 播放網址參數不一致會讓快取永遠不命中：以共用函式計算 qn／codec。
- BtrProxy 開頭快取的 range 處理是最大風險；完全落在 head 內才走快取，其他走原流程。
- 回退：`PrefetchService` 查詢一律可回 null，播放器照原流程。

## 審查紀錄

Sonnet 規格審查 10 條全部採用（以下優先於上文）：

1. **續播進度**：預載的 info 會剝除 `history` 欄位後才放進快取；播放器使用快取 info 時，依原本的 `history` 邏輯重抓 info（或只用快取取 cid／aid／pages）。最簡做法：播放器只拿快取的 `cid` 決定是否跳過 `getVideoCid`，`getVideoInfo` 照抓；改由 **playurl 與媒體開頭** 帶來加速。另外 `PlayerScreen` dispose 時呼叫 `PrefetchService.instance.invalidate(bvid)`。
2. **VIP 升級**：把「初次 qn 請求＋VIP 升級」整段抽成共用函式（例如 `PlayParams.resolvePlayInfo(bvid, cid, ...)`），預載與播放器都呼叫它，預載快取的是**最終** playInfo（升級後）；播放器先用快取的最終 playInfo，沒有才自己跑。
3. **T-A 失敗退回**：失敗或取回 0 筆時，只還原 loading 與 page 後直接 return，不進入 setState 的覆蓋分支；「是否取代清單」只看 `refresh` 或清單原本為空。
4. **prefetchHead headers**：自行設定 UA、`Referer: https://www.bilibili.com/`、`Origin`、accept-encoding，不依賴 `serve` 才初始化的 `late _headers`；之後 `serve` 收到 ExoPlayer 請求時照原邏輯處理。
5. **head 快取位置**：改在 `fetchPiece` 處理：piece 與 head 重疊的部分從 head 切出，其餘照原本抓取，自然支援部分重疊。
6. **取消**：預下載使用可取消的 http client（`http.Client` 在 cancel 時 `close()`），cancel 時中止 2MB 下載。
7. **競態**：快取存 `Future`；播放器 `take*` 時若預載仍在進行，最多 await 3 秒，逾時就自己抓。
8. **cid 優先序**：預載用與播放器相同的優先序：先 `PlaybackProgressCache.getCachedRecord`，再 info.history.cid（只用於決定 cid），再 info.cid。
9. **預覽共用快取（必做）**：`CardPreviewService` 先查 `PrefetchService` 的 cid 與 playInfo 快取（取其中的 `previewUrl`／`previewIsAvc`），沒有才自己抓。
10. **音訊**：預載 `playInfo['audioUrl']`，並確認與 `MpdGenerator` 實際放進 MPD 的音訊一致（不一致則以 MPD 用的那條為準）。
11. **歷史頁結構**：分頁列放最外層，只有內容區做載入中、空狀態、未登入的分支。
12. **onFocus 觸發**：`_loadMore` 判斷放在 `hasClients` 提前 return 之前。
