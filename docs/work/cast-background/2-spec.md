# 規格：App 未開啟時接收投放（#62）

## 設計

### 概念

- 前景服務 `CastWakeService` 與 App 在**同一個程序**。它只在「沒有 MainActivity 存活」時監聽 TCP 3322；MainActivity 存活時 Dart 的 `LocalServer` 擁有 3322，行為與現在相同（AC-6）。
- 服務收到已配對手機的 `/api/cast/play` 時，回應 200，關閉監聽，再用 Intent（extra `cast_payload` = 原始 JSON 字串）開啟 MainActivity。Dart 啟動後讀取 payload，等首頁出現後交給既有的 `CastPlayback.open`。
- 設定存在 Flutter 的 SharedPreferences（`shared_preferences_android` 2.4.x 舊版 API：檔名 `FlutterSharedPreferences`，key 前綴 `flutter.`），原生端直接讀：
  - `flutter.cast_background`（bool，預設 false）
  - `flutter.cast_tv_id`（String）
  - `flutter.cast_paired`（String，JSON 陣列 `[{deviceId, deviceName, token, pairedAt}]`）

### Android 原生（`android/app/src/main/kotlin/com/bili/tv/bili_tv_app/`）

#### 新檔 `CastWakeService.kt`

- `Service`，`companion object` 保存目前執行個體與狀態：
  - `@Volatile var activityAlive: Int`（MainActivity 存活數，由 MainActivity 維護）
  - `fun start(ctx)`：`ContextCompat.startForegroundService`。`fun stop(ctx)`：`stopService`。
  - `fun pauseListening()`：同步關閉 ServerSocket（可在主執行緒呼叫；關 socket 很快）。
  - `fun resumeListening()`：若服務在跑且 `activityAlive == 0`，排程重新繫結。
  - `fun isEnabled(ctx)`：讀 `flutter.cast_background`。
- `onCreate`：建通知頻道 `cast_background`（`IMPORTANCE_LOW`，名稱「投放接收」），`startForeground`：
  - API 34 以上用 `ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE`；以下用兩參數版本。
  - 通知：小圖示用 `R.mipmap.ic_launcher`（或既有可用的 drawable），標題「PiliBTRTV 投放接收中」，內容「手機可以直接投放到這台電視」；點通知開 MainActivity（`PendingIntent.FLAG_IMMUTABLE`）。
- `onStartCommand`：若設定已關閉 → `stopSelf()` 並回 `START_NOT_STICKY`；否則若 `activityAlive == 0` 開始監聽；回 `START_STICKY`。
- `onDestroy`：關閉監聽、清除執行個體。
- 監聽：一條背景執行緒 `ServerSocket()`，`reuseAddress = true`，`bind(InetSocketAddress(3322))`。
  - 繫結失敗（Dart 還沒釋放）→ 每 2 秒重試，最多 30 次；期間若 `activityAlive > 0` 或已 pause 就停止重試。
  - 每個連線用單一 worker 執行緒依序處理（不需要並行），`soTimeout = 5000`。
  - 只處理 HTTP/1.1 單一請求：讀 request line 與 header（上限 8 KB），依 `Content-Length` 讀 body（上限 8 KB，超過回 413 或 400）。回應一律 `Connection: close`、`Content-Type: application/json`、`Cache-Control: no-store`。
- 路由（與 `lib/services/cast/cast_service.dart` 的協定 v1 相同）：
  - `GET /api/cast/info` → 200 `{"app":"PiliBTRTV","v":1,"id":<tvId>,"name":"<製造商 型號>","port":3322}`。`tvId` 讀 `flutter.cast_tv_id`；沒有時產生 UUID v4 並寫回同一個 key。
  - `POST /api/cast/play`：
    1. `Content-Type` 的 mime 不是 `application/json` → 415 `unsupported_media_type`。
    2. body 不是 JSON 物件，或 `deviceId` 不是 1–64 字的字串 → 400 `bad_request`。
    3. `token` 為空或不存在（未配對）→ 回 503 `not_ready`，然後 `launchApp(null)`（AC-7）。
    4. token 與 `flutter.cast_paired` 中同 `deviceId` 的 token 不符（constant-time 比對：`MessageDigest.isEqual`）→ 403 `bad_token`。
    5. API 29 以上且 `!Settings.canDrawOverlays(this)` → 503 `not_ready`，不開 App（AC-5）。
    6. 否則回 200 `{"ok":true}`，`pauseListening()`，`launchApp(body)`。
  - `GET /api/cast/result` → 404 `not_found`。
  - 已知路徑但方法不對 → 405 `method_not_allowed`；其他路徑 → 404 `not_found`。
  - 其他驗證（bvid 格式、epId…）留給 Dart 端，原生只傳原始 JSON。
