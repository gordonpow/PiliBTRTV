# PiliBTRTV 專案紀錄

最後更新：2026-11-07

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
| （本次） | 開機動畫改為 PiliBTR 風格：粉紫光線匯聚後浮現圖示，無文字，2.4 秒（`tool/gen_splash.py` 產生） |

版本號：`lib/btr_version.dart` 為 `v1.2.2-btr.2`。發布：v1.2.2-btr.2（2026-11-07，附 release APK 57.6MB）。

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
