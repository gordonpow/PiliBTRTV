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
- 播放器導覽與手機回報（2026-11-10 實作中，規格見 `docs/work/player-nav-feedback/`）：
  - 播放完畢後的 5 種模式，並支援合集。
  - 控制列新增上一部、下一部按鈕。
  - 彈幕按鈕：短按開關，長按打開設定。
  - 相關影片改成底部橫排。
  - 用手機輸入回報問題／建議。

### 待辦

- 4K60 卡頓（Sony BRAVIA VH22，報告 2K4EBR、GCBB9P、BVESCZ、HXUSJ7）：
  - 換成 HEVC 4K60（`OMX.MTK.VIDEO.DECODER.HEVC`）後，掉幀一樣是 86–91%，「原生」和「相容」兩種模式都一樣；1080p60 是 0%。所以「AV1 解碼器太弱」的判斷不成立。
  - 目前最可能的原因：MTK 電視晶片在非隧道（non-tunneled）路徑上，4K60 的解碼輸出跟不上；官方 App 可能用了 tunneled playback。
  - 待確認：官方 App 播同一部影片時，是不是真的是 4K 60 幀。
  - 下一步：
    1. 效能紀錄加入解碼器的 `FEATURE_TunneledPlayback`、`getAchievableFrameRatesFor(3840x2160)`、`PerformancePoint`。
    2. 「原生」模式加入實驗性的 ExoPlayer tunneling 選項。

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
| 2026-11-10 昨晚做到哪裡、為何沒有對話紀錄；接著做並驗證 | 從對話檔補記上列紀錄。重開 TV 模擬器（冷開機，借用帳號仍登入，網路正常）；`flutter analyze` 無問題、113 項測試通過；Sonnet 子代理完成收藏／多選驗證。遙控器長按以 `--duration` 補驗通過。分 6 個 commit（57c1ada～1fb743f，排除 5 個只有格式變動的檔案）並推送；`--split-per-abi` 建置，簽章 `17fcf8ed…`、versionCode 1014／2014，x86_64 版裝到 TV 模擬器開啟正常；發布 GitHub Release v1.2.2-btr.10 |
| 2026-11-10 稍後再看與收藏加上移除功能 | 規格見 `docs/work/remove-saved/2-spec.md`（精簡版）。「稍後再看」分頁長按出現「從稍後再看移除」（`/x/v2/history/toview/del`），「我的收藏」分頁長按出現「從此收藏夾移除」（`dealFavorite` delIds），移除後焦點落在下一張、清單空時回到分頁列／收藏夾列，收藏夾數量同步減 1（Sonnet 實作）。`flutter analyze` 無問題、113 項測試通過。TV 模擬器以遙控器長按驗證：移除借用帳號中先前測試加入的稍後再看影片，重新整理後清單為空；「設計」收藏夾加入一部後移除，數量 2→1、焦點移到下一張 |
| 2026-11-10 推上去並發布 btr.11 | 版本升至 `v1.2.2-btr.11`（`1.2.2+15`），`--split-per-abi` 建置，簽章 `17fcf8ed…`、versionCode 1015／2015，推送並發布 GitHub Release v1.2.2-btr.11（移除稍後再看、從收藏夾移除） |

### 2026-11-10（下午）：播放器導覽、手機回報、4K60 診斷

- 請求：
  - 播完行為 5 種模式（含合集）。
  - 上一部／下一部按鈕。
  - 彈幕按鈕：短按開關、長按設定。
  - 底部相關影片可以展開。
  - 用手機打字回報問題／建議，「回報問題」改名為「回報問題/建議」。
- 4K 報告分析：
  - 2K4EBR、GCBB9P：AV1 4K60 掉幀約 90%。
  - BVESCZ、HXUSJ7：改成 HEVC 後一樣，「原生」和「相容」兩種模式都一樣；1080p60 是 0%。
  - 判斷是非隧道路徑撐不住 4K60。使用者確認官方 App 播同一部影片很順。
