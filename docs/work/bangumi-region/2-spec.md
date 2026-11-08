# 規格：分區修正、番劇支援、QR 登入提示

需求：[1-requirements.md](1-requirements.md)；程式探索：[explore.md](explore.md)
PiliBTR（只讀參考）：`C:\presonal_project\bilibili_bata\PiliPlus`

## T-1 分區 API（AC-1）

- `lib/screens/home/home_tab.dart` 的 `HomeCategory` tid 改為新分區 ID：影視 1001、遊戲 1008、知識 1010、科技 1012、音樂 1003、舞蹈 1004、生活 1030、美食 1020、動畫 1005。番劇（`anime`）改走 T-2，不用 tid。enum 名稱不變（設定以名稱儲存）。
- `lib/services/api/video_api.dart` `getRegionVideos(tid, page)`：改呼叫 `${apiBase}/x/web-interface/region/feed/rcmd`，參數 `display_id=page`、`request_cnt=20`、`from_region=tid`，headers 用 `BaseApi.getHeaders(withCookie: true)`。回傳 `data.archives[]`，欄位為 `cover`、`author{mid,name}`、`stat{view,danmaku}`、`duration`、`pubdate`、`bvid`、`cid`。新增 `Video.fromRegionFeed`（或在 fromRecommend 相容 `cover`／`author`）。失敗時 `debugPrint` code 與 message。
- 確認 home_tab 的分頁載入（page 遞增、去重）可用；同一 display_id 重複資料要去重（bvid）。

## T-2 番劇（AC-2～AC-7）

### 資料
- `lib/models/video.dart`：新增可選欄位 `int seasonId = 0`、`int epId = 0`、`String epIndexText`（選用）；`bool get isPgc => seasonId > 0`。`bvid` 仍必填（番劇卡片可先填空字串，進播放器後由季資訊補）。
- 新檔 `lib/services/api/pgc_api.dart`：
  - `getBangumiIndex({int page})`：`/pgc/season/index/result?season_type=1&type=1&order=3&sort=0&st=1&page=&pagesize=20`，回 `data.list[]`（`season_id`、`title`、`cover`、`index_show`、`badge`、`order`）→ `List<Video>`（`seasonId`、`title`、`pic`、`badge`、副標用 `index_show`）。
  - `getSeason({seasonId, epId})`：`/pgc/view/web/season`，回 `result`（`season_id`、`title`、`episodes[]`、`user_status.progress{last_ep_id,last_time}`；登入時有）。
  - `getPgcPlayUrl({epId, cid, qn})`：`/pgc/player/web/v2/playurl`，參數 `ep_id`、`cid`、`qn`、`fnval=4048`、`fnver=0`、`fourk=1`，headers 帶 Cookie。成功時 `result.video_info` 的結構與 UGC playurl 的 `data` 相同（`dash`、`accept_quality`、`accept_description`、`support_formats`…），轉成與 `PlaybackApi.getVideoPlayUrl` 相同的回傳格式（含 `dashData`、`qualities`、`currentQuality`、`codec`），讓 MPD／BTR 流程共用。失敗時回傳 `{error: '<B站 message>（<code>）'}`。
  - 實作前用 curl 確認 v2 回傳的實際欄位路徑。

### 首頁
- `home_tab.dart`：`HomeCategory.anime` 呼叫 `PgcApi.getBangumiIndex(page)`。卡片沿用 `TvVideoCard`；`index_show`（例如「全12話」）顯示在 UP 主位置或角標。點擊時 `PlayerScreen(video: video)`（video.isPgc）。

### 播放器
- `player_action_mixin.dart` `initializePlayer`：若 `widget.video.isPgc`：
  - 呼叫 `getSeason(seasonId)`，episodes 轉成選集面板使用的結構（與 UGC `pages` 相同的 key：`cid`、`part`=「第 N 話 long_title」、`page`=序號，另帶 `ep_id`、`bvid`、`aid`、`badge`），標題用季名；起始集：`user_status.progress.last_ep_id`（有時）否則第一集，起始進度 `last_time`。
  - 取播放網址改用 `getPgcPlayUrl(epId, cid, qn)`；其餘（MPD 產生、BTR、ExoPlayer）不變。切畫質、切集同樣走 PGC 分支（`switchEpisode`、畫質切換的兩處 `MpdGenerator.generate` 呼叫點都要處理）。
  - 不呼叫 UGC 專用 API：`getVideoInfo(bvid)`、線上人數、相關影片、UP 主面板、點讚投幣（用 `aid` 可行者保留，不確定的在 PGC 時隱藏或跳過）。
  - 播完：有下一集就播下一集；最後一集停止，不載入推薦。
  - 進度回報：`PlaybackApi.reportProgress` 增加可選 `epId`、`seasonId`，PGC 時帶 `epid`、`sid`、`type=4`、`sub_type=1`。
  - 錯誤：PGC playurl 失敗時 `errorMessage` 顯示 B站訊息（例如「抱歉您所在地區不可觀看！（-10403）」），不重試 3 次。
