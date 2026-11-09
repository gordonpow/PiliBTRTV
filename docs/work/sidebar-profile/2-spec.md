# 規格：側邊欄重整、個人頁面、關注直播、設定搜尋

需求見 `1-requirements.md`。三個任務改不同檔案，可平行實作；彼此只透過下面「介面約定」相依。

## 介面約定（三個任務都要遵守）

側邊欄新 index：0 搜尋、1 首頁、2 動態、3 歷史、4 直播、5 關注、6 個人、7 設定。

- `FollowLiveTab`（T-1 新增，`lib/screens/home/follow_live_tab.dart`）：`FollowLiveTab({Key? key, FocusNode? sidebarFocusNode, bool isVisible})`；`FollowLiveTabState` 公開 `refresh()`、`focusFirstItem()`。
- `ProfileTab`（T-2 新增，`lib/screens/home/profile/profile_tab.dart`）：`ProfileTab({Key? key, FocusNode? sidebarFocusNode, bool isVisible, VoidCallback? onLoginSuccess, VoidCallback? onLogout})`；`ProfileTabState` 公開 `refresh()`、`focusFirstItem()`、`bool handleBack()`（登入畫面開啟時關閉它並回傳 true，否則 false）。
- `SettingsView`（T-3 修改）：保留現有建構子參數（`onLogin`、`onLogout` 等可留著但不再使用，避免編譯錯誤），`SettingsViewState` 公開 `focusFirstCategory()`（現有）與 `bool handleBack()`（搜尋鍵盤／搜尋結果開啟時關閉並回傳 true）。
- 個人頁與設定頁內容最左按左鍵回到各自的 `sidebarFocusNode`。

## T-1 側邊欄與關注直播（`home_screen.dart`、`live_tab.dart`、新檔）

1. `home_screen.dart`：`_tabIcons` 加關注與設定圖示（新增 `assets/icons/follow.svg`、`assets/icons/settings.svg`，風格與現有 svg 一致，單色線條；或確認 pubspec assets 設定會包含新檔）。依新 index 重新對應探索報告列出的所有寫死 index：預設首頁 1、同分頁再按重新整理（加 5 關注、6 個人）、切換時重新整理（加 5）、返回鍵（6 呼叫 `ProfileTabState.handleBack`、7 呼叫 `SettingsViewState.handleBack`，其餘回首頁）、`isUserTab` 改為 index 6（頭像）、新版本紅點移到設定（7）、onMoveRight（4 直播、5 關注 `focusFirstItem`、6 個人 `focusFirstItem`、7 設定 `focusFirstCategory`）、IndexedStack children、`_refreshCurrentTab` 加關注與個人、`_preloadOtherTabs` 加關注（延遲 3000ms）。
2. 移除 `LoginTab` 的使用（檔案可刪除，若其他地方沒有引用）。登入成功（`ProfileTab.onLoginSuccess`）呼叫 `_refreshCurrentTab`；登出（`onLogout`）呼叫 `AuthService.logout()` 後 `_refreshCurrentTab` 並 `setState`（更新頭像）。
3. 從 `live_tab.dart` 抽出共用網格 `lib/screens/home/live/live_room_grid.dart`（`LiveRoomGrid`：rooms、sidebarFocusNode、onMoveUpFromTop、onLoadMore、scrollController、topPadding），LiveTab 與 FollowLiveTab 共用。LiveTab 移除「我的關注」分類，第一個分類為「推薦直播」（AC-4）。
4. `FollowLiveTab`：上方標題「關注直播」（固定，樣式同歷史頁舊標題），內容為 `LiveRoomGrid`，資料用 `LiveApi.getFollowedLive(page, pageSize: 20)`；未登入「請先登入」、空清單「暫無開播的主播」（AC-3）。

## T-2 個人頁面（新檔＋API＋UpSpaceScreen）

