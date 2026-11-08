# 規格：UP主全螢幕格狀頁面

需求：[1-requirements.md](1-requirements.md)

## 設計

### 資料流

```
播放器控制列「UP主」（player_event_mixin.dart:250 _activateControlButton case 1）
  ├─ 記錄 wasPlaying = videoController.value.isPlaying，暫停
  ├─ final picked = await Navigator.push<Video>(UpSpaceScreen(mid, name, face))
  ├─ picked != null → pushReplacement(PlayerScreen(video: picked))   （同舊 onVideoSelect）
  └─ picked == null → 若 wasPlaying 則 play()；showControls = true；startHideTimer()
```

- 移除 `showUpPanel` 的覆蓋面板用法：`player_screen.dart:275-295` 的 `UpPanel(...)`、`player_event_mixin.dart` 中 `showUpPanel` 的返回鍵處理（:48-55、:161-172）。`showUpPanel` 欄位可移除（`player_state_mixin.dart:102`），所有參照一併清掉。
- `lib/screens/player/widgets/up_panel.dart` 刪除（不再使用）。

### UP主資訊 API

`lib/services/api/video_api.dart` 新增 `getUpCard(int mid)`，`bilibili_api.dart` 加包裝：

- `GET ${BaseApi.apiBase}/x/web-interface/card?mid=<mid>&photo=false`，`BaseApi.getHeaders(withCookie: true)`。
- 回傳 `{'name', 'face', 'sign', 'fans'(int), 'archiveCount'(int)}`；`code != 0` 或例外回傳 null。
- 已用 curl 確認：`mid=2` 回 `code 0`，`data.card.name/sign/face/fans`、`data.archive_count`、`data.follower`（`fans` 以 `data.follower` 優先，退回 `card.fans`）。

### 新頁面 `lib/screens/up_space/up_space_screen.dart`

`UpSpaceScreen({required int mid, required String name, required String face})`，`StatefulWidget`，`Scaffold` 背景與首頁一致（參考 `search_results_view.dart`）。

- 版面：`CustomScrollView`
  - 資訊區（`SliverToBoxAdapter`）：頭像（radius 36）、名稱（粗體）、簽名（灰、最多 2 行）、「粉絲 X・投稿 Y」（數字格式同 `Video.viewFormatted`：萬／億）；右側排序按鈕（最新／最熱）、關注按鈕（樣式沿用 up_panel.dart:211-293）。
  - 影片格（`SliverGrid`，`crossAxisCount: 4`，間距與 `childAspectRatio` 沿用 `search_results_view.dart:203-210`），卡片用 `TvVideoCard`。
  - 載入中：中央 `CircularProgressIndicator`；空列表：「暫無影片」；載入更多時底部顯示小轉圈。
- 資料：
  - `initState` 同時呼叫 `getUpCard(mid)`、`getSpaceVideos(mid, page: 1, order)`、`checkFollowStatus(mid)`。
  - 資訊 API 失敗：用建構子傳入的 `name`、`face`，不顯示簽名與數字（AC-8）。
  - 分頁：`_page`、`_hasMore`（回傳筆數 < 30 時為 false）、`_isLoadingMore`；焦點移到最後兩列（index ≥ length - 8）時呼叫 `_loadMore()`。也可依 `ScrollController` 接近底部觸發（同 search_results_view.dart:77-80）。
  - 切換排序：重設為第 1 頁，清空列表，焦點回到第一張卡片。
- 焦點（沿用 search_results_view.dart:214-245 的寫法）：
  - 每張卡片 `FocusNode`（`Map<int, FocusNode>`，dispose 時全部釋放）。
  - 左右：同列移動，最左欄按左鍵不動；上下：±4；第一列按上鍵 → 排序按鈕；排序按鈕左右在排序、關注間切換，按下鍵 → 第一張卡片。
  - 第一張卡片 `autofocus`；沒有影片時焦點在排序按鈕。
  - 卡片 `onFocus` 時確保可見（`Scrollable.ensureVisible` 或沿用 search_results_view 的做法）。
- 選影片：`Navigator.pop(context, video)`。返回鍵：`Navigator.pop(context)`（`PopScope` 或預設行為即可）。

