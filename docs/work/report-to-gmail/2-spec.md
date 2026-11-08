# 規格：一鍵回報問題（Gmail）

需求：[1-requirements.md](1-requirements.md)

## 資料流

```
回報對話框（選類型）──送出──> ReportSendService.send(category, report)
   POST <scriptUrl>  Content-Type: text/plain;charset=utf-8  body = JSON
   ├─ 302 → 以 GET 跟隨 Location（script.googleusercontent.com/macros/echo…），取得腳本 JSON
   └─ 200 → 直接解析 JSON
腳本（doPost）：驗證 → 頻率限制 → MailApp.sendEmail（附件 report.txt）→ {ok:true,id} 或 {ok:false,error}
```

- 用 `text/plain` 送 JSON（Apps Script 讀 `e.postData.contents`），避免 CORS 預檢等問題。
- `http.Request('POST', uri)..followRedirects = false`，再對 `Location` 發 GET。逾時：POST 20 秒、GET 10 秒。

## App 端

### 設定 `lib/config/report_config.dart`（新增）

```dart
const String kReportScriptUrl = '';      // 開發者部署後填入 https://script.google.com/macros/s/.../exec
const String kReportToken = 'pilibtrtv-report-v1'; // 與腳本相同；只是基本過濾，不是機密
```

### `lib/services/report_send_service.dart`（新增）

- `static bool get enabled => kReportScriptUrl.isNotEmpty;`
- `static Future<String> installId()`：SharedPreferences `report_install_id`，沒有就產生 16 碼隨機英數字並儲存。
- `static String newReportId()`：6 碼大寫英數字（排除易混淆的 0/O/1/I）。
- `static Future<ReportSendResult> send({required ReportCategory category, required String report})`
  - body JSON：`{token, id, installId, category: category.label, version: btrVersion, device: '<brand> <model>', android, report}`。`device`、`android` 從報告前幾行解析不到時留空（或沿用 `ErrorReportService` 已取得的值，可新增 `ErrorReportService.deviceSummary()`）。
  - `report` 超過 500,000 字元時保留開頭 20,000 字元（裝置資訊）與最後的部分，中間以 `…（中略）…` 取代。
  - 結果：`ReportSendResult.ok(id)`、`ReportSendResult.fail(message)`。失敗訊息：無網路／逾時 → 「無法連線，請確認網路」；腳本 `{ok:false,error:'rate'}` → 「回報太頻繁，請稍後再試」；`'quota'` → 「今日回報已達上限，請改用手機查看」；其他 → 「送出失敗（<原因>）」。
- `enum ReportCategory { stutter('播放卡頓／畫面問題'), login('無法登入'), crash('閃退／當機'), playback('無法播放'), other('其他') }`。

### `lib/widgets/error_report_dialog.dart`

- 新增階段：`select`（選類型，`enabled` 時的第一步）、`sending`、`sent`、`failed`；保留 `confirm`／`share`（手機 QR）。
- `select`：標題「回報問題」，類型清單（`ListView` 的可聚焦按鈕，預設焦點：有閃退時「閃退／當機」，否則第一項），下方說明送出內容（沿用現有 confirm 的文字），按鈕「送出」（主要）、「改用手機查看」、「取消」。選類型＝聚焦＋確認即選取（選取項目以粉色框標示），「送出」才寄出。
- `sending`：轉圈＋「正在送出…」。
- `sent`：「已送出，回報編號 ABC123。開發者會透過 Email 收到這份報告。」按鈕「完成」。
- `failed`：顯示失敗訊息，按鈕「重試」「改用手機查看」「關閉」。
- `!ReportSendService.enabled`：維持現有流程（confirm → share），不顯示 select。
- 閃退情境（`crashSection != null`）：送出成功後與現在一樣清除閃退紀錄（沿用現有呼叫點的邏輯，不改 `home_screen.dart` 行為）。

## 腳本端 `docs/report-gmail/apps_script.gs`（新增）＋ `docs/report-gmail/README.md`（部署步驟）

```js
const TOKEN = 'pilibtrtv-report-v1';
const MAX_BYTES = 512 * 1024;
const PER_INSTALL_PER_HOUR = 5;
function doPost(e) {
  try {
    const raw = e && e.postData ? e.postData.contents : '';
    if (raw.length > MAX_BYTES) return out({ok:false, error:'size'});
    const d = JSON.parse(raw);
    if (d.token !== TOKEN) return out({ok:false, error:'token'});
    const cache = CacheService.getScriptCache();
    const key = 'n_' + String(d.installId || 'unknown').slice(0, 32);
    const n = Number(cache.get(key) || 0);
    if (n >= PER_INSTALL_PER_HOUR) return out({ok:false, error:'rate'});
    if (MailApp.getRemainingDailyQuota() < 1) return out({ok:false, error:'quota'});
    const id = String(d.id || '').replace(/[^A-Z0-9]/g, '').slice(0, 8);
    const subject = `[PiliBTRTV 回報 ${id}] ${s(d.category)}｜${s(d.version)}｜${s(d.device)}`;
    const body = [`回報編號：${id}`, `類型：${s(d.category)}`, `版本：${s(d.version)}`,
                  `裝置：${s(d.device)}`, `Android：${s(d.android)}`, `安裝 ID：${s(d.installId)}`,
                  '', '完整報告見附件。'].join('\n');
    MailApp.sendEmail({to: Session.getEffectiveUser().getEmail(), subject, body,
      attachments: [Utilities.newBlob(String(d.report || ''), 'text/plain', `report-${id}.txt`)]});
    cache.put(key, String(n + 1), 3600);
    return out({ok:true, id});
  } catch (err) { return out({ok:false, error:'server'}); }
}
function s(v) { return String(v == null ? '' : v).slice(0, 80).replace(/[\r\n]/g, ' '); }
function out(o) { return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON); }
```