- 4K 處理：做了「記住此裝置 4K60 不順」、「隧道播放（實驗）」開關、解碼器能力診斷（`docs/work/4k-av1/`）。
- 驗證：
  - 播放器功能已在模擬器驗證，結果見 `docs/work/player-nav-feedback/3-verification.md`。
  - analyze、test（152 項）、三個 ABI 建置都通過。
- 控制列重排（使用者附截圖）：
  - 點讚、投幣、收藏直接放在右下角，收藏一鍵切換（不用再進一層選單）。
  - 在看人數與畫質移到右上角，刪除彈幕數。
  - 收藏實際按壓沒有在借用帳號上測試（權限系統阻擋），待使用者確認。
- 發布 v1.2.2-btr.12：
  - commit：36f8ba0（手機回報）、89cb8d2（播放器與 4K60）、d4feaa8（版本），加上 docs commit。
  - APK 簽章 17fcf8ed…，versionCode 2016／1016。
  - 發布說明在 `docs/work/player-nav-feedback/release-notes-btr.12.md`。
- 備註：agy CLI 在這台電腦上沒有安裝，所以沒有詢問 agy。

### 2026-11-10（晚上）：4K 卡頓 log 與直式影片綠塊
- 分析 Sony BRAVIA VH22 的 4K 卡頓報告（report-FHEQR9、report-VYVM2X）：
  - 隧道模式播 HEVC 4K60 約 60fps 不掉幀；一般模式（textureView／隧道關）掉幀 42–86%。
  - 卡的那幾次都是按 OK 接手卡片預覽的暖機播放器；暖機強制 textureView，所以隧道不會生效。
  - qn=125 HDR 的長時間緩衝是網路瓶頸（32 位元裝置跳過 BTR，海外 CDN 約 16–20Mbps）。