- `launchApp(payload: String?)`：在主執行緒 `startActivity(Intent(this, MainActivity::class.java).addFlags(FLAG_ACTIVITY_NEW_TASK or FLAG_ACTIVITY_REORDER_TO_FRONT))`，payload 非 null 時放 extra `cast_payload`。例外只記 log。
- log 前綴 `CastWake`（`android.util.Log`）。

#### 新檔 `CastBootReceiver.kt`

- 處理 `ACTION_BOOT_COMPLETED` 與 `ACTION_MY_PACKAGE_REPLACED`：`CastWakeService.isEnabled(ctx)` 為 true 才 `CastWakeService.start(ctx)`（AC-3、AC-8）。例外只記 log。

#### `MainActivity.kt`

- `onCreate`：在 `super.onCreate` **之前**：`CastWakeService.activityAlive++`、`CastWakeService.pauseListening()`（確保 Dart 綁到 3322）；讀 `intent` 的 `cast_payload` 存到欄位 `pendingCastPayload`，並從 intent 移除該 extra（避免重建時重播）。若 `savedInstanceState != null` 不讀 payload。
- `onNewIntent`：有 `cast_payload` 時透過 channel 呼叫 Dart `castPayload`（參數為字串）。
- `onDestroy`：`activityAlive--`；`isChangingConfigurations` 為 false 時，若服務已啟用 → `CastWakeService.resumeListening()`（延遲 1.5 秒讓 Dart 的引擎先釋放連接埠，失敗再走重試）。
- 新 MethodChannel `com.bili.tv/cast`（在 `configureFlutterEngine` 註冊並保存，供 `onNewIntent` 使用）：
  - `takePendingPayload` → 回傳 `pendingCastPayload` 後清為 null。
  - `setBackground(enabled: bool)` → 啟用時 `CastWakeService.start`，停用時 `CastWakeService.stop`。回傳 null。
  - `canDrawOverlays` → API 29 以下回 true；以上回 `Settings.canDrawOverlays(this)`。
  - `openOverlaySettings` → 依序嘗試 `ACTION_MANAGE_OVERLAY_PERMISSION` + `package:` uri、不帶 uri 的同一 action；成功回 true，全部 `ActivityNotFoundException` 回 false。
  - `bringToFront` → `startActivity(Intent(this, MainActivity::class.java).addFlags(FLAG_ACTIVITY_REORDER_TO_FRONT or FLAG_ACTIVITY_NEW_TASK))`，例外忽略（AC-4）。

#### `AndroidManifest.xml`

- 權限：`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_SPECIAL_USE`、`RECEIVE_BOOT_COMPLETED`、`SYSTEM_ALERT_WINDOW`。
- `<service android:name=".CastWakeService" android:exported="false" android:foregroundServiceType="specialUse">`，內含 `<property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="Receive cast requests from the paired phone app on the local network"/>`。
- `<receiver android:name=".CastBootReceiver" android:exported="true">`，intent-filter：`android.intent.action.BOOT_COMPLETED`、`android.intent.action.MY_PACKAGE_REPLACED`。
- 註解用繁體中文（新增的部分）。

### Dart

#### `lib/services/settings_service.dart`

- 新增 `castBackground`（key `cast_background`，bool，預設 false）與 `setCastBackground(bool)`，寫法比照其他 bool 設定。

#### `lib/services/cast/cast_playback.dart`

- 新增首頁就緒信號：`static final Completer<void> _homeReady = Completer();`、`static void markHomeReady()`（未完成才 complete）。
- `open()` 開頭 `await _homeReady.future`（在 `_opening` 判斷之前），避免啟動畫面的 `pushReplacement` 把播放頁換掉。

#### `lib/screens/home_screen.dart`（HomeScreen 的 State）

- `initState` 最後呼叫 `CastPlayback.markHomeReady()`（用 `addPostFrameCallback`，確保路由已換好）。

#### `lib/services/cast/cast_service.dart`