### 卡片彈幕數

`TvVideoCard` 新增 `bool showDanmaku = false`。為 true 且 `video.danmaku > 0` 時，在播放數旁顯示彈幕圖示（`Icons.subtitles_outlined`）與 `video.danmakuFormatted`。其他頁面不傳，外觀不變。

`Video.fromSpaceVideo` 已有 `danmaku: video_review`、`duration: length`、`pubdate: created`、`ownerName: author`（`video.dart:186-198`），不用改。

## 要改的檔案

| 檔案 | 改什麼 |
|---|---|
| `lib/services/api/video_api.dart`、`lib/services/bilibili_api.dart` | `getUpCard` |
| `lib/screens/up_space/up_space_screen.dart`（新增） | 全螢幕頁面 |
| `lib/widgets/tv_video_card.dart` | `showDanmaku` |
| `lib/screens/player/mixins/player_event_mixin.dart` | 開啟頁面、暫停／恢復；移除 `showUpPanel` 返回鍵處理 |
| `lib/screens/player/player_screen.dart` | 移除 `UpPanel` |
| `lib/screens/player/mixins/player_state_mixin.dart` | 移除 `showUpPanel` |
| `lib/screens/player/widgets/up_panel.dart` | 刪除 |

## 任務

| ID | 內容 | 相依 |
|---|---|---|
| T-1 | `getUpCard` API | — |
| T-2 | `TvVideoCard.showDanmaku` | — |
| T-3 | `UpSpaceScreen` | T-1、T-2 |
| T-4 | 播放器改為 push 頁面、暫停／恢復，移除舊面板 | T-3 |

由一個 Sonnet 子代理依序完成（檔案互相關聯）。

## 驗證方式

| AC | 方式 |
|---|---|
| AC-1～AC-8 | 程式碼審查；實機由使用者測試 |
| AC-9 | `flutter analyze`、`flutter build apk` |

## 邊界情況與風險

- `ownerMid == 0`（例如番劇沒有 UP主）：控制列「UP主」按下時不開頁面，顯示提示「此影片沒有 UP主資訊」。
- 頁面開啟期間播放器的 hide timer、進度上報 timer：暫停狀態下照舊運作即可；返回時 `startHideTimer()`。
- 快速連按「UP主」：開頁面前檢查是否已開啟（用一個 bool 防重入）。
- 未登入：`checkFollowStatus` 失敗回 false，關注按鈕按下時 `followUser` 失敗顯示「操作失敗」（同舊行為）。
- 回退：revert 本次 commit 即恢復舊面板。

## 審查後修正（以本節為準，與上文衝突時優先）

1. **失敗與空列表區分**：`getSpaceVideos` 只有舊面板使用，改為回傳 `({List<Video> videos, int total})?`，失敗（例外、`code != 0`、HTTP 非 200）回 null；`total` 取 `data.page.count`。頁面：第一頁 null → 顯示「載入失敗，按確定重試」（可聚焦的重試按鈕）；`_loadMore` 失敗不改 `_hasMore`。`_hasMore = _videos.length < total`（total 為 0 時退回「本頁筆數 ≥ 30」）。
2. **並行請求**：`_requestId` 遞增；排序切換與每次載入都帶 id，回傳時 id 不符就丟棄。
3. **頁面開啟期間禁止播放器自行導航**：播放器 state 加 `bool upSpaceOpen`。開頁前設 true，返回後設 false。`upSpaceOpen` 為 true 時：`onVideoComplete` 的自動連播／推薦跳轉、`_redirectToPgc` 等 `pushReplacement` 直接略過。也作為快速連按防重入。
4. **開啟與返回**：`videoController == null` 或 `isLoading` 時照樣可開，`wasPlaying = false`。返回後先檢查 `mounted`，再依 `wasPlaying` 呼叫 `play()`（controller 非 null 且已初始化）。頁面開啟時 App 進背景：只上報進度，可接受。
5. **焦點恢復**：播放器根 `Focus`（`player_screen.dart:87-89`）改用明確的 `FocusNode playerFocusNode`（state 欄位，dispose 時釋放）。返回後 `addPostFrameCallback` 內 `playerFocusNode.requestFocus()`，並設 `backKeyJustHandled = false`。
6. **排序後焦點留在排序按鈕**；清空列表時釋放並重建卡片 `FocusNode`。
7. **捲動**：排序／關注按鈕取得焦點時 `Scrollable.ensureVisible(alignment: 0)`；卡片 `ensureVisible(alignment: 0.3)`。
8. **最左欄按左**：傳空函式 `() {}`，不傳 null。最右欄（index % 4 == 3）按右同樣傳 `() {}`；最後一列按下傳 `() {}`。
9. 刪除 `player_screen.dart` 對 `up_panel.dart` 的 import。名稱與簽名用 `zh_material` 的 `Text`（自動 ZhConvert）。粉絲／投稿數抽成共用函式 `formatCount(int)`（放 `lib/utils/`），`Video.viewFormatted` 可改用它。
10. **分頁只用 `ScrollController`**：`maxScrollExtent - 300` 以內觸發 `_loadMore`，由 `_isLoadingMore` 把關。
11. `ownerMid == 0` 時不開頁面，顯示提示。

