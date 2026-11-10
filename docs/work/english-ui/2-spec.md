# 規格：英文介面與語言選單

參考實作 A = `C:\presonal_project\bilibili_bata\PiliPlus`（PiliBTR）。本專案 B 已有同架構的繁簡轉換（`lib/utils/zh_convert.dart`、`lib/widgets/zh_material.dart` 只換 `Text`、`zh_text.dart`、`zh_toast.dart`）。

## 設計

### 執行時翻譯（AC-3、4、5、7、9）
- `lib/utils/zh_convert.dart`：比照 A `lib/utils/zh_convert.dart`
  - `enum ZhScript { traditional, simplified, english }`
  - 語言設定值 0 跟隨系統、1 繁體、2 簡體、3 英文（`SettingsService` key `app_language` 沿用）。`resolve` 依 AC-5 規則。
  - `convert`：英文模式先 `I18nPack.translate`，查不到回繁體原字串。
- 新增 `lib/utils/i18n_pack.dart`：移植 A 的 `i18n_pack.dart`，`url` 改為 `https://raw.githubusercontent.com/gordonpow/PiliBTRTV/main/i18n/en.json`；保留 strings／templates、LRU 快取、documents 存檔、7 天背景檢查、`download()` 回報進度與錯誤。
- 新增 `lib/widgets/zh_material_widgets.dart`：移植 A 的 `zh_material_widgets.dart`（IconButton tooltip、Tab、TextField／InputDecoration hint、Tooltip 等），由 `lib/widgets/zh_material.dart` 一併匯出並 hide 對應 material 類別。只移植 B 實際用到的元件；B 沒用到的不搬。
- API 資料不翻譯（AC-7）：A 的作法是什麼就照做（確認 A 如何避免翻譯影片標題等；若 A 是靠「字典沒有就不翻」，B 照同樣方式，並確保抽字串腳本只抽原始碼字面值）。
- `main.dart`：啟動時 `await I18nPack.load()`（英文模式才載入），設定 `Locale`（英文時 `Locale('en')`），英文模式啟動後背景檢查更新。

### 語言選單（AC-1、2、4）
- `lib/screens/home/settings/tabs/interface_settings.dart:152-172`：語言改為按確定開啟選單對話框（TV D-pad 可操作，焦點預設在目前值），項目：跟隨系統／繁體中文／簡體中文／English。不用 `SettingDropdownRow` 的循環切換。
- 選 English 或「跟隨系統」且結果為英文、且沒有語言包：顯示下載進度對話框；失敗 toast 並保持原值。
- 存檔後呼叫既有 `AppRestart.ask`（`lib/utils/app_restart.dart`）一次。選同一個值不做任何事。
- 英文模式時，同區塊多一項「更新語言包」（顯示目前語言包版本），按下手動下載。
- `lib/screens/home/settings/settings_index.dart`：語言項目說明改為「切換語言（繁體／簡體／English），重新啟動後生效」，新增「更新語言包」搜尋項目。

### 語言包內容（AC-6）
- 移植 A 的 `lib/scripts/extract_i18n.py`、`split_i18n.py`、`merge_i18n.py` 到 B 的 `tool/i18n/`（不放在 lib 下），路徑改為 B 的 `lib/`。
- 抽出 B 的介面中文字串（約 850 條）；有插值的字串用 templates（格式同 A）。
- 翻譯：先用 A 的 `i18n/en.json` 中完全相同的 key 沿用；其餘由子代理翻譯成自然、簡短的英文（TV 介面，盡量短）。產品名、技術名詞維持英文原名（BTR、CDN、HDR、AV1、H.265、UP 主→Uploader 等用法比照 A）。
- 產生 `i18n/en.json`，`version` 用建置時間 `yyyyMMddHHmm`。
- 用伺服器簡體字串比對的常數（CLAUDE.md 例外）不得被翻譯邏輯影響（它們是比對用，不顯示）。

### README（AC-8）
- 現有 `README.md` 內容移到 `README.zh-TW.md`；`README.md` 改寫成英文。兩檔第 5 行附近互相連結，格式同 A：`English | [繁體中文](README.zh-TW.md)`、`[English](README.md) | 繁體中文`。
- 英文版：說明這是 Android TV 用 Bilibili 第三方用戶端、BTR、下載哪個 APK（arm64-v8a／armeabi-v7a）、如何切到 English（Settings → Interface → Language）、語言包線上下載。

## 任務
- T-1（無相依）：執行時翻譯（zh_convert、i18n_pack、zh_material_widgets、main）＋單元測試（convert 英文分支、template 套用、查無字串回繁體、resolve 規則）。
- T-2（相依 T-1 介面）：語言選單、下載進度、更新語言包、settings_index。
- T-3（無相依，可與 T-1 平行）：腳本移植、抽字串、翻譯、產生 `i18n/en.json`。
- T-4（無相依）：README 兩版。
- T-5（相依 T-1～T-3）：在 TV 模擬器以英文模式檢查首頁、播放器、設定主要畫面溢出並修正（使用者要求驗證時）。

## 驗證對應
| AC | 方式 |
|---|---|
| AC-1、2、4 | diff 審查；模擬器操作（待使用者或要求時） |
| AC-3、5、9 | 單元測試；模擬器英文模式截圖 |
| AC-6 | 檢查 en.json 條數與抽字串覆蓋率（腳本輸出未翻譯數） |
| AC-7 | 程式審查：翻譯只發生在字典命中時 |
| AC-8 | 檢查兩份 README |