- 使用者回報 Google TV Streamer 直式影片右側有綠塊（report-WC3UPC 的 log 沒涵蓋那次播放）。畫面上影像寬度剛好是框的 9/16，推測是 textureView 尺寸錯位，同樣來自暖機接手。
- 修正（尚未 commit、尚未實機驗證）：畫面模式為「原生」時不接手 textureView 暖機播放器，改用 platformView 重新準備；「相容」模式維持暖機秒開。改動在 `lib/screens/player/player_screen.dart`、`lib/screens/player/mixins/player_action_mixin.dart`。
- 模擬器測試前一律先靜音（使用者要求）。
- 修正 commit `6825538`（原生畫面模式不接手 textureView 暖機播放器）並推送。
- 發布 v1.2.2-btr.13：版本 commit `cf4ee75`（`1.2.2+17`），`--split-per-abi` 建置，簽章 `17fcf8ed…`、versionCode 2017／1017；GitHub Release 附 arm64-v8a（23.9MB）、armeabi-v7a（21.7MB）。發布說明在 `docs/work/player-nav-feedback/release-notes-btr.13.md`。未實機驗證，待 BRAVIA 使用者回報。
- 使用者要求移除「記住此裝置 4K 60 幀不順、之後從 1080P60 開始」與設定頁「重設 4K 60 幀偵測」：Sonnet 刪除 8 個檔案中的相關程式（保留播放中依掉幀自動降畫質）；`flutter analyze` 無問題、148 項測試通過。尚未 commit。
- 發布 v1.2.2-btr.14：commit `2992ca3`（移除 4K60 不順記錄）、`4196abb`（版本 `1.2.2+18`），簽章 `17fcf8ed…`、versionCode 2018／1018；GitHub Release 附 arm64-v8a、armeabi-v7a。發布說明在 `docs/work/player-nav-feedback/release-notes-btr.14.md`。未實機驗證。
- 分析 report-Y6WQM3（btr.14，BRAVIA）：全部進入隧道模式，HEVC 4K60 約 60fps；AV1 4K60 在隧道模式三次卡在緩衝（23–46 秒）。
- 修正 AV1 卡住（`docs/work/av1-tunnel-stall/`）：A＝隧道＋原生＋auto 編碼播 4K 高幀率時優先 HEVC；B＝原生 playWhenReady＋BUFFERING 持續 8 秒且已緩衝 ≥ 10 秒判定解碼卡住，依 AV1→HEVC→AVC 換編碼重載（不寫永久設定）。Sonnet 規格審查 8 條採用 7 條，Sonnet 實作；`flutter analyze` 無問題、164 項測試通過、原生 Java 編譯成功。尚未 commit、未實機驗證。
- 模擬器 App 內更新失敗：x86_64 版 versionCode 4015，Release 只有 ARM（2018），被判降版（INSTALL_FAILED_VERSION_DOWNGRADE）；改用 adb 裝 btr.14 x86_64（4018）。
- 模擬器手動選真彩 HDR 黑畫面：HEVC Main10 超出解碼能力 → 永久改用 AVC 且標籤錯誤。修正（`docs/work/hdr-fallback-direct-speed/`）：HDR／10-bit 失敗只降到較低非 HDR 畫質、不寫永久設定；畫質標籤用實際串流；非 HDR 螢幕隱藏 125／126；CDN 狀態直連時顯示直連速度與估計頻寬。
- 兩項（AV1 卡住、HDR）合併 diff 審查（Sonnet）5 條：#1～#4 與 #5 的彈幕索引、降畫質計數採用並修正；`isPreview` toast 未採用（影響小）。`flutter analyze` 無問題、171 項測試通過。尚未 commit、未實機驗證。
- 補修重載剛結束時新播放器出錯被略過的時序問題（finally 後再檢查一次 hasError）。
- 發布 v1.2.2-btr.15：commit `f7c55d8`（AV1 卡住、HDR 回退、畫質標籤）、`1b7126b`（直連網速）、`581469e`（規格）、`3dc53ba`（版本 `1.2.2+19`）；簽章 `17fcf8ed…`、versionCode 2019／1019；GitHub Release 附 arm64-v8a、armeabi-v7a。發布說明在 `docs/work/av1-tunnel-stall/release-notes-btr.15.md`。未實機驗證，待 BRAVIA 使用者回報。
- 使用者回報：側邊欄「觀看歷史」按右鍵焦點落在中間卡片。修正：比照直播／個人頁，按右鍵呼叫 `HistoryTabState.focusFirstItem()`，落在目前分頁第一個項目。
- 使用者回報：搜尋一次後無法直接再搜尋，要按返回。修正：結果頁上方關鍵字改為可聚焦搜尋框（排序列按上、按確定回鍵盤），側邊欄搜尋在結果頁再按確定也回鍵盤；回鍵盤時帶入上次關鍵字並聚焦搜尋框。`flutter analyze` 無問題；尚未 commit、未在模擬器測試。
- 使用者回報：側邊欄設定按右鍵跳到上次停留的「關於軟體」。修正：`focusFirstCategory()` 一律聚焦第一個分類「播放設定」（聚焦即切換內容）。尚未 commit。
- 使用者提醒每個問題都要開 issue：補開 #6～#15（#6～#11 已發布並關閉，#12～#15 待發布／實作中）。
- 英文介面（`docs/work/english-ui/`）：比照 PiliBTR 執行時字典翻譯，語言改選單一次選定，README 英文＋繁中。Sonnet 規格審查 11 條採用 10 條；Sonnet／Haiku diff 審查兩份，採用並修正（下載互斥、60 秒時限、損毀重下、tv_live_card 型別、字典清理、抽字串閘門）。另把「天／個／秒」單位改為可翻譯寫法。`flutter analyze` 無問題、188 項測試通過、語言包 558 條未翻譯 0。
- 發布 v1.2.2-btr.16：commit `bed06ba`（#12）、`a7aab1c`（#13）、`0b4c235`（#14）、`45b4c15`（#15 英文介面）、`5db7eaf`（README）、`691b24d`（規格）、`31dc437`（版本 `1.2.2+20`）；簽章 `17fcf8ed…`、versionCode 2020／1020；`i18n/en.json` 已推到 main 並確認可下載。關閉 #12～#15。發布說明 `docs/work/english-ui/release-notes-btr.16.md`。未實機／模擬器驗證英文畫面排版。

