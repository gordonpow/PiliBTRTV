# 規格：遙控器操作與過場動畫整理（#40、#41）

## 需求（AC）
- AC-1：簡介面板在「簡介」分頁按左鍵關閉面板；「留言」分頁按左鍵回到「簡介」。面板背景不透明，後方控制列、時鐘、字幕不透出。
- AC-2：每個確認對話框開啟時就有焦點；破壞性操作（登出、清除快取、送出回報）預設焦點在「取消」。
- AC-3：稽核找到的焦點死路、確認鍵無反應、返回鍵不一致問題修正（見任務清單）。
- AC-4：播放器面板與覆蓋層、首頁分頁、焦點樣式等有淡入／滑入動畫；低記憶體裝置（MemoryTier low／critical）不做動畫。

## 共用元件（已完成）
`lib/utils/anim.dart`：
- `Anim.fast`（150ms）、`Anim.normal`（200ms）、`Anim.curve`、`Anim.of(d)`（低記憶體回傳 0）、`Anim.reduced`。
- `EnterTransition(child, offset, duration)`：掛上時淡入＋滑入，離場不做動畫。**注意**：`Positioned` 必須是 `Stack` 的直接子元件，所以 EnterTransition 要包在 `Positioned` 裡面（面板 build 內），不能包在外面。
- 所有新增動畫時長一律用 `Anim.of(...)`。不要做離場動畫（避免已關閉面板搶焦點、吃按鍵）；AnimatedOpacity／AnimatedContainer 這類同一元件內的狀態動畫可以雙向。

## 任務

### T-A 播放器（lib/screens/player/**）
1. info_panel.dart：`_tab==0` 按左鍵呼叫 `widget.onClose`（全域 handler 目前只處理返回鍵，onClose 要能關閉並把焦點還給控制列 info 按鈕，等同 `closeInfoPanel`）；`_tab==1` 左鍵回簡介。背景改不透明（`Color(0xFF1F1F1F)`，alpha 1）。分頁內容用 AnimatedSwitcher（Anim.fast 淡入），分頁底線改 AnimatedContainer／AnimatedAlign。面板進場用 EnterTransition（右側滑入）。
2. episode_panel.dart、settings_panel.dart：進場 EnterTransition（右側滑入）。settings_panel 子選單切換（:166 標題、:170 內容）用 AnimatedSwitcher Anim.fast 淡入。
3. related_strip.dart：進場 EnterTransition（offset 0,0.3，從底部）。
4. 暫停指示器（pause_indicator.dart）：進場淡入＋縮放 0.8→1（Anim.fast）。
5. 迷你進度條（player_screen.dart:168 附近）：改用 AnimatedOpacity（Anim.normal），與控制列交替。
6. 快退快進預覽／時間提示（player_screen.dart:180-211）：進場淡入 120ms。
7. 播完倒數卡片（:322）：EnterTransition 從右下。
8. SponsorBlock 跳過按鈕（:422-447）：進場 EnterTransition；焦點樣式改 AnimatedContainer。修正確認鍵按不到：`handleGlobalKeyEvent` 開頭在 `currentSkipAction != null` 時，確認鍵直接執行跳過（呼叫既有的跳過函式）並回 handled。
9. quality_picker_sheet.dart:67：在最上／最下一項繼續按上下鍵回 handled。
10. video_layer.dart:32：封面切到影片時影片淡入（Anim.normal）。

