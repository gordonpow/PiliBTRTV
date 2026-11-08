# 規格：手機輔助登入

需求：`1-requirements.md`。參考：PiliPlus `lib/http/login.dart`、`lib/pages/login/controller.dart`、`lib/pages/login/geetest/geetest_webview_dialog.dart`、`lib/utils/app_sign.dart`、`lib/utils/login_utils.dart`（路徑在 `C:\presonal_project\bilibili_bata\PiliPlus\`）。

## 架構

```
手機瀏覽器 ──HTTP(區網)──> 電視 LocalServer :3322 /login、/api/login/*
                                   │
                                   └─> PhoneLoginService ──HTTPS──> passport.bilibili.com
```

- 所有 B 站呼叫都在電視端（持有 buvid、deviceId、appkey 簽名）。手機網頁只收集輸入與極驗結果。
- 狀態機在電視端（`PhoneLoginService`），手機網頁輪詢 `/api/login/state` 取得下一步。

## 檔案

| 檔案 | 內容 |
|---|---|
| `pubspec.yaml` | 新增 `encrypt: ^5.0.3`（RSA PKCS#1 v1.5，PiliPlus 也用它） |
| `lib/services/api/app_sign.dart`（新） | android_hd appkey `dfca71928277209b`／appsec `b5475a8825547a4fc26c7d518eaaa02e`；`appSign(params)`：加 `appkey`、`ts`，依 key 排序，key/value `Uri.encodeComponent`，`sign = md5(query + appsec)`。另含 `generateBuvid()`、`genDeviceId()`（照 PiliPlus `login_utils.dart:97-131`），值存在 SharedPreferences 重複使用 |
| `lib/services/phone_login_service.dart`（新） | 一次性代碼、狀態、B 站登入 API（見下） |
| `lib/services/local_server.dart` | 新增路由 `GET /login`（網頁）、`/api/login/*`（JSON） |
| `lib/services/phone_login_page.dart`（新） | 手機網頁 HTML（字串常數，內含 CSS/JS 與極驗載入） |
| `lib/screens/home/login/login_view.dart` | 新增「用手機登入」區塊：QR 碼 + 網址 + 狀態文字；監聽 `PhoneLoginService.loggedIn` 後走與 QR 登入成功相同的流程 |
| `lib/services/auth_service.dart` | 新增 `saveCookieLogin(Map<String,String> cookies)`（只有 cookie、沒有 access_token） |

## PhoneLoginService

- `start()`：產生 16 字元隨機代碼（`Random.secure`）、狀態 `idle`，回傳網址 `http://<LocalServer.address>/login?t=<code>`。`stop()`：清除代碼。登入頁 `initState`／`dispose` 呼叫。代碼 15 分鐘逾期。
- `ValueNotifier<String> status`（電視顯示：等待手機、手機已連線、驗證中、登入成功、錯誤訊息）。
- 共用 app 參數與標頭照 PiliPlus（`build=2001100`、`mobi_app=android_hd`、`platform=android`、`channel=master`、`c_locale/s_locale=zh_CN`、`disable_rcmd=0`、`local_id=buvid`、`statistics`、標頭 `buvid`、`env: prod`、`app-key: android_hd`、BiliDroid UA、`content-type: application/x-www-form-urlencoded`）。

### 流程

1. **密碼**：`GET /x/passport-login/web/key` → `password = base64(RSA(key, hash + 密碼))`、`dt = base64(RSA(key, 16 位隨機字串))` → `POST /x/passport-login/oauth2/login`（參數同 PiliPlus `login.dart:230-271`）。
2. **簡訊送碼**：`POST /x/passport-login/sms/send`（`cid`、`tel`，非 86 時去掉開頭 0，`login_session_id = md5(buvid + ms)`）→ 取得 `captcha_key`。
3. **簡訊登入**：`POST /x/passport-login/login/sms`（`captcha_key`、`cid`、`tel`、`code`、`dt` 與裝置欄位）。
4. **極驗**：回應 `code == -105` 或 `data.recaptcha_url` 不為空時，從 URL 取 `gee_gt`、`gee_challenge`、`recaptcha_token`；拿不到時 `POST /x/safecenter/captcha/pre`。狀態改為 `captcha`（附 gt、challenge）。手機完成後送回 `geetest_challenge/validate/seccode`，電視把 `gee_challenge`、`gee_validate`、`gee_seccode`、`recaptcha_token` 加進原請求重送。
5. **風控驗證**（`data.status == 2`，`data.url`）：照 PiliPlus `login.dart:352-516`：`safecenter/user/info?tmp_code` → 狀態 `riskSms`（顯示 `hide_tel`）→ 極驗 → `safecenter/common/sms/send`（`sms_type=loginTelCheck`）→ 使用者輸入驗證碼 → `safecenter/login/tel/verify` → `oauth2/access_token`（`grant_type=authorization_code`）。
6. **成功**：`code == 0 && data.status == 0`：`AuthService.saveLoginCredentials(accessToken, refreshToken, mid, cookieInfo)` → 呼叫既有的 nav 取得使用者資訊流程 → 狀態 `done`、`loggedIn` 通知。
7. **Cookie**：解析 `name=value; ...`，必須有 `SESSDATA`、`bili_jct`、`DedeUserID`；帶 `Cookie` 呼叫 `GET https://api.bilibili.com/x/member/web/account`，`code == 0` 才接受 → `AuthService.saveCookieLogin`。

### 本機 API（全部需要 `t=<code>`，錯誤或過期回 403）

| 方法 | 路徑 | body | 回應 |
|---|---|---|---|
| GET | `/login?t=` | — | 手機網頁 |
| GET | `/api/login/state?t=` | — | `{step, message, gt?, challenge?, hideTel?}`；step：`input`、`captcha`、`smsSent`、`riskSms`、`done`、`error` |
| POST | `/api/login/password` | `{username, password}` | state |
| POST | `/api/login/sms/send` | `{cid, tel}` | state |
| POST | `/api/login/sms/login` | `{code}` | state |
| POST | `/api/login/captcha` | `{challenge, validate, seccode}` | state |
| POST | `/api/login/risk/verify` | `{code}` | state |
| POST | `/api/login/cookie` | `{cookie}` | state |

- 密碼不寫 log（`debugPrint` 也不印）；請求內容不進 `LogService`。
- 同時只處理一個登入流程；新的請求覆蓋舊流程。

## 手機網頁

- 行動版版面，三個分頁：密碼、簡訊、Cookie。頂端提示 AC-9 的文字。
- `step == captcha`：載入 `https://static.geetest.com/static/js/fullpage.0.0.0.js`，JSONP `https://api.geetest.com/gettype.php?gt=..`，`initGeetest`／`Geetest({gt, challenge, offline:false, new_captcha:true, product:"bind", width:"100%", https:true})`，`onReady` 後 `verify()`，`onSuccess` 用 `getValidate()` POST 到 `/api/login/captcha`。
- 每 1.5 秒輪詢 state；`done` 顯示「登入成功，可以關閉這個網頁」。

## AC 驗證方式

| AC | 驗證 |
|---|---|
| AC-1、AC-6 | 使用者實機 |
| AC-2〜AC-5、AC-7 | 使用者用手機實測（需要真實帳號） |
| AC-8 | 單元測試：錯誤代碼回 403（`PhoneLoginService.checkToken`） |
| AC-9 | 檢查網頁文字 |
| 簽名 | 單元測試：`appSign` 與 PiliPlus 相同輸入得到相同 `sign` |

## 風險

- B 站 app 登入參數可能變動；與 PiliPlus 同步維護。
- 區網明文 HTTP：密碼可能被同網段的人截取。用一次性代碼、15 分鐘逾期、登入後失效降低風險，並在網頁上提示。
- `encrypt` 新相依套件（使用者確認）。
- 回退：移除登入頁的手機區塊與路由即可，不影響 QR 登入。

## 任務

- T-1：`app_sign.dart` + `phone_login_service.dart` + `auth_service.dart` + 單元測試（Sonnet）
- T-2：`local_server.dart` 路由 + `phone_login_page.dart` 網頁（Sonnet，依 T-1 介面）
- T-3：`login_view.dart` 手機登入區塊（Sonnet，依 T-1 介面）

T-1 先做；T-2、T-3 在 T-1 完成後平行。

## 審查紀錄

使用者確認（2026-11-08）：新增 `encrypt` 套件；接受區網 HTTP 的風險（一次性代碼、15 分鐘逾期、網頁提示）。

全新 Sonnet 子代理審查，13 條全部採用，以下內容**優先於**上方規格：

1. **成功後寬限期**：登入成功後保留 60 秒唯讀狀態：`GET /api/login/state` 回 `done`，所有 POST 回 403。`stop()` 不清 `done`，等寬限期過或下一次 `start()` 才清。
2. **Cookie 登入**：`saveCookieLogin` 清掉 `_accessToken`、`_refreshToken`（含 prefs），`mid` 取自 `DedeUserID`。`lib/services/api/interaction_api.dart` 投幣在沒有 access token 時回傳「Cookie 登入不支援投幣，請改用掃碼或密碼登入」。
3. **流程 ID**：每次新流程產生 `flowId`，非同步回來時比對，不符就丟棄。密碼、簡訊、暫存資料只放記憶體，流程結束、逾期、`stop()` 時清除。
4. **位址**：`LocalServer` 新增 `refreshAddress()`（重新抓 IP）與 `isRunning`（`bind` 成功才為 true）。登入頁開啟時呼叫；位址為 null 或伺服器沒跑時，手機區塊顯示「請把電視連上 Wi-Fi 或有線網路」，不產生 QR。
5. **標頭**：`/login` 與 `/api/login/*` 不加 CORS 標頭（OPTIONS 也不放行），加 `Cache-Control: no-store`、`Referrer-Policy: no-referrer`。登入處理器自己 try/catch，只回固定訊息，不回傳例外字串。
6. **極驗設定**：照 PiliPlus：`Object.assign` 合併 gettype 回傳的 `data`，加 `protocol:"https://"`。gt/challenge 由 `/api/login/state` 的 JSON 取得，不拼進 HTML。
7. **風控細節**：從 `data.url` query 取出 `tmp_token`、`request_id`、`source` 暫存。風控簡訊送碼帶**原始**的 `gee_challenge`（captcha/pre 回傳值）＋極驗的 validate/seccode。`safecenter/common/sms/send` 與 `safecenter/login/tel/verify` 都帶 `Referer: data.url`。`/api/login/captcha` 依目前步驟決定重送哪一個請求（密碼登入、簡訊送碼、風控簡訊送碼）。
8. **編碼**：`dt` 與 `from_url` 先 `Uri.encodeComponent` 再進 `appSign`（同 PiliPlus `login.dart:242,247,314`）。單元測試比對 PiliPlus 的簽名結果。
9. **XSS**：手機網頁一律用 `textContent`；`url` 只有符合 `https://*.bilibili.com` 才做成連結。
10. **Cookie 解析**：只取 `SESSDATA`、`bili_jct`、`DedeUserID`，以第一個 `=` 切分。驗證時把這三個合併進 `BaseApi.getHeaders()` 的 Cookie（不要整串取代）。確認 `data.mid == DedeUserID`。
11. **限制**：登入 body 上限 8KB；token 用常數時間比對；連續 10 次錯誤代碼後呼叫 `stop()` 並重新產生代碼。
12. **雙流程**：手機登入成功時，LoginView 取消 QR 的 `_pollTimer`。使用者資訊只在一個地方取得：LoginView 沿用 QR 成功後的同一段程式。
13. **裝置識別**：完整複製 PiliPlus 的標頭（含 `x-bili-trace-id`、`bili-http-engine: cronet`）。登入用的 buvid 與 deviceId 另外存（`phone_login_buvid`、`phone_login_device_id`），不覆蓋 `BaseApi` 的 `buvid3`。
