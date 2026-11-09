# 規格：影片卡片焦點預覽

需求見 `1-requirements.md`。

## 設計

### 資料流

焦點進入卡片 → `BaseTvCard` 開 1 秒計時器 → 到時呼叫 `CardPreviewService.instance.start(owner, video)` →
取 cid（`video.cid > 0` 直接用，否則 `BilibiliApi.getVideoCid(bvid)`）→ `BilibiliApi.getVideoPlayUrl(bvid, cid, qn: 32, epId: 番劇才帶)` →
取回傳的 `previewUrl`（已挑好的 480P 以下 AVC 純視訊 m4s，沒有音訊）→ `VideoPlayerController.networkUrl(previewUrl, httpHeaders, viewType: VideoViewType.textureView)` →
`setVolume(0)`、`initialize()`、`play()` → 通知卡片在封面上疊 `VideoPlayer` → 10 秒後或焦點離開時 `stop(owner)` 釋放 controller，卡片恢復封面。

### 新增 `lib/services/card_preview_service.dart`

單例 `CardPreviewService.instance`：

- `final ValueNotifier<CardPreviewState?> current`：`CardPreviewState { Object owner; VideoPlayerController controller; }`，只有 `initialize()` 成功並開始播放後才設值。
- `Future<void> start(Object owner, Video video)`：
  1. 先 `stopAll()`（AC-4：同時最多一個）。
  2. 遞增 `_generation`，記下本次 generation 與 owner；每個 `await` 之後檢查 generation 是否仍相同，不同就丟棄（若已建立 controller 則 dispose）。
  3. 取 cid；`video.isLive` 或 bvid 為空時直接 return。番劇（`video.isPgc`）只在 `epId > 0` 時帶 `epId`，否則 return。
  4. `getVideoPlayUrl` 回傳含 `error` 或沒有 `previewUrl` 時 return（AC-6，不顯示錯誤）。
  5. 建 controller，headers 與播放器相同：`User-Agent`（同 player_action_mixin.dart 的 UA 字串，抽成常數或照抄）、`Referer: https://www.bilibili.com/`、`Origin: https://www.bilibili.com`、有 `BaseApi.cookieHeader` 時帶 `Cookie`。不經過 `BtrProxy`、不使用 `LocalServer`（LocalServer 只存一份 MPD，會蓋掉播放器）。
  6. `setVolume(0)`、`setLooping(false)`、`initialize()`、`play()`；成功後設 `current.value`，並開 10 秒計時器 → `stop(owner)`（AC-2）。
  7. 任何例外 catch 後 dispose controller、保持封面（AC-6）。
- `void stop(Object owner)`：owner 相同（或仍在準備中的 owner 相同）才停止：遞增 generation、取消計時器、`current.value = null`、dispose controller。
- `void stopAll()`：無條件停止。
- 設定關閉時（`SettingsService.cardPreview == false`）`start` 直接 return。

### 修改 `lib/widgets/base_tv_card.dart`

- 新增選填參數 `Video? previewVideo`（null 表示此卡片不預覽，直播、合集等不傳）。
- `_onFocusChange`：
  - focused 且 `previewVideo != null` 且 `SettingsService.cardPreview`：開 `Timer(1s)` → `CardPreviewService.instance.start(this, previewVideo!)`（AC-1）。1 秒內不發任何網路請求。
  - 失焦：取消計時器、`CardPreviewService.instance.stop(this)`（AC-3）。
- 確認鍵（`onTap`）：先取消計時器並 `CardPreviewService.instance.stopAll()`，再呼叫原本的 `widget.onTap`（AC-5，push 播放頁前釋放解碼器）。
- `dispose`：取消計時器、`stop(this)`。
- 封面區（`ClipRRect` 內 `widget.imageContent`）改成 `Stack`：底層 `imageContent`，上層 `ValueListenableBuilder<CardPreviewState?>`，`state?.owner == this` 時 `Positioned.fill(FittedBox(fit: BoxFit.cover, child: SizedBox(width, height = controller.value.size, child: VideoPlayer(controller))))`。角標、時長等會被蓋住，可接受（預覽只有 10 秒）；若 `imageContent` 內有角標層也可以只蓋圖片，但以簡單為主。

### 修改卡片