### T-B 首頁、設定、對話框
1. profile_tab.dart:156 登出確認：改用專案的 `showConfirmDialog`（或等效），預設焦點在「取消」。
2. storage_settings.dart:65 清除快取確認：「取消」autofocus。
3. error_report_dialog.dart：各階段（:383、:397、:421、:437）按鈕加 `ValueKey(_stage)` 讓 autofocus 重新生效；自動跳出時（:334）預設焦點改在「取消」。
4. video_action_dialogs.dart:564：名稱輸入框攔截下鍵改 `nextFocus()`（比照 btr_settings.dart:158）。
5. setting_dropdown_row.dart:92：左鍵往前一個值、右鍵往後一個值、確認鍵往後一個值（不改成 SettingPickerRow，避免大改；行為對齊左右方向）。
6. home_screen.dart:254 返回鍵：焦點在內容區時，第一次返回把焦點移回側欄目前分頁；焦點已在側欄時才維持原本行為（非首頁回首頁、首頁提示再按一次退出）。
7. home_tab.dart:170 首次載入失敗：也呼叫 onFirstLoadComplete，顯示可聚焦且 autofocus 的「重試」按鈕。
8. followings_screen.dart:136 載入失敗：加 autofocus 的「重試」按鈕；:83 下鍵目標不存在時移到最後一張。
9. dynamic_tab.dart:239：最後一列不滿時下鍵移到最後一張（比照 home_tab.dart:319）。
10. about_settings.dart:222：下載失敗按鈕恢復時 requestFocus 回下載鈕。
11. login_view.dart:491：QR 過期出現「重新產生」時加 key 或 requestFocus(_regenFocus)，焦點移到該鈕。
12. 動畫：
    - base_tv_card.dart:381 焦點白框用 FadeTransition 綁現有 `_glowAnim`。
    - tv_focusable_item.dart:50、tv_tab_bar.dart:94 焦點底色／邊框改 AnimatedContainer（Anim.fast）。
    - home_screen.dart:376 IndexedStack 不拆，外層在切換分頁時做 Anim.fast 淡入（例如 key 變化的 TweenAnimationBuilder 或 AnimatedSwitcher 包一層不影響 IndexedStack 狀態的 Opacity）。
    - settings_view.dart:566 設定子分頁切換 AnimatedSwitcher Anim.fast。
    - home_tab.dart:256、live_tab.dart:265、dynamic_tab.dart:158、history_tab.dart:604 載入中→內容 AnimatedSwitcher Anim.normal。
    - staggered_image.dart:59：無效的 AnimatedOpacity（永遠 1.0）刪掉。
    - 封面圖 fadeInDuration 維持 0（效能），不改。

### T-C 直播（lib/screens/live/live_player_screen.dart）
1. :724 彈幕設定第 2～6 項：`_toggleDanmakuSetting` 補 case 2～6，確認鍵與左右鍵有作用（行為比照 onTap）。
2. :474 設定面板開著時 Escape 先關面板。
3. :831 設定面板進場 EnterTransition（右側滑入）。

## 限制
- 註解與介面文字只用繁體中文（台灣用語）；新增介面字串加入 i18n/en.json（"strings"，含 {0} 放 "templates"）。
- 不可修改 lib/services/api/auth_api.dart、lib/services/api/live_api.dart、lib/services/btr/btr_config.dart、lib/utils/app_restart.dart、lib/utils/anim.dart。
- 不要 commit、不要 git stash。
- 只改自己任務範圍的檔案（T-A 只動 lib/screens/player/**；T-B 只動首頁、設定、lib/widgets/**、login、profile；T-C 只動 live_player_screen.dart）。i18n/en.json 由 T-B 負責；T-A、T-C 若有新字串，寫在 impl 回報裡，不要改 en.json。

## 驗證
- `flutter analyze`、`flutter test`、`python tool/i18n/extract_i18n.py` untranslated=0。
- 模擬器：使用者要求時。

## 審查紀錄（agy Sonnet）
1. related_strip EnterTransition 在 Positioned 外：不採用。RelatedStrip 回傳 Align，Stack 子元件不必是 Positioned，EnterTransition 在 Align 內無 ParentData 問題。
2. home_screen 返回鍵破壞搜尋流程：不採用。搜尋分頁在新邏輯之前已 return。
3. 跳過鍵吃掉畫質選單確認鍵：不採用。畫質選單是 showModalBottomSheet（獨立 route），按鍵不經過播放器全域 handler。
4. `?current` 語法：不採用。SDK ^3.10.3。
5. error_report_dialog 閃退時焦點落點：不採用（取消鈕 autofocus，content 沒有其他 autofocus），列為實機確認項。
6. about_settings builder 內賦值：不採用。只在下載→非下載時排 postFrame requestFocus，重複呼叫無害。

## 實作偏差
- video_layer 影片淡入撤回：Opacity 疊在 PlatformView／隧道播放上有風險。
- 直播設定面板 EnterTransition 由 agy 包在 Positioned 外，已改到 LiveSettingsPanel 內；左右鍵也能切換開關類彈幕設定。
