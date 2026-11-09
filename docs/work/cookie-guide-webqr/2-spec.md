# 規格：Cookie 登入圖文教學與網頁版掃碼登入

對應需求：[1-requirements.md](1-requirements.md)

## 設計

### B. 網頁版掃碼登入（AC-7～AC-12）

B 站網頁登入 QR 介面（2026-11-09 用 curl 實測：`generate` 回 `code 0` 與 `qrcode_key`，`poll` 回 `data.code 86101 未扫码`）：

- 產生：`GET https://passport.bilibili.com/x/passport-login/web/qrcode/generate` → `data.url`（做成 QR）、`data.qrcode_key`。
- 輪詢：`GET https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=<key>`，外層 `code 0`，狀態看 `data.code`：
  - `86101` 未掃描 → `waiting`
  - `86090` 已掃描未確認 → `scanned`
  - `86038` 已失效 → `expired`
  - `0` 成功 → `data.url` 形如 `https://passport.biligame.com/x/passport-login/web/crossDomain?DedeUserID=..&DedeUserID__ckMd5=..&Expires=..&SESSDATA=..&bili_jct=..&gourl=..`
  - 其他 → `error`（帶 `data.code`、`data.message`）
  - HTTP 非 200 或例外 → `network`
- 標頭：瀏覽器 User-Agent（`BaseApi` 現有網頁 UA）、`Referer: https://www.bilibili.com/`。
- 取得 Cookie：**手動切分 `data.url` 的原始 query 字串**（以 `&`、第一個 `=` 切），不做 URL 解碼，保留 `SESSDATA` 中的 `%2C` 等原樣（與瀏覽器 Cookie 值一致）。取 `SESSDATA`、`bili_jct`、`DedeUserID`，三者缺一視為 `error`。不採用 `Uri.queryParameters`：會把 `%2C` 解成 `,`，Cookie 值會不同。不採用 `Set-Cookie` 標頭：`http` 套件把多個 `Set-Cookie` 用逗號合併，`Expires` 內也有逗號，難以可靠切分。
- 取得後先驗證再儲存：把 `PhoneLoginService.submitCookie` 中「帶 Cookie 呼叫 `/x/member/web/account` 並比對 `mid == DedeUserID`」抽成共用函式 `AuthApi.verifyWebCookies(cookies) → bool`（`submitCookie` 改用它）。驗證失敗回 `error`（`_errorText = 'Cookie 驗證失敗，請重新掃描'`）。成功才呼叫 `AuthService.saveCookieLogin(cookies)`（外包 try/catch，例外轉 `error`），再走 `LoginViewState._completeLogin()`。
- 驗證規則共用：`phone_login_service.dart` 的 `safe` 正規式抽成頂層 `isSafeCookieValue(String)`，`submitCookie` 與 `parseWebLoginCookies` 共用；`parseWebLoginCookies` 另要求 `DedeUserID` 符合 `^\d+$`（`saveCookieLogin` 用 `int.tryParse`，非數字會丟 `ArgumentError`，見 `auth_service.dart:101-103`）。
- 手機頁的密碼／簡訊登入回 `48007` 時（`PhoneLoginService._msg` 依 `res['code']`），訊息改成「此帳號不支援 App 登入，請改用電視上的『網頁版掃碼』或 Cookie 登入」。

電視登入頁（`login_view.dart`）：

- 左側「TV 掃碼登入」區塊新增模式 `_LoginQrMode { tv, web }`，預設 `tv`。標題、說明文字、QR 資料、輪詢函式依模式切換；`_status`、`_qrUrl`、`_pollTimer`、`_expiredCount` 共用。
  - `web` 模式標題「網頁版掃碼登入」，說明「用 B 站手機 App 掃描，在手機上按確認；適用 TV 掃碼出現 48007 的帳號。此方式不支援投幣」。
