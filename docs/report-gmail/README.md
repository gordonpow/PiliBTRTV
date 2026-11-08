# 一鍵回報：Apps Script 部署步驟

使用者在 App 按下問題類型後，報告會 POST 到你部署的 Google Apps Script，由腳本寄信到你的 Gmail（報告以 `.txt` 附件附上）。不需要伺服器，也不需要寫程式。

## 一、建立專案並貼上程式碼

1. 用你要收信的 Google 帳號登入，開啟 <https://script.google.com>。
2. 左上角按「新專案」。
3. 把編輯器裡原本的內容全部刪掉，貼上 `docs/report-gmail/apps_script.gs` 的全部內容。
4. （選填）要寄到別的信箱，把 `const TO = '';` 改成 `const TO = 'you@example.com';`。留空就寄給部署的這個帳號。
5. 按「儲存」（磁碟片圖示），專案名稱可取 `PiliBTRTV Report`。

## 二、部署為網頁應用程式

1. 右上角「部署」>「新增部署作業」。
2. 左邊齒輪選「網頁應用程式」。
3. 設定：
   - 說明：隨意，例如 `v1`
   - **執行身分：我**（一定要選「我」，否則寄不出信）
   - **誰可以存取：所有人**（App 沒有登入 Google，選別的會回登入頁，導致送出失敗）
4. 按「部署」。

## 三、授權

第一次部署會要求授權：

1. 按「授權存取」，選你的帳號。
2. 出現「Google 尚未驗證這個應用程式」是正常的（這是你自己的腳本）。按左下「進階」，再按「前往 PiliBTRTV Report（不安全）」。
3. 權限是「以你的身分寄送電子郵件」與「連線至外部服務」，按「允許」。

## 四、取得網址並填入 App

1. 部署完成後複製「網頁應用程式網址」，結尾是 `/exec`。
2. 貼到 `lib/config/report_config.dart`：

   ```dart
   const String kReportScriptUrl = 'https://script.google.com/macros/s/xxxx/exec';
   ```

3. 重新建置 App。網址留空時，App 會退回手機 QR 流程。

## 五、測試（curl）

先確認網址是公開的（應回 `{"ok":true,"service":"PiliBTRTV report"}`）：

```
curl -L "https://script.google.com/macros/s/xxxx/exec"
```

送一封測試報告（編號必須是 6 碼大寫英數字；`-L` 會跟隨 Google 的 302 轉址）：

```
curl -L -X POST "https://script.google.com/macros/s/xxxx/exec" \
  -H "Content-Type: text/plain;charset=utf-8" \
  -d '{"id":"TEST23","installId":"curltest0000001","category":"其他","version":"test","device":"curl","android":"-","report":"hello"}'
```

回 `{"ok":true,"id":"TEST23"}` 且 Gmail 收到信就成功。同一編號再送一次會回 `"dup":true`，不會重寄。

限制：單一裝置每小時 5 封、全部裝置每小時 30 封、單一報告約 1 MB 以內、Gmail 每日寄信額度用完會回 `quota`。

## 六、更新腳本（網址不變）

修改程式碼並儲存後，**還要發新版本才會生效**：

1. 「部署」>「管理部署作業」。
2. 按既有部署旁的鉛筆（編輯）。
3. 「版本」選「新版本」，按「部署」。

不要用「新增部署作業」，那會產生新的網址，App 內的網址就要跟著改。

## 常見問題

- App 顯示「送出失敗（腳本未公開）」：「誰可以存取」沒設成「所有人」，請依第二節重新部署。
- 收不到信：檢查垃圾郵件，或到 Apps Script 左側「執行作業」看錯誤。
