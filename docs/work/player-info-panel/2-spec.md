# 規格：播放時查看影片簡介與留言（#39）

## 設計

### API：`lib/services/api/reply_api.dart`（新增）
- `ReplyApi.getReplies({required int aid, String offset = ''})` → `ReplyPage?`。
- GET `${BaseApi.apiBase}/x/v2/reply/wbi/main`，參數 `oid=aid`、`type=1`、`mode=3`（熱門）、`pagination_str={"offset":"<offset>"}`、`plat=1`、`web_location=1315875`，以 WBI 簽章（照 `video_api.dart:34-75`：`BaseApi.ensureWbiKeys()`、`SignUtils.signWithWbi`、`BaseApi.getHeaders(withCookie: true)`）。逾時 10 秒。
- 解析 `data.replies[]`；第一頁再把 `data.top_replies[]`（或 `data.upper.top`）放最前，標記置頂，去除重複 rpid。
- `data.cursor.pagination_reply.next_offset` 為下一頁 offset；`data.cursor.is_end` 為 true 或 offset 空字串時代表沒有下一頁。
- `code != 0` 或例外：回傳 null（呼叫端顯示錯誤）。
- 模型 `lib/models/reply_item.dart`：`rpid`、`uname`、`ctime`（秒）、`like`、`message`（`content.message`）、`replyCount`（`rcount`）、`isTop`。純函式 `parseReplyPage(Map json, {bool firstPage})` 供測試。
- 在 `BilibiliApi` 加轉發 `getReplies`。

### 狀態與按鍵
- `CtrlBtn` 加 `info = 8`（設定之後），讚／幣／藏改為 9／10／11，`count = 12`。
- `player_state_mixin.dart`：`showInfoPanel`。
- `player_event_mixin.dart`：
  - `_activateControlButton` 加 `CtrlBtn.info`：`setState(showInfoPanel = true)`、取消 hideTimer。
  - `handleGlobalKeyEvent`：`showInfoPanel` 時，返回鍵關閉面板（設 `backKeyJustHandled`），其他鍵回 `ignored`（面板自管焦點，參考 `related_strip.dart`）。
  - `onPopInvoked` 與 `_canHoldDanmaku` 一併考慮 `showInfoPanel`。
- 關閉面板：`showInfoPanel = false`，焦點還給 `playerFocusNode`，控制列顯示且 `focusedButtonIndex = CtrlBtn.info`（參考 `player_action_mixin.dart:2386-2397`）。
- 換集／換影片時（設定 aid 的位置）關閉面板。

### UI：`lib/screens/player/widgets/info_panel.dart`（新增）
- 右側 `Positioned(right:0, top:0, bottom:0, width: 520)`，半透明深色背景，樣式參考 `episode_panel.dart`。
- 參數：`Map? videoInfo`（`fullVideoInfo`）、`int aid`、`VoidCallback onClose`。
- 自管 FocusNode（開啟時 autofocus）；`onKeyEvent`：
  - 左右鍵：切換分頁（簡介 0／留言 1）。第一次切到留言才載入。
  - 上下鍵（含 KeyRepeat）：簡介分頁每次捲動 120px；留言分頁移動選取的留言並 `Scrollable.ensureVisible`；選到倒數 3 則內且還有下一頁、沒在載入時載入下一頁。
  - 確認鍵：留言錯誤狀態時重試。
  - 返回／Esc：`onClose`。
- 簡介內容：標題、UP 主、發布日期（yyyy-MM-dd HH:mm）、數字用 `formatCount`；`desc` 空或番劇時「沒有簡介」。B 站內容用 `ContentText`。
- 留言列表：每則顯示暱稱、相對或絕對時間、讚數、內容（不限行數）、`rcount > 0` 時「共 N 則回覆」；置頂加「置頂」標籤。選取中的留言加框。
- 狀態提示：「載入中…」、「留言載入失敗，按確認鍵重試」、「目前沒有留言」、「沒有更多留言」。

### 控制列：`controls_overlay.dart`
- 設定按鈕後加 `_buildControlButton`（icon `Icons.article_outlined`，標籤「簡介」），索引 `CtrlBtn.info`。

## 任務
- T-1：reply_api.dart、reply_item.dart、BilibiliApi 轉發、`test/reply_api_test.dart`（解析、置頂去重、is_end）。
- T-2：CtrlBtn、狀態、按鍵、控制列按鈕、info_panel.dart、player_screen.dart 掛載（相依 T-1）。
- T-3：i18n/en.json 新字串；`python tool/i18n/extract_i18n.py` untranslated=0。

## 驗證
- AC-1、2、3、4、5、6、8：模擬器（使用者要求時）或使用者實測。
- AC-7：程式碼檢查。
- `flutter analyze`、`flutter test`、i18n 檢查。

## 風險
- `reply/wbi/main` 回應格式變動：解析容錯，欄位缺漏時略過該則。
- 控制列索引重排：所有用到 like／coin／fav 的地方都用常數名，影響小。
