# 規格審查：BTR 多 CDN 播放加速（2-spec.md）

審查對象：`docs/work/btr-playback/2-spec.md`
來源（只讀）：`C:\presonal_project\bilibili_bata\PiliPlus\lib\services\download\btr_proxy.dart`（下稱 `btr_proxy.dart`）、`btr_cdn.dart`、`btr_config.dart`

## 1. 驗收條件未覆蓋或無法驗證（規格「AC 驗證方式」）

- **AC-5** 無法靠程式碼審查確認。`applyLocaleDefault`（`btr_config.dart`，`applyLocaleDefault` 內 `scriptCode == 'Hant'` / TW·HK·MO / `languageCode == 'zh'`）的判斷規則規格沒寫，只寫「同 PiliBTR」。修正：把判斷抽成純函式 `BtrCdnMode? cdnModeForLocale(Locale)`，寫單元測試覆蓋 zh-Hant、zh-TW、zh-HK、zh-CN、en、ja 六組；旗標鍵 `btr_cdn_locale_default_v1` 的型別與預設值在鍵表寫「—」，要補成 bool / 未設定。
- **AC-4** 有三個規格沒寫的驗收點：
  - 「超過 32 顯示限流警告」不在 `btr_settings.dart` 的描述裡。
  - 「最多 32 個」節點：`btr_config.dart` 的 `parseHosts` 在第 32 個就 `break`，靜默截斷。規格要寫明截斷時要不要提示。
  - 「自定義模式無節點不允許儲存」的觸發條件（切到自定義時是否強制開輸入框）只在 §要改的檔案寫一次，AC 表沒有對應測試項。
  修正：在 AC 驗證表逐條列出上述三個點，並標明驗證方式（程式碼審查 / 實機）。
- **AC-1** 的「切畫質」與「跳轉」只寫實機待測，沒有對應的程式碼驗證項。修正：至少寫明切畫質走 `player_action_mixin.dart:1153` 與 `:1269` 兩條路徑都會重新呼叫 `MpdGenerator.generate`，並列為審查項。
- **AC-3** 的「最多 3 次」與「0 bytes 連續兩次」由 `btr_cdn.dart` 的 `maxResets = 3`、`strikeLimit = 2` 實作，規格只說「移植」。修正：把這兩個常數寫進規格並列為審查項，免得移植時改掉。

## 2. 設計錯誤：對現有程式碼的錯誤假設

- **§要改的檔案 `pubspec.yaml`「加 dio」**：`pubspec.yaml:15` 已有 `dio: ^5.9.0`，`pubspec.lock` 也有。但 `lib/` 裡沒有任何 `package:dio` import，BiliTV 的 HTTP 走的是 `http` 套件（`pubspec.yaml:14`）。修正：改為「dio 已存在，本次首次實際使用」，並在規格寫明自建 `Dio` 的 adapter：`IOHttpClientAdapter`（HTTP/1.1，即 Dart 預設），不需要像 PiliPlus `init.dart:147-156` 那樣處理 system proxy 與 `autoUncompress`，但要在規格寫明為什麼不需要。
- **§設計「PiliBTR 中 `Request.http11Dio` 的地方改用本專案自建的 Dio」**：BiliTV 沒有 `Request` 類別，也沒有任何 `Dio(` 實例（`grep "Dio("` 在 `lib/` 無結果）。「本專案自建的 Dio」沒有指定位置與建立方式。修正：指定 `btr_cdn.dart` 內 `final Dio btrDio = Dio(BaseOptions(connectTimeout: 4s, receiveTimeout: 5s))` 與 `final Dio btrPassthroughDio = Dio()`，兩者都寫明。
- **§要改的檔案 `settings_service.dart`「加 `prefs` getter」**：`lib/services/settings_service.dart` 已有 `static SharedPreferences get prefs`，未 init 時拋 `StateError`。這一項應刪除，規格與現況不同步。
- **§要改的檔案 `AndroidManifest.xml`「改為 PiliBTRTV」**：`android/app/src/main/AndroidManifest.xml:15` 已是 `android:label="PiliBTRTV"`。另外 §邊界「確認 cleartext」已被滿足：`AndroidManifest.xml:19` 是 `android:usesCleartextTraffic="true"`，可直接寫「已確認」並刪掉待辦。
- **§資料流 只列一個 `MpdGenerator.generate` 呼叫點**：實際有三個，`player_action_mixin.dart:244`（初始化）、`:1153`（換畫質）、`:1269`（另一條換畫質路徑）。三者都已 `await`，因此 `_writeRepresentation` 改 async 不會破壞呼叫端，但規格要列出三處，並寫明三處都會經過 `BtrProxy.wrap`。

