# 規格審查：zh-update-icon（2-spec.md）

審查範圍：`1-requirements.md`、`2-spec.md`，以及規格指定的程式碼與 P（PiliPlus）參考檔。
時間點：21:43。`lib/services/api/base_api.dart` 於 21:42 已被實作修改，下列行號以當時內容為準；`update_service.dart` 仍為原始版本。

## 1. [T-3a] 比對點清單不完整，s2twp 會改壞伺服器比對與預設值（嚴重）

規格的 grep 只涵蓋 `==`、`contains(`、`startsWith(`、`case '`，漏了以下形式：

- 清單常數 + 迴圈 `contains`：`lib/plugins/ad_filter_plugin.dart:35-80`（`_adKeywords`、`_clickbaitKeywords`），300-321 行以 `title.toLowerCase().contains(keyword)` 和伺服器標題比對。`'广告'` 變 `'廣告'` 後，過濾失效。
- 預設值：`lib/plugins/danmaku_enhance_plugin.dart:154、160` 的 `['剧透', '前方高能']`，`剧` 變 `劇`，彈幕屏蔽預設失效。
- 數字單位解析：`lib/services/api/base_api.dart:204-209`（`endsWith('万')`、`replaceAll('万','')`、`'亿'`）。伺服器回 `1.2万`，s2tw 會把 万→萬、亿→億，`toInt` 回 0。
- Map 鍵正規化：`lib/plugins/ad_filter_plugin.dart:82-102`（`_simplifiedToTraditional`）與 249-275（`_normalizeChineseChars`）。s2twp 會把鍵 `说` 轉成 `說`，鍵值變成同字，UP 主拉黑的簡繁比對失效（249-258 行比對伺服器 UP 主名稱）。
- 單行比對但 grep 可能漏：`lib/models/video.dart:44`（`'投稿视频'`，伺服器 badge）、`video.dart:103`、`lib/widgets/history_video_card.dart:76`（`== '未开播'`）、`lib/screens/live/live_player_screen.dart:289`（`desc != '默认'`，伺服器畫質描述）。

修正：
- T-3a 改列上述形式，並列出「例外檔案：行」清單，轉換前排除。
- 比對常數改用 `\u` 跳脫（例如 `'广告'`）並加註解，s2twp 不會改動。
- 轉換前先備份，轉換後以備份 diff 逐行檢查，凡轉換的字串不在 Text／Toast 顯示路徑者列為還原項。本專案不是 git repo，所以要用備份，不能用 git diff。

影響 AC：AC-1、AC-2、AC-4。

## 2. [T-3a] 錯誤假設：`home_category_order`、`enabled_categories` 不是中文值

證據：`lib/services/settings_service.dart:262-263、277-278、305-318`。兩個 key 的預設值與儲存值都是 ASCII id（`'recommend'`、`'popular'`…），不需遷移。規格第 24 行要求的「用同一張對照轉成新值」是多做的工作。

實際需要處理的使用者中文資料：`plugin_config_*` JSON 內的使用者輸入關鍵字與 UP 主名稱（`ad_filter_plugin.dart:141-154`、`danmaku_enhance_plugin.dart:51-64`），以及搜尋紀錄（`search_history_service.dart:30-36`）。這些值用來比對伺服器資料，必須保留原文，不能在讀取時轉換。

修正：刪除第 24 行的遷移項，改寫為「已存的中文使用者資料不轉換」。

## 3. [T-3b] `ZhConvert.init()` 放在 `main()` 會拋 StateError

證據：`lib/main.dart:12-30` 沒有 `SettingsService.init()`，它只在 `lib/screens/splash_screen.dart` 的 `Future.wait` 內呼叫。`lib/services/settings_service.dart:44-50` 的 `prefs` 在未 init 時拋 `StateError`。P 的 `zh_convert.dart:75` `resolve(Pref.appLanguage)` 在 try 外，會直接拋出。

另外 P 的 `zh_convert.dart` 與 `zh_text.dart` 的 import 是 `package:PiliPlus/...`，本專案套件名為 `bili_tv_app`（`main.dart` 的 import），要改寫。

