# 規格：未登入時的本機收藏（#20）

## 現況（探索結果）
- `lib/widgets/video_action_dialogs.dart`
  - `favoriteVideoFlow(context, aid)`（:385）第一行 `_requireLogin()` 擋未登入；流程：`InteractionApi.getFavFoldersForVideo` → `showFavFolderPicker`（:191，吃 `FavFolderState` 清單，回傳勾選 id 集合）→ `diffFavFolders` → `dealFavorite` → toast「已收藏到 「…」」／「已取消收藏」，回傳 `bool?`。
  - 呼叫端：卡片長按選單 `showVideoActionMenu`（:177）、播放器 `_openFavoritePicker`（player_event_mixin.dart:350）、設定面板 `activateSetting` case 4（player_action_mixin.dart:2878），兩者都用 `videoActions.setFavorited(faved)`。
- `VideoActionsController.load(aid)`（video_actions_controller.dart）以 `checkFavoriteStatus` 判斷星星，未登入恆為 false。
- 收藏分頁：`history_tab.dart` 在 `!loggedIn` 時三個分頁都顯示「請先登入」；已登入的 `_tab == 1` 才顯示 `FavView`（history/fav_view.dart，收藏夾 `TvTabBar` + `HistoryVideoGrid`）。
- 登入成功：`LoginView._completeLogin` → `ProfileTab._handleLoginSuccess`（profile_tab.dart:127）→ `HomeScreen._refreshCurrentTab`。登出：`HomeScreen` 的 `ProfileTab.onLogout` 呼叫 `AuthService.logout()` 後 `_refreshCurrentTab()`。
- 儲存慣例：SharedPreferences（SettingsService）、app documents JSON + tmp→rename（content_translator.dart）。

## 設計
### LocalFavoritesService（lib/services/local_favorites_service.dart）
- 單例 `LocalFavoritesService.instance`（ChangeNotifier），建構子可注入 `directoryProvider` 與 `now`，方便測試。
- 檔案 `local_favorites.json`（app documents）：`{version:1, nextId, folders:[{id,name,createdAt}], entries:[{folderId,bvid,aid,title,pic,ownerName,duration,addedAt}]}`。
- 預設夾 id=1「本機收藏」：不可刪、可重新命名；讀檔後若缺少就補上。
- 損毀檔（JSON 不合法或型別錯誤）：把原檔改名 `.bad` 保留，從空資料開始。
- 寫入：序列化成一條 Future 鏈，寫 `.tmp` 後 `rename`；失敗只 debugPrint。
- 介面：`ensureLoaded()`、`folders`、`createFolder`、`renameFolder`、`deleteFolder`（預設夾回傳 false）、`folderStates(bvid)`（給 picker 用的 `FavFolderState`）、`setVideoFolders(info, selected)`、`removeFromFolder`、`removeVideo(bvid)`、`entriesIn(folderId)`、`distinctEntries()`、`totalVideos`、`isFavoritedAid`、`importDeclined`／`setImportDeclined`（SharedPreferences `local_fav_import_declined`）。
- 以 bvid 為影片鍵；同影片可在多個夾。`aid` 建立時用 `Video.resolvedAid`。

### 匯入（lib/services/local_fav_import.dart，純邏輯可測）
`importLocalFavorites(service, getFolders, addToFolder)`：先 `getFolders(0)` 取得預設夾（`isDefault`）；逐部 distinct 影片：`getFolders(aid)` 若預設夾已 faved → 略過（算成功）；否則 `addToFolder(aid, defaultId)`；成功 → `service.removeVideo(bvid)`；失敗保留。回傳 `(ok, skipped, failed)`。取不到預設夾 → 全部失敗。

