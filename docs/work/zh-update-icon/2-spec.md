# 規格：修正影片資訊、繁簡切換、自動更新、圖示、模擬器

需求：[1-requirements.md](1-requirements.md)
PiliBTR（只讀）：`C:\presonal_project\bilibili_bata\PiliPlus`（以下簡稱 P）

## T-1 buvid3（AC-1）

- `lib/services/api/base_api.dart`：新增 `static String? buvid3`、`static Future<void> ensureBuvid()`：先讀 SharedPreferences `buvid3`；沒有時請求 `/x/frontend/finger/spi` 取 `data.b_3`（失敗時產生 `UUID 大寫 + 5 位數字 + "infoc"` 格式的隨機值），存回 prefs。`getHeaders()` 一律帶 `Cookie`：`buvid3=...`，已登入時再加 `SESSDATA`、`bili_jct`（`withCookie` 為 false 時也帶 buvid3）。
- 在 `splash_screen.dart` 的初始化 `Future.wait` 之後 `await BaseApi.ensureBuvid()`（有逾時 5 秒）。
- 檢查 `lib/` 中所有自己組 header 的 B站請求（`http.get`/`http.post` 未用 `getHeaders` 的、`player_action_mixin.dart` 給 ExoPlayer 的 3 處 `Cookie`），都改為含 buvid3。
- 驗證：用 curl 已確認 412 → 帶 buvid3 後 `code: 0`；實作後模擬器未登入狀態點影片可播放。

## T-2 圖示（AC-11）

- 複製 P 的 `assets/images/logo/logo_2.png`（及 P 的 launcher 設定用到的其他圖）到本專案 `assets/icons/`；`pubspec.yaml` 的 `flutter_launcher_icons` 改成與 P 相同（白底 adaptive、前景 logo_2、monochrome），執行 `dart run flutter_launcher_icons`。
- `android/app/src/main/res/drawable*/banner.png`：用 Python（Pillow）產生 320×180（xhdpi 為 640×360 視既有檔案而定）banner：白底或與 P 相近底色，左側 logo，右側「PiliBTRTV」字樣。覆蓋既有 banner 檔案（保持檔名與尺寸）。
- 確認 `AndroidManifest.xml` 的 `android:icon`、`android:banner` 指向更新後的資源。

## T-3 繁簡切換（AC-2～AC-5）

### T-3a 原始碼文字轉為台灣繁體
- 寫 `tool/s2twp_source.py`（Python + `opencc`，已安裝）：對 `lib/**/*.dart` 的整個檔案文字做 `s2twp`（中文只會出現在字串與註解；識別字為 ASCII）。另外處理 `lib/services/local_server.dart` 內嵌的 HTML。
- 轉換後逐一檢查「和伺服器資料比對」或「當作 API 參數送出」的中文字串（grep `==`、`contains(`、`startsWith(`、`case '`、map key、URL 參數中的中文），改回簡體原文並加註解 `// 與伺服器回傳的簡體文字比對，保留原文`。
- 存在 SharedPreferences 的中文值（例如分區名稱 `home_category_order`、`enabled_categories`）：若以中文為鍵，加相容處理：讀取時把舊的簡體值用同一張對照轉成新值（或改用 ASCII id）。新 applicationId 沒有舊資料，但 v1.2.2-btr.1 使用者會有，要處理。
- `canvas_danmaku`、`fluttertoast` 等不經過 `Text` 的文字，見 T-3b。

