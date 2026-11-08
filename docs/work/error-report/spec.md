# 需求與規格：錯誤報告上傳（精簡版）

日期：2026-11-08

## 目標

使用者遇到登入失敗或其他錯誤時，可以在電視上一鍵上傳「去除個人資訊」的錯誤報告，取得一個網址（與 QR Code）傳給開發者，用來查 App 的 log 在哪裡出錯。

## 驗收條件

- **AC-1**：登入頁（QR Code 畫面）與「設定 → 關於軟體」都有「回報問題」按鈕，遙控器可選到。
- **AC-2**：按下後先顯示確認對話框，清楚列出會上傳與不會上傳的內容，使用者按「同意並上傳」才上傳；「取消」或返回鍵不上傳。對話框可「預覽內容」（可捲動）。
- **AC-3**：上傳內容只有：
  - App 版本（`btrVersion`）、Android 版本與 SDK、裝置製造商與型號、CPU 架構（ABI）、螢幕解析度、系統語言、App 語言設定。
  - 設定摘要：BTR 開關、CDN 模式、執行緒設定、預設畫質相關設定（不含帳號）。
  - 是否已登入（是／否）。
  - App 內記錄的最近 300 行 log（含未捕捉的例外與 Flutter 錯誤），已去除個人資訊。
- **AC-4**：不會上傳：帳號名稱、UID、頭像、Cookie（SESSDATA、bili_jct、buvid3、buvid4、b_nut）、access_token／refresh_token、觀看紀錄、搜尋紀錄、IP 位址。去識別化規則：
  - `SESSDATA=…`、`bili_jct=…`、`buvid\d=…`、`b_nut=…`、`DedeUserID…=…`、`access_key=…`、`access_token`、`refresh_token`、`csrf=…`、`w_rid=…`、`mid=…`、`uid=…` 的值 → `***`。
  - `Cookie:` 整行 → `Cookie: ***`。
  - IPv4 位址 → `x.x.x.x`。
  - URL 只保留 scheme＋host＋path，query 全部去掉。
  - 搜尋關鍵字 log（`searchVideos`、搜尋紀錄）不記錄。
- **AC-5**：上傳成功後顯示報告網址、可用手機掃描的 QR Code，以及說明「請把網址傳給開發者（Threads 或 GitHub issue）」。失敗時顯示錯誤並可重試。
- **AC-6**：上傳服務依序嘗試 `https://dpaste.com/api/v2/`（form 欄位 `content`、`syntax=text`、`expiry_days=30`，回應本文為網址）與 `https://paste.rs/`（POST 純文字，回應本文為網址）。逾時 15 秒。
- **AC-7**：log 寫入檔案（App 文件目錄 `logs/app.log`，超過 512 KB 時輪替保留一份 `app.log.1`），所以 App 當掉後重開仍可上傳前一次的錯誤。
- **AC-8**：`flutter analyze` 無問題。

## 設計

- 新檔 `lib/services/log_service.dart`：
  - `LogService.init()` 在 `main()` 最前面（`WidgetsFlutterBinding.ensureInitialized()` 之後）呼叫：覆寫 `debugPrint`（仍輸出到 console）、設定 `FlutterError.onError`（保留原本行為並寫入）、`PlatformDispatcher.instance.onError`；`runApp` 包在 `runZonedGuarded` 中捕捉非同步錯誤。
  - 寫入時先去識別化再寫檔（記憶體保留最近 300 行，檔案非同步附加）。每行前綴時間 `HH:mm:ss.SSS`。
- 新檔 `lib/services/error_report_service.dart`：`buildReport()` 組報告文字；`upload(String text)` 依 AC-6 上傳並回傳網址。裝置資訊用既有的 `com.bili.tv/update` MethodChannel 新增 `getDeviceInfo`（回傳 `Build.MANUFACTURER`、`Build.MODEL`、`Build.VERSION.RELEASE`、`SDK_INT`、`SUPPORTED_ABIS`），不新增套件。
- 新檔 `lib/widgets/error_report_dialog.dart`：確認對話框（AC-2 文字見下）→ 上傳中 → 結果（網址文字＋`qr_flutter` QR Code）。遙控器操作：初始焦點在「取消」以外的按鈕要明確；返回鍵關閉。
- 確認對話框文字：
  - 標題：「回報問題」
  - 「將上傳以下內容到公開的貼文服務（dpaste.com），30 天後自動刪除：」
  - 「・App 版本、Android 版本、裝置型號、CPU 架構、螢幕解析度、語言」
  - 「・BTR 與畫質等設定摘要、是否已登入」
  - 「・App 最近的執行紀錄（log），用來找出哪裡出錯」
  - 「不會上傳：帳號、UID、Cookie、登入憑證、觀看與搜尋紀錄、IP 位址。」
  - 按鈕：「預覽內容」「取消」「同意並上傳」
- 入口：`lib/screens/home/login/login_view.dart`（QR 下方，「重新產生 QR Code」旁）與 `lib/screens/home/settings/tabs/about_settings.dart`（新的一列「回報問題」）。