1. API（新增 `lib/services/api/user_api.dart`，`bilibili_api.dart` 加轉接）：
   - `getMyInfo()`：`GET /x/web-interface/nav`（cookie）→ `face`、`uname`、`mid`、`level_info.current_level`／`current_exp`／`next_exp`（next_exp 可能是字串 "--"）、`money`（硬幣）、`wallet.bcoin_balance`、`vipStatus`、`vipDueDate`（毫秒）、`vip_label.text`。
   - `getMyStat()`：`GET /x/web-interface/nav/stat`（cookie）→ `following`、`follower`、`dynamic_count`。
   - `getFollowings(pn)`：`GET /x/relation/followings?vmid={mid}&pn=&ps=20&order=desc`（cookie）→ `list[]{mid, uname, face, sign}`、`total`。
2. `ProfileTab`：
   - 已登入：上方個人卡（頭像含 `VipAvatarBadge`、暱稱、UID、Lv 與經驗條、硬幣、B 幣、大會員狀態／到期日 `yyyy-MM-dd`）；下方一列可聚焦按鈕：「關注 N」「粉絲 N」（只顯示數字，不可進入）、「動態 N」（只顯示）、「關注列表」、「我的投稿」、「退出登入」（確認框沿用 settings_view.dart :147-174 的樣式與文字）。
   - 「關注列表」開新頁 `lib/screens/home/profile/followings_screen.dart`：4 欄卡片（頭像、名稱、簽名一行），焦點接近底部載入下一頁；確認鍵開 `UpSpaceScreen(mid, name, face)`；返回鍵回個人頁。
   - 「我的投稿」開 `UpSpaceScreen(mid: AuthService.mid, name: uname, face: face, isSelf: true)`。
   - 未登入：顯示「尚未登入」與「登入」按鈕，按下後在本頁內顯示 `LoginView`（沿用 `login_tab.dart` 的切換方式：`focusDefault`、`onLoginSuccess` 後關閉登入畫面並呼叫 `widget.onLoginSuccess`）；`handleBack` 關閉登入畫面。
   - `isVisible` 由 false 變 true 且已登入時載入資料；`refresh()` 重新載入。
   - 讀取失敗顯示錯誤文字與「重試」按鈕；AuthService 的 face／uname 可先顯示，API 回來再補。
3. `UpSpaceScreen` 加 `bool isSelf = false`：為 true 時隱藏「關注」按鈕且不呼叫 `checkFollowStatus`。

## T-3 設定頁（`settings_view.dart`、設定 row 元件、新檔）

1. 移除 `settings_view.dart` 標頭（頭像、名稱、UID、登入／退出按鈕與 `_logoutFocusNode` 相關焦點邏輯，AC-9）。分類列按上鍵改為移到搜尋框。
2. 搜尋框：分類列上方一個可聚焦的搜尋列（放大鏡圖示＋提示「搜尋設定」）。按確認鍵後聚焦隱藏的 `TextField` 開系統鍵盤（參考 `search_keyboard_view.dart` :367-380 與 `SearchImeBackGuard` 的返回鍵處理），輸入時即時更新結果。輸入框有文字時，內容區改為顯示搜尋結果清單（取代分類內容）；清空或按返回鍵恢復分類內容。
3. 設定索引 `lib/screens/home/settings/settings_index.dart`：靜態清單 `SettingsEntry{label, subtitle, category}`，涵蓋所有分類的標準 row（Toggle／Dropdown／Action 的 label 與 subtitle，逐一對照各 tabs 檔案）；外掛中心與介面設定的自訂區塊也各加一筆（label 用區塊標題，例如各外掛名稱、「首頁分區」「直播分區」等）。搜尋時 query 與 label＋subtitle 都先 `ZhConvert` 轉成繁體再比對（不分大小寫，AC-12）。
4. 搜尋結果：每筆一列（名稱、說明、分類名稱），上下鍵移動，確認鍵 → 清空搜尋、切到該分類、設定 `SettingsFocusTarget`（InheritedWidget 或 ValueNotifier，值為 label），對應 row 在 build 後 `requestFocus` 並 `Scrollable.ensureVisible`，然後清除 target（AC-11）。自訂區塊找不到 row 時聚焦該分類第一個項目。
5. Row 元件（`setting_toggle_row.dart`、`setting_dropdown_row.dart`、`setting_action_row.dart`）支援 focus target：label 符合時請求焦點。`SettingDropdownRow` 目前沒有 focusNode，需改為內部持有 FocusNode（StatefulWidget）。不得改變現有焦點行為。
6. 「關於軟體」分類的紅點保留。