### T-3b 顯示時轉換
- 移植 P：`lib/utils/zh_convert.dart` → `lib/utils/zh_convert.dart`；`assets/zh/s2t.txt`、`t2s.txt`、`LICENSE` 複製；`t2s_ui.txt` 用 P 的 `lib/scripts/gen_zh_dict.py` 的 `write_ui_table` 邏輯，針對本專案 `lib/` 重新產生（腳本放 `tool/gen_zh_dict.py`）。`pubspec.yaml` 加 `assets/zh/`。
- 移植 P 的 `zh_text.dart`（`Text` 替代品），新增 `lib/widgets/zh_material.dart`：`export 'package:flutter/material.dart' hide Text;` + `export 'zh_text.dart';`；`lib/widgets/zh_widgets.dart` 同理對 `widgets.dart`。把 `lib/` 中 `import 'package:flutter/material.dart'` 與 `widgets.dart` 改為對應的 zh 版本（參考 P 的 `lib/scripts/use_zh_text.py`）。`TextField` 不轉換（使用者輸入）。
- 其他顯示路徑：`Fluttertoast.showToast`／`SettingsService.toast` 的 msg、彈幕文字（`canvas_danmaku` 的 `DanmakuContentItem` 文字）、`TextSpan`／`RichText` 中的伺服器文字，用 `ZhConvert.convert` 包起來。
- 設定：`SettingsService` 加 `appLanguage`（int：0 跟隨系統、1 繁體、2 簡體，預設 0）；`ZhConvert.init()` 在 `main()` 的 `runApp` 前（需要 `WidgetsFlutterBinding.ensureInitialized()` 與 prefs）。
- 介面設定分頁加「語言」下拉列（`SettingDropdownRow`）。改變後彈「需要重新啟動」對話框（立即／稍後）。重新啟動：`MainActivity` 的 `com.bili.tv/update` channel 加 `restart` 方法（同 P 的 `MainActivity.kt`：重新啟動 launch intent 後結束程序）。

## T-4 自動更新（AC-6～AC-10）

- 新增 `lib/btr_version.dart`：`const btrVersion = String.fromEnvironment('btr.version', defaultValue: 'v1.2.2-btr.2');`。
- 重寫 `lib/services/update_service.dart`（移植 P 的 `lib/utils/update.dart`）：用 `ValueNotifier` 取代 GetX 的 `Rxn`/`obs`；`dio` 下載；GitHub API `https://api.github.com/repos/gordonpow/PiliBTRTV/releases`；`_parse`/`_isNewer` 同 P；`startAuto()`、`check({silent})`、`downloadAndInstall(info)`、`_deleteDownloads()` 同 P；APK 選擇：ABI 相符優先，否則第一個 `.apk`（`device_info_plus` 或 `Platform`/channel 取 ABI；可用既有 `_getDeviceArch` 的做法）。刪除 `update_server_url`、`update_api_key`、`lib/config/env.dart` 中的更新設定（若 env 只有這些，整個刪除並移除引用）。
- `MainActivity.kt`：`installApk` 回傳 `"permission"`（Android 8+ 沒有 `canRequestPackageInstalls()` 時開啟 `ACTION_MANAGE_UNKNOWN_APP_SOURCES` 設定頁），成功回 `"ok"`；FileProvider 路徑包含 `cache/update/`（檢查 `res/xml/file_paths.xml`）。
- 設定：`SettingsService` 加 `autoUpdate`（預設 true）、`updateIntervalHours`（預設 24，選項 1、6、12、24、48、168）。
- UI：「關於軟體」分頁：目前版本（`btrVersion`）、「檢查更新」（動作列，檢查中顯示「檢查中…」；有新版時值顯示新 tag 並帶紅點，按下開更新對話框）、「自動檢查更新」開關、「檢查間隔」下拉。更新對話框：tag、版本說明（可捲動）、「下載並安裝」（顯示進度百分比）、「稍後」、遙控器可操作。設定側欄「關於軟體」分類標籤與首頁側欄的設定入口顯示紅點（`ValueListenableBuilder`）。
- 排程：`HomeScreen` 初始化時 `UpdateService.startAuto()`；`WidgetsBindingObserver` 在 `resumed` 時再呼叫；設定改變時呼叫。
- 所有新增 UI 文字為台灣繁體（會經過 ZhConvert）。

## T-5 建置與模擬器（AC-12、AC-13）

- `flutter analyze`、`flutter build apk --debug`。
- 模擬器：AVD `Android_TV_API33`（`system-images/android-33/android-tv/x86`，裝置 `tv_1080p`）。`emulator -avd Android_TV_API33`，`adb install`，`adb shell am start`，`adb exec-out screencap -p` 截圖存 `docs/work/zh-update-icon/screens/`。方向鍵用 `adb shell input keyevent`。
- 檢查：首頁、點一部影片能播放（未登入）、設定 → 語言切換、關於軟體的更新項目、線程撕裂者。

## 任務順序

T-1、T-2 平行 → T-3（會改動幾乎所有檔案，單獨執行）→ T-4 → T-5。

## 邊界與風險