- 下方按鈕列新增切換按鈕：`tv` 模式顯示「改用網頁版掃碼」，`web` 模式顯示「改用 TV 掃碼」。切換時取消輪詢、`_expiredCount = 0`、重新產生該模式的 QR。
- TV 輪詢回 `error` 且 `code == 48007`：`_errorText = '此帳號不支援 TV 掃碼，請改用網頁版掃碼'`，`_status = 'error'`，`_is48007 = true`。焦點：切換按鈕有自己的 `FocusNode _switchFocus`（dispose 時釋放），48007 時用 `addPostFrameCallback` 呼叫 `_switchFocus.requestFocus()`（autofocus 在焦點已存在時不會移動）。「重新產生 QR Code」的 `autofocus` 改為 `qrFailed && !_is48007`，避免兩個按鈕同時綁 `_defaultButtonFocus`（`login_view.dart:278`）。
- 過期自動重產與上限沿用 `_maxAutoRegenerate`；`network` 狀態沿用。
- generation 防護：`_generateQrCode` 開頭（第一個 `await` 前）遞增 `_qrGen` 並記下 `gen`；產生的 `await` 之後、每次輪詢 `await` 之後都比對 `gen == _qrGen && mounted && !_loginHandled`，不同就丟棄。成功分支在第一個 `await`（驗證、儲存）之前先 `timer.cancel()` 並遞增 `_qrGen`，避免重疊的輪詢回應（如 `86038`）重產 QR 覆蓋成功狀態。切換模式也遞增 `_qrGen`。
- log（AC-12）：`WebLogin: 產生 QR 成功/失敗 code=..`、`WebLogin: 狀態 waiting→scanned` 等狀態變化、`WebLogin: 輪詢錯誤 code=.. message=..`、`WebLogin: 登入成功 mid有效=true`。不記錄 URL、Cookie 值。

### A. Cookie 分頁圖文教學（AC-1～AC-6）

整個流程在 Firefox 裡完成：先把登入頁本身移到 Firefox 開啟，之後登入 B 站、讀 Cookie、貼上都在同一個瀏覽器裡切分頁，不需要在 App 間複製網址。

教學步驟（實際步驟與截圖數以 T-3 拍攝結果為準，預計 14～16 張）：

1. 在目前瀏覽器按「用 Firefox 開啟本頁」（`intent://` 連結，指定 `package=org.mozilla.firefox`；未安裝時 Chrome 會自動開 Google Play 的 Firefox 頁面）。
2. Google Play：Firefox 頁面按「安裝」，完成後按「開啟」。
3. Firefox 第一次開啟的歡迎畫面：如何略過。
4. 回到原瀏覽器再按一次「用 Firefox 開啟本頁」，或在 Firefox 網址列貼上本頁網址（頁面提供「複製本頁網址」按鈕）。
5. 在 Firefox 的本頁按「安裝 Cookie-Editor」（連到 `https://addons.mozilla.org/android/addon/cookie-editor/`）。
6. 附加元件頁按「新增至 Firefox」。
7. 權限對話框按「新增」。
8. 安裝完成提示。
9. 回到本頁按「開啟 B 站登入」（`https://passport.bilibili.com/h5-app/passport/login`，新分頁）。
10. 輸入帳密或簡訊登入（遇驗證照畫面完成）。
11. 登入後看到 B 站首頁。
12. 在 B 站頁面按 Firefox 選單（⋮）→「附加元件」→「Cookie-Editor」。
13. Cookie-Editor 視窗按「匯出」（Export）→「Header String」，提示已複製。
14. 按 Firefox 分頁按鈕切回本頁（電視登入）。
15. 切到 Cookie 分頁，長按輸入框貼上，按「登入」。
16. 電視與本頁顯示登入成功。

頁面結構：

- Cookie 分頁頂部：iPhone 提示框（AC-5）「iPhone 無法用這個方式（Safari 不允許讀取登入用的 Cookie），請在電視上選『改用網頁版掃碼』」。UA 判斷為 iPhone／iPad（`/iPhone|iPad|iPod/` 或 `Macintosh` 且有觸控）時，提示框醒目顯示，圖文教學整段收合並標示「僅限 Android」；其他裝置提示框為一般樣式。
- 接著兩個按鈕／連結：「用 Firefox 開啟本頁」（只在 UA 含 `Android` 且不含 `Firefox` 時顯示）、「複製本頁網址」。
- 教學用 `<details>` 分段（AC-6）：「第一次使用：安裝 Firefox 與 Cookie-Editor」（步驟 1～8）、「登入 B 站並複製 Cookie」（步驟 9～13）、「貼上並登入」（步驟 14～16）。前兩段預設收合，若使用者已經在 Firefox 中（UA 含 `Firefox`）第一段標示「已完成可略過」。
- 每步：編號、一句說明（點哪裡、看到什麼）、截圖 `<img>`。`img{max-width:100%;height:auto}`，`loading="lazy"`，有 `alt`。
- 圖片 `src` 不寫在 HTML：靜態標記用 `data-guide="01"`，由 JS 設成 `'/login/guide/01.webp?t='+encodeURIComponent(token)`（頁面規則：不用 innerHTML，只設屬性與 textContent）。
- 「安裝 Cookie-Editor」「開啟 B 站登入」連結 `target="_blank" rel="noopener noreferrer"`。
- 「複製本頁網址」：http 頁面沒有 `navigator.clipboard`（非安全來源），用隱藏 textarea＋`document.execCommand('copy')`，失敗時把網址顯示在輸入框讓使用者長按複製。
- 「用 Firefox 開啟本頁」的 intent 網址由 JS 依 `location.host`（已含 port）組出：`intent://'+location.host+'/login?t=<token>#Intent;scheme=http;package=org.mozilla.firefox;end`。