修正：規格明寫 `main()` 先 `await SettingsService.init()`，再 `ZhConvert.init()`；新增 `SettingsService.appLanguage` getter 取代 `Pref.appLanguage`；所有 import 改為 `package:bili_tv_app/...`。

## 4. [T-3b] 簡體模式的 UI 對照表有漏網，Flutter 內部文字未轉換

- P `lib/scripts/gen_zh_dict.py` 的 `write_ui_table`（第 128 行）正規表示式只抓單引號 `'...'`。本專案 `lib/` 有 31 行雙引號中文字串，例如 `lib/screens/home/live_tab.dart:243、252`、`lib/screens/live/live_player_screen.dart:422`，都不會進入 `t2s_ui.txt`。
- 含 `$` 插值的字串被排除，例如 `about_settings.dart:83` `'当前版本: $_currentVersion'`，需要拆開或分段轉換。
- `hintText`、`helperText`、`Tab(text:)`、`tooltip` 不經過 zh 版 `Text`：`ad_filter_plugin.dart:485、547`、`danmaku_enhance_plugin.dart:298`、`btr_settings.dart:197-198`。規格 T-3b 沒列。

修正：t2s_ui 的表達式同時處理 `'` 與 `"`；含 `$` 的字串分段呼叫 `ZhConvert.convert`；hintText、helperText 包 `ZhConvert.convert(...)`。驗證指令：`rg "hintText|helperText|labelText|tooltip" lib`，逐一確認。

## 5. [T-4] ABI 偵測的前提錯誤，AC-9 在模擬器上無法驗證

- 規格說「可用既有 `_getDeviceArch` 的做法」。`lib/services/update_service.dart:87-99` 讀的是 `Platform.version`（Dart VM 版本字串），不含 ABI，回傳的是猜測值，不可沿用。
- 規格寫「device_info_plus 或 Platform/channel」，但 `pubspec.yaml` 沒有 `device_info_plus`。
- 模擬器是 x86（T-5），release 資產通常只有 arm APK。AC-9 的 fallback「取第一個 `.apk`」會下載 arm APK，安裝失敗（INSTALL_FAILED_NO_MATCHING_ABIS）。AC-9 因此無法用真實 release 驗證。另外 P `update.dart:165-169` 的做法是找不到就提示並開網頁，與 AC-9 的 fallback 不同，需要確認 AC 是否要保留。

修正：在既有 channel `com.bili.tv/update` 加 `getSupportedAbis`，回傳 `Build.SUPPORTED_ABIS`（Kotlin，不需新套件）。測試改用假 release JSON，或加名稱含 `x86_64` 的假資產。

## 6. [T-4] 安裝權限與 Dart/Kotlin 介面細節

- `MainActivity.kt` 的 `ACTION_MANAGE_UNKNOWN_APP_SOURCES` 沒有 try/catch。部分 Android TV 機種沒有此 Activity，`startActivity` 會拋 `ActivityNotFoundException`，UI 只會看到失敗。修正：catch 後 fallback 到 `Settings.ACTION_SECURITY_SETTINGS`。
- 現有 Kotlin `installApk` 回傳 `result.success(true)`（`MainActivity.kt:27`），Dart `_installApk`（`update_service.dart:215-223`）為 void。規格改回傳字串 `"permission"`／`"ok"` 時，Dart 必須同步改為 `invokeMethod<String>`，否則 `true` 會造成型別錯誤。規格未寫。
- 重新啟動（AC-5）：`SettingsService` 的 `setInt`／`setString` 是非同步，重啟前必須 `await`，否則程序結束時設定可能遺失。規格 T-3b 未寫。
- 已確認不需改：`AndroidManifest.xml:5` 已有 `REQUEST_INSTALL_PACKAGES`；`file_paths.xml:6` 的 `cache-path` 已涵蓋 `cache/update/`；FileProvider authority `${applicationId}.fileprovider` 與 Kotlin 的 `${packageName}.fileprovider` 一致。

