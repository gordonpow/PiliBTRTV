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
| `7d9aca0` | UP主頁改為全螢幕頁面，新增主頁／動態／投稿分頁（規格：`docs/work/up-space-page/`） |
| `99a1742` | 修正 TV 掃碼登入 48007（改用 android_hd appkey），登入流程加 log |
| `edefb36` | 修正直播間載入失敗時閃退（null controller） |
| `2f0d008` | 一鍵回報問題，經 Google Apps Script 寄到開發者 Gmail（規格：`docs/work/report-to-gmail/`，部署：`docs/report-gmail/`） |

版本號：`lib/btr_version.dart` 為 `v1.2.2-btr.6`（pubspec `1.2.2+6`）。發布：v1.2.2-btr.2（2026-11-07，附 release APK 57.6MB）；v1.2.2-btr.3（2026-11-08，分 64 位元 arm64-v8a 21.3MB 與 32 位元 armeabi-v7a 19.2MB 兩個 APK）；v1.2.2-btr.4（2026-11-08，arm64-v8a 21.6MB、armeabi-v7a 19.5MB）；v1.2.2-btr.5（2026-11-08）；v1.2.2-btr.6（2026-11-09）。

### 已實作、尚未 commit

- 回報編號紀錄：送出成功後在 App 內保存最近 20 筆（編號、時間、類型），「設定 → 關於 → 回報紀錄」可查看。
- 播放器：控制欄隱藏時按 OK 顯示控制欄，新增播放／暫停按鈕（index 0）；自動升級畫質不再升到 HDR／杜比／8K；新增「播放畫面模式」（原生／相容）。
- 設定畫面焦點：移除分頁第一列 autofocus（避免搶走上方分類列焦點）、上鍵改為找正上方最近項目（找不到才回分類列）、退出登入按下鍵回到目前分類、Switch 不再單獨取得焦點、側邊欄向右回到目前分類。
- 觀看歷史：側邊欄焦點移到歷史、從歷史頁播放器返回時背景靜默重抓第一頁。
- 影片卡片焦點預覽：焦點停 1 秒後在卡片內靜音播放 480P AVC 預覽 10 秒（`CardPreviewService`），介面設定可關閉（預設開）；規格見 `docs/work/card-preview/`。
- 焦點暖機秒開：UGC 卡片預覽改用正式畫質播放器（`PlaybackPreparer`、`CardPreviewService` 暖機），按 OK 由播放頁接手；規格見 `docs/work/instant-play/`。
- 卡片預覽即時啟動：單次移動 0.15 秒後開始預覽與預載，長按或快速連按時等停住才只預覽最後一張（`NavSettle`）。
- 播放頁：控制列顯示時按下鍵開相關影片；新增「播放完畢後」（播完暫停／順序播放／單個循環／列表循環／自動連播）與「連播倒數」（預設 5 秒），倒數時右下角顯示待播卡片，OK 立即播、返回取消、下鍵看相關影片；規格見 `docs/work/preview-upnext/`。
- 觀看歷史頁分頁列右側新增「重新整理」按鈕（重新整理目前分頁）。
- 開播加速：`packages/video_player_android`（覆寫套件，起播緩衝 2.5 秒改 0.5 秒）；焦點停住時背景預先解析鄰近 4 張卡片（同排優先）；`BtrHostRanker` 啟動時測 CDN 主機延遲，開播單一連線與 prefetchHead 改用最快主機（失敗退回原網址）；`btrDio` 連線保留 90 秒。規格見 `docs/work/fast-start/`。

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
| UP主主頁改成首頁那種格狀卡片（2026-11-09） | 使用者選全螢幕新頁面、加上粉絲數與投稿數；curl 確認 `x/web-interface/card` 不需登入。Sonnet 審查規格 10 條（9 條半採用），Sonnet 實作；`flutter analyze` 無問題、36 項測試通過；debug APK 已裝到 Android TV API 36 模擬器，待使用者驗證、未 commit |
| 第一次進入 UP主頁載入失敗、UP主要有主頁／動態／投稿（同 PiliBTR） | 失敗原因為 `arc/search` 缺少防風控參數（-352），補上 PiliPlus 的參數並在 -351／-352 時重試一次。Explore 整理 PiliPlus 會員頁：以 App API `x/v2/space` 驅動，curl 確認未登入可用；使用者選動態只顯示影片、投稿含影片與合集／系列、主頁顯示影片類區塊。Sonnet 審查規格 10 條（採用 9 條半），Sonnet 實作；`flutter analyze` 無問題、43 項測試通過；已裝到 TV 模擬器 `emulator-5556`，待驗證、未 commit |
| 使用者無法登入（附 TV 掃碼與手機登入截圖） | TV 掃碼顯示 48007；原因為 TV appkey（雲視聽小電視）拒絕部分帳號，PiliBTR 用 android_hd appkey，curl 實測可產生 QR 與輪詢。Sonnet 修正並為登入流程加上 log；手機登入失敗原因無紀錄，待使用者用新版重試後回報。`flutter analyze` 無問題、43 項測試通過；未 commit |
| 4K 卡頓使用者的 log（Sony BRAVIA VH22，btr.5）、改用 Gmail 回報 | log 顯示已依解碼能力升到 120／125，低 FPS 應非編碼選擇問題，待使用者做「關閉播放加速」「關閉彈幕」對照測試；log 另有直播閃退（`live_player_screen.dart:814` null），已修正。使用者選 Google Apps Script 寄 Gmail；Sonnet 審查規格 8 條全採用、Sonnet 實作；使用者部署腳本，curl 測試回 `ok`。`flutter analyze` 無問題、52 項測試通過 |
| 先發布 | 分 6 個 commit（排除 6 個只有格式變動的檔案與 `log/` 使用者截圖），發布 `v1.2.2-btr.6`；一鍵回報、UP主頁面未經完整實機驗證 |
| 改收件信箱方式、確認網址相同、增加回報編號紀錄、32 位元能否跑 4K | 說明改 Apps Script 的 `TO` 並以「管理部署作業→新版本」更新（網址不變）；確認網址與 App 內相同。使用者選 App 內紀錄，Sonnet 實作；`flutter analyze` 無問題、54 項測試通過，已裝到模擬器，未 commit。說明 32 位元本身不限制 4K，Sony 使用者的低 FPS 待對照測試 |
| 使用者回報：OK 鍵叫不出選項、介面不直觀、設定選不到上方 BAR、4K FPS 低且色彩偏淡 | Explore 找出 OK 只切換播放、設定分頁 autofocus 搶焦點；使用者選不自動升 HDR＋新增播放畫面模式，介面直觀待使用者說明。兩個 Sonnet 平行實作；發現控制欄沒有播放鍵，退回加上播放／暫停按鈕。`flutter analyze` 無問題、54 項測試通過，已裝到模擬器；另提出手機補充說明（Apps Script 表單）待使用者確認 |
| 開模擬器；OK 鍵仍直接暫停 | 開啟 `Android_TV_API36`；模擬器上是舊版，裝最新 debug APK（已含 OK 叫出控制列） |
| 觀看歷史不顯示最新 | 側邊欄焦點切換只換分頁不重抓；加 `refreshSilently()`，焦點到歷史與從播放器返回時背景更新。`flutter analyze` 無問題，已裝到模擬器 |
| 設定頁上鍵跳到分類列、退出登入下鍵跳到介面設定 | 上鍵改為自己找正上方最近項目；退出登入下鍵回到目前分類。`flutter analyze` 無問題，已裝到模擬器 |
| 影片卡片焦點預覽 | 使用者選全部卡片、停 1 秒播 10 秒、靜音、介面設定開關預設開。Explore 探索、Sonnet 審查規格 12 條全採用、Sonnet 實作；`flutter analyze` 無問題、54 項測試通過。模擬器確認預覽播放、預覽中按 OK 進播放頁正常（1080P H.265）；有一支影片預覽遇 CDN 回 567，靜默保持封面。未 commit |
| 焦點 0.3 秒預載、首頁分區往下只有兩列、歷史頁加我的收藏與稍後再看 | 使用者選預載 API＋開頭 2MB、收藏先選收藏夾、三個分頁。首頁根因為 grid builder 中呼叫會 setState 的 `_loadMore`（build 期間 setState），改為卡片 onFocus 觸發並修正失敗還原。Sonnet 審查規格 10 條全採用，三個 Sonnet 平行實作（`PrefetchService`、`PlayParams`、`BtrProxy.prefetchHead`；`TvTabBar`、`fav_view`、`watch_later_view`、`fav_api`）。`flutter analyze` 無問題、57 項測試通過；模擬器 log 確認 playurl、彈幕、預覽命中預載並正常播放 1080P。待使用者測試、未 commit |
| 直播的我的關注與推薦混在一起、個人與設定混在一起、個人資料太少、側邊欄加設定且設定可搜尋 | 使用者選關注獨立成側邊欄、個人頁含基本資料／關注粉絲／我的投稿／登入登出、設定頁搜尋設定項目、設定放最下。側邊欄改為搜尋、首頁、動態、歷史、直播、關注、個人、設定；新增 `FollowLiveTab`、`LiveRoomGrid`、`ProfileTab`、`FollowingsScreen`、`UserApi`、設定索引與搜尋（繁簡共用 `ZhConvert` 正規化）；刪除 `login_tab.dart`。Sonnet 審查規格 12 條全採用，三個 Sonnet 平行實作。`flutter analyze` 無問題、66 項測試通過，已裝到模擬器；待使用者測試、未 commit |
| 關注放回直播頁、齒輪像太陽、直播與歷史互換；沒有預覽；往下一排就補新影片；預載後仍轉圈 | 側邊欄改為搜尋、首頁、動態、直播、歷史、個人、設定，關注為直播頁第一個分類並以分隔線隔開，齒輪重畫（Sonnet）。預覽失敗根因為直連 CDN 回 HTTP 567，改走 BtrProxy；首頁剩不到 3 列就載入；開頭 2MB 改為先直接向原始網址抓（多節點遇連不上的節點要 10 秒以上）；開播前改顯示封面＋角落小轉圈；加 `⏱ [Startup]` 計時 log；側邊欄背景撐滿高度。模擬器自測：預覽出現、往下 8 列持續載入、直播頁分類正確、預載命中後開播 3.3 秒（原 5.4 秒，模擬器網路慢）。`flutter analyze` 無問題、66 項測試通過；未 commit |
| 繼續未完成工作；卡片預覽 1 秒太久要馬上預覽但長按不能每張都預覽；播放中再按下鍵看相關影片；播完倒數 5 秒連播（秒數與模式可調，同 PiliBTR），顯示待播卡片，往下看相關影片停止倒數 | 未完成的是焦點暖機秒開（已實作、analyze 無問題）。新需求寫入 `docs/work/preview-upnext/`；模式沿用 PiliBTR 的 PlayRepeat 五種，倒數秒數 0/3/5/10/15。Sonnet 審查規格 11 條全採用，兩個 Sonnet 平行實作（`NavSettle`＋卡片計時；播放頁倒數、`UpNextCard`、設定）。`flutter analyze` 無問題、66 項測試通過、debug APK 建置成功；模擬器未開啟未安裝，待使用者測試、未 commit |
| 新增觀看紀錄刷新按鈕 | 歷史頁分頁列右側加「重新整理」按鈕，OK 重新整理目前分頁（歷史／收藏／稍後再看）；`flutter analyze` 無問題 |
| 從點選影片到開始播放要約 0.5 秒；預覽要等很久才開始 | 模擬器實測：暖機就緒後按 OK 0.135 秒；移過去馬上按 OK 2.8～3.6 秒（videoInfo＋playurl 約 0.65 秒、播放器 initialize 1.5～2.6 秒）。使用者選兩項都做：覆寫 `video_player_android` 起播緩衝 0.5 秒、鄰近卡片預先解析（Sonnet）。之後發現主因為 B 站給的 `mirrorcosov` 主機 TLS 0.6～2 秒（`mirroraliov` 0.13 秒），新增 `BtrHostRanker` 選最快主機並保留連線（Sonnet）。改善後馬上按 OK 約 2.1 秒（initialize 約 1.1 秒）；同排鄰居優先預先解析後，模擬器網路斷線未能再量。`flutter analyze` 無問題、66 項測試通過；未 commit |
| 推新版並打包專案 ZIP 到另一台電腦修改 | 排除 4 個只有格式變動的檔案與 `log/`、`img/` 截圖，分 6 個功能 commit（`87620f2` 側邊欄／個人頁／設定搜尋、`67cbdca` 歷史頁收藏與重新整理、`290e721` 卡片預覽與暖機秒開、`f3fc6d5` 播完倒數連播、`a466c21` 開播加速、`98c838b` 回報紀錄），版本升至 `v1.2.2-btr.7` 並發布；搬移包見 `C:\presonal_project\PiliBTRTV_transfer_20261109.zip` |