驗證表補實機清單（使用者執行）：播放中進入再返回（繼續播放）、暫停中進入再返回（維持暫停）、返回後遙控器仍可操作控制列、排序連續切換、捲到底自動載入、網路失敗重試。

## 審查紀錄

規格審查（Sonnet，2026-11-09）10 條：第 1～9 條採用（見上節）；第 10 條採用（只用 ScrollController）。第 9 條「未登入關注提示請先登入」不採用，維持舊行為。

## 實作偏差

- 卡片彈幕數：番劇卡片（`isPgc`）不顯示彈幕數（番劇卡片本來不顯示播放數）。
- 排序按鈕載入中（`_isLoading`）按確定不動作，避免連按。
- 初次載入完成後，只有焦點仍在排序按鈕時才移到第一張卡片（避免搶走使用者已移動的焦點）。
- 載入失敗的重試按鈕為第三個可聚焦按鈕；失敗時焦點自動移到重試按鈕。
- 實作過程中 `dart format` 誤格式化了 7 個無關檔案（cdn_status_view、seek_thumbnail_strip、live_api、pgc_api、btr_config、btr_proxy、app_restart），僅空白／換行差異；cdn_status_view 已手動還原，其餘 6 個需 commit 前由主代理還原（子代理被權限拒絕使用 git 還原）。

---

# 第二階段規格：主頁／動態／投稿分頁

需求：`1-requirements.md` 第二階段（AC-10～AC-16）。

## API（新增 `lib/services/api/space_api.dart`，`bilibili_api.dart` 加包裝）

App API 共用：`https://app.bilibili.com` + `AppSign.appSign`（`lib/services/api/app_sign.dart`）；固定參數 `build=8430300`、`mobi_app=android`、`platform=android`；已登入時加 `access_key=AuthService.accessToken`（簽名前加入）；UA `Mozilla/5.0 BiliDroid/8.43.0 (bbcallen@gmail.com)`。`code != 0`、HTTP 非 200、例外 → 回 null（並 debugPrint code/message）。

| 函式 | 端點與參數 | 回傳 |
|---|---|---|
| `getSpace(int mid)` | `/x/v2/space`，`vmid` | `SpaceData?`（見下） |
| `getCollectionVideos(SpaceCollection c, {int pn = 1})` | 合集：`/x/v2/space/season/videos`，`season_id`、`ps=20`、`pn`；系列：`/x/v2/space/series`，`series_id`、`vmid`、`ps=20`、`pn` | `({List<Video> videos, bool hasMore})?`。合集：本頁筆數 == 20 時 hasMore；系列：用 `data.next`／`data.total` 判斷 |
| `getSpaceDynamics(int mid, {String offset = ''})` | Web：`/x/polymer/web-dynamic/v1/feed/space`，WBI 簽名；`host_mid`、`offset`、`timezone_offset=-480`、`platform=web`、`web_location=333.1387`、`features=itemOpusStyle`、`dm_img_*`（用 `BaseApi.randomBase64`）；Referer `https://space.bilibili.com/<mid>/dynamic`、Origin `https://space.bilibili.com`；-351／-352 時更新 WBI 金鑰重試一次（同 `getSpaceVideos`） | `({List<Video> videos, String offset, bool hasMore})?`。只取 `modules.module_dynamic.major.type == MAJOR_TYPE_ARCHIVE` 的項目；`DYNAMIC_TYPE_FORWARD` 取 `orig` 內的 archive。解析可參考 `VideoApi.getDynamicFeed`（`video_api.dart:270-353`），抽出共用的 `Video? _archiveFromDynamicItem(Map item)` 兩處共用 |

