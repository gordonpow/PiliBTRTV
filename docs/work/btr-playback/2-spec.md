# 規格：PiliBTRTV — BTR 多 CDN 播放加速

需求：[1-requirements.md](1-requirements.md)
來源專案（只讀）：`C:\presonal_project\bilibili_bata\PiliPlus`（以下簡稱 PiliBTR）

## 設計

### 資料流

```
PlayerActionMixin → MpdGenerator.generate(dashData)
   └─ 每個 Representation：BTR 開 → BaseURL = await BtrProxy.wrap(baseUrl, backups: backupUrl)
                          BTR 關 → 原本的 baseUrl + backupUrl（不變）
ExoPlayer ──Range──▶ 127.0.0.1:<隨機埠>/btr/<id>.m4s（BtrProxy）
                      └─ 切塊 → BtrNodePool 選節點 → 多個 CDN 並行 GET → 依序寫回
```

- 代理是獨立的 `HttpServer`（`InternetAddress.loopbackIPv4`，埠 0），**不**併入 `LocalServer`（`LocalServer` 綁 `anyIPv4:3322`，給手機設定網頁用，不應對外暴露媒體代理）。
- HTTP 用戶端：新增相依套件 `dio`（PiliBTR 的 proxy 依賴 `ResponseBody` 串流與 `CancelToken`，直接移植最少改動）。`btrDio` 為 HTTP/1.1，connectTimeout 4 秒、receiveTimeout 5 秒；PiliBTR 中 `Request.http11Dio` 的地方改用本專案自建的 `Dio`（不設 timeout 的直通用）。
- 設定儲存：沿用 BiliTV 的 `SharedPreferences`（`SettingsService`）。`SettingsService` 新增 `static SharedPreferences get prefs`（未 init 時拋錯即可），`BtrConfig` 用它同步讀寫。
- 節點池：`BtrNodePool(url, {List<String> backups})`，節點 = 原始 URL + `backupUrl`（去重）+ CDN 模式 host 替換（規則同 PiliBTR `_build`）。
- 代理來源上限 `_maxSources` 改為 64（一個 MPD 有多個畫質與音軌，每個 Representation 一個來源）。
- `http2https`：PiliBTR 的字串擴充，移植時在 `btr_proxy.dart` 內寫私有函式取代。
- `kDebugMode` 的 `debugPrint` 保留。

### 要改或新增的檔案

| 路徑 | 改什麼 |
|---|---|
| `pubspec.yaml` | 加 `dio`（與 Flutter 3.47.9 相容的最新 5.x）；`description` 改為 PiliBTRTV |
| `lib/services/btr/btr_config.dart`（新） | 移植 PiliBTR `lib/services/download/btr_config.dart`：只保留播放相關（`playback`、`cdnMode`、`applyLocaleDefault`、`customCdn`、`autoThreads`、`threads`、`playbackThreads`、`hosts`、`parseHosts`、常數）；刪 `enable`（下載）與 `threadsFor`。新增 setter（async，寫入 prefs）。鍵名前綴 `btr_` |
| `lib/services/btr/btr_cdn.dart`（新） | 移植 `btr_cdn.dart`，加 `backups` 參數 |
| `lib/services/btr/btr_proxy.dart`（新） | 移植 `btr_proxy.dart`；`wrap(url, {backups})`；新增 `activeStats()`：回傳最近 5 秒內有服務過資料的來源的 `(served, nodes)` 列表（`_BtrSource` 加 `lastServedAt`），給狀態面板用 |
| `lib/services/mpd_generator.dart` | `_writeRepresentation` 改為 async；BTR 開且 `BtrProxy.isEligible(baseUrl)` 時只寫代理 URL 一個 `<BaseURL>`，否則維持原樣 |
| `lib/services/settings_service.dart` | 加 `prefs` getter |
| `lib/screens/splash_screen.dart` | `SettingsService.init()` 在此（約第 73～78 行的 `Future.wait`）；`Future.wait` 之後呼叫 `BtrConfig.applyLocaleDefault()` |
| `lib/screens/home/settings/settings_view.dart` | `SettingsCategory` 加 `btr('線程撕裂者')`（放在 `playback` 之後），`_buildContent` 加分支 |
| `lib/screens/home/settings/tabs/btr_settings.dart`（新） | 設定分頁，用既有 `SettingToggleRow`、`SettingDropdownRow`、`SettingActionRow`；項目見 AC-4。自訂節點：`SettingActionRow` 開 `AlertDialog` + 多行 `TextField`（遙控器 IME 輸入），儲存時 `parseHosts`；CDN 模式為自定義且節點清單為空時，切到自定義先開輸入框，空的不儲存並 toast「請至少輸入一個 CDN 節點」。任何變更後呼叫 `BtrProxy.reset()` 並 toast「已儲存，下一部影片生效」。焦點：第一項 `isFirst` + `onMoveUp`，參照 `playback_settings.dart` |
| `lib/screens/player/widgets/settings_panel.dart` | `SettingsMenuType` 加 `cdn`；主選單加第 4 項「CDN 狀態」（值：BTR 開→「BTR」，關→「直連」）；`cdn` 子選單為狀態檢視（見下） |
| `lib/screens/player/widgets/cdn_status_view.dart`（新） | 參照 PiliBTR `lib/plugin/pl_player/widgets/cdn_status_panel.dart`：`Timer.periodic(1s)`，用 `BtrProxy.activeStats()` 算總速度（served 差值）與各節點：host、速度（KB/s 或 MB/s）、已收量、停用標記。無資料顯示「未使用 BTR（直連）」 |
| `lib/screens/player/focus/player_focus_handler.dart` 與相關 mixin | 主選單項目數 +1、`cdn` 選單的上下鍵與返回鍵行為（返回回到主選單第 4 項）；照既有 `speed`／`danmaku` 的處理方式 |
| `android/app/build.gradle.kts` | `applicationId = "com.gordonpow.pilibtrtv"`（`namespace` 不改，避免動 Kotlin package） |
| `android/app/src/main/AndroidManifest.xml` | `android:label="PiliBTRTV"` |
| `README.md` | 開頭加 PiliBTRTV 說明（繁體中文）：基於 BiliTV、BTR 功能、來源與授權；原 README 內容保留在下方 |
| `docs/PROJECT_LOG.md`（新） | 依全域規則建立 |