### 2026-11-11：播放完畢後改用次級選單
- 使用者要求播放器設定「播放完畢後」改用次級選單（#16）：比照播放速度，確定／右鍵進入，列出所有模式並標示目前模式，確定套用後回主選單，左鍵／返回回主選單；移除循環切換 `cyclePlayEndMode`。Sonnet 實作，`flutter analyze` 無問題、188 項測試通過。尚未 commit。
- 使用者反映英文模式下彈幕、字幕、影片名稱不會翻譯（依設計 B 站內容不翻譯）。討論後決定以 Google ML Kit 裝置端翻譯分兩階段做：#17 第一階段（標題、簡介、UP 主名稱、留言、字幕）、#18 第二階段（彈幕，需低階電視效能驗證）。調查中。
- 使用者測試 #16 次級選單 OK；btr.17 已建置（簽章 `17fcf8ed…`、versionCode 2021／1021）但 push／Release 被自動權限擋下，未發布。
- 使用者要求收藏按鈕顯示收藏到哪個資料夾（#19）：☆改開收藏夾選單，套用後 toast 列出資料夾名稱並同步星星；已裝到模擬器待測，未 commit。
- #17 範圍確認：CC 字幕（新功能，所有語言）＋英文模式 ML Kit 翻譯標題／UP 主名稱／直播標題／簽名／字幕；APK 增大已接受。需求 `docs/work/content-translate/1-requirements.md` 使用者已確認，撰寫規格中。
- #17 實作完成（T-1／T-2／T-3），APK 各增加約 16～17MB；diff 審查兩份（字幕 8 項、翻譯 8 項）皆採用。字幕修正進行到一半時 Sonnet 達 5 小時用量上限（02:00 重置）中斷；待修清單記在 `docs/work/content-translate/2-spec.md` 末尾。尚未 commit。
- 使用者測試 #19 收藏 OK，commit `b80ee6a`（只含 #19 的 hunk）。新增需求 #20 本機收藏：多個本機收藏夾、顯示於觀看歷史「收藏」分頁、登入後詢問是否匯入帳號預設收藏夾。需求文件 `docs/work/local-favorites/1-requirements.md`。
- #17 模擬器測試回饋：未登入無法收藏（屬 #20）、英文模式標題沒翻譯（翻譯開關預設關閉、模型從未下載）、未登入沒有字幕選項。使用者決定：英文模式預設開啟翻譯並背景下載模型；控制列彈幕旁加字幕按鈕（無字幕變暗並提示原因）；未登入比照 PiliPlus 用 gRPC DmView 取得字幕。兩個 Sonnet 平行實作中。另修 btr.16 的 i18n_pack_test 偶發失敗（Windows 刪暫存資料夾重試）。
- 第二輪模擬器回饋：英文標題要先開字幕再退出才變英文（背景下載後未刷新）、控制列設定與按讚圖示太近、未登入收藏仍要求登入（#20 尚未實作）。兩個 Sonnet 平行：修 #17 刷新與排版；#20 寫規格並實作（規格審查併入 diff 審查）。
- #20 本機收藏實作完成，diff 審查 8 項全部採用並修正（匯入焦點與再詢問、bvid 判斷星星、存 cid／epId／seasonId、只有 JSON 損毀才改名備份等）。子代理誤跑 `dart format lib test`，6 個無關檔案只有排版差異，已確認後 `git restore`。#17 第二輪：翻譯模型輪詢就緒後刷新、控制列間距、字幕依控制列實際高度上移、標題資訊分段翻譯；先前誤判的簡體字為影片內嵌硬字幕。`flutter analyze` 無問題、246 項測試通過。均未 commit。
- 使用者測試 OK，要求推送並發布。commit `ab2ce84`（測試修正）、`7bef312`（#17＋#20 合併：兩者共用播放器檔案與語言包）、`abff112`（規格）。發布 v1.2.2-btr.17（含 #16 `e9fbe23`、#19 `b80ee6a`、#17、#20；版本 commit `224768d`，`1.2.2+21`）：簽章 `17fcf8ed…`、versionCode 2021／1021，arm64-v8a 39.2MB、armeabi-v7a 32.6MB。#18（彈幕翻譯）保留。發布說明 `docs/work/player-nav-feedback/release-notes-btr.17.md`。