登入頁代碼時效（審查第 1 點）：

- 現況：`PhoneLoginService.tokenLifetime = 15 分鐘`，到期 `_regenerate()` 換新代碼（`phone_login_service.dart:69`、`:198-208`）。教學流程（裝 Firefox、附加元件、登入 B 站）常超過 15 分鐘。
- 改法：第一次有效 `GET /login` 時，把 `_tokenExpiry` 與 `_expiryTimer` 延長為「從產生起算 45 分鐘」（`extendedTokenLifetime`），只延長一次，不再續期。新增常數，測試用 `_now` 注入驗證。
- 安全取捨：代碼只在區網、有錯誤次數上限，延長到 45 分鐘風險有限；使用者已同意（2026-11-09）。

圖片來源（AC-3）：

- 截圖放 `assets/login_guide/NN.webp`（兩位數編號），寬 720 px、WebP 品質約 75，單張 ≤ 100 KB（超過就降到 600 px 或品質 65），總大小 ≤ 1.5 MB。`pubspec.yaml` 加 `- assets/login_guide/`。
- `LocalServer._handleRequest`：`reqPath.startsWith('/login/guide/')` 交給 `_handleLoginGuideImage`：
  - 只接受 `GET`；檔名必須符合 `^\d{2}\.webp$`，否則 404。
  - 新增 `PhoneLoginService.checkTokenQuiet(t)`：與 `checkToken(write: false)` 相同判斷，但錯誤時**不累計** `_badCount`（14～16 張圖用舊代碼載入會把目前有效代碼作廢，見 `phone_login_service.dart:236-245`）。不通過 → 403。
  - `rootBundle.load('assets/login_guide/$name')`，找不到 → 404；成功 → `Content-Type: image/webp`、`Cache-Control: private, max-age=600`、`Referrer-Policy: no-referrer`。
- 截圖遮蔽（AC-2）：Cookie 值、使用者名稱、頭像、UID、手機號、網址中的 `t=` 代碼、電視區網 IP 都用實心色塊遮蓋；紅框／箭頭標示要點擊處。用 Python Pillow 在 scratchpad 處理，輸出到 assets。

### 要改的檔案

| 檔案 | 改什麼 |
|---|---|
| `lib/services/api/auth_api.dart` | 新增 `generateWebQrCode()`、`pollWebQrLogin(key)`、`parseWebLoginCookies(url)`（純函式，可測） |
| `lib/services/bilibili_api.dart` | 轉接 `generateWebQrCode`、`pollWebQrLogin` |
| `lib/screens/home/login/login_view.dart` | `_LoginQrMode`、切換按鈕、48007 提示、generation 防護、web 模式成功時 `saveCookieLogin` |
| `lib/services/local_server.dart` | `/login/guide/NN.webp` 路由；首次有效 `GET /login` 呼叫延長代碼時效 |
| `lib/services/phone_login_service.dart` | `isSafeCookieValue` 抽出共用；`submitCookie` 改用 `AuthApi.verifyWebCookies`；`checkTokenQuiet`；`extendOnFirstOpen()`；48007 訊息改寫 |
| `test/phone_login_test.dart` | 代碼延長（只延一次、45 分鐘上限）、`checkTokenQuiet` 不累計錯誤次數、48007 訊息 |
| `lib/services/phone_login_page.dart` | Cookie 分頁：iPhone 提示、Firefox 開啟／複製網址、分段圖文教學、JS 設定圖片 src |
| `assets/login_guide/*.webp` | 新增截圖 |
| `pubspec.yaml` | 加入 `assets/login_guide/` |
| `test/web_login_parse_test.dart` | `parseWebLoginCookies` 測試 |

### 介面與設定