- 新增 `static const _castChannel = MethodChannel('com.bili.tv/cast');`。
- 抽出 `CastRequest? _parseCast(Map<String, dynamic> body)`：把 `_handlePlay` 裡從 body 建 `CastRequest` 與 bvid／epId 驗證的部分移入（`_handlePlay` 改用它，行為不變）。
- 新增 `Future<void> initNative()`（`main()` 中 `LocalServer.instance.start()` 之後呼叫，不 await 播放）：
  - `_castChannel.setMethodCallHandler`：`castPayload` → `_openPayload(arg)`。
  - `takePendingPayload` 有值 → `_openPayload`。
  - `SettingsService.castBackground` 為 true → 呼叫 `setBackground(true)`（App 開啟時確保服務在跑）。
  - 所有 channel 例外忽略（`MissingPluginException` 等）。
- `_openPayload(String json)`：`jsonDecode`，是 Map 才 `_parseCast`；成功就 `_startPlayback`。
- `_startPlayback` 開頭呼叫 `_castChannel.invokeMethod('bringToFront')`（忽略例外，不 await 結果也可）。
- 新增給設定頁用的方法：`Future<void> setBackground(bool)`（寫設定並呼叫 channel）、`Future<bool> canDrawOverlays()`、`Future<bool> openOverlaySettings()`。

#### `lib/main.dart`

- `await LocalServer.instance.start();` 之後加 `unawaited(CastService.instance.initNative());`。

#### `lib/screens/home/settings/cast_settings_page.dart`

- 在「重新整理」與「已配對的手機」之間新增區塊：
  - `SettingToggleRow`：標題「App 未開啟時也接收投放」，副標「開機自動啟動，通知列會顯示常駐通知」，值 = `SettingsService.castBackground`，切換時 `CastService.instance.setBackground(v)`、`setState`，並重新檢查權限。
  - 開關開啟且 `canDrawOverlays == false` 時：`SettingActionRow` label「顯示在其他應用程式上層」，value「未授權：App 關閉時無法開啟畫面」，按鈕「前往授權」→ `openOverlaySettings()`；回傳 false 時改顯示文字：「這台電視沒有授權頁面，請用電腦執行：adb shell appops set com.gordonpow.pilibtrtv SYSTEM_ALERT_WINDOW allow」（套件名寫死為 applicationId `com.gordonpow.pilibtrtv`）。
  - App 回到前景（`WidgetsBindingObserver.didChangeAppLifecycleState` resumed）時重新檢查權限。
  - 焦點：新列放在「重新整理」之後，`isFirst/isLast` 依實際排列調整，上下鍵可在所有列之間移動（比照現有列的寫法）。

## 任務

- T-1：Android 原生（`CastWakeService.kt`、`CastBootReceiver.kt`、`MainActivity.kt`、`AndroidManifest.xml`）。
- T-2：Dart（`settings_service.dart`、`cast_playback.dart`、HomeScreen、`cast_service.dart`、`main.dart`、`cast_settings_page.dart`）。
- T-1、T-2 只以 channel 名稱與方法名稱相依，可平行；由同一個實作者依序做也可以。

## AC 驗證方式

- 全部：`flutter analyze` 無新問題；`flutter build apk --release --target-platform android-x64` 成功；安裝到 TV 模擬器（API 36）。
- AC-1、AC-3、AC-8：模擬器上 `adb shell dumpsys activity services com.gordonpow.pilibtrtv` 看服務狀態；重開機後再看。
- AC-2、AC-4、AC-7：模擬器上 `adb shell appops set … SYSTEM_ALERT_WINDOW allow` 後，用 curl 對 `/api/cast/play`（需先取得配對 token：讀 prefs 或走一次配對）。功能面待使用者以手機實測。
- AC-5：模擬器撤銷權限後打 `/api/cast/play`，預期 503。
- AC-6：App 開著時 `curl /api/cast/info` 回應來自 Dart（例如 port 欄位與 `LocalServer.port` 相同），且 Dart log 有 `LocalServer started at …:3322`。

## 邊界與風險

- **Dart 釋放連接埠的時機**：活動結束後 Flutter 引擎銷毀，Dart isolate 的 socket 應隨之關閉；沒關閉時原生端重試繫結 60 秒後放棄（記 log），下次 App 開啟、退出時再試。
- **Activity 重建**（設定變更）：`isChangingConfigurations` 時不恢復監聽；`savedInstanceState != null` 時不讀 payload。
- **Dart 端沒拿到 payload**：`takePendingPayload` 在 `initNative` 呼叫，時間點在 `configureFlutterEngine` 之後，欄位已設好。
- **權限**：Android 10 以上沒有 overlay 權限時，背景開 Activity 會被系統擋下；所以服務先檢查並回 503。
- **Android 15 開機啟動前景服務**：`specialUse` 不在 BOOT_COMPLETED 禁止清單內。
- **安全**：原生端只接受已配對 token；未配對請求只會喚起 App，不會播放；body 上限 8 KB、逾時 5 秒；單一 worker 依序處理，避免被大量連線拖垮。
- **電視待機**：系統可能凍結網路或殺掉服務，屬已知限制。
- 回退：關閉開關即停用；完全移除時還原上述檔案，新設定 key 不影響舊資料。

