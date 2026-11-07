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

### 已實作、尚未 commit

- 繁簡切換（T-3）：原始碼文字轉台灣繁體、執行時 ZhConvert、語言設定與重啟（規格：`docs/work/zh-update-icon/`）；已於 feat/zh-update 分支 commit。
- GitHub 自動更新（T-4）：`UpdateService` 改為檢查 gordonpow/PiliBTRTV releases，App 內下載並安裝（`installApk` 回傳 ok/permission、`getSupportedAbis`）；關於軟體分頁新增檢查更新、自動檢查、間隔，有新版時顯示紅點；已於 feat/zh-update 分支 commit。

### 待辦

- 實機測試：播放、跳轉、切畫質、CDN 狀態、設定頁遙控器操作、自訂節點輸入框。
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