- `static Future<Map<String, String>?> AuthApi.generateWebQrCode()` → `{'url', 'qrcode_key'}` 或 `null`。
- `static Future<Map<String, dynamic>> AuthApi.pollWebQrLogin(String key)` → `{'status': 'success'|'waiting'|'scanned'|'expired'|'error'|'network', 'cookies': Map<String,String>?, 'code', 'message'}`。
- `Map<String, String>? parseWebLoginCookies(String url)`：三個值齊全才回傳，否則 `null`；值不可含空白、`;`、`"`、`\`、控制字元（同 `submitCookie` 的 `safe` 規則）。
- 新路由：`GET /login/guide/NN.webp?t=<token>`。
- 無新相依套件、無新設定鍵。

## 任務

| ID | 任務 | 相依 | 完成條件 |
|---|---|---|---|
| T-1 | 網頁版掃碼 API＋解析＋共用驗證（`auth_api.dart`、`bilibili_api.dart`、`phone_login_service.dart` 的 `isSafeCookieValue`／`submitCookie` 改用 `verifyWebCookies`／48007 訊息、`test/web_login_parse_test.dart`） | — | `flutter analyze` 無問題、新舊測試通過（含 `%2C` 保留、缺欄位、不安全字元、`DedeUserID` 非數字回 null） |
| T-2 | 電視登入頁模式切換、48007 提示與焦點、generation 防護（`login_view.dart`） | T-1 | `flutter analyze` 無問題；模擬器上可切換兩種 QR、切換按鈕可用遙控器操作 |
| T-3 | 模擬器拍攝教學截圖（手機模擬器 `Pixel_9_Pro_XL`：安裝 Firefox、Cookie-Editor；使用者自己登入 Google 與 B 站帳號），標註、遮蔽、轉 WebP | — | `assets/login_guide/` 有每步截圖、單張 ≤ 100 KB、總大小 ≤ 1.5 MB；全新子代理逐張複查無個資與有效 Cookie |
| T-4 | 代碼時效延長、`checkTokenQuiet`、圖片路由、Cookie 分頁教學頁面（`phone_login_service.dart`、`local_server.dart`、`phone_login_page.dart`、`pubspec.yaml`、`test/phone_login_test.dart`） | T-1、T-3（步驟與檔名） | `flutter analyze` 無問題、測試通過；手機開頁面圖片顯示、錯誤代碼 403 且不累計錯誤次數 |

T-1 與 T-3 平行；T-2 在 T-1 後；T-4 在 T-1、T-3 後（同改 `phone_login_service.dart`，不可與 T-1 平行）。

## 驗證計畫

| AC | 驗證方式 | 證據 |
|---|---|---|
| AC-1、AC-2、AC-6 | 手機（實機 `R5CY136L62J` 經 `adb reverse`）開 Cookie 分頁截圖；全新子代理逐張複查遮蔽 | 截圖、複查結果 |
| AC-3 | curl：正確 token 200 `image/webp`；錯誤 token 403 且連續 15 次後原代碼仍可用；`curl --path-as-is` 檔名 `../x` 404 | curl 輸出 |
| AC-4 | 依教學匯出 Header String 貼上登入 | 待使用者測試 |
| AC-5 | 頁面截圖 | 截圖 |
| AC-7、AC-8、AC-9 | TV 模擬器切到網頁版掃碼，使用者用 B 站 App 掃描登入，看個人頁、首頁推薦、動態、歷史 | 待使用者測試；log |
| AC-10 | 讀程式碼確認分支與焦點設計（不共用 FocusNode）；實際由回報的使用者測試 | diff 審查 |
| AC-11 | 等 QR 過期（約 180 秒）看自動重產；中斷網路看 network 狀態 | log |
| AC-12 | `adb logcat` 檢查 `WebLogin:` 行不含 Cookie 值、`DedeUserID` 值、`crossDomain`、`qrcode_key`、`data.url` | log 片段 |

## 邊界情況與風險

- Firefox 或 Cookie-Editor 改版導致截圖與實際不符：頁面文字描述為主，圖片為輔；需要時重拍。
- 使用者手機沒有 Google Play（部分華為等）：步驟 1 補充「也可從 `https://www.mozilla.org/firefox/browsers/mobile/` 下載」。
- Cookie-Editor 權限要求所有網站的資料存取：頁面註明這是附加元件讀 Cookie 必須的權限，用完可移除。
- `intent://` 在 Samsung Internet、Chrome 可用；其他瀏覽器可能無反應 → 有「複製本頁網址」備案。
- 登入頁代碼時效：首次開啟後延長到 45 分鐘（見上）；仍超過時頁面顯示「連結已失效」，教學開頭提示「連結失效時請回電視重新掃描」。手機瀏覽器在背景時頁面輪詢暫停，不影響時效計算（以電視端時間為準）。
- 網頁 QR 的 `data.url` 格式若改變導致解析失敗：回 `error`，log 記錄缺哪個欄位名稱（不記值）。
- 網頁 Cookie 登入不支援投幣：與 Cookie 登入相同，已有處理。
- 回退：還原這次 commit；assets 與路由獨立，移除不影響其他登入方式。