- `lib/widgets/tv_video_card.dart`、`lib/widgets/history_video_card.dart`：把 `video` 傳給 `BaseTvCard(previewVideo: video.isLive ? null : video)`。
- `up_home_tab.dart:264`、`space_collection_card.dart`、`tv_live_card.dart` 直接用 `BaseTvCard` 的不傳（合集、直播不預覽）。

### 播放頁保險

- `lib/screens/player/player_screen.dart` `initState` 開頭呼叫 `CardPreviewService.instance.stopAll()`（防止其他進入播放頁的路徑漏停）。

### 設定

- `lib/services/settings_service.dart`：`_cardPreviewKey = 'card_video_preview'`，`static bool get cardPreview => _prefs?.getBool(key) ?? true`（預設開，AC-7），`setCardPreview(bool)`。
- `lib/screens/home/settings/tabs/interface_settings.dart`：在「總是顯示時間」後加 `SettingToggleRow(label: '影片卡片預覽', subtitle: '游標停在影片卡片上 1 秒，靜音預覽 10 秒')`，關閉時呼叫 `CardPreviewService.instance.stopAll()`。

## 任務

- **T-1**：`CardPreviewService` + `SettingsService.cardPreview`。
- **T-2**（依賴 T-1）：`BaseTvCard`、`TvVideoCard`、`HistoryVideoCard`、`PlayerScreen.initState`。
- **T-3**（依賴 T-1）：介面設定開關。

單一 Sonnet 子代理依序完成。

## 驗證方式

| AC | 方式 |
|---|---|
| AC-1～AC-5 | 待使用者在模擬器／電視測試 |
| AC-4、AC-5 | 程式碼審查：generation 檢查、onTap 前 stopAll |
| AC-6 | 程式碼審查：所有失敗路徑 return、不 toast |
| AC-7 | 程式碼審查＋使用者測試 |
| AC-8 | 程式碼審查：五類頁面都使用 TvVideoCard／HistoryVideoCard |
| 全部 | `flutter analyze` 無問題、`flutter test` 通過、debug APK 建置成功 |

## 邊界與風險

- 快速移動焦點：1 秒計時器，未滿 1 秒不發請求；generation 檢查丟棄過期結果。
- 硬體解碼器數量：同時只一個預覽、480P AVC、進播放頁前 stopAll。
- `getVideoPlayUrl` 會觸發 HDR／解碼能力查詢與 wbi 簽名，請求較重；只在停留滿 1 秒後才呼叫。
- 番劇試看／大會員集：取不到串流就保持封面。
- 回退：設定關閉即可停用；或還原 `BaseTvCard` 的修改。

## 審查紀錄

Sonnet 規格審查 12 條，修正如下（以下補充優先於上文）：

1. **previewUrl 不保證 AVC**（採用）：`playback_api.dart` 在 DASH 分支回傳中加 `'previewIsAvc': bool`（有選到 avc 軌才 true）；durl 分支不加（視為 false）。`CardPreviewService` 只在 `previewIsAvc == true` 時預覽，否則保持封面。
2. **m4s 直接播放未驗證**（採用）：實作後在模擬器實測；失敗再回到規格改用 MPD。
3. **getVideoPlayUrl 可能回 null**（採用）：null、含 `error`、`previewUrl` 空、`isPreview == true`（番劇試看）都 return。
4. **dispose 時機**（採用）：`stop` 先 `current.value = null`，再用 `WidgetsBinding.instance.addPostFrameCallback` dispose controller；卡片 build 時另外檢查 `controller.value.isInitialized`。
5. **initialize 逾時、播放錯誤**（採用）：`initialize().timeout(8 秒)`，逾時或例外就 dispose；`initialize` 回來後再檢查 generation；加 listener，`value.hasError` 時 `stop(owner)`。
6. **計時器在 dispose 後觸發**（採用）：dispose 一定取消計時器；回呼先檢查 `mounted && _isFocused`。
7. **PlayerScreen.initState stopAll**（採用，列為必做）。
8. **風控**（採用）：同 bvid 的 `previewUrl` 快取 3 分鐘（記憶體 Map，上限 50 筆）；連續 3 次取流失敗後暫停預覽 60 秒。
9. **PGC 判斷**（採用）：番劇需 `epId > 0` 且 bvid 不空；`cid` 為 0 時不預覽（避免取到別集）。
10. UA 照抄、textureView（不需修改）。
11. `up_home_tab.dart:264` 行號（不影響設計：直接用 `BaseTvCard` 的卡片不傳 `previewVideo` 即不預覽）。
12. video_player 版本相容（不需修改）。