- 彈幕：用該集 `cid` 照舊取得。

## T-3 QR 登入（AC-8）

- `lib/screens/home/login/login_view.dart`：
  - 說明文字改為兩行：「請用 B站手機 App 掃描（建議更新至最新版）」「若手機顯示驗證頁，請按『是我的帳號，驗證登入』完成驗證」。
  - status `scanned` 顯示「已掃描，請在手機上確認」。
  - `expired` 時自動重新 `_generateQrCode()`（最多連續 5 次，之後顯示「QR Code 已過期，按確認鍵重新產生」）。
  - `error` 時顯示 `錯誤：<message>（<code>）`，`AuthApi.pollTvLogin` 回傳 code 與 message；網路錯誤顯示「網路錯誤，重試中…」並繼續輪詢。
- `lib/services/api/auth_api.dart`：`pollTvLogin` 的 `mid` 用 `BaseApi.toInt`；`http.post` 帶 `BaseApi.getHeaders()`（UA、Referer、buvid3）。

## 任務

| ID | 內容 | 相依 |
|---|---|---|
| T-1 | 分區 API | — |
| T-2 | 番劇 | T-1（同改 home_tab，同一位實作者先後做） |
| T-3 | QR 登入 | — |
| T-4 | analyze、debug 建置、模擬器驗證 | T-1～T-3 |

## 驗證

| AC | 方式 |
|---|---|
| AC-1、AC-2 | 模擬器截圖各分區、番劇分頁 |
| AC-3～AC-5、AC-7 | 模擬器播放番劇（選可播與 -10403 各一部）、切集、切畫質、播到下一集 |
| AC-6 | logcat 看 heartbeat 回應 code |
| AC-8 | 模擬器登入頁截圖；過期自動刷新以縮短等待或程式審查驗證 |
| AC-9 | `flutter analyze` |

## 風險

- PGC 回傳結構與 UGC 略有不同（`video_info` 包裝）；以 curl 實測為準。
- 番劇有大會員、預告集（`badge`），播放失敗時顯示訊息即可。
- 播放器 mixin 很大（1300+ 行），PGC 分支以集中判斷（`isPgc`）方式加入，避免散落。

## 審查紀錄

2026-11-08：agy 審查，見 [review-spec.md](review-spec.md)。全部採用，實作以本節為準：

- R1：`getSeason` 的 `episodes` 為空時，改用 `sections[].episodes`（第一個非空的正片區塊）。
- R2：`Video` 不可變；播放器新增可變狀態 `currentBvid`、`currentEpId`、`currentSeasonId`，切集時更新。進度快取的 key：PGC 用 `pgc_<seasonId>`（存 epId＋秒數），UGC 照舊用 bvid；心跳用該集的 bvid。
- R3：`switchEpisode` 由 cid 查出 ep_id 更新 `currentEpId`；`switchEpisode`、`switchQuality` 檢查 `playInfo['error']`，失敗顯示訊息並返回，不可對 null 強制解包。
- R4：playurl 回錯誤（例如 -10403、-404、大會員限定）時跳出 codec 迴圈，直接顯示錯誤，不重複請求。
- R5：試看（`is_preview == 1` 或 `accept_description` 含「试看」）時提示「此集為大會員專屬，目前僅提供試看」，播完不自動跳下一集，不回報完播。
- R6：VIP 畫質升級的 playurl 呼叫也要走 PGC 分支。
- R7（簡化設計）：不另做 PGC 的 DASH 解析，改在 `PlaybackApi.getVideoPlayUrl` 加可選參數 `int? epId`；`epId != null` 時請求 `/pgc/player/web/v2/playurl`，以 `result.video_info` 當作 `data` 走既有解析。`PgcApi` 只負責番劇索引與季資訊。
- R8～R10：見 review-spec.md 第 8～10 項（選集標題格式改為「第 N 話 標題」、其他項依原文修正）。