## 邊界與風險
- 語言包必須在 App 發布前推到 main，否則使用者選 English 下載不到。發布順序：先 push `i18n/en.json`，再發 Release。
- 下載失敗（無網路、GitHub 被擋）：維持原語言並提示。
- 舊設定值只有 0～2，新增 3 相容。
- 英文過長溢出：T-5 處理主要畫面；其他畫面列為已知限制。
- 與上游 BiliTV merge：改動集中在 utils/widgets 與設定頁，衝突有限。

## 審查後修訂（覆蓋上文相衝突的部分）

- R-1 `zh_convert.dart`：B 的 `convert`（:97）、`span`（:150）在 `_table.isEmpty` 時直接 return，英文分支必須放在這個判斷之前（A:105-106 的順序）。`init`、`resolve` 同步改。`systemScript`：zh-Hant／TW／HK／MO → 繁體；zh-Hans／CN／SG → 簡體；其他（含 en）→ english，但 `I18nPack.isLoaded == false` 時回繁體並觸發背景下載（下次啟動生效）。加單元測試。
- R-2 首次啟動：`main.dart` 在 `ZhConvert.init()` 後，若設定為 0 且系統解析為英文但沒有語言包 → 背景下載。下載失敗也記錄檢查時間，同一天（24 小時）內不再重試；手動「更新語言包」不受限。
- R-3 元件覆蓋：A 的 `zh_material_widgets.dart` 依賴 `material_ui`，不可照搬。B 新增 `lib/widgets/zh_material_widgets.dart`，以 `package:flutter/material.dart` 為基礎包裝 B 實際用到的：`Tooltip`、`IconButton`（tooltip）、`Tab`、`TextField`／`InputDecoration`（hintText、labelText）、`SnackBar` 內容走 Text 不另處理。`zh_material.dart` 一併 `hide` 並匯出。用腳本（擴充 `tool/use_zh_text.py` 或新增 `tool/i18n/check_widgets.py`）確認 lib 下沒有直接 `import 'package:flutter/material.dart'` 又使用上述元件而漏網的檔案。`SettingsService.toast`、`showZhToast`、`Fluttertoast` 三條路都要經過 `ZhConvert.convert`。
- R-4 語言選單：新增 `lib/screens/home/settings/widgets/setting_picker_row.dart`（按確定開選單，左右鍵不動作、上下照常導航）與 TV 用選單對話框（清單項目可 D-pad 選取，開啟時焦點在目前值，返回鍵關閉）。`SettingDropdownRow` 不改。
- R-5 語言包更新：與 A 相同，背景檢查直接下載整包再比 `version`（約數百 KB，可接受），AC-4 的「比對 version」即此意。`load` 失敗（損壞）視為未載入：英文模式下回繁體並觸發重新下載。tmp→rename 中斷殘留 tmp 可接受。
- R-6 `error_report_service.dart:66` 改為「0 跟隨系統, 1 繁體, 2 簡體, 3 English」。錯誤報告內容是純文字上傳，不經 `Text`，不受翻譯影響。
- R-7 AC-7 修正為：只翻譯與字典完全相同的字串或符合 template 的字串；API 資料（標題、暱稱、彈幕、留言）剛好等於字典 key 時會被翻譯，列為已知限制（與 PiliBTR 相同）。設定頁的分區排序名稱是介面標籤，可翻譯。
- R-8 設定搜尋（`settings_index.dart:110`）：英文模式下以翻譯後的 label＋subtitle 比對，同時保留原中文比對。
- R-9 刪除「設定 `Locale('en')`」：`MaterialApp` 沒有 localizationsDelegates，設定無作用。
- R-10 覆蓋率閘門：抽字串腳本輸出「原始碼中文字面值總數／已翻譯數／未翻譯清單」，未翻譯數須為 0（不適合翻譯的字串，如伺服器比對常數、log、錯誤報告，列入腳本的排除清單）。

## 審查紀錄
- Sonnet 規格審查 11 條：#1～#10 採用（R-1～R-10）；#11 無問題。

## 實作偏差
- 背景下載觸發放在 `ZhConvert.init`（main 已呼叫），不另寫在 main.dart；init 先 load 語言包再 resolve，否則跟隨系統（英文）無法判斷。
- `systemScript` 保持無副作用；新增 `needsEnglishPack(language)`（只看設定與系統語言）供選單判斷是否要下載。
- 選單行 `SettingPickerRow`：左鍵仍回側邊欄（與其他列一致），右鍵不動作。
- 失敗退避：meta.json 多存 `ok`；沒有語言包或上次失敗為 24 小時，已載入且成功為 7 天。
- 新增 `showI18nDownloadDialog`（下載進度）、`ZhConvert.clearCache`／`resetForTest`、`SettingsEntry.englishOnly`（「更新語言包」搜尋項只在英文模式出現）。
- `SettingsService.appLanguage` 超出 0～3 視為 0。
- `zh_material_widgets.dart` 只包裝 Tooltip、IconButton（預設建構式）、Tab、InputDecoration（常用欄位）；B 其他處已用 ZhConvert.convert 的 hintText 重複轉換無害。
- 誤對整個 lib 跑 dart format，已用 git checkout 還原 7 個原本乾淨的檔案；既有未 commit 修改的檔案 diff 大小未變。
