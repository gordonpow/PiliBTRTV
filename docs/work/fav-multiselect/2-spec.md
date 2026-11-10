# 規格：影片收藏選單、觀看紀錄多選

對應需求：1-requirements.md（AC-1～AC-9）。

## 設計

1. 長按偵測集中在 `BaseTvCard`：新增 `Future<void> Function()? onLongPress`。
   - 遙控器：`TvFocusScope` 新增 `preKeyHandler`（先於一般處理）。確認鍵（select／enter／numpadEnter／gameButtonA）
     KeyDown 啟動 500ms Timer 並吞掉事件，KeyRepeat 吞掉；Timer 到點觸發長按；KeyUp 若尚未觸發長按則視為短按（呼叫原 `_handleSelect`）。
   - 未提供 `onLongPress` 時完全走原本邏輯，短按行為不變。
   - 觸控：`GestureDetector.onLongPress`。
   - 長按完成（對話框關閉）後，把焦點還給長按前的 `primaryFocus`（AC-9）。
2. `TvVideoCard` 預設 `onLongPress` = 開「影片選項」（番劇／直播／無 bvid 不啟用）。所有使用處自動生效（AC-1）。
3. `HistoryVideoCard` 新增 `onLongPress`、`selectionMode`、`selected`（勾選框覆蓋層）。
4. 新檔 `lib/widgets/video_action_dialogs.dart`：
   - `showVideoActionMenu`（收藏／稍後再看／取消）。
   - `showFavFolderPicker`（勾選清單＋確定／取消）。
   - 流程函式 `favoriteVideoFlow`、`watchLaterFlow`、`batchFavoriteFlow`、`batchWatchLaterFlow`。
   - 對話框元件用 `Focus` + 方向鍵預設遍歷；確認鍵只處理 KeyDownEvent（避免長按殘留事件誤觸）。
5. 播放器設定面板新增第 5 項「收藏」（index 4）；`activateSetting` case 4 呼叫 `favoriteVideoFlow`（用 `aid`）。既有收藏按鈕不動。
6. 歷史頁（`history_tab.dart`）多選：`_selecting`、`_selected`（以 kid 或 bvid 為 key 的 Set<int> index→改用 Video 物件 identity 不可靠，採 `historyKid` / bvid 組成的 key）。
   - 上方（分頁列下方）顯示「已選 N 部」＋按鈕列：全選、刪除、加入收藏、稍後再看、取消；按鈕列用 `Focus` 左右移動，下鍵回卡片、卡片第一列上鍵進按鈕列。
   - 多選中短按 = 切換勾選；返回鍵（`HistoryTabState.handleBack`，由 `home_screen` 的 PopScope 呼叫）= 取消多選。
   - 刪除：確認對話框 → `InteractionApi.deleteHistory(kids)` → 從列表移除，焦點移到合理位置。

## API（`lib/services/api/interaction_api.dart`）

- `getFavFoldersForVideo(aid)`：`GET /x/v3/fav/folder/created/list-all?up_mid=<mid>&type=2&rid=<aid>`，回 `List<FavFolderState>?`（失敗 null）；`parseFavFolderStates(json)` 純函式。
- `dealFavorite(aid, addIds, delIds)`：`POST /x/v3/fav/resource/deal`，多 id 以逗號分隔，回 `String?` 錯誤訊息（null＝成功）。
- `addWatchLater(aid)`：`POST /x/v2/history/toview/add`（aid、csrf），回 `String?`。
- `deleteHistory(kids)`：`POST /x/v2/history/delete`，`kid=a,b`，每批 50 筆，回失敗筆數。
- 不記錄 Cookie／csrf。

## 純函式（`lib/utils/fav_utils.dart`，有單元測試）

- `bvidToAid(bvid)`：BV → av（Video 無 aid 欄位時使用）。
- `buildHistoryKid(business, oid, kid)`：archive→`archive_<oid>`、pgc→`pgc_<kid>`、其他 `<business>_<oid>`；缺值回空字串。
- `diffFavFolders(original, selected)` → `(add, del)`。
- `joinIds(ids)`。

## Model

`Video` 新增 `aid`（歷史 archive 取 `history.oid`）、`historyKid`。`resolvedAid` getter：aid>0 用 aid，否則由 bvid 換算。

## 任務與檔案

| 檔案 | 變更 |
|---|---|
| lib/utils/fav_utils.dart | 新增 |
| lib/services/api/interaction_api.dart、bilibili_api.dart | 新 API |
| lib/models/video.dart | aid、historyKid |
| lib/core/focus/focus_navigation.dart | `preKeyHandler` |
| lib/widgets/base_tv_card.dart | 長按 |
| lib/widgets/tv_video_card.dart、history_video_card.dart | 長按／勾選 |
| lib/widgets/video_action_dialogs.dart | 新增 |
| lib/screens/home/history_tab.dart、home_screen.dart | 多選、返回 |
| lib/screens/player/widgets/settings_panel.dart、mixins/player_action_mixin.dart、player_event_mixin.dart | 設定面板收藏項 |
| test/fav_utils_test.dart | 新增 |

## 邊界情況

- 未登入：提示「請先登入」。csrf 空：提示錯誤。
- 收藏夾清單載入失敗：提示「讀取收藏夾失敗」。無任何變更按確定：直接關閉不呼叫 API。
- 番劇歷史多選：刪除可用（`pgc_<season_id>`）；收藏／稍後再看略過，計入失敗筆數。
- 刪除後列表為空：離開多選。長按後殘留 KeyUp／KeyRepeat 不觸發任何動作。
- 多選模式下重新整理／切分頁：離開多選並清空。
- 稍後再看已存在：單筆先查清單，已存在提示「已在稍後再看」。