## 審查後修訂（優先於上方「設計」）

規格審查（Claude Sonnet）後採用的修改，實作以本節為準：

- R-1（背景啟動）：API 29 以上 `launchApp` 前，服務先用 `WindowManager` 加一個 1×1、`TYPE_APPLICATION_OVERLAY`（API 26 以下用 `TYPE_PHONE`，但 API 29 以下不需要這個視窗）、`FLAG_NOT_TOUCHABLE | FLAG_NOT_FOCUSABLE`、透明的視窗，`startActivity` 後 3 秒移除（Android 15 起 SAW 豁免可能要求有可見的 overlay 視窗）。加視窗失敗只記 log，仍嘗試 `startActivity`。
- R-2（看門狗）：`launchApp` 後 10 秒若 `activityAlive == 0`，`resumeListening()`。`resumeListening` 的延遲 Runnable 執行時再檢查一次 `activityAlive == 0` 與服務仍在執行。
- R-3（Home 背景）：Dart `_handlePlay` 在 token 驗證通過、回 200 之前：若 `WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed` 且 `await canDrawOverlays()` 為 false → 回 503 `not_ready`。
- R-4（未配對喚起冷卻）：原生 `launchApp(null)` 全域冷卻 30 秒；冷卻中仍回 503 `not_ready` 但不喚起。路由明確化：
  - `token` 不存在或空字串 → 503 + 喚起（受冷卻限制）。
  - `token` 非空但 `deviceId` 不在清單或 token 不符 → 403 `bad_token`，不喚起。
- R-5（HTTP 解析）：header 名稱大小寫不敏感；有 `Transfer-Encoding` → 411 `length_required`；`Content-Length` 缺少或非數字 → 400；`Expect: 100-continue` 時先送 `HTTP/1.1 100 Continue

` 再讀 body。
- R-6（設定時序）：Dart `setBackground(v)` 先 `await` 寫入 prefs，再呼叫 channel `setBackground`，參數 `{enabled: v}`；原生 `start` 時在 Intent 帶 extra `enabled=true`，`onStartCommand` 有此 extra 時以它為準，沒有（開機、系統重啟）才讀 prefs。已確認 `shared_preferences_android` 為 2.4.18（舊 API，`FlutterSharedPreferences` 檔與 `flutter.` 前綴）；原生讀取處加註解說明此相依。tvId：原生只在 key 不存在時產生，Dart 只在啟動時讀取。
- R-7（服務健壯性）：`startForeground` 以 try/catch 包住（API 31 以上可能丟 `ForegroundServiceStartNotAllowedException`），失敗就 `stopSelf()`。`onStartCommand` 的 intent 可能為 null。AC-1 的通知在 API 33 以上未授權 POST_NOTIFICATIONS 時可能不顯示，驗證以 `dumpsys` 的服務狀態為準（TV 多半沒有通知列，不另外要求通知權限）。compileSdk 由 Flutter 3.47 提供，≥ 34。
- R-8（首頁逾時與原生驗證）：`CastPlayback.open` 等 `_homeReady` 最多 15 秒，逾時仍開啟。原生 `/api/cast/play` 也驗證：`epId` 為正整數，或 `bvid` 符合 `^BV[0-9A-Za-z]{10}$`；都不符 → 400 `bad_request`。
- R-9：`openOverlaySettings` 捕捉所有 `Exception`。驗證加上 `adb install -r` 後確認服務重新啟動。AC-8 改寫為「開關關閉時不啟動服務」（receiver 仍靜態註冊）。

## 審查紀錄

- 2026-11-15 規格審查（Claude Sonnet）：第 1–9 點採用，見上節 R-1～R-9。
- 第 10 點（改用單一迴圈輪詢 `activityAlive`）不採用：R-2 的看門狗與延遲時再檢查已解決重試遺漏；改輪詢反而要固定喚醒，閒置時耗電。