### 2026-11-11（下午）：Chromecast ANR 與模擬器巡檢
- 使用者提供回報 ED3GSM（btr.15，Google Chromecast，ANR），要求找出錯誤並修正、驗證，再操作 App 找問題並自行修復。
- 分析：主執行緒在 Dart 程式碼中等待分頁換入（RSS 616MB、Swap 69MB），事件迴圈停約 10.6 秒；停頓前連續移動焦點，預載、暖機播放器、鄰近預先解析同時進行，已取消的暖機仍會跑完 `initialize`。發布版沒有符號檔，重建 btr.15 的位址對不上，無法還原 Dart 函式名稱。開 #21。
- #21 修正（已實作未 commit）：預覽／暖機播放器序列化（`PlayerSlot`）、連續移動時延長等待、低記憶體裝置降低圖片快取與預先解析數量、記憶體不足時停止預覽並清快取。需求與規格在 `docs/work/focus-anr/`。
- 使用者指定新分工：實作先用 agy 的 Sonnet、用完換 Claude 的 Sonnet；驗證先用 agy 的 Gemini Flash、用完換 Claude 的 Fable；遇到用量限制等解除後自動重做。
- 驗證：Claude Fable 達用量上限，改用 agy Gemini 3.8 Flash 審查，#21 四項發現查證後都不採用。agy 的 Sonnet（`claude-sonnet-4-6`）在非互動模式兩次都只讀檔就結束、沒有改檔，實作改由 Claude Sonnet 進行。
- 模擬器巡檢（英文介面）：#21 的五項測試通過（快速移動焦點無 ANR、按 OK 接手正常、記憶體不足時播放不中斷）。另找到五個問題並開 issue：#22 分頁列被時鐘蓋住、#23 App 更新後語言包沒有跟著更新、#24 搜尋結果第一排卡片被裁切、#25 觀看歷史卡片名稱與時間沒有間隔、#26「抽幀逾時」log 洗版。
- #22–#26 修正（已實作未 commit）：Gemini Flash 審查兩項低嚴重度，採用一項（分頁卸載時的 `context.mounted` 保護）。模擬器複測 #22、#24 通過；#23、#25、#26 只有程式碼審查與單元測試。`flutter analyze` 無問題，測試 258 個通過。

