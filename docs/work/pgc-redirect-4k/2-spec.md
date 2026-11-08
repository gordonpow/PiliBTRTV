# 規格：番劇轉向與 4K 畫質／解碼上限

需求：[1-requirements.md](1-requirements.md)

## 設計

### A. 番劇轉向（AC-1、AC-2、AC-3）

資料流：

```
歷史紀錄 business=='pgc' ──> Video(seasonId=kid, epId=history.epid) ──> 番劇模式（既有）
其他入口 bvid ──> PlayerScreen (UGC) ──> view API
      └─ data.redirect_url 符合 /bangumi/play/(ep|ss)(\d+)
           ss → seasonId；ep → getSeason(epId) 取 seasonId
           └─ Navigator.pushReplacement(PlayerScreen(Video(seasonId, epId)))
進入時 seasonId==0 且 epId>0 ──> 同上，以 epId 查 seasonId 後 pushReplacement
```

- `history.kid` 是番劇的 season_id（PiliPlus 刪除歷史用 `pgc_<kid>`，`pages/history/controller.dart:114`）。`kid` 為 0 時不設 `seasonId`，改由播放器以 `epId` 解析（見上）。
- `Video.isPgc` 維持 `seasonId > 0`，`progressCacheKey`（`player_state_mixin.dart:39`）與首頁去重（`home_tab.dart:180`）不受影響。
- 轉向時新 `Video` 帶原本的 `title`、`pic`，`bvid` 為空字串。番劇起始集沿用 `_setupPgcSeason` 的順序（伺服器紀錄 > 本地快取 > `epId` > 第一集）。
- 轉向發生在建立 `videoController` 之前，`initializePlayer` 直接 `return`，不會留下播放器資源。
- 轉向失敗（查不到 season）時：
  - 由 view 的 `redirect_url` 觸發：繼續原本的 UGC 流程。
  - 進入時 `bvid` 為空、只有 `epId`：顯示 `getSeason` 的番劇錯誤訊息，不走 UGC（否則必定顯示「獲取影片資訊失敗」）。
- `pushReplacement` 前檢查 `mounted`。
- 網址解析抽成純函式 `PgcApi.parseBangumiUrl(String url) → ({int seasonId, int epId})?`（`/bangumi/play/ss<id>` 或 `/bangumi/play/ep<id>`），方便單元測試。
- 自動連播推薦影片走 `pushReplacement(PlayerScreen(...))`（`player_action_mixin.dart:909`），會經過 `initializePlayer`，所以也會轉向。

### B. 解碼能力與畫質上限（AC-4、AC-5）

Native（`MainActivity.kt`，channel `com.bili.tv/codec`）新增兩個方法：

| 方法 | 參數 | 回傳 |
|---|---|---|
| `canHwDecode` | `codec`（`avc`／`hevc`／`av1`）、`width`、`height`、`fps`（double，≤0 表示不檢查幀率） | `bool`：逐一檢查解碼器，**同一個**解碼器同時滿足：非 encoder、名稱不以 `.secure` 結尾、是硬體、支援該 MIME、`videoCapabilities.areSizeAndRateSupported(w, h, fps)`（fps≤0 時用 `isSizeSupported`）為真 |
| `isHdrDisplay` | 無 | `bool`：`display.hdrCapabilities.supportedHdrTypes` 非空（API 24 以上；以下回 false） |

- 硬體判斷：API 29 以上用 `MediaCodecInfo.isHardwareAccelerated`；以下沿用現有名稱規則（不含 `google`、`software`、`sw`，不以 `c2.android` 開頭）。抽成一個共用函式，`getHardwareDecoders` 也改用它。
- MIME 對應：`avc`→`video/avc`、`hevc`→`video/hevc`、`av1`→`video/av01`。
- 例外時回 `true`（無法判斷就不阻擋，維持現有行為）。

Dart（`lib/services/codec_service.dart`）：

- `static Future<bool> canHwDecode(String codec, int width, int height, double fps)`：以 `'$codec:$width:$height:$fps'` 快取結果；呼叫失敗回 `true`。
- `static Future<bool> isHdrDisplay()`：快取；失敗回 `false`。
- `static String? codecFamily(String codecs)`：`avc*`→`avc`；`hev*`/`hvc*`/`dvh*`/`dvhe*`→`hevc`；`av01*`/`av1*`→`av1`；其他 null。
- `static double parseFps(dynamic v)`：接受 num 或字串（如 `"29.970"`、`"30000/1001"`），失敗回 0。

播放網址（`lib/services/api/playback_api.dart` 的 DASH 分支，約 197-343 行）：

