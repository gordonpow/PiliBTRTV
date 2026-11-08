# 規格：錯誤報告改用手機網頁查看

日期：2026-11-08。模擬器實測：dpaste.com（連線錯誤 unknown）、paste.rs（HTTP 400）、bytebin（Cloudflare 403）全部失敗。使用者選「手機開網頁複製」。

## 驗收條件

- AC-1：錯誤報告對話框多一個按鈕「用手機查看」。按下後顯示 QR 碼與網址 `http://<電視 IP>:3322/report?t=<代碼>`，並提示「手機需與電視連接同一個 Wi-Fi」。
- AC-2：手機開啟網址後顯示去識別化後的完整報告（與預覽內容相同），並有「複製全部」與「下載 .txt」按鈕。
- AC-3：「上傳」三個服務都失敗時，失敗畫面直接顯示同一個 QR 碼（不用再按按鈕），錯誤細節收合成一行摘要（例如「dpaste.com、paste.rs、bytebin 都無法使用」）。
- AC-4：代碼錯誤或過期（30 分鐘、或對話框關閉後）回 403。
- AC-5：電視沒有區網位址或 LocalServer 沒在跑時，不顯示 QR，改顯示「請把電視連上 Wi-Fi 或有線網路」。
- AC-6：預設焦點仍在「取消」／「關閉」，D-pad 可操作所有按鈕。

## 設計

- 新檔 `lib/services/report_share_service.dart`：`start(String text)` 產生 16 字元隨機代碼（`Random.secure`），保存報告文字，回傳網址（無位址回 null）；`stop()` 清除；`checkToken(t)` 常數時間比對、30 分鐘逾期。可參考 `lib/services/phone_login_service.dart` 的代碼與比對寫法（可抽共用函式，或直接重用其 `constantTimeEquals`）。
- `lib/services/local_server.dart`：`GET /report?t=` 回 HTML 頁面，`GET /api/report?t=` 回純文字報告。比照 `/login` 的處理方式：不加 CORS 標頭、`Cache-Control: no-store`、`Referrer-Policy: no-referrer`、錯誤代碼 403。開啟前呼叫 `refreshAddress()` 並檢查 `isRunning`。
- 網頁（新檔 `lib/services/report_page.dart`，HTML 字串常數）：行動版版面，fetch `/api/report?t=` 後用 `textContent` 放進 `<pre>`（不可用 innerHTML）。
  - 「複製全部」：先試 `navigator.clipboard.writeText`。區網 http 不是安全環境，通常不能用，所以要退回 `<textarea>` 加 `select()` 再 `document.execCommand('copy')`。成功與失敗都要提示。
  - 「下載 .txt」：用 Blob 加 `<a download="PiliBTRTV-report.txt">`。
  - 頁面上方說明：「把內容貼到 Threads 私訊或 GitHub issue 給開發者」。
- `lib/widgets/error_report_dialog.dart`：
  - 確認階段加「用手機查看」按鈕，按鈕順序為：取消、預覽、用手機查看、上傳。
  - 新增 `_Stage.share`，顯示 QR（`qr_flutter`）、網址、提示。
  - 失敗階段改為顯示 QR，並把錯誤摘要成一行；保留「重試」。
  - 對話框 dispose 時呼叫 `ReportShareService.stop()`。
  - 有 `crashSection` 時，報告內容也要包含它。
- 錯誤報告上傳（`ErrorReportService.upload`）照舊保留，某些網路可能可以用。

## 驗證

- `flutter analyze`、`flutter test`（新增測試：token 錯誤或過期被拒）。
- 模擬器：`adb forward tcp:3322 tcp:3322` 後，在電腦瀏覽器開 `http://127.0.0.1:3322/report?t=<代碼>`。

## 2026-11-08 變更

使用者決定：第三方貼文服務（dpaste、paste.rs、bytebin）在各處都被擋，完全移除上傳，改由手機網頁開預填的 GitHub issue。不內嵌任何 GitHub token。

- 移除 `ErrorReportService.upload` 與對話框的「上傳」、上傳中、完成、失敗階段。確認階段按鈕：取消（預設焦點）、預覽、用手機查看。說明文字改為報告只顯示在電視網頁、僅同一 Wi-Fi 可開，可複製或在 GitHub 回報。
- 手機網頁新增「在 GitHub 回報」：先複製完整報告（含 `execCommand` 退路），再開新分頁 `https://github.com/gordonpow/PiliBTRTV/issues/new?title=&body=`。標題為 `[錯誤報告] ` 加版本行；內文為說明加 ```text 區塊。編碼後網址超過 7000 字元時，保留 `== 最近 log ==` 之前的內容與盡可能多的最後幾行 log，並加註「log 已截斷，完整報告已複製到剪貼簿，可以貼在下方」。
- 按鈕下方提示：「需要在手機上登入 GitHub 才能送出 issue」。
- 本文件上方 AC-3 與「上傳照舊保留」已作廢。