## 7. AC 驗證缺口

- AC-13：規格 T-5 寫 `flutter build apk --debug`，AC-13 要求 `--release`。
- AC-2：無驗證步驟。建議：轉換後 `rg -n "视频|设置|软件" lib`，排除例外清單後應為 0。
- AC-10：無驗證步驟。建議：`rg "update_server_url|update_api_key|Env\." lib` 應為 0。
- AC-11：T-5 只截首頁，launcher 圖示與 TV banner 未驗。建議用 adb 截 launcher 畫面。
- AC-5：不在 T-5 檢查清單（立即重啟、稍後生效）。
- AC-1 已登入情境：T-5 只測未登入。
- AC-3、AC-6、AC-9 的邏輯（`resolve`、`systemScript`、`_parse`、`_isNewer`、ABI 選擇）沒有自動測試。建議新增純 Dart 測試（`test/zh_convert_test.dart`、`test/update_version_test.dart`），`_parse`、`_isNewer` 需改為非 private 或加 `@visibleForTesting`。

## 8. [T-1] Cookie 點位數量錯誤，且有未帶 header 的請求

- 規格寫 `player_action_mixin.dart` 的 ExoPlayer「3 處」。實際是 `player_action_mixin.dart:269、1171、1293` 加上 `lib/screens/live/live_player_screen.dart:344`，共 4 處，都用 `BaseApi.cookieHeader`（`base_api.dart:24`）。
- 未經 `getHeaders` 的 B站請求：`lib/services/api/auth_api.dart:55、85`（`http.post(uri)`，無 header，TV 登入 QR）、`lib/services/api/playback_api.dart:252-258`（`comment.bilibili.com` 彈幕 XML，手寫 UA）。規格只寫「檢查」，未列出。
- 修正：規格列出上述點位；`comment.bilibili.com` 與 passport 請求是否需要 buvid3，用 curl 先驗證，不要只憑 AC-1 的「所有 B站 API」推定。

## 9. [T-3b／T-4] TV 遙控器焦點與對話框行為未規格化

語言下拉、重啟對話框（立即／稍後）、更新對話框、下載進度對話框都沒寫初始焦點、返回鍵行為、下載中能否關閉。P 的進度對話框用 `barrierDismissible: false`，但 SmartDialog 不適用本專案（pubspec 沒有 `flutter_smart_dialog`）。

修正：參考 `lib/screens/home/settings/widgets/setting_action_row.dart` 的 focusNode／onMoveUp 模式。規格明寫：更新對話框 autofocus 在「下載並安裝」；下載中以 `PopScope` 攔截返回鍵；「稍後」可用遙控器返回關閉。

## 10. [T-4] 移植 P 的依賴未對應，檔名與 P 不一致

- P `update.dart` 使用 `Api.latestApp`（P `lib/http/api.dart:420`）、`Constants.sourceCodeUrl`、`PageUtils.launchURL`、`Pref`、GetX 的 `Rxn`／`obs`、`SmartDialog`，本專案都沒有。規格寫「移植，同 P」，卻沒有對應表。
- P 的 `use_zh_text.py` 會把 import 改成 `zh_flutter_material.dart`、`zh_material_widgets.dart`，規格只建立 `lib/widgets/zh_material.dart` 與 `zh_widgets.dart`。實作者若直接沿用 P 腳本會失敗。修正：規格明寫目標檔名，並改寫腳本的 TARGETS。
- `UpdateService.init()`（`splash_screen.dart` 的 Future.wait 內）與 `about_settings.dart` 的呼叫要同步改。
- `Env` 只被 `update_service.dart:54-55` 使用（grep 確認），整檔刪除安全，規格寫法正確。
- 簡化建議：本 App 只跑 Android，`downloadAndInstall` 的非 Android 分支（P `update.dart:153-156`）可刪；訊息用既有 `SettingsService.toast`；`_lastCheck` 只存在記憶體，每次冷啟都打 GitHub。若要 AC-7 的 24 小時間隔真正生效，應把 lastCheck 存入 SettingsService。