### 2026-11-11（傍晚）：記憶體分級、長按快進、隱藏互動按鈕、續播進度
- 使用者提出四項：依記憶體動態調整快取與預載（#27）、播放時短按微調長按快進（#28）、設定個別隱藏投幣／按讚／收藏（#29）、手機調整進度後電視按播放從頭開始（#30）。需求與規格在 `docs/work/feedback-1111/`。
- #30 根因（模擬器確認）：`x/web-interface/view` 不回傳 `history`，續播一律用電視本地快取（無時間戳），舊值接近片尾就被當成看完從頭播。改為已登入時先查 `x/player/wbi/v2` 的 `last_play_time`／`last_play_cid`，失敗才比較本地快取（新增儲存時間）與列表 `view_at` 取較新者。
- #27：總記憶體分 low／mid／high，每 15 秒查可用記憶體，不足或收到記憶體壓力時進入 critical（停止預覽／暖機與鄰近預解析、縮小快取），連續兩次恢復才離開。
- #28：短按固定 10 秒；按住依時間加速（30→90→max(180, 片長/20) 秒/秒）。#29：播放設定新增三個顯示開關。
- 實作：T-2 由 agy Sonnet（`--mode accept-edits`，原本的 runner 是唯讀 plan 模式）完成；T-1、T-3 的 agy Sonnet 讀檔後結束，重試時 agy 用量用完（429），改由 Claude Sonnet 完成。審查用 agy Gemini 3.8 Flash：規格 5 條全採用；實作審查 3 條採用 2 條。
- 驗證：`flutter analyze` 無問題、292 項測試通過。模擬器：啟動 tier=mid、trim-memory 進入 critical、約 25 秒後恢復 mid；觀看歷史卡片 02:30 開啟後 log `source=server progress=150`。#28、#29 未在模擬器操作。均未 commit。
- 使用者回報 #31：設定頁捲到底後切到其他頁再回來，焦點重置到頂端但捲動位置停在底部。Claude Sonnet 全域檢查並修正：焦點重置到第一項時同步把捲動位置歸零（設定、我的、直播、觀看歷史、收藏夾、稍後再看）；返回原位置的流程不動。模擬器驗證設定頁情境通過。未 commit。
- 使用者回報 #32 字幕跑到畫面中間（`Align` 內多包 `Center` 撐滿區域，已移除）與 #33 大會員杜比音效沒有選項。#33 新增播放器「音質」子選單（標準／杜比全景聲／Hi-Res 無損，裝置不支援變暗，選擇會記住，杜比播放失敗自動退回標準），MPD 只放選定的一條音軌。規格 `docs/work/dolby-audio/2-spec.md`。Claude Sonnet 實作；使用者指定驗證改用 agy Opus，但 agy 用量用完，改由 Claude Sonnet 審查（7 條採用 5 條）與模擬器驗證（#32 通過、音質選單通過，杜比變暗未能驗證）。`flutter analyze` 無問題、296 項測試通過。未 commit。
- 使用者回報 #34：請別人在電視上掃碼登入，常卡在「已掃描，請在手機上確認」。可能原因：登入流程的請求沒有逾時，成功後抓使用者資訊卡住或丟例外時輪詢已停，畫面停在已掃描；輪詢每 2 秒觸發會重疊。只改 `login_view.dart`（`auth_api.dart` 為使用者修改中的檔案，不動）：輪詢不重疊且晚到的結果照常處理（20 秒 watchdog）、抓使用者資訊 8 秒逾時且不擋登入、存憑證失敗顯示錯誤可重新掃描、已掃描超過 60 秒顯示提示、TV 模式也記狀態轉換 log。agy 審查 3 條全採用。`flutter analyze` 無問題、296 項測試通過。未實際登入驗證，未 commit。
- 使用者要求發布。commit `e776ea6`（#22–#26、#31、#32 介面修正）、`2cea491`（#34 掃碼登入）、`1436e65`（#21、#27、#28、#29、#30、#33 合併：共用播放器與預載檔案）、`44a09c4`（需求與規格）、`8321aad`（版本 `1.2.2+22`）。語言包補齊 3 條並把 log 字串加入 exclude，未翻譯 0。發布 v1.2.2-btr.18：簽章 `17fcf8ed…`、versionCode 2022／1022，arm64-v8a 41.1MB、armeabi-v7a 34.3MB。使用者修改中的 4 個檔案只有排版差異，未 commit。發布說明 `docs/work/feedback-1111/release-notes-btr.18.md`。
