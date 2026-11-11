# 規格：CC 字幕與 B 站內容翻譯（#17 第一階段）

A = `C:\presonal_project\bilibili_bata\PiliPlus`（參考），B = 本專案。

## 設計

### 1. 相依套件
- `pubspec.yaml` 加 `google_mlkit_translation: ^1.0.1`（A:pubspec.yaml:185 同版）。Android `minSdk` 24 已滿足。

### 2. 翻譯服務 `lib/services/translate/content_translator.dart`
- 移植 A `lib/services/translate/translator.dart` 的 ML Kit 部分（不移植 DeepL／Google Cloud）。
- API：
  - `bool get enabled`：`SettingsService.translateContent && ZhConvert.script == ZhScript.english && modelReady`。
  - `Future<bool> isModelDownloaded()`、`Future<void> downloadModel()`（Wi-Fi 不限制；回報失敗原因：無 Play 服務／網路）。
  - `String? cached(String zh)`：同步查快取。
  - `Future<String?> translate(String zh)`：查快取→ML Kit `OnDeviceTranslator(chinese→english)` 單例→寫快取。同時最多 2 個翻譯在跑（佇列），同字串進行中的請求合併。
  - `Future<List<String>> translateBatch(List<String>)`：字幕用，逐句走同一佇列。
  - 快取：記憶體 LRU 5000 條＋磁碟 JSON（app documents `translate_cache.json`，延遲寫入，啟動載入）。
  - 輸入先做繁→簡？不做；ML Kit `chinese` 直接吃繁簡（實作時以實測為準，記入實作偏差）。
- 只翻含中日韓字元的字串，其他原樣返回。

### 3. 內容文字元件 `lib/widgets/content_text.dart`
- `ContentText(String text, {style, maxLines, overflow, ...})`：
  - 一律做既有繁簡轉換（`ZhConvert` 的轉換，但**跳過 I18nPack 字典**，AC-11）。需在 `zh_convert.dart` 提供 `convertContent(String)`（只做繁簡，不查字典）。
  - `ContentTranslator.enabled` 時：有快取直接顯示英文；沒有則先顯示原文並非同步翻譯，完成後 `setState`（mounted 檢查）。
- `ConditionalMarquee` 加 `content: bool` 參數，`true` 時同樣走 ContentText 的邏輯。
- 套用處（標題／UP 主名稱／直播標題／簽名）：
  - `lib/widgets/tv_video_card.dart:171,181,205`
  - `lib/widgets/history_video_card.dart:256,274,297`
  - `lib/screens/player/widgets/up_next_card.dart:94`
  - `lib/screens/player/widgets/episode_panel.dart:167`
  - `lib/screens/player/widgets/controls_overlay.dart:65,122`
  - `lib/widgets/tv_live_card.dart:37,44,133,143,165`
  - `lib/screens/live/live_player_screen.dart:933`
  - `lib/screens/up_space/up_space_screen.dart:328,357,369`
  - 實作時再以 grep 確認 `video.title`、`ownerName`、`uname`、`sign` 的顯示處無遺漏。

### 4. CC 字幕
- API：`lib/services/api/subtitle_api.dart`
  - `getSubtitles({aid, cid, bvid, epId, seasonId})`：`GET https://api.bilibili.com/x/player/wbi/v2`，以 `BaseApi.ensureWbiKeys`＋`SignUtils.signWithWbi` 簽名、`getHeaders(withCookie: true)`（參考 playback_api.dart:110-124）。解析 `data.subtitle.subtitles[]`：`id, lan, lan_doc, subtitle_url, type`（type==1 為 AI）。未登入或無字幕回空清單。
  - `getSubtitleBody(url)`：`https:` 補前綴，取 `body[]` 的 `from, to, content`。