## 驗證方式

| AC | 方式 |
|---|---|
| AC-1、AC-2 | 模擬器操作（使用者測試） |
| AC-3、AC-4 | 模擬器（需登入；空狀態可驗證） |
| AC-5～AC-8 | 模擬器（需登入帳號，使用者測試） |
| AC-9～AC-12 | 模擬器：搜尋「彈幕」「弹幕」「更新」 |
| 全部 | `flutter analyze` 無問題、`flutter test` 通過、debug APK 建置成功 |

## 邊界與風險

- home_screen 寫死 index 很多，漏改會讓焦點跳錯頁：T-1 需逐一對照探索報告清單。
- 三個任務平行：T-1 引用 T-2、T-3 的類別；若 T-2 尚未完成，T-1 先依介面約定寫，最後一起 analyze。
- 回退：還原 `home_screen.dart` 即可回到舊側邊欄（新頁面檔案不影響）。

## 審查紀錄

Sonnet 規格審查 12 條全部採用（以下優先於上文）：

1. **UpSpaceScreen isSelf**（T-2）：不建立關注按鈕；tab 列 `onUp` 設 null；初始焦點改給 tab 列（`_focusTabBar` 或第一個 tab），確認 :125 等依賴 `_followNode` 的地方都處理。
2. **IME 返回鍵**（T-1＋T-3，介面約定）：home_screen 返回鍵的 IME 保護條件改為 `(_selectedTabIndex == 0 || _selectedTabIndex == 7) && SearchImeBackGuard.shouldSwallowBack()`；T-3 設定頁的 TextField 開鍵盤時設 `SearchImeBackGuard.imeOpen = true`、關閉時 `markClosed()`（照 search_keyboard_view.dart 的用法）。
3. **繁簡比對**（T-3）：query 與索引文字都用同一個 `ZhConvert.convert` 正規化後比對（不要強制轉繁體）；另外再各轉一次 `toLowerCase()`。
4. **assets**（T-1）：必須在 `pubspec.yaml` 的 assets 清單加 `assets/icons/follow.svg`、`assets/icons/settings.svg`。
5. **側邊欄高度**（T-1）：8 項可能超出 540 邏輯高度；縮小每項 margin（例如 12→6）並把側邊欄 Column 包 `SingleChildScrollView`（或確保不 overflow）。
6. **登出**（T-2）：登出後焦點移到「登入」按鈕；`refresh()` 與 build 都處理未登入狀態並清空 info／stat。
7. **API**（T-2）：擴充 `lib/services/api/auth_api.dart`（或在 user_api 中重用其 nav 呼叫，不要兩處各自解析 face／uname）；關注列表回傳空頁、筆數少於 ps、或已載入數 ≥ total 時停止載入；一律 `BaseApi.getHeaders(withCookie: true)`。
8. **關注直播分頁**（T-1）：回傳數量 < pageSize 或為空時停止載入；以 roomid 去重。
9. **isVisible 重複請求**（T-1、T-2）：FollowLiveTab、ProfileTab 只在尚未載入過時因 isVisible 載入；其他重新整理由 `refresh()`（側邊欄按確認鍵）觸發。
10. **LiveTab 死碼**（T-1）：一併刪除 `_LiveCategoryType.following`、`showLoginText`、`isFollowingTab` 等只供關注分類使用的程式。
11. **row focus target**（T-3）：用 `ValueNotifier<String?>`（例如 `SettingsFocusTarget.notifier`），row 內自行監聽並 `requestFocus`；外部傳入 focusNode 時用外部的，否則用內部的；搜尋框按左鍵回 `sidebarFocusNode`、按下鍵到分類列。
12. **編譯相容**：T-3 把 `SettingsView` 的 `onLogin`、`onLogout` 改為 optional；T-1 不再傳它們。`login_tab.dart` 由 T-1 刪除（T-2 的 ProfileTab 直接使用 `LoginView`，不依賴 LoginTab）。
