# 播放器導覽與手機回報：驗證

日期：2026-11-10。環境：Android TV 模擬器 emulator-5554（x86_64 release APK），帳號是借用帳號。

## 自動檢查

- `flutter analyze`：No issues found!
- `flutter test`：+152 All tests passed!
- `flutter build apk --release --split-per-abi`：三個 ABI 都建置成功。

## AC 對照

| AC | 結果 | 證據 |
|---|---|---|
| 1.1 五種模式 | 通過 | C:\Users\abcz0\AppData\Local\Temp\claude\ca322064af67bc3b\e2694336-c4e6-416b-b36b-df7e0a763a5f\scratchpad\verify-nav\ac1.1-options.png |
| 1.2 設定面板切換與同步 | 通過 | C:\Users\abcz0\AppData\Local\Temp\claude\ca322064af67bc3b\e2694336-c4e6-416b-b36b-df7e0a763a5f\scratchpad\verify-nav\L-q2.png、Y-q1.png |
| 1.3 倒數後播下一部 | 通過 | C:\Users\abcz0\AppData\Local\Temp\claude\ca322064af67bc3b\e2694336-c4e6-416b-b36b-df7e0a763a5f\scratchpad\verify-nav\ac1.3-after-countdown.png |
| 1.3 循環播放此影片 | 通過 | C:\Users\abcz0\AppData\Local\Temp\claude\ca322064af67bc3b\e2694336-c4e6-416b-b36b-df7e0a763a5f\scratchpad\verify-nav\N-q2.png |
| 1.3 直接播下一部、播完暫停、列表循環 | 未驗證 | 模擬器操作時間不足 |
| 1.3 分P、合集順序 | 部分 | 合集上一部的 log 正常（除錯紀錄）；合集下一部、分P未實測 |
| 1.4 沒有 0 秒選項 | 通過 | C:\Users\abcz0\AppData\Local\Temp\claude\ca322064af67bc3b\e2694336-c4e6-416b-b36b-df7e0a763a5f\scratchpad\verify-nav\cyc1~cyc6.png |
| 1.5 舊設定轉換 | 通過（單元測試） | test/play_repeat_test.dart |
| 1.6 番劇最後一集 | 未驗證 | 找不到合適的番劇；PGC 推薦 API 已用 curl 確認 |
| 2.1、2.3 按鈕順序、變暗跳過 | 通過 | C:\Users\abcz0\AppData\Local\Temp\claude\ca322064af67bc3b\e2694336-c4e6-416b-b36b-df7e0a763a5f\scratchpad\verify-nav\n-A.png |
| 2.2、2.4 上一部／下一部 | 通過 | C:\Users\abcz0\AppData\Local\Temp\claude\ca322064af67bc3b\e2694336-c4e6-416b-b36b-df7e0a763a5f\scratchpad\verify-nav3\t5.png、c3.png、c4.png、d2.png、d3.png |
| 3.1–3.3 彈幕按鈕 | 通過 | C:\Users\abcz0\AppData\Local\Temp\claude\ca322064af67bc3b\e2694336-c4e6-416b-b36b-df7e0a763a5f\scratchpad\verify-nav\n-ac3.2-a.png、n-r2.png |
| 3.3 從子選單返回時焦點在「彈幕」 | 未驗證 | |
| 4.1–4.5 底部相關影片 | 通過 | C:\Users\abcz0\AppData\Local\Temp\claude\ca322064af67bc3b\e2694336-c4e6-416b-b36b-df7e0a763a5f\scratchpad\verify-nav\D-q1~q4.png、E-q3.png |
| 5.x 手機回報 | 未驗證（裝置） | 單元測試涵蓋組裝與 token；實際寄信待使用者測 |

## 審查

- 規格審查：19 項意見全部採用。
- 實作審查：
  - 播放器 4 項已修正：上一部換到自己、換片重入、彈幕短按後控制列很快隱藏、分P指定範圍。
  - 手機回報 2 項已修正：對話框關閉後仍產生代碼、錯誤訊息改成中文。
- 裝置發現 1 項，已修正：`resolvePrev` 在 build 中 pop 播放紀錄。修正後用 log 確認 3 個情境都通過。

## 已知限制

- UpNextCard 和底部相關影片同時出現時會重疊（相關影片打開期間影片播完）。
- 相關影片每次打開都會重新請求一次 API。
