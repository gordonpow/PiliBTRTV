# 稍後再看／我的收藏：移除影片（精簡版）

使用者請求（2026-11-10）：測試時加進借用帳號的稍後再看無法在 App 內移除，要加上稍後再看與收藏的移除功能。

## 驗收條件

- AC-1 「觀看紀錄 → 稍後再看」分頁長按影片卡片，「影片選項」多一顆「從稍後再看移除」。按下後呼叫 B 站 API 移除，成功提示「已從稍後再看移除」並從畫面清單拿掉；失敗提示錯誤訊息，清單不變。
- AC-2 「我的收藏」分頁（某個收藏夾）長按影片卡片，「影片選項」多一顆「從此收藏夾移除」。成功提示「已從收藏夾移除」，從清單拿掉，收藏夾標籤的數量減 1；失敗提示錯誤，清單不變。
- AC-3 移除後焦點落在原位置的下一張卡片（原本是最後一張則落在新的最後一張）；清單變空時焦點回到上方分頁列（稍後再看）或收藏夾列（我的收藏）。
- AC-4 其他頁面（首頁、搜尋等）長按的「影片選項」不出現移除按鈕，行為不變。

不做：多選批次移除、移除前確認對話框（單筆可再加回）、稍後再看「清除已看完」。

## 設計

1. `lib/services/api/interaction_api.dart`：新增 `static Future<String?> removeWatchLater(int aid)`，POST `${BaseApi.apiBase}/x/v2/history/toview/del`，body `aid=$aid&csrf=$csrf`，寫法比照 `addWatchLater`（null = 成功）。收藏移除沿用 `dealFavorite(aid:, delIds: [folderId])`。
2. `lib/widgets/video_action_dialogs.dart`：`showVideoActionMenu(context, video, {String? removeLabel, Future<String?> Function()? onRemove})` 改回傳 `Future<bool>`（true = 已移除）。`removeLabel`／`onRemove` 都有值時，在「稍後再看」與「取消」之間加一顆按鈕（`Icons.delete_outline`）。按下後執行 `onRemove`，依結果用既有的提示方式（與 `watchLaterFlow` 相同）顯示成功文字（由呼叫端以參數 `removedMessage` 傳入）或錯誤訊息。既有呼叫端不受影響（忽略回傳值）。
3. `lib/screens/home/history/video_grid.dart`：`HistoryVideoGrid` 新增 `Future<void> Function(Video video, int index)? onLongPressVideo`，有值時傳給 `TvVideoCard.onLongPress`；新增 `void focusIndex(int i)`。
4. `lib/screens/home/history/watch_later_view.dart`、`fav_view.dart`：傳入 `onLongPressVideo`，呼叫 `showVideoActionMenu` 帶移除參數；回傳 true 時 `setState` 移除該影片，下一個 frame 依 AC-3 移焦點。`FavView` 同步把目前收藏夾 `mediaCount` 減 1（`FavFolder` 欄位若為 final，用新物件取代）。

## 陷阱

- `base_tv_card.dart` 長按結束後會把焦點還給長按前的 `primaryFocus`（AC-9 of fav-multiselect）。移除後該卡片可能已不存在或節點換成別的影片，要確認還原焦點與 AC-3 的移焦點不會互相覆蓋（AC-3 必須在還原之後生效）。
- `HistoryVideoGrid` 的 `FocusNode` 以 index 為 key，移除後 index 對應的影片會改變。

## 驗證

`flutter analyze` 無問題、`flutter test` 全過；TV 模擬器：用借用帳號在稍後再看移除「來東京，拍到了些怪東西」（這筆是之前測試加入的，本來就要移除），確認 AC-1、AC-3；AC-2 用一部自己先加入某收藏夾的影片測試後移除，收藏夾數量要回到原值。