- 模型 `lib/models/subtitle.dart`：`SubtitleTrack {id, lan, lanDoc, url, isAi}`、`SubtitleLine {from, to, content}`。
- 狀態（player_state_mixin）：`List<SubtitleTrack> subtitleTracks`、`int subtitleIndex`（-1 關閉）、`List<SubtitleLine> subtitleLines`、`String? currentSubtitle`、`bool subtitleMachineEn`（選了機器翻譯軌）。
- 載入：與 `loadDanmaku()` 同處觸發（player_action_mixin.dart:504、:718、:2631 附近），換集／換 P 時清空重載；用 cid 作廢舊請求。
- 預設選擇（AC-3）：`SettingsService.subtitleEnabled`（bool，預設 false）為 true 時自動選：英文介面＝lan 以 `en` 或 `ai-en` 開頭 > 中文（zh*/ai-zh）；否則中文。非 AI 優先於 AI。
- 機器翻譯軌（AC-10）：英文介面且 `ContentTranslator.enabled` 且沒有英文軌、有中文軌時，選單多一項「English（機器翻譯）」：以中文軌內容 `translateBatch`，翻好前顯示原文，逐句替換。
- 同步（AC-2）：在 `_onPlayerStateChange`（:1458，彈幕同步旁 :1479）以二分搜尋找 `from <= pos < to` 的行，變更時才更新 `currentSubtitle`。seek／重載後同樣由位置驅動，不需額外處理。
- 顯示：`lib/screens/player/widgets/subtitle_layer.dart`，插在 `player_screen.dart` 彈幕層之後、控制層之前（:145 後）；置中底部，白字黑色半透明背景，字級 28，最多 2 行；`showControls` 為 true 時往上移 150。內容走 `ZhConvert.convertContent`（AC-5；機器翻譯軌直接顯示英文）。
- 選單（AC-1、AC-4）：`settings_panel.dart` 加 `SettingsMenuType.subtitle` 與 main index 6「字幕」（value＝目前軌名稱或「關閉」）；只有 `subtitleTracks` 非空時顯示（main maxIndex 依此為 5 或 6）。次級選單：「關閉」＋各軌（lanDoc，AI 標「（自動生成）」）＋機器翻譯項；目前選擇標「當前」。比照 playEnd 次級選單修改 `player_event_mixin.dart`（:573-577、:583-604、:636-641、:647、:652）與 `player_action_mixin.dart` `activateSetting`（:2687-2711）。選定即設定 `SettingsService.subtitleEnabled = (選的不是關閉)`。

### 5. 設定頁（AC-6、7、13）
- `interface_settings.dart:213-224` 英文區塊內、「更新語言包」之後加 `SettingToggleRow`「翻譯 B 站內容」，subtitle「使用 Google ML Kit 在本機翻譯影片標題、UP 主名稱與字幕（需下載約 30MB 模型）」。
- 開啟時：模型未下載→顯示下載進度對話框（可沿用 i18n 下載對話框樣式，返回鍵可取消）；成功才存檔；失敗 toast「翻譯模型下載失敗：<原因>」並保持關閉。
- `SettingsService`：`translateContent`（bool，key `translate_content`）、`subtitleEnabled`（bool，key `subtitle_enabled`），慣例同 :287-298。
- `settings_index.dart` 加「翻譯 B 站內容」搜尋項（englishOnly）。

## 任務
- T-1：套件、`ContentTranslator`、`convertContent`、`ContentText`、`ConditionalMarquee content`、設定頁開關與下載、單元測試（快取、只翻含 CJK、合併重複請求；ML Kit 以介面注入假實作）。
- T-2（相依 T-1 的 `ContentTranslator` 介面，可平行用介面先寫）：字幕 API／模型／載入／同步／顯示／選單＋單元測試（解析、二分搜尋、預設選擇規則）。
- T-3（相依 T-1）：各顯示處改用 `ContentText`。
- T-4：新增介面字串補 `i18n/en.json`（extract 未翻譯 0）；三個 ABI APK 建置成功並記錄大小差異。

## 驗證對應
| AC | 方式 |
|---|---|
| AC-1～5 | 單元測試（解析、同步查找、預設選擇）；模擬器播有字幕影片截圖（待使用者） |
| AC-6～9、13 | 單元測試（快取、佇列）；模擬器英文模式（ML Kit 需 Play 服務，TV 模擬器若無則實機） |
| AC-10 | 單元測試（機器翻譯軌出現條件） |
| AC-11、12 | 程式審查：ContentText 不呼叫 I18nPack；翻譯關閉時路徑不變 |
| AC-14 | analyze、test、三 ABI 建置 |

## 邊界與風險
- 未登入時 v2 可能不給字幕：顯示「無字幕」即可，不實作 gRPC（記為已知限制）。
- `subtitle_url` 可能為空（需登入）：略過該軌。
- ML Kit 在無 Play 服務裝置：下載失敗並提示，開關保持關閉。
- 大量卡片同時翻譯：佇列上限 2，畫面外的 widget dispose 後放棄結果。
- 快取檔損毀：讀取失敗清空重建。
- APK 增加約 6～16MB（使用者已接受）。
- 回退：revert；設定 key 不影響舊版。