- 新增私有函式 `_hwOk(stream)`：以 `codecFamily(codecs)`、`width`、`height`、`frameRate`（或 `frame_rate`）呼叫 `canHwDecode`；family 為 null 回 false。
- 自動編碼（`userCodec == auto` 且 `forceCodec == null`）：依 AV1 > HEVC > AVC 的順序，在 `candidateVideos` 中選第一個 `_hwOk` 為真的串流（`fallbackToAvc` 為真時只看 AVC）。都沒有時，先選該畫質的 AVC 串流，再沒有才用既有兜底（`candidateVideos.first`）。
- 使用者指定編碼與 `forceCodec` 路徑：不改。
- 回傳的 map 新增：
  - `hwDecodable`（bool）：最終選到的串流 `_hwOk` 結果。
  - `maxDecodableQn`（int?）：`dash.video` 中 `_hwOk` 為真、且編碼屬於「這次呼叫允許的家族」的串流裡最大的 `id`；HDR 顯示不支援時排除 125、126。沒有任何符合的串流時為 null。允許的家族：`forceCodec` 非 null 且非 auto → 該家族；否則使用者指定編碼（非 auto）→ 該家族；否則 `fallbackToAvc` → 只有 avc；否則 avc、hevc、av1 都可以。
- durl 分支：`hwDecodable: true`、`maxDecodableQn: null`。

大會員自動升級（`player_action_mixin.dart:205-248`）：

- 目標畫質：`supportedQns` 中 ≤ 上限的最大值。上限：`maxDecodableQn` 不為 null 時為 `maxDecodableQn`，否則不限制。另外 `!isHdrDisplay` 時排除 125、126。
- 目標畫質 ≤ 目前畫質時不升級。
- 升級結果 `hwDecodable == false` 時捨棄，沿用升級前的 `playInfo`（其 `currentQuality` 不變，畫質顯示一致），並 `debugPrint` 原因。每次 `getVideoPlayUrl` 迴圈最多升級請求一次（維持現狀）。
- `maxDecodableQn` 只代表首次回應的 `dash.video` 內容。目標畫質不在首次回應中時（例如 8K 只在請求時才出現），靠升級後的 `hwDecodable` 檢查把關。

### C. BTR 依碼率調整執行緒（AC-6）

- `BtrProxy.wrap(url, {backups, int bandwidth = 0})`：`_BtrSource` 保存 `bandwidth`。同一 URL 重用既有來源時，以較大的值更新。
- `_Pump.run` 的執行緒數改為 `source.threads`：`BtrConfig.autoThreads` 且 `bandwidth >= 8000000` 時為 16，否則為 `BtrConfig.playbackThreads`（手動設定時不變）。
- `mpd_generator.dart` 呼叫 `wrap` 時傳入 `stream['bandwidth']`（轉 int，失敗為 0）。
- `_probe` 的 debug log 改印 `threads`（實際使用值）。
- `btrDio` 用預設 `IOHttpClientAdapter`，`HttpClient.maxConnectionsPerHost` 預設不限制，16 執行緒有效。

## 要改的檔案

| 檔案 | 改什麼 | 任務 |
|---|---|---|
| `lib/models/video.dart` | `fromHistory`：`business=='pgc'` 時設 `seasonId`、`epId`，`epIndexText` 用 `show_title` | T-1 |
| `lib/services/api/pgc_api.dart` | `getSeason({int seasonId = 0, int epId = 0})`：`seasonId>0` 用 `season_id`，否則用 `ep_id` | T-1 |
| `lib/services/bilibili_api.dart` | `getPgcSeason` 包裝同步新增 `epId` | T-1 |
| `lib/screens/player/mixins/player_action_mixin.dart` | 番劇轉向（`initializePlayer` 開頭與 view 之後）；大會員升級上限 | T-2、T-4b |
| `android/app/src/main/kotlin/com/bili/tv/bili_tv_app/MainActivity.kt` | `canHwDecode`、`isHdrDisplay`、共用硬體判斷 | T-3 |
| `lib/services/codec_service.dart` | `canHwDecode`、`isHdrDisplay`、`codecFamily`、`parseFps` | T-3 |
| `lib/services/api/playback_api.dart` | 自動編碼檢查解析度與幀率；回傳 `hwDecodable`、`maxDecodableQn` | T-4a |
| `lib/services/btr/btr_proxy.dart`、`lib/services/mpd_generator.dart` | 依碼率調整執行緒 | T-5 |

## 任務

| ID | 內容 | 相依 |
|---|---|---|
| T-1 | 歷史紀錄番劇解析；`getSeason` 支援 `epId` | — |
| T-2 | 播放器番劇轉向 | T-1 |
| T-3 | Native 與 Dart 解碼能力查詢 | — |
| T-4a | playback_api 自動編碼與回傳欄位 | T-3 |
| T-4b | 大會員升級上限（只讀 `hwDecodable`、`maxDecodableQn`、`CodecService.isHdrDisplay`） | T-3、T-4a 的介面 |
| T-5 | BTR 依碼率調整執行緒 | — |

分派：子代理 A 做 T-1、T-2、T-4b（所有 `player_action_mixin.dart` 的修改）；子代理 B 做 T-3、T-4a、T-5。兩者的介面以本規格為準，可平行。

## 驗證方式

