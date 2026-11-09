# 規格：焦點暖機播放器（按 OK 約 0.4 秒開播）

## 需求

使用者回報（2026-11-09）：預載後按 OK 仍要約 3.4 秒才開播，要求約 0.4 秒。使用者選「預覽改用正式播放器」：焦點停 1 秒後，卡片預覽直接用正式畫質的播放器（靜音）；按 OK 時播放頁接手同一個播放器並開聲音。

- **AC-1**：焦點停在一般影片（UGC）卡片 1 秒後，卡片內以正式播放器靜音預覽（從續播進度開始；沒有進度從頭）。
- **AC-2**：預覽已開始時按 OK，播放頁在 0.5 秒內顯示畫面並有聲音（log `⏱ [Startup] adopted Nms`）。
- **AC-3**：預覽尚未就緒時按 OK，播放頁走原流程，播放正常（並沿用已預載的 playurl）。
- **AC-4**：焦點離開卡片時釋放暖機播放器；同一時間最多一個。番劇、直播不暖機（維持原本流程，番劇卡片可沿用 480P 預覽或不預覽）。
- **AC-5**：暖機失敗（初始化錯誤、逾時）時靜默保持封面，不改任何設定（不得 `setCodecFallbackAvc`）。
- **AC-6**：接手後播放頁所有功能正常：進度條、快退快進、彈幕、畫質切換、選集、續播進度上報、播完連播、返回。
- **AC-7**：預覽 10 秒後暫停並恢復封面，但播放器保留（已緩衝）直到焦點離開，期間按 OK 仍可秒開（從預覽開始的位置或續播位置播放，見設計）。
- **AC-8**：「影片卡片預覽」設定關閉時不暖機。

## 設計

### 抽出共用的「準備播放」

`lib/screens/player/mixins/player_action_mixin.dart` 的 `initializePlayer` 目前混合：網路請求（info、cid、續播進度、playurl）→ 產生 MPD → 建 controller → `initialize()` → 掛 listener、seek、play、彈幕等。

1. 新增 `lib/services/playback_preparer.dart`：`PlaybackPreparer.prepare(Video video, {bool muted})` 回傳 `PreparedPlayback`，包含 controller（已 initialize、已 seek 到續播位置、未播放）、`videoInfo`、`cid`、`aid`、`playInfo`、`currentQuality`、`codec`、`resumePosition`、續播相關欄位，以及播放器 `initializePlayer` 後續需要的其他狀態。邏輯從 `initializePlayer` 的 UGC 路徑原樣搬出（含 redirect_url 轉番劇時回傳 null 讓呼叫端走原流程、編碼重試迴圈），但**預熱呼叫時**（`warm: true`）初始化失敗不得寫入任何設定（`setCodecFallbackAvc` 只在播放器自己呼叫時執行）。
2. `initializePlayer` 的 UGC 路徑改為：先 `WarmPlayerService.instance.take(bvid)`；有就用回傳的 `PreparedPlayback`（`mark('adopted')`），沒有就 `PlaybackPreparer.prepare(...)`；之後共用同一段「接上播放」程式（掛 listener、startHideTimer、setState isLoading=false、play、loadDanmaku、線上人數、videoshot、相關影片、進度上報計時器等）。行為必須與現在完全相同（對照重構前後的副作用清單）。
3. 番劇路徑不變。

### `WarmPlayerService`（取代 `CardPreviewService` 的 UGC 部分）

- 檔案：沿用 `lib/services/card_preview_service.dart`（保留類別名與 `current` ValueNotifier，卡片不用大改），內部 UGC 改呼叫 `PlaybackPreparer.prepare(video, muted: true)`；番劇維持目前 480P 預覽。
- `start(owner, video)`：stopAll → prepare（generation 檢查、逾時 10 秒）→ `setVolume(0)`、`play()` → `current.value = state` → 10 秒後 `pause()` 並 `current.value = null`（卡片恢復封面），但 `_prepared` 保留。
- `stop(owner)` / `stopAll()`：dispose `_prepared` 的 controller（若未被 take）。
- `PreparedPlayback? take(String bvid)`：bvid 相符就交出並清空自身引用（之後 stop 不會 dispose 它），同時 `current.value = null`；不符回 null。
- 卡片按 OK（`BaseTvCard._handleSelect`）**不再** `stopAll()`；改為不動作（讓播放器 take）。`PlayerScreen.initState` 的 `stopAll()` 要移到 `initializePlayer` 的 take 之後（take 失敗才 stopAll，釋放解碼器）。
- `LocalServer` 只存一份 MPD：暖機時會 `setMpdContent`；被 take 後播放器沿用同一份；暖機播放器被 dispose 時不需還原。播放器若之後自己 prepare 會覆寫，沒有衝突。
- 視圖：controller 的 `viewType` 依 `SettingsService.playerTextureView`（與播放器一致）。卡片內顯示 `VideoPlayer(controller)`；若 platformView 在卡片內無法正確裁切或縮放，卡片改為不加圓角裁切（直角）也可接受，但必須在模擬器確認畫面位置正確、不會蓋到其他卡片。
- 進度：暖機的 controller 預覽時有播放 10 秒；接手時若 `resumePosition` 存在則先 seek 回 resumePosition 再播（使用者看預覽的那段不算觀看）；沒有進度就從 0 開始。