## 審查後修訂（覆蓋上文相衝突的部分）

- R-1（AC-7 調整）：`google_mlkit_translation` 不回報下載進度（A translator.dart:310），對話框為「下載中…（不確定進度）」＋返回鍵取消；失敗訊息為通用「翻譯模型下載失敗」＋底層例外文字，不承諾區分無 Play 服務或網路。
- R-2 `convertContent(raw)`：三種 script 行為——繁體：與現有 convert 的繁簡轉換相同；簡體：與現有 convert 相同（含 `_exact`）；英文：轉繁體顯示（不查字典）。加測試：繁／簡模式下一般文字 `convertContent == convert`（字典沒命中的情況）。ContentText 只在英文模式改變行為（AC-12）。
- R-3 翻譯來源：快取 key 與 ML Kit 輸入一律用 B 站原文 raw；只有顯示原文時才 `convertContent(raw)`。
- R-4 並行度改為 1（序列佇列，同 A `_offlineChain`），卡片與字幕共用；佇列任務可取消：ContentText dispose 時移除尚未開始的任務；`translateBatch(lines, {bool Function() isCancelled})` 每句之間檢查，取消即停止並不再入列。
- R-5 `modelReady` 初始化：App 啟動時（`ZhConvert.init` 之後）若 `translateContent` 為 true 才非同步檢查一次；開關開啟並下載成功時設 true；關閉開關時 `close()` 翻譯器並清單例。
- R-6 設定慣例：`SettingsService.translateContent`／`setTranslateContent(bool)`、`subtitleEnabled`／`setSubtitleEnabled(bool)`（static get＋static Future set，比照 settings_service.dart:183、:194）。
- R-7 `controls_overlay.dart:63-73` `_buildVideoInfoText`：改為 `Text.rich`／`Row`，UP 名用 ContentText，「釋出於」「次觀看」等介面字串走 Text（字典）。`:122` 標題只在 `video.title.isNotEmpty` 時走 content，fallback「載入中...」仍走 Text。
- R-8 `ConditionalMarquee` 改 StatefulWidget，`content: true` 時非同步替換文字，`Marquee` 加 `ValueKey(顯示文字)`。
- R-9 字幕次級選單用帶 ScrollController 的 ListView（比照彈幕子選單捲動）；軌道過濾 `subtitle_url` 為空者；過濾後為空則不顯示「字幕」項目。
- R-10 字幕載入：在 `loadDanmaku()` 呼叫處旁**不 await** 呼叫 `loadSubtitles()`，以 cid＋`subtitleGen` 作廢；`_reloadWithCodec`、`switchQuality` **不重載**字幕（狀態保留）。
- R-11 字幕同步：不存 `currentSubtitle`；`SubtitleLayer` 接收 `lines` 與播放位置，在 build 以二分搜尋查找（`_onPlayerStateChange` 已每次 setState，:1503）。不放在 `danmakuEnabled` 條件內。
- R-12 機器翻譯軌：`SubtitleTrack` 加 `machine: true` 旗標，選單一致處理，不另設 `subtitleMachineEn`。
- R-13 PGC：v2 API 參數以 `aid`＋`cid` 為主（PGC 播放流程可取得 aid，player_action_mixin.dart:2514、:777）；`ep_id`／`season_id` 有就帶。實作時以實際回應確認，記入實作偏差。
- R-14 磁碟快取：單一 debounce Timer（2 秒）＋寫入 Future 鏈，寫 tmp 再 rename；讀取失敗清空。
- R-15 UP 主簽名：實作時確認 `up_space_screen.dart` 是否顯示簽名，有才套用。
- R-16 AC-6 驗證補充：英文介面但語言包未載入時 `ZhConvert.script` 為繁體，開關不顯示、翻譯不啟用，屬預期。

## 審查紀錄
- Sonnet 規格審查 23 點全部採用（R-1～R-16）。R-1 調整 AC-7 的「進度」與「原因」，屬實作限制，於回報時告知使用者。

