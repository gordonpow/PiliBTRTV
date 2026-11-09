# 規格：回報紀錄顯示處理狀態

對應需求：[1-requirements.md](1-requirements.md)

## 設計

狀態檔 `report_status.json` 放在 repo 根目錄，App 從
`https://raw.githubusercontent.com/gordonpow/PiliBTRTV/main/report_status.json` 讀取。

```json
{
  "version": 1,
  "reports": {
    "EKAKJQ": {
      "status": "resolved",
      "note": "已在 v1.2.2-btr.8 修正，請更新",
      "updated": "2026-11-09"
    }
  }
}
```

- `status`：`resolved`（已解決，綠 `#4CAF50`）、`in_progress`（處理中，橘 `#FFB74D`）、`cannot_reproduce`（無法重現，灰 `#9E9E9E`）。其他值忽略該筆。
- `note`：可省略；顯示時截到 80 字。
- 編號比對前轉大寫並去空白。
- 解析逐筆做型別檢查：`reports` 不是 Map 回空；單筆 `status` 非字串或未知值、`note` 非字串只跳過該筆（note 非字串時視為無說明）。`note` 以 `runes` 截到 80 字，避免切斷 emoji。
- 下載規則（`load()`）：
  - URL 加 `?t=<毫秒>` 避開 raw CDN 快取（請求標頭 `Cache-Control` 無效）。
  - HTTP 200 且解析為合法格式（JSON 物件含 `reports` Map）→ 存原始字串到快取 `report_status_cache` 並回傳。
  - HTTP 404（狀態檔已刪除）→ 視為空狀態，清除快取並回傳空 Map（符合回退：刪除檔案即不顯示標籤）。
  - HTTP 200 但格式不合法、其他狀態碼、逾時、連線錯誤 → 不動快取，讀快取（用同一個 decode）；無快取回空 Map。
  - 狀態檔 URL 用 `String.fromEnvironment('REPORT_STATUS_URL', defaultValue: <raw URL>)`，測試或驗證時可覆寫，不必推假資料到公開 repo。
  - `load()` 可注入 `fetch`（回傳狀態碼與內文）與快取讀寫函式，方便測試。

### 要改的檔案

| 檔案 | 改什麼 |
|---|---|
| `lib/services/report_status_service.dart`（新增） | `enum ReportStatusKind`、`class ReportStatus`、純函式 `Map<String, ReportStatus> decodeReportStatus(String raw)`（格式錯誤回空 Map）、`ReportStatusService.load()`：下載（8 秒逾時、`Cache-Control: no-cache` 請求標頭），成功時存 SharedPreferences `report_status_cache` 並回傳；失敗讀快取；都失敗回空 Map。只記 log 不拋例外 |
| `lib/widgets/error_report_dialog.dart` | `_ReportHistoryDialog` 用 `FutureBuilder` 包住 `ReportStatusService.load()`（future 在 State 或建立對話框時建立一次，避免重建時重新下載）；紀錄為空時不呼叫 `load()`；先顯示紀錄，future 完成後補標籤；`_ReportRecordTile` 加 `ReportStatus?` 參數：編號右側顯示圓角標籤，說明顯示在時間列下方（白 70%、14 號字、最多 2 行）。紀錄存在時對話框高度由 280 改為 340 |
| `report_status.json`（新增，repo 根目錄） | 初始內容 |
| `test/report_status_test.dart`（新增） | `decodeReportStatus`：正常、未知狀態忽略、單筆型別錯只跳過該筆、`reports` 非 Map、壞 JSON、`version` 缺少仍可解析、編號大小寫、note 以 runes 截斷；`load()`：200 合法存快取、404 清快取回空、200 壞內容不覆蓋快取並回快取、逾時回快取、無快取回空 |

## 任務

| ID | 任務 | 相依 | 完成條件 |
|---|---|---|---|
| T-1 | 服務、UI、測試、初始狀態檔 | — | `flutter analyze` 無問題、測試通過 |

## 驗證計畫

| AC | 驗證方式 | 證據 |
|---|---|---|
| AC-1～AC-4 | 單元測試；畫面由使用者在實機確認 | 測試輸出；待使用者測試 |
| AC-5 | 推送狀態檔後用 curl 取回 `<raw URL>?t=<時間>` 比對內容 | curl 輸出 |
| AC-6 | `load()` 單元測試（注入 fetch 與快取） | 測試輸出 |
| AC-7 | 讀程式碼確認非同步補上 | diff 審查 |

## 邊界情況與風險

- 對話框關閉後下載才完成：`setState` 前檢查 `mounted`。
- raw.githubusercontent.com 在部分網路被擋：沿用快取，不顯示錯誤。
- 回退：刪除狀態檔即不顯示任何標籤。

## 審查紀錄

| 來源 | 意見 | 處理 |
|---|---|---|
| Haiku 審查 1 | 404 未與網路失敗區分，刪檔後舊標籤仍在 | 採用：404 清快取回空 |
| Haiku 審查 2 | 200 但內容錯會覆蓋好快取 | 採用：只有合法才寫快取，快取存原始字串 |
| Haiku 審查 3 | `Cache-Control` 請求標頭對 raw CDN 無效 | 採用：URL 加時間戳；AC-5 改為 curl 比對 |
| Haiku 審查 4 | 失敗路徑沒有測試 | 採用：`load()` 注入 fetch 與快取並加測試；widget test 不採用（UI 只是補標籤，成本高） |
| Haiku 審查 5 | 驗證要推假資料到公開 repo | 採用：URL 可用 dart-define 覆寫；畫面改由使用者實機確認 |
| Haiku 審查 6 | 欄位型別錯、emoji 截斷 | 採用 |
| Haiku 審查 7 | 無紀錄仍下載；高度 | 採用無紀錄不下載；高度維持 340，內容可捲動 |
| Haiku 審查 8 | 改用 FutureBuilder | 採用 |

## 實作偏差

- 新增 `ReportFetchResult(statusCode, body)` 作為注入 fetch 的回傳型別。