### 播放頁接手

- `VideoLayer` 已會在 initialized 時顯示 `VideoPlayer(controller)`；接手後立刻 `setState(isLoading=false)`。
- 接手時 `setVolume(1.0)`（或使用者音量設定）。
- `disposePlayer` 照常 dispose 接手的 controller。

## 任務

- **T-1**（Sonnet）：`PlaybackPreparer` 抽出＋`initializePlayer` 改用＋`CardPreviewService` 改用 prepare/take＋`BaseTvCard`／`PlayerScreen` 調整。單一子代理依序完成。

## 驗證

| AC | 方式 |
|---|---|
| AC-1、AC-2、AC-7 | 模擬器：聚焦 2 秒後按 OK，log `adopted` 與 `play` 時間；截圖預覽 |
| AC-3 | 模擬器：聚焦 0.5 秒內按 OK |
| AC-4、AC-5 | 程式碼審查＋快速移動焦點時 log 無錯誤 |
| AC-6 | 模擬器：接手後快退快進、返回、再進另一部影片 |
| 全部 | `flutter analyze`、`flutter test`、debug APK 建置 |

## 風險

- `initializePlayer` 重構範圍大：以「副作用清單」逐項對照。
- 預覽解碼正式畫質（1080P/4K）：舊電視效能。設定可關閉。
- platformView 在卡片中的顯示。
- 暖機時 LocalServer MPD 被覆寫：若同時有播放頁開著（例如從播放頁的相關影片？），不會發生，因為卡片只在首頁等頁面。

## 審查紀錄

Sonnet 規格審查 10 條全部採用（以下優先於上文）：

1. **交接時機**：`BaseTvCard._handleSelect` 先呼叫 `CardPreviewService.instance.reserve(bvid)`：把暖機結果標記為「保留給播放頁」並解除 owner（之後卡片失焦、dispose 的 `stop(this)` 不會釋放它）；保留 5 秒未被 take 就自動 dispose。`PlayerScreen.initState` 第一個 await 前同步 `take(widget.video.bvid)` 並存進 State，`initializePlayer` 使用該欄位。
2. **通知時機**：take／reserve 時 `current.value = null` 一律延到 `addPostFrameCallback`／microtask；卡片在 reserve 後立即不再顯示 `VideoPlayer`（卡片端自行檢查 reserved 狀態），避免同一 controller 同時掛在兩個視圖。
3. **AC-3 競態**：prepare 在 `LocalServer.setMpdContent` 前檢查 generation（暖機已被取消就不寫），`setMpdContent` 與建立 controller／`initialize()` 之間不得有其他 await；被取消時 dispose 已建立的 controller。
4. **進度**：暖機從續播位置（或 0）開始靜音播放；接手時**從目前位置接續**（不 seek 回去，避免丟緩衝）。AC-7 改為「從預覽暫停的位置接續」。
5. **副作用清單**：prepare 不得 setState、不得 toast、不得呼叫 PluginManager、不得開計時器；只回傳資料。播放器接手端統一套用：fullVideoInfo／episodes／cid／aid／qualities／currentQuality／currentCodec／currentAudioUrl／previewFrameUrl／isPreview、PluginManager.onVideoLoad、initialProgress、resetDanmakuIndex、「從xx繼續播放」toast（接手時位置若 > 0 才顯示）、_fetchOnlineCount＋計時器、loadVideoshot、相關影片、進度上報計時器、listener。實作時先列出重構前 initializePlayer 的所有副作用，逐項確認重構後仍執行。
6. **prepare 參數化**：`PlaybackPreparer.prepare(video, {required int qn, VideoCodec? codec, bool warm})`，不讀 mixin State；take 比對 bvid（cid 由 prepare 決定並回傳，接手端使用回傳的 cid）。
7. **播放頁底下的卡片**：新增 `PlayerScreen.activeCount`（initState +1、dispose -1）；> 0 時卡片走原本 480P 預覽（不暖機，不碰 LocalServer）。
8. **viewType**：暖機 controller 固定 `VideoViewType.textureView`；接手後播放頁也就是 textureView（「播放畫面模式」設定對秒開的影片不生效，於設定說明中不需更改，回報給使用者）。
9. **暫停後保留上限**：預覽 10 秒暫停後最多保留 60 秒，超過自動 dispose。
10. **AC-5**：暖機失敗不得 `setCodecFallbackAvc`、不得 toast，沿用 `_failCount` 與暫停冷卻。