README：建立 Apps Script 專案 → 貼上程式碼 → 部署 → 新增部署作業 → 類型「網頁應用程式」→ 執行身分「我」、存取權「所有人」→ 授權 → 複製 `/exec` 網址 → 填入 `report_config.dart`。說明更新腳本時要「管理部署作業 → 編輯 → 新版本」才會生效，網址不變。

## 要改的檔案

| 檔案 | 改什麼 |
|---|---|
| `lib/config/report_config.dart`（新增） | 網址與 token |
| `lib/services/report_send_service.dart`（新增） | 送出、installId、回報編號、類型 |
| `lib/services/error_report_service.dart` | （必要時）`deviceSummary()` |
| `lib/widgets/error_report_dialog.dart` | 新階段 |
| `docs/report-gmail/apps_script.gs`、`docs/report-gmail/README.md`（新增） | 腳本與部署步驟 |
| `test/report_send_test.dart`（新增） | 回報編號格式、報告截斷、302／200 回應解析（把解析抽成純函式測試） |

## 任務

| ID | 內容 |
|---|---|
| T-1 | 設定、送出服務、測試 |
| T-2 | 對話框新階段 |
| T-3 | Apps Script 與 README |

由一個 Sonnet 子代理完成。

## 驗證

| AC | 方式 |
|---|---|
| AC-1～AC-6、AC-9 | 程式碼審查；模擬器由使用者測試（網址填入後） |
| AC-7、AC-8 | 開發者部署腳本後實際送一份，檢查 Gmail；連送 6 次確認第 6 次被擋 |
| AC-10 | 文件 |
| AC-11 | `flutter analyze`、建置 |

## 邊界情況

- 302 的 `Location` 缺少：視為失敗「送出失敗（無回應）」。
- 腳本回非 JSON（例如 Google 登入頁，表示部署存取權設錯）：「送出失敗（腳本未公開）」，並在 debugPrint 記錄 HTTP 狀態。
- 連按「送出」：送出中按鈕停用。
- 報告內含使用者的 log；`buildReport` 已遮蔽 UID／Cookie／IP，不另外處理。

## 審查後修正（以本節為準）

規格審查（Sonnet，2026-11-09）8 條全部採用，細節如下：

1. 腳本加 `const TO = '';`，空字串時才用 `Session.getEffectiveUser().getEmail()`；README 寫明「執行身分必須是『我』」。
2. **302 處理**：`followRedirects = false`；相對 `Location` 以請求 URI 解析；每個回應都要讀完或 drain body。POST 收到 302 後，若 echo GET 失敗或逾時，視為「已送出（未收到確認）」並顯示回報編號，不顯示失敗。腳本以 CacheService `id_<id>`（6 小時）去重，同一編號重送回 `{ok:true,id,dup:true}`，不重寄。
3. **大小與頻率**：App 端以 `utf8.encode` 的位元組數截斷到 400 KB（開頭 20 KB＋結尾，中間「…（中略）…」）；腳本只擋 `raw.length > 1000000`。頻率限制改用整點分桶（key 含 `Math.floor(Date.now()/3600000)`），並以 `LockService.getScriptLock().waitLock(5000)` 包住讀寫；另加全域每小時上限 30 封（`g_<bucket>`）。
4. 腳本驗證 `id` 符合 `^[A-Z0-9]{6}$`，否則回 `bad_id`；App 產生的編號字元集為 `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`；測試涵蓋字元集與長度。
5. 閃退流程維持現狀：`home_screen.dart` 在對話框關閉後清除閃退紀錄（不論是否送出），不改。送出中用 `PopScope(canPop: false)` 防止關閉；所有 `setState` 前檢查 `mounted`。
6. **簡化選類型**：類型清單每一項都是按鈕，按下即送出（一個動作完成）；有閃退時預設焦點在「閃退／當機」。下方另有「改用手機查看」「取消」。
7. 補充：`buildReport` 例外時以「（報告產生失敗：<型別>）」加上裝置摘要仍送出；新增 `ErrorReportService.deviceSummary()` 回傳 `{device, android}`，不解析報告文字；`SocketException` →「無法連線，請確認網路」，`TimeoutException` →「連線逾時，請稍後再試」；對話框說明加一行「・匿名安裝 ID（用來限制回報次數，不含帳號資訊）」。
8. 移除 token 欄位（不是機密，沒有效果）。

## 實作偏差

- 腳本加了 `doGet`（回 `{ok:true,service}`），讓部署後可用瀏覽器或 curl 檢查是否公開。
- POST 收到 302 但缺 `Location`：回「送出失敗（無回應）」（依邊界情況）；echo GET 失敗或逾時才視為已送出。
- `http.Response.fromStream` 讀完 POST 回應；非 200／302 的狀態顯示「送出失敗（HTTP n）」。
- 送出中按鈕顯示「送出中…」且停用；`ReportSendService.send` 多一個選用參數 `reportId`。
- 對話框 select 階段已移除「預覽」按鈕（僅保留於手機 QR 流程的 confirm 階段）。
