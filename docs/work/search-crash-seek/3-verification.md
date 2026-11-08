# 驗證：搜尋鍵盤殘留、閃退回報、Netflix 式縮圖列

日期：2026-11-08

## 自動檢查

| 項目 | 結果 |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 15 項通過（含新增 `test/videoshot_index_test.dart` 6 項） |
| `flutter build apk --debug` | 成功（Kotlin `CrashChannel.kt`、`FrameChannel.kt` 編譯通過） |

## AC 對照

| AC | 程式碼層面 | 功能測試 |
|---|---|---|
| A1 | `_submit()`、`_selectSuggestion()` 先呼叫 `_closeIme()`（unfocus + `TextInput.hide`） | 待使用者測試 |
| A2 | 播放器 `initState` 呼叫 `TextInput.hide`；`Scaffold` `resizeToAvoidBottomInset: false` | 待使用者測試 |
| A3 | 鍵盤頁重建時 `_imeVisible` 重置；返回鍵也呼叫 `_closeIme()` | 待使用者測試 |
| A4 | 內建鍵盤流程未改 | 待使用者測試 |
| B1–B4 | `CrashChannel`（uncaught handler + `ApplicationExitInfo`，5 秒內合併，ack 基準時間）、`CrashReportService`、首頁 2 秒後詢問、關閉後 ack | 待使用者測試（`adb shell am crash com.gordonpow.pilibtrtv`） |
| C1、C2 | `SeekThumbnailStrip`；`_performSeek` 每按一次（含長按 repeat）移動一幀 | 待使用者測試 |
| C3 | 幀索引沿用 B 站「減 1」規則；`timeOfIndex` 與 `indexAt` 互為反函數（單元測試） | 待使用者測試 |
| C4 | 停 400ms 後以 `MediaMetadataRetriever` 從 480P AVC 串流解出真實畫面 | 待使用者測試 |
| C5 | 確認／1.5 秒自動確認／返回取消沿用 | 待使用者測試 |
| C6 | 沒有縮圖資料時退回 10／30／60 秒步進，只顯示進度條 | 待使用者測試 |

## 實作審查（agy，`diff-review.md`）

5 條全部採用並修正：
1. pvdata 未載入時 `indexAt` 恆為 0，快進卡在第 1 幀 → `indexAt(pos, total)` 無時間戳時依長度換算（新增單元測試）。
2. 首次安裝的基準時間寫在 `getLastCrash`，首次閃退會被吞掉 → 移到 `installHandler`。
3. `setDataSource` 失敗時 retriever 未釋放 → 失敗時 `release()`。
4. IME 狀態按返回鍵未關鍵盤 → 改呼叫 `_closeIme()`。
5. `didUpdateWidget` 路徑中的 `setState` → 直接賦值。

主導者另外修正：原生崩潰的 `traceInputStream` 是二進位 tombstone，只讀 ANR 的文字 trace。

## 已知限制

- API 30 以下偵測不到原生崩潰與 ANR。
- 真實畫面抽幀在部分電視盒可能很慢或失敗，失敗時維持雪碧圖。
- 首次安裝本版（含從 btr.2 升級）時以安裝後第一次啟動為基準，之前的閃退不詢問。