### 2026-11-09：新電腦還原專案

| 請求 | 結果 |
|---|---|
| 配置專案並開啟模擬器 | 專案從搬移包複製到 `C:\presonal_project\PiliBTRTV`（原路徑，對話紀錄可 `/resume`）；`C:\flutter` 由 3.32.0 切到 3.47.9；`flutter config --android-sdk` 後 `flutter pub get` 成功並產生 `android/local.properties`；開啟模擬器 `Pixel_9_Pro_XL`（Android 16） |
| 模擬器上沒看到 App | 前次只開模擬器未安裝；`flutter build apk --debug` 成功（約 6 分鐘），裝到 `Pixel_9_Pro_XL` 並啟動，開機動畫正常。這台沒有 TV 模擬器 `Android_TV_API36` |
| 建一台 Android TV 模擬器，方向鍵要能控制 | 下載 `system-images;android-36;android-tv;x86_64`，建立 `Android_TV_API36`（`tv_1080p`、`hw.dPad=yes`、`hw.keyboard=yes`、4GB RAM）。sdkmanager 需 JDK 17 以上：系統 `JAVA_HOME` 無效、Android Studio `jbr` 損壞，改用 `C:\Program Files\Java\jdk-23`。裝入 debug APK，adb 送兩次 DPAD_DOWN，側邊欄由首頁移到直播，方向鍵可用 |
| 手機登入的手機端網頁打不開 | 模擬器 IP 為 NAT 內的 `10.0.2.15`，手機連不到，實機電視不受影響，不改程式。`adb forward tcp:3321 tcp:3322` 後本機 `/login` 回 403（缺 token，表示服務正常）；區網中繼（電腦 `10.16.32.67:3322`）被權限擋下，交由使用者自行執行 |
| 手機用 USB 網路共用給電腦；手機開網址出現 ERR_TOO_MANY_RETRIES | 區網中繼（只綁 `10.16.32.67`）電腦端測試 200，但手機連線沒到電腦：手機 App 流量走行動網路 `rmnet_data7`，不經 USB 共用介面。改開手機 USB 偵錯，`adb -s R5CY136L62J reverse tcp:3322 tcp:3321`，手機開 `http://127.0.0.1:3322/login?t=...`，手機端 curl 回 403（缺 token，連線正常）；已停止區網中繼 |
| 分析無法登入的使用者 log（report-EKAKJQ，btr.6，SPPL Google TV） | TV 掃碼與簡訊登入都回 48007；btr.6 已改用 android_hd appkey 仍被擋，判斷為 B 站依帳號限制 App 登入。說明 Cookie 登入作法 |
| Cookie 頁加入只用手機的逐步圖文教學；iPhone 改用網頁版掃碼 | iPhone Safari 擴充功能讀不到 HttpOnly 的 SESSDATA。需求與規格見 `docs/work/cookie-guide-webqr/`（Sonnet 規格審查 11 條，採用 9 條）。已實作：網頁版掃碼 API 與 Cookie 解析（T-1）、電視登入頁 TV／網頁版切換與 48007 提示（T-2，第一次子代理回報完成但未寫入檔案，重做後確認）、手機登入代碼首次開啟後延長到 45 分鐘與教學圖片路由（T-4a）。使用者決定先暫停 Cookie 圖文教學，先讓 48007 使用者測試網頁版掃碼。`flutter analyze` 無問題、77 項測試通過；未 commit |
| 使用者回報當機（report-8S73RW，btr.6，自稱 Pixel 3、Android 12、32 位元） | `PlatformViewExoPlayerEventListener.sendInitialized` 對 `getVideoFormat()` 做 `requireNonNull`，裝置解不了影片軌只播聲音時為 null 而閃退。精簡流程修正：null 時改用 VideoSize 回報、旋轉角度異常不修正。「無畫面時改用 H.264 重播」未做 |
| 登入頁按鈕列：回報問題按左鍵跳過重新整理；最左按鈕按左鍵跳到設定而非個人 | 原因為 `focusInDirection` 幾何搜尋選錯目標（含高度相近的側邊欄設定圖示）。每顆按鈕獨立 FocusNode，左右鍵依順序移動，最左按左鍵回 `sidebarFocusNode`（個人），上下鍵與最右按右鍵停留（Sonnet）。`flutter analyze` 無問題、77 項測試通過，已裝到 TV 模擬器，待使用者測試 |
| 網頁版掃碼確認後顯示「Cookie 解析失敗：缺少 SESSDATA、bili_jct、DedeUserID（0）」 | poll 回 `data.code 0` 但 `data.url` 不含 Cookie，推測只由 `Set-Cookie` 下發。輪詢改用 `dart:io` HttpClient，先取 `response.cookies`、缺的再從 url 補；失敗 log 只記欄位名稱與 Set-Cookie 名稱（Sonnet）。`flutter analyze` 無問題、81 項測試通過，已裝到 TV 模擬器，待使用者重測 |
| 開播前載入圈圈放在畫面正中間 | `video_layer.dart` 封面上的轉圈由右下角改為置中，加半透明黑色圓底。`flutter analyze` 無問題，已裝到 TV 模擬器 |
| 推送、建 issue、commit 並發布 | 使用者選合併發布 btr.8（btr.7 未曾推送與發布）；winget 安裝 GitHub CLI 2.103.3、使用者授權登入。建 issue #1（48007 無法登入）、#2（播放閃退）、#3（登入頁焦點）；第一次誤建在上游 Hyper-Beast/BiliTV（#45～#47，因 `upstream` 遠端），已改為「誤建，請忽略」並關閉，`gh repo set-default gordonpow/PiliBTRTV`。分 5 個 commit（排除 4 個只有格式變動的檔案、`img/`、`docs/work/search-crash-seek/` 未追蹤檔），版本升至 `v1.2.2-btr.8`，`--split-per-abi` 建置並發布 GitHub Release；`flutter analyze` 無問題、81 項測試通過 |
| 在使用者的回報紀錄標註已解決 | 使用者選三種狀態（已解決／處理中／無法重現）、只在回報紀錄顯示。repo 根目錄 `report_status.json` 記錄編號、狀態、說明，App 開回報紀錄時下載（URL 加時間戳、404 清快取、壞內容不覆蓋快取、可用 `REPORT_STATUS_URL` 覆寫）。Haiku 規格審查 8 條全採用，Sonnet 實作；`flutter analyze` 無問題、95 項測試通過。TV 模擬器以本機狀態檔與注入的測試紀錄確認：8S73RW、EKAKJQ 顯示綠色「已解決」與說明，未列入的編號無標籤；測試資料已清除。未 commit |
| 從側邊欄個人按右鍵應落在「改用網頁版掃碼」而非「回報問題」 | `login_view.dart` 一般狀態的預設焦點改為按鈕列最左邊的切換按鈕（QR 失敗時仍為「重新產生 QR Code」）。第一次 Edit 因檔案已變動未寫入，發現後重改並重新建置；`flutter analyze` 無問題，已裝到 TV 模擬器 |
| commit 並發布 btr.9 | 建 issue #4（側邊欄進登入頁焦點），分 4 個 commit（回報狀態、焦點修正、文件、版本號），推送 `report_status.json`（8S73RW、EKAKJQ 標為已解決），版本升至 `v1.2.2-btr.9`，`--split-per-abi` 建置並發布 GitHub Release |
| 使用者更新顯示「未安裝應用程式」 | apksigner 比對：btr.6 簽章 SHA-256 `17fcf8ed…`、btr.8／btr.9 為 `1e2d03e1…`（新電腦的 debug.keystore，搬移包未包含）。使用者從舊電腦取回金鑰，指紋相符；複製到 `C:\Users\abcz0\.android\pilibtrtv_release.keystore`，`android/key.properties`（gitignore）指定，`build.gradle.kts` 有此檔時 debug／release 都用它簽署。重新建置 btr.9 並以 `--clobber` 取代 Release 附檔，下載回驗證簽章為 `17fcf8ed…`；btr.8、btr.9 說明加註；issue #5 |
| 2026-11-10 還是無法登入，寫 Cookie 詳細教學；報告 D2MQH4；32 位元 4K 低 FPS | D2MQH4：TV 掃碼、簡訊、網頁版掃碼全部 48007。Cookie 分頁加 16 步圖文教學（Firefox＋Cookie-Editor，複製後切回原瀏覽器貼上），模擬器實拍、遮蔽、轉 WebP（`assets/login_guide/01～16.webp`）；使用者在模擬器登入後實測 Header String 貼上登入成功；圖片路由 200／錯誤代碼 403／不存在 404 已驗證。測試資料已清除。4K 低 FPS 待使用者回報測試結果（未 commit） |
| 2026-11-10 加播放診斷記錄；用借來的帳號測 4K 掉幀並修復 | 新增 `[Stream]`（選定串流）、`[Stats]`（每 10 秒解碼器與掉幀，`PlayerStats.java` AnalyticsListener 經 codec channel 讀取）、報告加畫面模式。模擬器 4K60 每 10 秒掉 140～180 幀：`canHwDecode` 的 `areSizeAndRateSupported` 高估，解碼器 performance point 只到 4K30；改用 performance point／實測幀率判斷，同影片改選 1080p 後不再掉幀。詳見 `docs/work/playback-diag/spec.md`（未 commit） |
| 2026-11-10 3322 埠被佔用時影片全部無法播放 | 手機測試時 3322 被 adb reverse 佔用，LocalServer 啟動失敗，播放器連不到本機 MPD（`Source error`）。`LocalServer.start` 改為 3322～3331 依序嘗試、都失敗由系統分配，`port` 改為實際埠。手機實測：3322 被佔用時改用 3323，4K AV1 正常播放 0 掉幀（未 commit）。另：借用帳號轉移到手機測試（S25 系列 4K60 AV1 硬解 0 掉幀）；Sony 使用者改 HEVC 仍卡，待 btr.10 診斷報告 |
| 2026-11-10 優化效能：先做卡頓自動降畫質、32 位元略過 BTR，並把效能 log 記到最詳細 | 規格見 `docs/work/playback-diag/spec-2.md`。每 10 秒算掉幀率，連續 20 秒超過 15% 自動降一級畫質（每部影片最多 2 次，手動選過畫質後不再降），播放設定新增「卡頓時自動降畫質」（預設開）；32 位元裝置播 4K 不走 BTR 多執行緒；錯誤報告新增「播放效能」一節（`perf_log.dart`、`playback_perf.dart`，最多 200 行，含裝置、螢幕、串流、每 10 秒統計與事件）。TV 模擬器實測：4K60 掉幀 48%／43% 降到 1080p60，再降到 1080p30（16.7%，已達上限）。獨立審查 8 項中低問題已修，113 項測試通過。32 位元略過 BTR 無法在模擬器觸發，待 Sony 使用者報告。觀察：「原生」模式下 1080p60 也只顯示約每秒 9 格，瓶頸可能在影片疊進 Flutter 畫面，「相容」模式畫面停住的問題值得接著查（未 commit） |
| 2026-11-10 影片選項加入收藏、觀看紀錄多選 | 卡片長按選單可選收藏夾、播放器設定面板加「收藏」；觀看紀錄多選可刪除、加入收藏、加入稍後再看（`fav_utils.dart`、`video_action_dialogs.dart`，規格見 `docs/work/fav-multiselect/`）。TV 模擬器以借用帳號驗證 AC-1～7、9 通過（AC-8 未登入情境為免登出而跳過）；遙控器長按以 `input keyevent --duration 900 23` 補驗可跳出選單（`--longpress` 會被判成短按）。測試產生的收藏、觀看紀錄已還原；稍後再看多出「來東京，拍到了些怪東西」一筆，App 無移除功能，需在 B 站手動移除 |
| 2026-11-10 做完驗證完直接推上去（btr.10） | 驗證途中電腦換了網路，TV 模擬器斷網；凌晨約 03:30 冷開機重啟 `Android_TV_API36`（未清資料，借用帳號仍登入）。04:28 對話因 context 滿自動壓縮後停住，之後關機，收藏／多選驗證、commit、推送、發布 btr.10 都**未完成**。對話紀錄當時也未寫入本檔，10:44 補記 |
| 2026-11-10 昨晚做到哪裡、為何沒有對話紀錄；接著做並驗證 | 從對話檔補記上列紀錄。重開 TV 模擬器（冷開機，借用帳號仍登入，網路正常）；`flutter analyze` 無問題、113 項測試通過；Sonnet 子代理完成收藏／多選驗證。接著 commit、推送並發布 btr.10 |