### T-2（CC 字幕）偏差
- 純邏輯（解析、`findSubtitleLine` 二分搜尋、`pickDefaultSubtitle`、`machineTrackAvailable`）放在 `lib/models/subtitle.dart`，便於單元測試；`SubtitleApi.parseTracks` 負責 v2 回應解析。
- 預設選軌：英文介面且機器翻譯軌可用、又沒有英文軌時，預設選「English（機器翻譯）」而非中文軌（spec 未明載，取英文使用者的預期）。
- 機器翻譯軌用 `SubtitleTrack.machineEnglish`（`machine: true`）附加在 `subtitleTracks` 末端；譯文以就地替換 `subtitleLines[i]` 更新，播放中靠每次 tick 重建，暫停時才 `setState`。
- 選單「關閉」索引 0、軌索引 = subtitleIndex + 1；確定後回 main 焦點 6。選定即 `setSubtitleEnabled(index >= 0)`。
- `SubtitleLayer` 目前以 `ZhConvert.convertContent` 顯示（T-1 已提供）。
- PGC（R-13）：v2 以 aid＋cid 為主並帶 ep_id／season_id；未實機驗證實際回應。未登入時 subtitle_url 多為空 → 軌被過濾 → 不顯示「字幕」。
- `aid` 為 0／null 的 UGC 改帶 bvid。

### 實作偏差（T-1／T-3）
- `ContentTranslator` 新增 `request(raw)` 回傳可取消的 `TranslateRequest`（`translate` 為其 future）、`init()`（啟動檢查模型＋載入快取，main.dart 在 `ZhConvert.init` 後 `unawaited` 呼叫）、`close()`（放棄佇列、存檔、釋放 ML Kit）；ML Kit 抽成 `TranslateEngine`，測試用 `ContentTranslator.withEngine`。
- `translate()` 本身不檢查 `enabled`（由 ContentText／字幕呼叫端判斷），方便單元測試。
- CJK 判斷用 code point 組成 RegExp，避免被 i18n 掃描器當成介面字串。
- `ContentResolver`（content_text.dart）供 `ContentText` 與 `ConditionalMarquee` 共用。
- `ConditionalMarquee` 加 `pauseAfterRound` 參數；`history_video_card.dart` 原本直接用 `Marquee`，改用 `ConditionalMarquee(alwaysScroll: true, content: true)`，行為不變（停頓 1 秒）。
- `tv_live_card.dart`：沒有標題時顯示「無標題」（介面字串）走 `Text`，有標題才走內容翻譯。
- 下載對話框返回鍵取消時不等下載結束（背景繼續），開關保持關閉、toast「翻譯模型下載失敗：已取消」。
- 未涵蓋（規格範圍外）：followings_screen、up_contribute_tab、up_home_tab、space_collection_card、tv_live_horizontal_list 等仍直接用 Text 顯示 B 站內容。
- APK 大小 arm64 39.0MB／v7a 32.3MB／x86_64 41.5MB（btr.17：22.8／20.8／24.3），增加約 16～17MB，略高於預估 6～16MB。

## diff 審查（翻譯服務／ContentText）待修，全部採用
1. 全域 ValueNotifier（modelReady／enabled 變動時遞增），ContentText 與 ConditionalMarquee 監聽後重新解析。
2. models/video.dart:96（「868.4万追番」）、:113（類型標籤）放在 ownerName 的介面型字串：該來源卡片改走 Text（或 Video 加 ownerIsContent 旗標）。
3. 先 `_loadCache()` 再設 modelReady；`_loadCache` 改存 Future 避免並行重複。
4. interface_settings.dart:162-164 下載成功後不要再呼叫 init()，只載入快取。
5. 佇列優先序：新請求插到前面（LIFO）；字幕請求優先於卡片。
6. 磁碟快取 debounce 拉長到 10 秒且每次重設，App 進背景（paused）時 flush。
7. 英文模式未啟用翻譯時 convertContent 結果加快取（key 加前綴）。
8. ConditionalMarquee content true→false 取消請求；設定說明補「與字幕」；episode_panel.dart:117 「P{n} 」前綴用 Text、分集名用 ContentText。

## diff 審查（字幕）待修
已交給字幕實作代理，修到一半因 Sonnet 用量上限（2026-11-11 02:00 重置）中斷：switchEpisode 清字幕狀態、面板焦點 clamp、暫停時只在目前行被替換才 setState、機器翻譯從目前位置環狀翻、findSubtitleLine 處理長字幕、字幕載入失敗 toast 並還原、http timeout 10 秒、確認 fallback 不覆蓋使用者選軌。中斷時 `flutter analyze` 無問題，需逐項確認完成度。