資料模型（`lib/models/space_data.dart`）：

```dart
class SpaceCollection { final int id; final String title; final String cover; final int count; final bool isSeries; }
class SpaceData {
  final String name, face, sign; final int fans, following, likes;
  final List<String> tabs;          // tab2 的 param，只保留 home/dynamic/contribute，順序同 API
  final String defaultTab;          // home/dynamic/contribute（default_tab 為 video 時轉成 contribute）
  final List<Video> archive; final int archiveCount;
  final List<SpaceCollection> seasons, series;
  final List<Video> coins, likesArchive, bangumi;
}
```

- `Video.fromSpaceApp(Map item)`（`video.dart`）：`bvid`、`title`、`pic=cover`（`_fixPicUrl`）、`ownerName=author`、`view=play`、`danmaku`、`duration`、`pubdate=ctime`。`bvid` 為空的項目略過。
- 追番 `season.item`：`Video(bvid:'', title, pic: cover, seasonId: int.parse(param), epIndexText: newest_ep_index 的顯示文字)`。
- `ugc_season.item` → `SpaceCollection(id: season_id, title, cover, count, isSeries: false)`；`series.item` → `SpaceCollection(id: series_id, title: name, cover: '', count: 0, isSeries: true)`（API 沒有封面，卡片用預設圖示）。
- 名稱、簽名、粉絲：`card.name/face/sign/fans`、`card.attention`、`card.likes.like_num`。

## 頁面結構（`lib/screens/up_space/`）

- `up_space_screen.dart`：資訊區（沿用；資料改由 `getSpace`，失敗時退回 `getUpCard`，再失敗退回建構子的名稱與頭像）＋分頁列＋目前分頁內容。排序按鈕移到投稿分頁內。
- `tabs/up_home_tab.dart`：`ListView` 的區塊；每區塊標題＋橫向 `ListView` 卡片（`TvVideoCard`，寬度固定約 260）。合集／系列卡片用新的 `SpaceCollectionCard`（封面、標題、「N 個影片」）。區塊最後一張「更多」卡片（AC-11）。
- `tabs/up_dynamic_tab.dart`：4 欄格狀（沿用第一階段的格狀、捲動載入、失敗重試、`_requestId` 寫法）。
- `tabs/up_contribute_tab.dart`：子分頁列「影片｜合集／系列」。影片沿用第一階段的格狀與 `getSpaceVideos`（Web，最新／最熱）。合集／系列：先顯示合集卡片格狀；選取後顯示該合集影片格狀（`getCollectionVideos`），上方顯示合集名稱。
- 第一階段的格狀、焦點、捲動、重試邏輯抽成共用元件 `widgets/space_video_grid.dart`（參數：載入函式、`onSelect`、`onMoveUpFromTop`），三處共用。

## 焦點（AC-16）

- 分頁列 `FocusNode` 每個分頁一個；左右切換並立即切換內容；下鍵 → 目前分頁內容的第一個可聚焦元素；上鍵 → 關注按鈕。
- 內容最上方（格狀第一列、主頁第一個區塊、投稿子分頁列）按上鍵 → 目前分頁的分頁列按鈕。
- 主頁區塊：左右在區塊內移動，上下在區塊之間移動（移到該區塊第一張）。
- 返回鍵：投稿分頁開著合集影片時 → 回到合集列表；否則 `Navigator.pop`。
- 切換分頁時保留各分頁已載入的資料（`IndexedStack` 或快取 state），不重新載入。