## 審查紀錄

| 來源 | 意見 | 處理 |
|---|---|---|
| Sonnet 審查 1 | 代碼 15 分鐘時效不夠走完教學 | 採用：首次開啟後延長到 45 分鐘，只延一次（使用者已同意） |
| Sonnet 審查 2 | 圖片用錯誤代碼會累計 `_badCount` 作廢有效代碼 | 採用：`checkTokenQuiet` |
| Sonnet 審查 3 | autofocus 兩按鈕共用 `_defaultButtonFocus`、autofocus 不會移動既有焦點 | 採用：切換按鈕獨立 FocusNode＋postFrame `requestFocus` |
| Sonnet 審查 4 | generation 只防輪詢、未防產生；成功與重疊輪詢競態 | 採用：產生前遞增、成功先取消並遞增 |
| Sonnet 審查 5 | `DedeUserID` 非數字會讓 `saveCookieLogin` 丟例外；`safe` 規則重複 | 採用：`^\d+$`、try/catch、`isSafeCookieValue` 共用 |
| Sonnet 審查 6 | 網頁登入未驗證 Cookie，失效時仍顯示成功 | 採用：抽出 `verifyWebCookies` 與 `submitCookie` 共用 |
| Sonnet 審查 7 | 驗證計畫缺口（AC-9 三頁、AC-12 關鍵字、`--path-as-is`、截圖複查、48007 測試） | 採用前四項；48007 widget 測試不採用：`LoginView` 直接呼叫靜態 API，注入成本高，改以獨立 FocusNode 設計消除 assert 風險並在 diff 審查確認 |
| Sonnet 審查 8 | intent 按鈕在 iPhone／Firefox 內無意義；iPhone 時教學應收合；用 `location.host` | 採用 |
| Sonnet 審查 9 | 圖片大小可能超標 | 採用：單張 ≤ 100 KB |
| Sonnet 審查 10 | 改用策略物件 | 不採用：只有兩種模式，集中 generation 防護後分支簡單，策略物件增加檔案與抽象 |
| Sonnet 審查 11 | 密碼／簡訊登入 48007 沒有導引 | 採用：改寫訊息導向網頁版掃碼或 Cookie 登入 |

## 實作偏差

- T-1：`isSafeCookieValue` 放在 `auth_api.dart`（`phone_login_service.dart` 已 import `auth_api.dart`，避免循環 import）。
- T-1：`verifyWebCookies` 直接用 `http.get`＋15 秒逾時，不經 `PhoneLoginService._getJson`（`getHeaders()` 不需裝置資訊，行為相同）。
- T-1：未新增 `_msg` 的 48007 測試（private static，無既有 helper 可間接測試），改由 diff 審查確認。
- T-1：poll 成功但 Cookie 解析失敗回 `error`，訊息只列缺少的欄位名稱；外層 `code != 0` 或 `data` 不是 Map 也回 `error`。
- T-2：輪詢回呼發現世代已換時一律取消該計時器；切換模式時清空 `_qrUrl` 避免殘留舊 QR；驗證失敗與儲存失敗共用訊息「Cookie 驗證失敗，請重新掃描」。48007 時 `focusDefault()` 改把焦點移到切換按鈕。
- T-4 拆成 T-4a（代碼延長、`checkTokenQuiet`、圖片路由、測試，不依賴截圖）與 T-4b（Cookie 分頁教學頁面，依 T-3 截圖）。
- 2026-11-09 使用者決定：Cookie 圖文教學（T-3 截圖、T-4b 頁面）先暫停，先發布網頁版掃碼給 48007 使用者測試，確定網頁版不行再恢復。T-4a（代碼延長、圖片路由）保留；`assets/login_guide/` 目前只有 `.gitkeep`。