- s2twp 可能把和伺服器比對的字串改掉，造成功能失效：T-3a 必須列出檢查過的比對點。
- 全面替換 import 可能造成 `Text` 名稱衝突（例如檔案同時 import widgets 與 material）：analyze 必須乾淨。
- 轉換效能：ZhConvert 有 LRU 快取（P 已有）；舊電視需注意，只在非空字串且含中文時轉換。
- GitHub API 未授權每小時 60 次限制：24 小時間隔足夠。
- 自動更新只在 Android；debug 簽署的 APK 才能互相覆蓋安裝。

## 審查紀錄

2026-11-07：Haiku 子代理審查，見 [review-spec.md](review-spec.md)。以下採用，實作以本節為準（優先於上文）：

- R1（T-3a）比對點：轉換後用 `git diff` 逐行檢查；凡不在顯示路徑（Text／Toast／對話框）的中文字串一律還原為簡體並加註解，包含：`ad_filter_plugin.dart` 的關鍵字清單與 `_simplifiedToTraditional`／`_normalizeChineseChars` 對照表、`danmaku_enhance_plugin.dart` 預設屏蔽詞、`base_api.dart` 的「万」「亿」解析、`models/video.dart` 的 `'投稿视频'` 等 badge 比對、`history_video_card.dart` 的 `'未开播'`、`live_player_screen.dart` 的 `'默认'`，以及其他同類。這些常數保留原文並加註解（之後重跑轉換腳本時要跳過含此註解的行）。
- R2：`home_category_order`／`enabled_categories` 是 ASCII id，不需遷移。使用者輸入的中文資料（插件關鍵字、UP 主名稱、搜尋紀錄）不轉換。
- R3：`main()` 先 `WidgetsFlutterBinding.ensureInitialized()`、`await SettingsService.init()`，再 `await ZhConvert.init()`；`SettingsService.appLanguage` 取代 P 的 `Pref.appLanguage`；import 改 `package:bili_tv_app/...`。
- R4：`t2s_ui.txt` 產生器同時抓單引號與雙引號字串；含 `$` 插值的字串在簡體模式靠字表轉換即可。`hintText`、`helperText`、`labelText`、`tooltip`、`Tab(text:)` 等不經過 `Text` 的屬性包 `ZhConvert.convert(...)`（`rg "hintText|helperText|labelText|tooltip" lib` 逐一確認）。
- R5（T-4）ABI：`com.bili.tv/update` channel 加 `getSupportedAbis`（回傳 `Build.SUPPORTED_ABIS`）。選擇：檔名含 ABI 者優先；否則檔名不含任何 ABI 字樣（`arm64-v8a`、`armeabi-v7a`、`x86_64`、`x86`）的通用 `.apk`；都沒有時 toast「找不到適用此裝置的安裝檔」。
- R6：`installApk` 回傳字串 `ok`／`permission`，Dart 用 `invokeMethod<String>`；開權限頁 `ACTION_MANAGE_UNKNOWN_APP_SOURCES` 失敗時 fallback `Settings.ACTION_SECURITY_SETTINGS`；重啟前 await 寫入設定。
- R7：AC 驗證補充：`rg -n "视频|设置|软件" lib` 只剩例外清單；`rg "update_server_url|update_api_key|Env\." lib` 為 0；模擬器截 launcher 畫面驗證 banner；測試語言切換重啟。
- R9：更新對話框 autofocus「下載並安裝」；下載中以 `PopScope` 攔截返回鍵；其他對話框返回鍵可關閉。
- R10：P 的依賴對應：`Api.latestApp` → 常數 URL；GetX `Rxn`/`obs` → `ValueNotifier`；`SmartDialog.showToast` → `SettingsService.toast`；`PageUtils.launchURL` 不需要；`Pref` → `SettingsService`。`use_zh_text.py` 目標檔名改為 `lib/widgets/zh_material.dart`、`zh_widgets.dart`。`UpdateService.init()` 與 `about_settings.dart` 同步改。

不採用：
- R5 假 release 測試、R7 單元測試：本次不加，以模擬器測試為主。
- R8：`comment.bilibili.com`、passport QR 登入維持原樣（不是 412 的來源）。
- R10 `_lastCheck` 持久化：與 PiliBTR 相同（記憶體），冷啟動時檢查一次。
- 審查稱「本專案不是 git repo」不正確，已用 git 管理。

## 實作偏差

（實作中補）
