# PiliBTRTV 專案紀錄

最後更新：2026-11-08

本檔記錄專案介紹、新增功能與開發對話紀錄。每次對話結束或功能完成時更新。

## 1. 專案介紹

- **名稱**：PiliBTRTV
- **性質**：Android TV 版第三方 Bilibili 用戶端，基於 [BiliTV](https://github.com/Hyper-Beast/BiliTV)（Flutter）修改。
- **目標**：加上「線程撕裂者」（BTR）多 CDN 並行播放加速，邏輯與手機版 PiliBTR（`C:\presonal_project\bilibili_bata\PiliPlus`）相同。
- **Repo**：https://github.com/gordonpow/PiliBTRTV（`origin`），上游 BiliTV 為 `upstream`
- **技術**：Flutter 3.47.9、Dart、video_player（ExoPlayer）、shared_preferences、dio
- **applicationId**：`com.gordonpow.pilibtrtv`（可與原版 BiliTV 同時安裝）
- **本機路徑**：`C:\presonal_project\PiliBTRTV`

### 架構重點

| 模組 | 檔案 | 說明 |
|---|---|---|
| MPD 產生 | `lib/services/mpd_generator.dart` | BTR 開時把每個 Representation 的 `BaseURL` 換成本機代理 URL；代理失敗時寫回原始 URL 與 backupUrl |
| 播放代理 | `lib/services/btr/btr_proxy.dart` | `127.0.0.1` 隨機埠 HTTP 代理，把 ExoPlayer 的 Range 請求切塊，多節點並行下載後依序交回；來源快取 LRU（64） |
| 節點池 | `lib/services/btr/btr_cdn.dart` | 原始 URL + backupUrl + CDN 模式 host 替換；連續兩次 0 bytes 停用；依速度 ÷ 進行中請求數選節點 |
| 設定 | `lib/services/btr/btr_config.dart` | 播放加速、CDN 模式、自訂節點、執行緒數（存在 SharedPreferences，鍵前綴 `btr_`） |
| 設定頁 | `lib/screens/home/settings/tabs/btr_settings.dart` | 設定 → 線程撕裂者 |
| CDN 狀態 | `lib/screens/player/widgets/cdn_status_view.dart` | 播放器設定選單 → CDN 狀態，每秒更新 |

## 2. 新增功能

### 已發布（已 commit 並推送）

| Commit | 功能 |
|---|---|
| `f1afe82` | BTR 多 CDN 播放加速、設定分頁「線程撕裂者」、播放器 CDN 狀態、改名 PiliBTRTV 與新 applicationId、Gradle 9.1.0（規格：`docs/work/btr-playback/`） |

發布：v1.2.2-btr.1（2026-11-07）。尚未實機測試。

| `9c96830` | 所有 B站請求帶 buvid3（修正點影片「獲取影片資訊失敗」，HTTP 412）；圖示改為 PiliBTR、TV banner |
| `f9beb34` | 繁簡切換：介面改台灣繁體用語（s2twp），顯示時 ZhConvert（繁 s2tw／簡 tw2sp），語言設定與重新啟動 |
| `d176bb8` | GitHub 自動檢查更新與 App 內安裝（紅點、間隔、ABI 選檔） |
| `5d2c4e8`、`7acf7dd`、`c917280` | Cookie 加 b_nut、Referer 結尾斜線、未登入取 WBI 金鑰（修正搜尋 412／無結果）；轉換表 CRLF 造成字間空白；CDN 狀態暫停時仍顯示 |
| `16c63e2` | 未登入也能進入設定頁（登入按鈕開 QR 登入頁，返回鍵回設定） |
| `3e1c437` | 動態空白（mid／pub_ts 改為字串）、歷史紀錄一直轉圈（失敗時缺欄位）、登入後分頁重新載入 |
| `107303c` | 修正分區影片 API，新增番劇 (PGC) 播放支援與選集連播（規格：`docs/work/bangumi-region/`） |
| `adf063b` | 解碼器失敗自動改用 H.264（AVC）並寫入設定；錯誤報告預設焦點改為取消（規格：`docs/work/player-fixes/spec.md` A & C） |
| `b364a91` | Netflix 式左右鍵快退快進進度條與預覽卡片，連按加速與自動確認（規格：`docs/work/player-fixes/spec.md` B） |
| `5f21da3` | 番劇大會員集改播試看片段（durl）並顯示「此集為大會員專屬，目前僅提供試看」，試看結束不自動連播 |
| `e9ac2cd` | 模擬器測試報告與截圖（`docs/work/player-fixes/test-report.md`、`fix-report.md`） |
| （本次） | 開機動畫改為 PiliBTR 風格：粉紫光線匯聚後浮現圖示，無文字，2.4 秒（`tool/gen_splash.py` 產生） |
| `3a9ec8d` | 修正播放 -351：改用 `x/player/wbi/playurl` 並帶防風控參數，-351／-352 時重試一次 |
| `aa0a0a5` | 搜尋後關閉系統鍵盤，避免進影片時鍵盤殘留而當機（規格：`docs/work/search-crash-seek/`） |
| `baf859a` | 快退快進改為 Netflix 式縮圖列，停 400ms 後中間改為串流抽出的清晰畫面 |
| `2de58b7` | 閃退後詢問回報；錯誤報告改為手機網頁查看（複製、下載、預填 GitHub issue），移除上傳（規格：`docs/work/error-report-lan/`） |
| `82adf29` | 手機輔助登入（密碼、簡訊、Cookie，需同一個 Wi-Fi）；修正登入頁焦點（規格：`docs/work/phone-login/`） |
| `085029f` | 官方授權番劇（銀魂等）從歷史紀錄或一般入口開啟時改以番劇模式播放，修正「獲取影片資訊失敗」（規格：`docs/work/pgc-redirect-4k/`） |
| `88f6412` | 4K 低 FPS：MPD 只放選定串流；依硬體解碼器的解析度／幀率能力選編碼與畫質上限；手動選畫質無法硬解時改用可硬解畫質並提示 |
| `d71e072` | BTR 自動執行緒在碼率 ≥ 8 Mbps 時使用 16 個 |

版本號：`lib/btr_version.dart` 為 `v1.2.2-btr.5`（pubspec `1.2.2+5`）。發布：v1.2.2-btr.2（2026-11-07，附 release APK 57.6MB）；v1.2.2-btr.3（2026-11-08，分 64 位元 arm64-v8a 21.3MB 與 32 位元 armeabi-v7a 19.2MB 兩個 APK）；v1.2.2-btr.4（2026-11-08，arm64-v8a 21.6MB、armeabi-v7a 19.5MB）；v1.2.2-btr.5（2026-11-08）。

### 已實作、尚未 commit

（無）

### 待辦

- 實機測試：切畫質、自訂節點輸入框、App 內更新安裝流程、登入後功能。
- 已在模擬器（Android TV API 36 x86_64）驗證：搜尋、播放、BTR 多節點、CDN 狀態、繁簡切換與重啟、未登入設定頁、關於軟體更新項目。TV launcher banner 未驗證。
- 搜尋鍵盤（8.7px）與影片卡片（0.325px）有版面溢出，原版即有，未處理。
- Android TV API 33 映像檔是 32 位元 x86，Flutter 不支援，模擬器請用 `Android_TV_API36`。
- 直播尚未接 BTR。

## 3. 對話紀錄

時間為台灣時間（UTC+8）。

### 2026-11-07：建立專案與 BTR 播放加速

| 請求 | 結果 |
|---|---|
| 以 BiliTV 為基底做 BTR 版本，介面邏輯同 PiliBTR，repo 為 gordonpow/PiliBTRTV | clone BiliTV、設定 remote；確認範圍：播放加速 + 設定 + CDN 狀態面板、改名與新 applicationId、commit 並 push |
| 寫需求與規格 | `docs/work/btr-playback/1-requirements.md`、`2-spec.md`；agy 審查逾時，改由 Haiku 審查，採用 5 項修正 |
| 實作 | T-1 BTR 核心、T-2 設定分頁、T-3 CDN 狀態，各檔 analyze 無問題 |
| 建置與發布 | 全專案 `flutter analyze` 無問題；JDK 25 與 Gradle 8.14 不相容，wrapper 升到 9.1.0 後 `flutter build apk --release` 成功（63.2MB）；commit `f1afe82` 推送到 origin/main |
| 推到 GitHub、發 Release | 已推送；發布 Release `v1.2.2-btr.1`（附 APK，debug 金鑰簽署） |
| 怎麼看 agy 進度 | agy 用 `--print`，跑完才輸出；可用 `/tasks` 看背景工作 |

### 2026-11-07：繁簡切換（T-3）

| 請求 | 結果 |
|---|---|
| 實作 T-3 繁簡切換 | 80 個檔案以 OpenCC s2twp 轉為繁體，伺服器比對點保留簡體；新增 ZhConvert、zh_text、語言設定與重啟；`flutter analyze` 無問題 |

### 2026-11-07：修正無法播放、繁簡切換、自動更新、圖示、模擬器

| 請求 | 結果 |
|---|---|
| 點影片顯示獲取影片資訊失敗；加繁簡切換（規則同 PiliBTR，繁體用台灣用語）；加自動更新（邏輯同 PiliBTR）；圖示改與 PiliBTR 相似；能否用模擬器測試 | 根因為缺 buvid3（412）；另找到搜尋需 b_nut、Referer 結尾斜線、未登入 nav 回 -101 仍有 WBI 金鑰。完成繁簡切換、GitHub 自動更新、圖示與 banner。建立 Android TV API 36 模擬器並實測（截圖：`docs/work/zh-update-icon/screens/`） |
| 未登入也能進設定 | 設定頁一律顯示，未登入時顯示「登入」按鈕開 QR 頁 |

### 2026-11-07：登入後問題與開機動畫

| 請求 | 結果 |
|---|---|
| 模擬器點擊沒反應 | TV App 只回應遙控器按鍵；AVD 設 `hw.keyboard=yes` 後可用方向鍵、Enter、Esc 操作 |
| 動態顯示暫無動態、歷史紀錄一直轉圈、直播關注一開始空白 | 分別修正（見 `3e1c437`），模擬器確認動態與歷史正常 |
| 開機動畫換成自己風格、不要有字 | 重新製作 `assets/icons/startup.mp4`（1920x1080、30fps、246 KB），模擬器確認播放 |

### 2026-11-07：搜尋支援系統鍵盤

| 請求 | 結果 |
|---|---|
| 搜尋同時支援內建鍵盤與電視系統鍵盤（IME）以輸入中文；修正鍵盤區底部溢位 | 搜尋框可用 D-pad 聚焦，按確認鍵開啟系統鍵盤（隱藏 TextField 與 `_searchText` 雙向同步，組字中不回寫）；返回鍵先關鍵盤並以 `SearchImeBackGuard` 避免 HomeScreen 同時處理；按鍵格改為依高度自適應；`flutter analyze` 無問題 |
| 發布 | GitHub Release `v1.2.2-btr.2`（含搜尋系統鍵盤 `29591a3`、卡片溢出與標題實體 `a535085`） |

### 2026-11-08：去識別化錯誤報告上傳

| 請求 | 結果 |
|---|---|
| 登入失敗時可一鍵上傳去除個人資訊的錯誤報告 | 新增 `LogService`（覆寫 `debugPrint`、捕捉未處理例外、寫入 `logs/app.log` 並輪替）、`sanitizeLogLine` 去識別化、`ErrorReportService`（dpaste.com → paste.rs）、確認／預覽／結果對話框；入口在登入頁與「設定 → 關於軟體」；規格見 `docs/work/error-report/spec.md`；單元測試 `test/log_sanitize_test.dart` |

### 2026-11-08：分區修正、番劇播放、解碼回退與 Netflix 式快退快進

| 請求 | 結果 |
|---|---|
| 修正分區影片、支援番劇播放 | 分區改用新 API（`region/feed/rcmd`）並修正 ID；新增 PGC 番劇索引與季資訊，播放器支援番劇集數解析、連播、進度上報與試看/地區限制處理；commit `107303c` |
| 解碼失敗自動改用 H.264、錯誤報告預設取消 | 偵測 MediaCodec/Decoder 錯誤自動降級 AVC 並寫入設定記錄；AVC 也失敗才顯示錯誤；錯誤報告對話框預設焦點改至「取消」；commit `adf063b` |
| Netflix 式快退快進與預覽卡片 | 控制列隱藏時左右鍵喚出底部進度條與上方預覽卡片（雪碧圖縮圖/時間）；連按加速（10s/30s/60s）；1.5 秒無操作或按確認鍵跳轉，返回鍵取消；commit `b364a91` |
| 建置與安裝驗證 | `flutter build apk --debug` 成功，以 adb 安裝至 `emulator-5554` 成功 |
| 番劇大會員集無法切換 | 改播試看片段並顯示提示；commit `5f21da3`，模擬器驗證 PASS（`e9ac2cd`） |
| 確認進度並發布 64／32 位元版本 | 確認工作皆已 commit；`flutter analyze` 無問題、`flutter test` 8 項通過；版本升至 `v1.2.2-btr.3`，以 `--split-per-abi` 建置 arm64-v8a 與 armeabi-v7a release APK，發布 GitHub Release `v1.2.2-btr.3`（App 內更新會依裝置 ABI 選檔） |
| 搜尋後點影片容易當機（鍵盤殘留）、閃退時詢問上傳錯誤報告、快退快進改成 Netflix 式縮圖列 | agy 調查：B 站雪碧圖最大 160x90；使用者選混合式（停 400ms 後換成從 480P AVC 串流抽出的畫面）。agy 規格審查 5 條、diff 審查 5 條皆採用；`flutter analyze` 無問題、15 項測試通過、debug APK 建置成功；功能待實機測試 |
| 內建 VPN 是否更好 | 說明 VPN 不會加速，只能解地區限制；使用者決定先不做 |
| 看影片出現 -351、錯誤報告上傳 HTTP 400、增加登入方式（同 PiliBTR） | -351 改用 wbi/playurl 與防風控參數；上傳加 bytebin 備援與詳細錯誤；使用者選手機輔助登入、同意新增 `encrypt` 與區網 HTTP 風險；Explore 整理 PiliPlus 登入流程、Sonnet 審查規格 13 條全採用、Sonnet 實作；畫面註明需同一個 Wi-Fi。`flutter analyze` 無問題、22 項測試通過、debug APK 建置成功；未實機測試 |
| 模擬器上錯誤報告仍上傳失敗 | 三個貼文服務都擋 App；使用者選「手機開網頁複製」，Sonnet 實作，26 項測試通過，已裝到模擬器 |
| 關閉上傳或改推 GitHub issue | 不在 App 內放 GitHub token（可被拆出濫用）；移除上傳，手機報告網頁加「在 GitHub 回報」開啟預填的 issue（先複製完整報告，log 過長時截斷）；已裝到模擬器 |
| 請自己在模擬器驗證報告網頁 | 用 adb 操作驗證：發現並修正兩個 bug——登入頁按右鍵焦點進不去（`LoginTab.focusFirstCategory` 未處理登入頁，新增 `LoginViewState.focusDefault`）、報告網頁 JS 字串含實際換行導致整個 script 語法錯誤（改用 `NL`）。驗證：`/report` 200、錯誤代碼 403、`no-store`／`no-referrer`、實際網頁 JS 通過 `node --check`、報告 318 行不含 Cookie／token、GitHub issue 網址 6942 字元並正確截斷；手機登入頁 JS 語法也通過 |
| 按「在 GitHub 回報」出現 GitHub「Whoops, something went wrong!」 | 網址太長：curl 實測 GitHub issues/new 約 7000 字元以上回 500、更長回 414，登入後 Cookie 也占請求標頭；上限從 7000 降為 3500，實際報告產生 3434 字元網址，GitHub 回 302 正常 |
| commit 並發布 64／32 位元版本 | 分 5 個功能 commit、版本升至 `v1.2.2-btr.4`；`flutter analyze` 無問題、26 項測試通過；`--split-per-abi` 建置並發布 GitHub Release `v1.2.2-btr.4` |
| 官方授權影片（銀魂）「獲取影片資訊失敗」、4K 很卡 | curl 確認銀魂 view API 回 `redirect_url` 指向番劇、`season?ep_id=` 可查季；原因為歷史紀錄未處理 `business=='pgc'`、UGC 路徑未轉向。使用者選兩種卡頓原因都修、大會員升級上限為裝置可硬解畫質。Sonnet 審查規格 8 條（採用 6 條半），兩個 Sonnet 平行實作；`flutter analyze` 無問題、10 項新測試通過、release APK 建置成功 |
| 4K 卡頓是 FPS 很低，官方 App 很順（Sony BRAVIA 4K VH22、Android TV 12）；先補手動選 4K 的處理再發布 | 找到根因：MPD 把所有畫質與編碼的串流交給 ExoPlayer 自行選軌，可能選到無法硬解的 4K 而改用軟體解碼；改為只放選定串流（T-6），手動選畫質無法硬解時改用可硬解畫質並提示（T-7，Sonnet）。先前被使用者拒絕的 `git stash` 其實已執行，從 stash 還原並重新套用 T-6／T-7，無資料遺失。`flutter analyze` 無問題、36 項測試通過；分 5 個 commit，發布 `v1.2.2-btr.5`；未實機測試 |
