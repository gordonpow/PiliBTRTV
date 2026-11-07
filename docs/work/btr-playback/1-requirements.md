# 需求：PiliBTRTV — BiliTV 加上 BTR 多 CDN 播放加速

日期：2026-11-07

## 目標

以 [BiliTV](https://github.com/Hyper-Beast/BiliTV)（Flutter，Android TV 版 B站用戶端）為基底，做出 PiliBTRTV：
把 PiliBTR（`C:\presonal_project\bilibili_bata\PiliPlus`）的「線程撕裂者」（BTR）多 CDN 並行播放加速移植過來，
讓電視上看影片時，資料同時從多個 CDN 節點抓取，減少卡頓。BTR 的設定邏輯與 PiliBTR 相同。

## 驗收條件

- **AC-1**：BTR 播放加速開啟時，一般影片（DASH）的影音資料經由 `127.0.0.1` 本機代理播放；代理把每個 Range 請求切塊，並行向多個 CDN 節點下載後依序交回播放器。影片可正常播放、跳轉、切畫質。
- **AC-2**：BTR 關閉時，播放行為與原版 BiliTV 相同（MPD 內為原始 `baseUrl` 與 `backupUrl`）。
- **AC-3**：節點容錯規則同 PiliBTR：同一檔案中，某節點連續兩次回傳 0 bytes 即停用；全部停用時重新啟用全部節點（最多 3 次）；選節點依「速度 ÷ 進行中請求數」，比最快節點慢 12 倍以上的節點跳過。
- **AC-4**：設定頁新增「線程撕裂者」分類，項目：播放加速開關（預設開）、CDN 模式（大陸／海外／自定義）、自動執行緒數（預設開，播放用 8）、執行緒數（4、8、16、32、64、128；超過 32 顯示限流警告）、自訂 CDN 節點（每行一個 host 或 URL，最多 32 個；自定義模式下沒有節點時不允許儲存並提示）。全部可用遙控器操作。
- **AC-5**：首次啟動依系統語言決定 CDN 模式：繁體中文或 TW/HK/MO 地區用「海外」，其他中文用「大陸」，其他語言保留預設（大陸）；使用者選過的模式不會被覆蓋。
- **AC-6**：改變 BTR 設定後，下一部影片生效（清除代理的來源快取）。
- **AC-7**：播放器設定選單新增「CDN 狀態」，每秒更新：總下載速度、各節點 host、速度、已收資料量、是否停用；BTR 關閉或沒有代理資料時顯示「未使用 BTR（直連）」。
- **AC-8**：App 名稱改為 `PiliBTRTV`，`applicationId` 改為 `com.gordonpow.pilibtrtv`，可與原版 BiliTV 同時安裝。
- **AC-9**：`flutter analyze` 對新增與修改的檔案沒有 error；`flutter build apk` 成功。
- **AC-10**：程式碼推送到 `https://github.com/gordonpow/PiliBTRTV.git`（`origin`），上游 BiliTV 保留為 `upstream`。

## 不做的範圍

- 離線下載（BiliTV 原本就沒有）。
- 直播（`live_player_screen.dart`）的 BTR 加速。
- 既有介面文字從簡體轉為繁體（只有新增的文字用繁體中文）。
- 更換圖示、改 Dart package 名稱（`bili_tv_app`）、改 Kotlin package 路徑。
- PiliBTR 的其他功能（迷你播放器、豎屏等）。

## 限制

- 新增文字、註解、文件、commit 只用繁體中文（台灣用語）或英文。
- BTR 程式碼來源：PiliBTR（GPL v3）與 Bilibili-thread-ripper-desktop（MIT），檔頭保留來源說明。
- 電視遙控器操作：方向鍵、確認鍵、返回鍵。
- 使用者已在需求問答中確認範圍，AC 關卡略過（2026-11-07）。
