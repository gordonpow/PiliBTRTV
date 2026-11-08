### 1. Project A 影片播放流程與 UGC 假設

**呼叫流程順序**：
1. **觸發與初始化**：[`PlayerScreen.initState`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/player_screen.dart#L46-L48) 呼叫 [`PlayerActionMixin.initializePlayer`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L55-L104)。
2. **獲取影片詳情 (view API)**：[`PlayerActionMixin.initializePlayer`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L63) 呼叫 [`PlaybackApi.getVideoInfo`](file:///C:/presonal_project/PiliBTRTV/lib/services/api/playback_api.dart#L14-L35)，請求 `GET https://api.bilibili.com/x/web-interface/view?bvid=$bvid`。
3. **建構分 P 與選集面板**：
   - 在 [`player_action_mixin.dart:74`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L74) 解析 `episodes = videoInfo['pages'] ?? []`，並依歷史/快取或首集解析 `cid`。
   - 控制列點擊「選集」設 `showEpisodePanel = true`，在 [`player_screen.dart:253-266`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/player_screen.dart#L253-L266) 掛載 [`EpisodePanel`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/widgets/episode_panel.dart)；切換分 P 呼叫 [`switchEpisode(newCid)`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L1121)。
4. **請求播放地址 (playurl)**：
   - 呼叫 [`PlaybackApi.getVideoPlayUrl`](file:///C:/presonal_project/PiliBTRTV/lib/services/api/playback_api.dart#L62-L88)（由 [`player_action_mixin.dart:178`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L178) 呼叫，支援 VIP 畫質升級）。
   - **端點**：`GET https://api.bilibili.com/x/player/playurl` (WBI 簽名)。
   - **參數**：`bvid`, `cid`, `qn`, `fnval='4048'` (DASH 全格式), `fnver='0'`, `fourk='1'`。DASH 串流透過 [`MpdGenerator`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L247) 與內部記憶體伺服器 [`LocalServer`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L250) 提供播放。
5. **進度 / 心跳上報 (Heartbeat)**：
   - 暫停、退出或後台事件呼叫 [`reportPlaybackProgress()`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L654)。
   - 透過 [`PlaybackApi.reportProgress`](file:///C:/presonal_project/PiliBTRTV/lib/services/api/playback_api.dart#L312-L355) 請求 `POST https://api.bilibili.com/x/click-interface/web/heartbeat`，參數：`bvid`, `cid`, `played_time`, `real_played_time`, `start_ts`, `csrf`。

**Video Model 欄位 ([`models/video.dart:1-21`](file:///C:/presonal_project/PiliBTRTV/lib/models/video.dart#L1-L21))**：
`bvid` (必填), `title` (必填), `pic` (必填), `ownerName`, `ownerFace`, `ownerMid`, `view`, `danmaku`, `duration`, `pubdate`, `progress`, `viewAt`, `cid`, `historyPage`, `historyPart`, `historyVideos`, `badge`, `isLive`。

**假設 UGC (僅 bvid) 之處**：
- [`models/video.dart`](file:///C:/presonal_project/PiliBTRTV/lib/models/video.dart#L3)：無 `ep_id`、`season_id`，且 `bvid` 為必填字串。
- [`playback_api.dart:18`](file:///C:/presonal_project/PiliBTRTV/lib/services/api/playback_api.dart#L18)：`getVideoInfo` 僅支援 `bvid` 查詢 `/x/web-interface/view`。
- [`player_action_mixin.dart:74`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L74)：分 P 假設結構為 `pages`（PGC 回傳結構為 `episodes` / `sections`）。
- [`playback_api.dart:88`](file:///C:/presonal_project/PiliBTRTV/lib/services/api/playback_api.dart#L88)：`getVideoPlayUrl` 僅請求 UGC 端點 `/x/player/playurl`。
- [`playback_api.dart:322`](file:///C:/presonal_project/PiliBTRTV/lib/services/api/playback_api.dart#L322)：心跳上報缺少 PGC 必需之 `sid`、`epid`、`type: 4`。
- [`player_action_mixin.dart:626`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L626)：自動連播直接請求 UGC 的 `getRelatedVideos(bvid)`。

---

### 2. Project A 首頁分類載入與播放跳轉

**HomeCategory 列舉與 API 映射 ([`screens/home/home_tab.dart:518-535`](file:///C:/presonal_project/PiliBTRTV/lib/screens/home/home_tab.dart#L518-L535), [`L139-156`](file:///C:/presonal_project/PiliBTRTV/lib/screens/home/home_tab.dart#L139-L156))**：
- `recommend('推薦', 0)`：呼叫 `BilibiliApi.getRecommendVideos(idx)`。
- `popular('熱門', 0)`：呼叫 `BilibiliApi.getPopularVideos(page)`。
- 分區分類：`anime('番劇', 13)`、`movie('影視', 181)`、`game('遊戲', 4)`、`knowledge('知識', 36)`、`tech('科技', 188)`、`music('音樂', 3)`、`dance('舞蹈', 129)`、`life('生活', 160)`、`food('美食', 211)`、`douga('動畫', 1)`。
  - **載入 API**：所有分區（**含番劇**）皆呼叫 `BilibiliApi.getRegionVideos(tid, page)`，走 UGC 分區影片列表（`/x/web-interface/dynamic/region`），**非 PGC 番劇 API**。

**卡片開啟播放器**：
- [`screens/home/home_tab.dart:211-215`](file:///C:/presonal_project/PiliBTRTV/lib/screens/home/home_tab.dart#L211-L215) `_onVideoTap(Video video)`：
  點擊或遙控器確認鍵觸發後，使用 `Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(video: video)))` 導向播放頁。

---

### 3. Project B PGC (番劇) 支援端點與請求代碼

| 項目 | 常數名稱 ([`lib/http/api.dart`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/http/api.dart)) | 端點 | 請求代碼位置 |
| :--- | :--- | :--- | :--- |
| **(a) 排行 / 索引** | `Api.pgcRank`<br>`Api.pgcSeasonRank`<br>`Api.pgcIndexResult`<br>`Api.pgcTimeline` | `/pgc/web/rank/list`<br>`/pgc/season/rank/web/list`<br>`/pgc/season/index/result`<br>`/pgc/web/timeline` | [`lib/http/video.dart:1125`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/http/video.dart#L1125) (`pgcRankList`)<br>[`lib/http/video.dart:1148`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/http/video.dart#L1148) (`pgcSeasonRankList`)<br>[`lib/http/pgc.dart:15`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/http/pgc.dart#L15) (`pgcIndexResult`)<br>[`lib/http/pgc.dart:93`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/http/pgc.dart#L93) (`pgcTimeline`) |
| **(b) 劇集詳情與單集** | `Api.pgcInfo` | `/pgc/view/web/season` | [`lib/http/search.dart:153-169`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/http/search.dart#L153-L169) (`SearchHttp.pgcInfo`)，帶 `season_id` 或 `ep_id`，回傳 [`PgcInfoModel`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/models_new/pgc/pgc_info_model/result.dart) 包含 `episodes`/`sections`（單集 [`EpisodeItem`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/models_new/pgc/pgc_info_model/episode.dart) 內有 `ep_id`, `aid`, `bvid`, `cid`）。入口在 [`lib/utils/page_utils.dart:623`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/utils/page_utils.dart#L623) (`viewPgc`)。 |
| **(c) PGC 播放網址** | 主: `Api.ogvUrl`<br>備: `Api.pgcUrl` | `/ogv/player/playview`<br>`/pgc/player/web/v2/playurl` | [`lib/http/video.dart:300-350`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/http/video.dart#L300-L350) (`VideoHttp.videoUrl`)。<br>**參數**：`ep_id`, `season_id`, `cid`, `qn`, `fnval: 4048`, `fourk: 1`, `fnver: 0`, `biz_type: 'ogv'`, `scene: 'normal'`, `from_client: 'BROWSER'`, `app_id: 100`, `try_look: 1`, `wbi` 簽名與裝置參數。若遇 DRM (`is_drm: true`) 自動降級改請求備用端點。 |
| **(d) PGC 心跳進度** | `Api.heartBeat`<br>`Api.heartBeatMobile` | `/x/click-interface/web/heartbeat`<br>`/x/report/heartbeat/mobile` | [`lib/http/video.dart:830-855`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/http/video.dart#L830-L855) (`heartBeat`)，帶 `bvid`, `cid`, `epid`, `sid`, `type: 4`, `played_time`, `csrf`。App 心跳在 [`lib/http/video.dart:859`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/http/video.dart#L859) 帶 `type: 4`, `spmid: 'pgc.pgc-video-detail.0.0'`。 |

---

### 4. Project B 地區限制與 VIP 單集處理

1. **角標解析與顯示 (Badge)**：
   - [`lib/models_new/video/video_detail/episode.dart:22-26`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/models_new/video/video_detail/episode.dart#L22-L26)：`badgeType` 將「預告」轉為灰標 `.gray`，「限免」轉為綠標 `.free`，其餘（如「VIP」、「會員」、「付費」）轉為主題粉標 `.primary`。
   - [`lib/pages/episode_panel/view.dart:616-629`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/episode_panel/view.dart#L616-L629)：選集列表中若 `isCharging == true` 顯示紅標「充電專屬」，其餘單集根據 `badge` 與 `badgeType` 渲染 `PBadge`。
2. **錯誤碼與限制提示 (如 -10403)**：
   - **Playurl 失敗原因**：[`lib/http/video.dart:385-391`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/http/video.dart#L385-L391) 解析伺服器回傳之 `not_playable_reason` (`code` 與 `message`)。
   - **錯誤碼對應**：[`lib/http/video.dart:427-433`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/http/video.dart#L427-L433) `_parseVideoErr` 僅針對 `-404` 與 `87008` (包月充電) 做文字自訂；**對 `-10403` (地區限制) 無特判分支，直接落入預設 `錯誤($code): $msg`**，直接 Toast 顯示 B 站回傳之錯誤訊息。
   - **專屬試看提示**：[`lib/pages/video/controller.dart:1052-1057`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/controller.dart#L1052-L1057) 當 `acceptDesc` 含「试看」時彈出「該影片為專屬影片，僅提供試看」。
   - **未登入降級**：[`lib/pages/video/controller.dart:440-444`](file:///C:/presonal_project/bilibili_bata/PiliPlus/lib/pages/video/controller.dart#L440-L444) PGC 未登入時將 `_actualVideoType` 改設為 UGC 嘗試試看播放。
   - **無內建解除地區限制代理**：專案 B 無內建解除港澳台版權限制之反向代理/解鎖機制。
