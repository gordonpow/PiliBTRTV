# 需求：英文介面與語言選單

## 目標
讓不懂中文的使用者也能使用 PiliBTRTV：加入英文介面（做法與 PiliBTR 相同），語言改為一次選定，README 提供英文與繁體中文版。

## 驗收條件
- AC-1：「設定 → 介面設定 → 語言」按確定彈出清單：跟隨系統、繁體中文、簡體中文、English；選定後才存檔並跳出一次重新啟動提示（稍後／重新啟動）。選目前的值不提示。方向鍵左右不再循環切換語言。
- AC-2：選 English 時先下載語言包 `https://raw.githubusercontent.com/gordonpow/PiliBTRTV/main/i18n/en.json`，顯示下載中；失敗時提示並維持原語言、不存檔。成功才存檔並提示重新啟動。
- AC-3：英文模式重新啟動後，介面文字（`Text`、toast、按鈕、提示文字、Tab、輸入框提示、Tooltip、對話框）以語言包翻譯；查不到的維持繁體中文。
- AC-4：語言包存在 app documents 資料夾，啟動時讀取；英文模式每 7 天在背景檢查是否有新版本（比對 `version`），有就下載，下次啟動生效。設定頁英文模式多一項「更新語言包」可手動更新。
- AC-5：「跟隨系統」：系統語言為英文時使用英文（需已有語言包，沒有就用繁體並在背景下載）；繁中地區用繁體；簡中地區用簡體；其他語言用英文（同上規則）。
- AC-6：repo 新增 `i18n/en.json`，涵蓋本 App 介面中文字串（格式同 PiliBTR：`version`、`strings`、`templates`），以及抽字串、合併的腳本。
- AC-7：伺服器回傳的內容（影片標題、UP 主名稱、彈幕、留言、分區名稱等 API 資料）不翻譯。
- AC-8：README：`README.md` 改為英文，新增 `README.zh-TW.md`（繁體中文，現有內容），兩者開頭互相連結；英文版說明下載哪個 APK、如何切換英文。
- AC-9：繁體／簡體模式行為不變。

## 不做
- 不打包語言包進 APK（與 PiliBTR 相同，線上下載）。
- 不改用 gen-l10n。
- 不處理英文過長造成的所有排版問題；只修明顯溢出的主要畫面（首頁、播放器控制列、設定）。

## 限制
- 註解、文件只用繁體中文或英文。
- `flutter analyze` 無問題、測試通過。
- 參考實作：`C:\presonal_project\bilibili_bata\PiliPlus`（PiliBTR）的 `lib/utils/i18n_pack.dart`、`lib/utils/zh_convert.dart`、`lib/common/widgets/zh_material_widgets.dart`、`lib/pages/setting/models/style_settings.dart:83-88,935-1050`、`lib/scripts/*_i18n.py`、`i18n/en.json`。

使用者已指定「做法與 PiliBTR 相同」，未另詢問。