## 3. 缺少的邊界案例

### 3.1 所有節點失敗時連線會卡住，不是「proxy 回錯誤」（§邊界與風險「所有節點失敗」）

規格寫「proxy 回錯誤，播放器既有重試邏輯處理」。實際上 `btr_proxy.dart:455-483`：`_Pump.run` 的外層 `try` 的 `catch (_) { _stop(); }`（第 480-483 行）沒有 `res.close()`；內層 `fallback` 的 `pipeRemaining` 失敗也落到這個 catch。結果是 HTTP response 永遠不關閉，ExoPlayer 等到自己的 socket timeout 才會重試，不是快速失敗。
修正：在第 480 行的 catch 內加 `try { await res.close(); } catch (_) {}`；若 header 尚未 flush，先設 `res.statusCode = 502`。規格要寫明「回傳截斷的 206 回應，ExoPlayer 以錯誤處理並重試」，並加一條實機驗證：拔網路後播放器在幾秒內進入重試，不是無限轉圈。

### 3.2 來源快取 FIFO 淘汰與 `reset()` 會打斷正在播放的影片（§資料流 `_maxSources` 64、§AC-6）

`btr_proxy.dart:66-70`：淘汰用 `_sources.keys.first`，最早插入的先被刪，且存取時不會更新順序。`:111-115` 找不到來源就回 404。規格把上限從 32 改成 64，但沒有計算每部影片會插入幾筆：每次呼叫 `MpdGenerator.generate` 會為每個 Representation（視訊與音訊）各呼叫一次 `wrap`，BiliTV 的 CDN URL 含簽章參數，換畫質時可能產生新 URL。估計約 12 筆／次，約 5 次換畫質就會把目前影片的來源淘汰，之後的 Range 請求拿到 404。
另外 `btr_proxy.dart:34-37` 的 `reset()` 會清空 `_sources`，AC-6 的「清除代理的來源快取」若在播放中呼叫（例如從其他路徑進設定），現有 MPD 的 `/btr/<id>` 全部 404。
修正（見第 4 點的簡化設計）：來源生命週期綁定「目前播放 session」，每次 `PlayerActionMixin` 開始新影片時 `BtrProxy.beginSession()` 清空；`reset()` 只清 `_idByUrl`，不清正在用的 `_sources`。規格要寫明淘汰策略。

### 3.3 探測失敗會永久停用加速，且探測最慢約 27 秒（§邊界、§設計 `btr_proxy.dart`）

`btr_proxy.dart:205-236`：`_probe` 失敗時 `_total` 為 null，但 `:227` 無條件 `_probed = true`。`serve`（`:160-161`）之後每個請求都走 `_passthrough`，直到 reset，不會重試。另外 `:206` 對前 3 個節點各試一次，每次 connect 4 秒加 receive 5 秒（`btr_cdn.dart` 的 `btrDio` 設定），最壞約 27 秒，這段時間 ExoPlayer 的 `initialize()` 在等第一個 byte。
修正：探測失敗時不設 `_probed = true`，下一個請求重試；總探測時間上限 5 秒；或探測只用第 1 個節點。規格要寫明「探測失敗 → 單連線直通，下一請求重試」與上限值。

### 3.4 代理只轉送 User-Agent 與 Referer，丟掉 Cookie 與 Origin（§AC-1）

`btr_proxy.dart:150-154` 只帶 `user-agent`、`referer`、`accept-encoding`。BiliTV 給 ExoPlayer 的 `httpHeaders` 含 `Origin` 與 `Cookie: SESSDATA=…`（`player_action_mixin.dart:262-268`）。登入後才能看的畫質（大會員、1080P 以上）可能因為缺 Cookie 而 403，且只在代理開啟時發生，會被誤判為「代理壞掉」。
修正：`_headers` 改為轉送播放器給的全部 `httpHeaders`（至少 `Cookie`、`Origin`、`Referer`、`User-Agent`）；驗收項加「登入帳號播放 1080P 以上，BTR 開與關結果一致」。