## 分頁決定（AC-10）

`SpaceData.tabs` 非空時用它；`getSpace` 失敗時用 `['home','dynamic','contribute']` 但主頁內容只能顯示「載入失敗，按確定重試」（主頁區塊依賴 `getSpace`）；初始分頁 `defaultTab`，失敗時 `contribute`。

## 要改的檔案

| 檔案 | 改什麼 |
|---|---|
| `lib/services/api/space_api.dart`（新增）、`lib/services/bilibili_api.dart` | 三個 API |
| `lib/models/space_data.dart`（新增）、`lib/models/video.dart` | 模型、`fromSpaceApp` |
| `lib/services/api/video_api.dart` | 抽出 `_archiveFromDynamicItem` 供兩處共用（改為 public static 放 space_api 或 video_api） |
| `lib/screens/up_space/up_space_screen.dart` | 分頁列與分頁切換 |
| `lib/screens/up_space/tabs/*.dart`、`lib/screens/up_space/widgets/*.dart`（新增） | 三個分頁、共用格狀、合集卡片 |
| `test/space_parse_test.dart`（新增） | `SpaceData` 解析（用最小 JSON）、`_archiveFromDynamicItem`（一般與轉發）、`Video.fromSpaceApp` |

## 任務

| ID | 內容 |
|---|---|
| T-5 | API、模型與單元測試 |
| T-6 | 共用格狀元件（由第一階段程式抽出），投稿分頁 |
| T-7 | 主頁分頁、動態分頁、分頁列與焦點 |

由一個 Sonnet 子代理依序完成。

## 邊界情況

- UP主沒有任何影片（新帳號）：主頁顯示「暫無內容」。
- `tab2` 只有部分分頁（例如沒有 home）：只顯示存在的分頁。
- 系列沒有封面：顯示預設圖示。
- 動態全部是非影片類型、本頁解析出 0 部影片但 `has_more`：自動再載下一頁，最多連續 3 次，避免空白畫面。
- 登入狀態下 `access_key` 過期：App API 仍回公開資料或回錯誤 → 視為失敗，走退回邏輯。

## 第二階段審查後修正（以本節為準）

規格審查（Sonnet，2026-11-09）10 條，處理如下：

1. **App API 參數**：不採用「改 android_hd」——curl 已用 `AppSign.appKey`（`dfca71928277209b`）＋`mobi_app=android`、`platform=android`、`build=8430300` 實測 `/x/v2/space`、`archive/cursor`、`season/videos`、`series` 皆 `code 0`，沿用這組。採用：**預設不帶 `access_key`**（所需資料皆公開；TV 登入的 token 與此 appkey 不相容）。所有參數值用字串。
2. **共用格狀** `SpaceGrid<T>`：參數 `Future<SpacePage<T>?> Function(Object? cursor) load`（`SpacePage<T>({List<T> items, bool hasMore, Object? cursor})`，三種分頁語意由各 API 包裝成這個型別）、`Widget Function(T item, FocusNode node, ...) itemBuilder` 或內建影片卡片、`onSelect`、`onMoveUpFromTop`、`bool active`。格狀自己持有 `ScrollController`、`_requestId`、重試、空狀態、卡片 FocusNode；對外提供 `GlobalKey<SpaceGridState>` 的 `reload()` 與 `focusFirst()`。
3. **分頁建立**：不用 `IndexedStack`。`Map<String, Widget>` 快取已建立的分頁（首次選取才建立），非目前分頁包 `Offstage` + `ExcludeFocus(excluding: true)`；只有目前分頁的 `autofocus`／`active` 為 true。分頁列切換內容延遲 150ms（按住連發時只建立最後一個）。
4. **焦點補充**：關注按鈕下鍵 → 目前分頁列按鈕。投稿：格狀第一列上鍵 → 子分頁列（影片子分頁另有排序鈕在子分頁列右側）；子分頁列上鍵 → 分頁列。合集影片返回合集列表時，焦點還原到原合集卡片（記 index）。
5. **主頁區塊**：外層 `SingleChildScrollView + Column`；內層橫向 `ListView` 固定 `itemExtent`，聚焦前先 `animateTo` 再 `requestFocus`；`clipBehavior: Clip.none` 與左右 padding 容納 1.08 倍放大。上下切換區塊時沿用相同 column index（超出則取最後一張）。
6. **跨分頁「更多」**：`contributeSubTab`（video／collections）與 `openedCollection` 提升到 `UpSpaceScreen` state，主頁以回呼寫入並切到投稿分頁；返回鍵用 `PopScope(canPop: openedCollection == null)`，否則清除 `openedCollection`。
7. **動態解析**：共用 `VideoApi.archiveFromDynamicItem(Map item)`（public static）：保留 `visible != true` 過濾；轉發取 `orig` 的 `modules.module_dynamic.major.archive`、作者 `orig.modules.module_author`。`getSpaceDynamics` 未登入可能回 -352／-101：-352 更新 WBI 重試一次，仍失敗顯示重試按鈕。
8. **追番**：`int.tryParse(param)`，失敗略過；`fromSpaceApp` 的「bvid 空略過」只用於影片項目。
9. 測試對象 `archiveFromDynamicItem` 為 public。實機驗證清單（使用者執行）：三個分頁切換、各分頁上下左右與返回鍵、主頁「更多」跳到投稿與合集、合集返回焦點還原、追番播放、動態載入更多、未登入／已登入各開一次。
10. 系列：保留，卡片顯示「系列」字樣與預設圖示（不顯示數量）。
11. **資訊區收合**：焦點在分頁內容時，資訊區收合為一行（小頭像＋名稱，`AnimatedSize`）；焦點回到分頁列或資訊區時展開。分頁列固定在資訊區下方，內容區自己捲動。