### UI
- `favoriteVideoFlow(context, aid, {Video? video})`：未登入走 `_localFavoriteFlow`，使用 `video.bvid`；picker 新增 `onCreate` 參數，顯示「新增收藏夾」按鈕（先彈名稱輸入框，建立後自動勾選）。toast 與帳號版相同格式。
- 新增 `showNameInputDialog`（video_action_dialogs.dart）供新增／重新命名。
- 播放器：`player_state_mixin.dart` 加 `favVideo` getter（用 `fullVideoInfo`／`widget.video` 組 Video），兩個呼叫端傳入。`VideoActionsController.load` 未登入時用 `isFavoritedAid`（先 `ensureLoaded`）。
- 收藏分頁：`history_tab.dart` 的 `_tab == 1` 不論登入都顯示 `FavView`；`FavView` 未登入時回傳新的 `LocalFavView`（history/local_fav_view.dart：資料夾 TvTabBar + 動作列〔新增收藏夾／重新命名／刪除〕+ `HistoryVideoGrid`；長按影片 → 取消收藏選單）。已登入且本機有影片時 `FavView` 多一個虛擬分頁「本機收藏 (N)」，內容為 `LocalFavView(embedded: true)`，動作列多「匯入帳號」。
- `history_tab.dart` 登入保護（`_refreshCurrent`、`_focusContent`、`focusFirstItem`）對 tab 1 放行；`refresh()` 呼叫 `FavView.refreshAuth()` 處理登入／登出切換。
- 登入成功：`ProfileTab._handleLoginSuccess` 呼叫 `maybePromptLocalFavImport(context)`（lib/widgets/local_fav_import.dart）：本機有影片且未選過「否」才跳對話框。是 → 匯入並 toast；否 → `setImportDeclined(true)`。手動匯入成功後清除 declined 旗標。
- 登出：不需動本機資料；`LocalFavView` 由 `AuthService.isLoggedIn` 決定顯示。

## 任務與檔案
1. 新增 local_favorites_service.dart、local_fav_import.dart、local_fav_import（widget）、local_fav_view.dart。
2. 改 video_action_dialogs.dart、fav_view.dart、history_tab.dart、profile_tab.dart、video_actions_controller.dart、player_state_mixin.dart、player_event_mixin.dart、player_action_mixin.dart。
3. 測試 test/local_favorites_service_test.dart、test/local_fav_import_test.dart。
4. i18n/en.json 補字串。

## AC 對應
- AC-1/2：`_localFavoriteFlow` + picker `onCreate`；星星同步用 `setFavorited`。
- AC-3：`LocalFavView`。
- AC-4：entries 欄位 + JSON 檔；播放用 `PlayerScreen(video)`（bvid）。
- AC-5：`maybePromptLocalFavImport`、`importLocalFavorites`、「本機收藏」虛擬分頁。
- AC-6：已登入分支不動。
- AC-7：登出後 `FavView` 回到本機模式，本機檔案未被登入流程修改（匯入成功才移除）。
- AC-8：analyze／test／i18n 工具。

## 邊界情況
- bvid 空（番劇／直播）→ toast「無法取得影片資訊」。
- 刪除含影片的資料夾：連同其 entries 移除（確認對話框）。
- 資料夾名稱空白／重複：空白拒絕；允許重複。
- 匯入期間登出或網路失敗：失敗保留。
- 讀檔前呼叫一律 `await ensureLoaded()`。

## 實作偏差
- 「不再自動詢問」旗標直接用 SharedPreferences（`local_fav_import_declined`，寫在 LocalFavoritesService），未動 `settings_service.dart`（#17 另一代理修改中）。
- 匯入對話框按鈕是「是／否」；返回鍵關閉視為未決定，不寫入旗標。`showConfirmDialog` 回傳 `bool?`。
- 匯入檔案拆成 `lib/services/local_fav_import.dart`（純邏輯）與 `lib/widgets/local_fav_import.dart`（對話框、toast），未另建第三個 widget 檔。
- 已登入時的「本機收藏」是收藏夾列最後一個虛擬分頁，內嵌的 LocalFavView 有自己的收藏夾列；手動匯入按鈕在其管理按鈕列。
- 資料夾管理用影片格上方的按鈕列（新增收藏夾／重新命名／刪除），不是長按。
- 長按本機收藏影片使用既有 `showVideoActionMenu`（收藏、稍後再看、從此收藏夾移除、取消）；未登入時「稍後再看」會 toast「請先登入」。
- `history_tab.dart` 的 `FavView` 於 tab 1 一律建立，登入判斷在 `FavView` 內。
- 順手修正 `profile_tab.dart` 一處原有的 `curly_braces` 寫法（dart format 後觸發 lint）。