### 設定鍵

| 鍵 | 型別 | 預設 |
|---|---|---|
| `btr_playback` | bool | true |
| `btr_cdn_mode` | int（`BtrCdnMode.index`） | 未設定 → mainland |
| `btr_custom_cdn` | List&lt;String&gt; | [] |
| `btr_auto_threads` | bool | true |
| `btr_threads` | int | 16 |
| `btr_cdn_locale_default_v1` | bool | — |

## 任務

| ID | 內容 | 相依 |
|---|---|---|
| T-1 | `dio` 相依、`btr_config.dart`、`btr_cdn.dart`、`btr_proxy.dart`、`SettingsService.prefs`、`main` 呼叫 `applyLocaleDefault`、`MpdGenerator` 接上代理 | — |
| T-2 | 設定分頁 `btr_settings.dart` 與 `settings_view.dart` | T-1 |
| T-3 | 播放器「CDN 狀態」選單（settings_panel、cdn_status_view、焦點處理） | T-1 |
| T-4 | 改名與 applicationId、README、PROJECT_LOG | — |
| T-5 | `flutter pub get`、`flutter analyze`、`flutter build apk --release`（或 debug） | T-1~T-4 |
| T-6 | git：remote 設定、commit、push | T-5 |

T-1 與 T-4 可平行；T-2、T-3 在 T-1 後可平行。

## AC 驗證方式

| AC | 方式 |
|---|---|
| AC-1、AC-3 | 程式碼審查（移植對照 PiliBTR）；實機播放待使用者測試 |
| AC-2 | 程式碼審查 `mpd_generator.dart` 的分支 |
| AC-4、AC-6、AC-7 | 程式碼審查；遙控器操作待使用者測試 |
| AC-5 | 程式碼審查 |
| AC-8 | 檢查 gradle 與 manifest；APK 安裝待使用者測試 |
| AC-9 | `flutter analyze`、`flutter build apk` 輸出 |
| AC-10 | `git remote -v`、`git push` 輸出 |

## 邊界與風險

- ExoPlayer DASH 會對 `indexRange`／`initialization` 發小範圍 Range 請求：代理須支援任意 Range 與 `bytes=N-`（PiliBTR 已支援）。
- 代理啟動失敗：`wrap` 回傳原 URL（PiliBTR 已有），此時 MPD 退回寫原始 URL + backup。
- 所有節點失敗：proxy 回錯誤，播放器既有重試邏輯（3 次）處理。
- 換畫質：`MpdGenerator.generate` 會重新呼叫，`_idByUrl` 讓相同 URL 共用來源。
- Android 9 以上明文 HTTP：確認 `AndroidManifest.xml` 已允許 cleartext 到 127.0.0.1（BiliTV 本來就用 `http://127.0.0.1:3322/video.mpd`，所以應已允許；實作時確認）。
- 舊電視（armv7、Android 5～9）效能：預設自動執行緒 8，與 PiliBTR 相同。

## 回退

設定頁關閉「播放加速」即回到原版行為；程式碼層面 revert BTR commit。

## 審查紀錄

2026-11-07：agy 逾時（4 分 40 秒），改由 Haiku 子代理審查，結果見 [review-spec.md](review-spec.md)。

採用：
- 3.1 Pump 失敗時關閉 response，避免播放器卡住等 timeout。
- 3.2 來源快取改 LRU；`reset()` 只清 URL 對照表，不中斷正在播放的來源。
- 3.3 探測失敗 10 秒後可重試；探測最多 2 個節點、約 6 秒上限。
- 3.4 轉送 `cookie`、`origin`。
- 3.6 `wrap` 的設定讀取放進 `try`。

不採用或已處理：
- 2（dio、prefs、manifest 已存在）：審查時 T-1 已完成，是實作結果，不是規格錯誤。
- 3.5：T-1 已用 `wrap` 回傳值判斷，失敗時寫原 URL 與 backupUrl。
- 4 改 session 範圍：LRU 已解決淘汰問題，改動較小。
- 4 狀態面板 5 秒時間窗：BTR 開但無資料時顯示「BTR 已開啟，等待資料…」，不會誤顯示直連。
- 1 AC-5 單元測試：本次不新增測試，以程式碼審查驗證。
- 5 返回焦點：採「回到主選單 CDN 狀態項」，T-3 依此實作；T-3 已要求檢查所有寫死主選單長度的位置。

## 實作偏差

（實作中補）