## 實作偏差（第二階段）

- `getCollectionVideos` 多一個必填具名參數 `mid`（系列 API 需要 `vmid`）。系列的 `hasMore`：本頁筆數 >= 20，且 `total > 0` 時再以 `pn*20 < total` 判斷（未依賴 `data.next`，其語意未驗證）。
- 主頁「合集／系列」區塊的「更多」只切到投稿的合集／系列列表，不開啟特定合集；選取合集卡片才開啟該合集（AC-11 字面「開啟該合集」解讀為卡片選取）。
- 合集列表只含 `/x/v2/space` 回傳的 `ugc_season.item`／`series.item`（可能少於 `count`），未另外分頁載入。
- `SpaceGrid` 沒有 `active` 參數：非目前分頁由 `Offstage` + `ExcludeFocus` 隔離；格狀以 `autofocusIndex`（第一頁載入後聚焦）處理合集開啟／關閉的焦點還原。
- `archiveFromDynamicItem` 加 `includeForward` 參數：原本的 `getDynamicFeed` 傳 false 維持原行為，UP主動態傳 true。
- 子分頁（影片／合集）以按確定切換，不隨焦點切換；切換子分頁會重新載入該格狀（主分頁間才保留資料）。
- 分頁列在 `getSpace` 完成前不顯示（避免初始分頁跳動）；初始焦點在關注按鈕，載入完成後若焦點仍在關注按鈕則移到目前分頁按鈕。主頁重試時只讓主頁顯示載入中，不重建整個內容區。
- 「更多」跳到投稿時，格狀尚未載入完成則焦點先落在子分頁按鈕；合集影片格狀載入完成後自動聚焦第一張。
- `SpaceData.fans` 取 `card.fans`；`default_tab` 不在 `tab2` 內時取 `tab2` 第一個。
- 未做實機驗證（只通過 analyze 與單元測試）；`dart format` 只對新增／修改的 up_space、space_data、space_api、測試檔執行。
- 修正（實機回報投稿「影片」一直載入失敗）：投稿影片改用 App API `/x/v2/space/archive/cursor`（`SpaceApi.getArchives`，參數 `vmid`、`ps=20`、`order`（空字串／`click`）、`aid`=上一頁 `next_cursor`，以 `has_next` 判斷下一頁），不再用 Web WBI 的 `getSpaceVideos`（該端點在實機被風控）。`getSpaceVideos` 保留未刪。