| AC | 方式 |
|---|---|
| AC-1、AC-2 | 程式碼審查；實機測試由使用者做（歷史紀錄點銀魂、熱門點番劇影片） |
| AC-3 | `curl pgc/view/web/season?ep_id=326317` 已確認回傳 `season_id 33577`；程式碼審查 |
| AC-4、AC-5 | 程式碼審查；實機由使用者做（4K 影片、看設定選單的畫質與 CDN 狀態） |
| AC-6 | 程式碼審查 |
| AC-7 | `flutter analyze`、`flutter build apk --release --split-per-abi` |
| AC-2～AC-4（純函式） | 單元測試 `test/pgc_codec_utils_test.dart`：`PgcApi.parseBangumiUrl`、`CodecService.codecFamily`、`CodecService.parseFps`（`"29.970"`、`"30000/1001"`、空字串、數字） |

## 邊界情況與風險

- `kid` 不是 season_id 的情況：`getSeason` 失敗會顯示番劇錯誤。緩解：`seasonId` 查詢失敗且 `epId > 0` 時，以 `epId` 再查一次。
- view API 失敗（例如地區限制回非 0）：沒有 `redirect_url`，維持原本錯誤訊息。
- 部分電視的 `areSizeAndRateSupported` 回報保守（實際能播卻回 false）：會少升一級畫質，可接受；使用者仍可手動選畫質。
- 杜比視界串流的 codecs 可能是 `dvh1`／`dvhe`：歸類為 HEVC，另外受 HDR 顯示檢查限制。
- 不檢查 profile（10-bit HEVC Main10、AV1 10-bit）：接受風險。HDR 畫質另受顯示器檢查限制；一般 4K 多為 8-bit。
- `canHwDecode` 每個串流呼叫一次 platform channel，有快取，影響很小。
- 回退：每個任務獨立，可個別 revert。

## 追加（2026-11-08，使用者回報「4K FPS 很低，官方 App 很順」，電視 Sony BRAVIA 4K VH22、Android TV 12）

### 新發現的根因

`MpdGenerator.generate`（`lib/services/mpd_generator.dart:27-35`）把 `dash.video` 的**所有**串流（所有畫質、所有編碼）寫進同一個 AdaptationSet。ExoPlayer 會自己選軌，可能選到 AV1／HEVC 4K。硬體解碼器不支援時，會改用軟體解碼器，造成 FPS 很低。`playback_api` 選的 `selectedVideo` 只影響顯示的 `codec` 與預覽，實際播放的軌不受控制；手動選畫質也一樣。

### 新增驗收條件

- **AC-8**：MPD 只包含 `playback_api` 選定的那一個影片串流（音訊不變），播放的畫質與編碼和程式選擇一致。
- **AC-9**：手動選畫質時，若該畫質沒有可硬解的串流（`hwDecodable == false`）：
  - 有可硬解的較低畫質（`maxDecodableQn`）：改用該畫質，並顯示提示「此電視無法順暢播放 <畫質>，已改用 <畫質>」。
  - 沒有：照使用者選的播放，並顯示提示「此電視可能無法順暢播放 <畫質>」。

### 新增任務

| ID | 內容 |
|---|---|
| T-6 | `playback_api.dart` DASH 回傳的 `dashData` 改為 `{...data['dash'], 'video': [selectedVideo]}` |
| T-7 | `player_action_mixin.dart` 的 `switchQuality`：依 AC-9 處理，改用較低畫質時重新請求 `getVideoPlayUrl(qn: maxDecodableQn)` |

### 取捨

- 單一串流後，ExoPlayer 不再自動依網速降畫質。原本混合編碼的 AdaptationSet 本來就不適合做自適應切換；官方 App 也是固定畫質。網路不足時使用者可手動降畫質。

## 審查紀錄

規格審查（Sonnet，2026-11-08）：

| # | 意見 | 處理 |
|---|---|---|
| 1 | `maxDecodableQn` 沒考慮限制編碼（降級 AVC、指定編碼） | 採用：只算允許的家族 |
| 1b | 升級捨棄時再以 `maxDecodableQn` 升一次 | 不採用：家族限制後上限已準確，再多一次請求不值得 |
| 2 | 捨棄升級時 `currentQuality` | 採用：寫明沿用升級前結果 |
| 3 | 轉向的 `mounted`、只有 `epId` 失敗時錯誤訊息 | 採用 |
| 3b | 同一 State 內切換 bvid 不會轉向 | 不採用：自動連播走 `pushReplacement`，分 P 切換不換 bvid |
| 4 | 同一解碼器判斷、排除 encoder 與 `.secure`、10-bit | 採用前兩項；10-bit 列為風險 |
| 5 | 移除 `hasXxxHw` 的重複判斷 | 採用：自動分支只用 `_hwOk` |
| 6 | 兜底選最難解的串流 | 採用：先選 AVC |
| 7 | 連線上限、log | 已確認無上限；log 採用 |
| 8 | 單元測試 | 採用 |

## 實作偏差

（實作時填寫）

- T-4a：`_hwOk` 與 `maxQn` 以 `getVideoPlayUrl` DASH 分支內的區域函式實作（需要 `forceCodec`、`videos` 等區域變數），非類別私有方法。移除不再使用的 `getHardwareDecoders` 呼叫。
- T-4a：自動編碼依家族順序逐一在 `candidateVideos` 找「家族相符且 `_hwOk`」的串流。
