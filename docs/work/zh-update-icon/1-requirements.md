# 需求：修正影片無法播放、繁簡切換、自動更新、圖示、模擬器測試

日期：2026-11-07
參考專案（只讀）：PiliBTR `C:\presonal_project\bilibili_bata\PiliPlus`

## 目標

修正 v1.2.2-btr.1 點影片顯示「获取视频信息失败」的問題；加入與 PiliBTR 相同規則的繁簡切換、GitHub 自動更新，圖示改為與 PiliBTR 相似；並在電腦上用 Android TV 模擬器測試。

## 根因（已查證）

`https://api.bilibili.com/x/web-interface/view` 沒帶 `buvid3` cookie 時回 HTTP 412（B站風控）；帶上 `buvid3` 就回 `code: 0`。和 BTR 無關。`buvid3` 可由 `https://api.bilibili.com/x/frontend/finger/spi` 取得（`data.b_3`）。

## 驗收條件

### 影片資訊
- **AC-1**：未登入與已登入時，點影片都能取得影片資訊並開始播放（不再出現「獲取影片資訊失敗」）。所有 B站 API 請求都帶 `buvid3` cookie。

### 繁簡切換（規則同 PiliBTR）
- **AC-2**：介面原始文字改為繁體中文台灣用語（OpenCC `s2twp`，例如「视频」→「影片」、「设置」→「設定」、「软件」→「軟體」）。和伺服器回傳文字比對的字串常數保留簡體並加註解。
- **AC-3**：設定新增「語言」：跟隨系統（預設）／繁體中文／簡體中文。跟隨系統：系統語言為 zh 且為 Hans 或 CN、SG → 簡體，其他 → 繁體。
- **AC-4**：繁體模式：畫面上所有文字（含伺服器資料：標題、UP 主名稱、留言、彈幕）在顯示時以 OpenCC `s2tw` 轉成繁體字（不做詞彙替換，資料本身不改）。簡體模式：以 `tw2sp` 轉回簡體，介面字串用整句對照表（`t2s_ui.txt`）得到完整簡體用語。
- **AC-5**：切換語言後詢問是否立即重新啟動 App；選「立即」會重啟，選「稍後」則下次啟動生效。

### 自動更新（邏輯同 PiliBTR）
- **AC-6**：從 `https://api.github.com/repos/gordonpow/PiliBTRTV/releases` 取得最新非 draft、非 prerelease 的 release，tag 依 `主.次.修-btr.N` 比較版本，比目前版本（`lib/btr_version.dart`）新才算有更新。
- **AC-7**：自動檢查：預設開；App 啟動時、回到前景時、設定改變時排程；間隔預設 24 小時（可設定）。自動檢查不彈視窗，只在設定側欄分類與「關於」相關項目顯示紅點。
- **AC-8**：設定中可手動「檢查更新」（顯示「已是最新版本」／「發現新版本 vX」／「檢查更新失敗，請檢查網路」）、開關自動檢查、設定間隔。
- **AC-9**：有新版本時可檢視版本說明，按「下載並安裝」下載 APK（顯示進度）後開啟系統安裝程式；沒有安裝權限時引導開啟權限並提示再按一次。APK 選擇：檔名含裝置 ABI 者優先，否則取 release 中第一個 `.apk`。
- **AC-10**：移除 BiliTV 原本的私有更新伺服器設定（`update_server_url`、`update_api_key`）。

### 圖示
- **AC-11**：launcher 圖示改用 PiliBTR 的圖示（`assets/images/logo/logo_2.png` 前景、白底，與 PiliBTR 的 `flutter_launcher_icons` 設定相同）；TV banner（`@drawable/banner`，320×180）改為 PiliBTR 圖示加「PiliBTRTV」文字。

### 模擬器
- **AC-12**：建立 Android TV 模擬器（API 33，x86），可在電腦上安裝並執行 debug APK；以 adb 截圖確認首頁、設定（語言、更新、線程撕裂者）與影片播放畫面。

### 共通
- **AC-13**：`flutter analyze` 無 error；`flutter build apk --release` 成功。

## 不做的範圍

- 開機動畫影片（`assets/icons/startup.mp4`）不換。
- 直播 BTR。
- 簽署金鑰維持 debug（沿用 BiliTV）。

## 限制

- 文字、註解、文件、commit 只用繁體中文或英文。
- 遙控器可操作。
- 使用者已在請求中指定範圍，AC 關卡略過（2026-11-07）。