### 3.5 MPD 分支與 `wrap` 失敗的對應（§mpd_generator、§邊界「代理啟動失敗」）

規格寫「BTR 開且 `isEligible` 時只寫代理 URL 一個 `<BaseURL>`，否則維持原樣」。但 `btr_proxy.dart:74-77` 在失敗時回傳原 URL，這時「否則」分支不會觸發，MPD 只剩原 URL，backupUrl 會漏掉。
修正：規格要寫明判斷依據是 `wrap` 的回傳值（`proxied != original`），並在「proxy 失敗」時照舊寫出全部 `<BaseURL>`（baseUrl + backupUrl）。

### 3.6 `wrap` 的設定讀取在 `try` 之外（§設計 `BtrProxy.wrap`）

`btr_proxy.dart:58` 的 `BtrConfig.playback` 在 `try` 之外。移植時若 `SettingsService.prefs` 尚未 init（規格寫「未 init 時拋錯即可」），`wrap` 會拋出 Future 錯誤，`MpdGenerator.generate` 無 catch，直接讓播放失敗。
修正：`wrap` 的整段（包含 `BtrConfig.playback`）都放進 `try`，失敗回傳原 URL；規格寫明此點。

## 4. 較簡單且符合相同驗收條件的設計

- **來源範圍改為單一播放 session**：`BtrProxy.beginSession()` 在 `PlayerActionMixin` 初始化新影片時清空 `_sources` 與 `_idByUrl`；換畫質不清。這樣去掉 `_maxSources` 與 FIFO 淘汰（§3.2），並滿足 AC-6「下一部影片生效」。
- **CDN 狀態不用 5 秒時間窗**：`activeStats()` 的「最近 5 秒內有服務過資料」（規格 §要改的檔案 `btr_proxy.dart`）會在暫停或緩衝超過 5 秒時顯示「未使用 BTR（直連）」，與 AC-7「BTR 開時」不符。改為：`statsFor(originalUrl)`（`btr_proxy.dart:82-87`，已存在）取得目前影片來源；BTR 開且來源存在即顯示「BTR」與各節點狀態，不看時間。
- **MPD 分支不另外判斷 `isEligible`**：直接用 `wrap` 回傳值判斷（§3.5），少一處重複邏輯。

## 5. 規格內部矛盾：播放器選單返回行為

- §要改的檔案寫「返回回到主選單第 4 項」，但同一行又說「照既有 `speed`／`danmaku` 的處理方式」。既有處理是回到第 0 項：`player_event_mixin.dart:20-23`、`:120-124`、`:391`、`:429` 都設 `focusedSettingIndex = 0`。修正：二擇一並寫明；建議回第 0 項以維持一致，或在規格明確定義 cdn 為特例。
- 規格只提到「主選單項目數 +1」，實際需要改的點更多：
  - `player_event_mixin.dart` 的 `_getSettingsMaxIndex`（約 381-450 行的 switch，`main` 回傳 `2`）要改為 `3`。
  - `player_action_mixin.dart:1208-1224` 的 `activateSetting` 沒有 `case 3`，按確認鍵第 4 項沒有反應。
  - `player_event_mixin.dart` 的 `arrowLeft` 分支（約 381-392 行）只處理 `speed`，`cdn` 子選單按左鍵沒有返回。
  - `settings_panel.dart:3` 的 enum 要加 `cdn`；`:92-95` 的 `title` 要加 cdn；`:147-157` 的 `_buildSettingsList` switch 沒有 `cdn` 分支，會落到 `default` 顯示主選單。
  修正：規格 T-3 列出以上五個位置。

## 6. 規格中的待釐清事項（簡短）

- §設定鍵 `btr_threads` 預設 16，但播放在 `btr_auto_threads` 為開時固定用 8（`btr_config.dart` 的 `playbackThreads`）。規格的 AC-4「自動執行緒數（預設開，播放用 8）」已寫，但 `threads` 的 UI 在自動開啟時是否灰掉，規格沒寫。
- §要改的檔案 `btr_settings.dart`「任何變更後呼叫 `BtrProxy.reset()`」：若 §3.2 的 `reset()` 行為不變，這裡的 reset 也會打斷正在播放的來源（設定頁通常不在播放中，但規格應註明）。

---

審查未修改任何檔案，未 commit，未建置。