## 追加（使用者測試回饋）

- A：translateContent 預設 true；ContentTranslator.init／語言選單選 English 後在背景下載模型（downloadInBackground；失敗 24 小時內不重試，prefs key translate_download_failed_at；選 English 時 force 略過退避）。翻譯狀態寫 PerfLog（「== 播放效能 ==」區段）；錯誤報告設定摘要新增「翻譯 B 站內容」一行。
- B：控制列新增字幕按鈕（CtrlBtn.subtitle=6，設定以後索引順延，count=11）。長按共用彈幕按鈕的 hold 機制（_handleDanmakuHold）；沒有字幕軌時長按視為短按（toast）。新增 subtitleLoading 旗標與 defaultSubtitleIndex()／onSubtitleButton()。
- 偏差：en.json 為 {strings, templates} 結構，新字串放進 strings。

## 偏差：未登入 CC 字幕改走 gRPC DmView

- `SubtitleApi.getSubtitles`：v2 無可用字幕時（含未登入）且有 aid，改呼叫 `getSubtitlesGrpc`（pid=aid、oid=cid、type=1）；失敗回空清單，10 秒逾時。
- 新增 `lib/grpc/dm_view.pb.dart`（精簡手改版，僅 DmViewReq／DmViewReply／VideoSubtitle／SubtitleItem／SubtitleType）與 `lib/grpc/dm_grpc.dart`（frame 編解碼、手工編 metadata／device／locale／network／fawkes header）。
- 新增套件 protobuf ^6.0.0、fixnum ^1.1.1；HTTP 沿用 `package:http`（HTTP/1.1 即可，不需 http2 adapter），gzip 用 dart:io。
- 測試：`test/subtitle_grpc_test.dart`；真實網路 `test/subtitle_grpc_network_test.dart`（@Tags network，需環境變數 BILI_NET_AID／BILI_NET_CID）。

## 偏差：重啟後首頁標題不自動變英文、控制列間距

- 根因：`content_translator.dart` 的 `init()`／`downloadInBackground()` 只有在「這次程序自己」下載成功或啟動檢查已下載才 `enable()`。重啟打斷先前的下載、或下載丟例外／被 24 小時退避略過時，原生層之後才完成下載，`modelReady` 卻一直是 false，沒有人再通知 ContentText，要到下次重啟才翻譯。
- 修法：新增 `_watchModel()`（`pollInterval` 預設 5 秒、最多 60 次）：init 偵測未下載、背景下載失敗後輪詢 `isModelDownloaded()`，一旦為 true 就 `enable()`（內部 notifyChanged），ContentText／ConditionalMarquee 監聽後重新翻譯。`ContentTranslator.instance` 由 `static final` 改為可指定（測試用）。
- 測試：`test/content_translator_test.dart` 新增 ContentText 在 modelReady 變 true 後重新翻譯、輪詢啟用兩項。
- 控制列（`controls_overlay.dart`）：按鈕間距 24 → 12，左側群與右側（讚／幣／藏）之間 `Spacer` 後再加 `SizedBox(width: 48)` 保證最小間距。裝置 logical 寬 960，總寬約 816 < 880 可用寬度。

## 偏差：字幕避開控制列、字幕軌補選、標題列發布時間翻譯

- `ControlsOverlay.bottomHeight`（`_MeasureHeight` 量測底部控制區實際高度）；`SubtitleLayer` 控制列顯示時 bottom = 高度 - 40 + 12，隱藏時 48，不再寫死 150。
- `player_screen` 監聽 `ContentTranslator.changes` → `onTranslatorChanged()`：enabled 變 true 時補上機器翻譯軌，使用者沒手選過（`subtitleUserPicked`）且字幕開啟時自動改選。
- 標題列「釋出於{0}／{0}次觀看」各段先經 `ZhConvert.convert` 再合併（整串合併對不到 template）。
- 模擬器 e2／f1 畫面上的大字簡體字幕是影片內嵌硬字幕（無底框、不受 App 控制），非 SubtitleLayer；未登入該影片沒有 CC 軌，無法實機驗證 CC 層位置。
