# 規格：直播 v2 取流（#49）與本機時移（#51）

需求見 `1-requirements.md`。兩個任務平行：T-1 新增時移服務（新檔案），T-2 改 API、直播畫面與設定，依照下面定義的介面呼叫 T-1。

## 介面（T-1 提供，T-2 使用）

檔案 `lib/services/live/live_timeshift.dart`：

```dart
class LiveTimeshiftSession {
  LiveTimeshiftSession({
    required Future<String?> Function() resolveUrl, // 取得新的遠端 fmp4 m3u8 完整網址；失敗回 null
    required Duration maxBuffer,
    Map<String, String> headers = const {},          // 下載遠端用的標頭（UA、Referer、Cookie）
  });

  /// 開始錄製並啟動本機 server。暫存到 init 與至少 3 個片段後，回傳本機播放網址
  /// `http://127.0.0.1:<port>/live/<id>/index.m3u8`。15 秒內做不到就丟例外。
  Future<String> start();

  /// 目前暫存的總長度（播放清單中所有片段的 EXTINF 總和）。
  Duration get bufferedDuration;

  /// 錄製開始至今已刪除的片段總長度。
  /// 本機播放清單第一個片段的絕對時間 = droppedDuration。
  Duration get droppedDuration;

  /// 錄製狀態變化：`recording`、`stalled`（連續失敗中）、`recovered`、`fatal`（重新取流也失敗超過 60 秒）。
  Stream<LiveTimeshiftState> get states;

  /// 停止輪詢、關閉這個 session 的路由、刪除暫存目錄。可重複呼叫。
  Future<void> dispose();

  /// App 啟動時呼叫：刪除 `<temp>/live_timeshift/` 下所有殘留目錄。
  static Future<void> cleanupStale();
}
```

位置換算（T-2 使用）：ExoPlayer 的 `position` 是相對於播放清單視窗起點，所以
- 目前絕對位置 ≈ `droppedDuration + position`
- 落後直播 = `bufferedDuration - position`
- 跳到絕對位置 `a`：`controller.seekTo(a - droppedDuration)`，夾在 `[0, bufferedDuration - 3s]`
- 回到 LIVE：`seekTo(bufferedDuration - 3s)`

誤差約 1～2 秒（ExoPlayer 重新載入清單的時間差），可接受。

## T-1 時移服務（AC-9～12）

新檔案：`lib/services/live/live_timeshift.dart`（可再拆 `live_hls_playlist.dart` 放解析與產生），`test/live_hls_playlist_test.dart`。

- **本機 server**：單一靜態 `HttpServer`，綁 `InternetAddress.loopbackIPv4` port 0，第一次 `start()` 時啟動，所有 session 共用，以 `<id>`（隨機字串）區分。路由：
  - `GET /live/<id>/index.m3u8`：即時產生，`Content-Type: application/vnd.apple.mpegurl`，`Cache-Control: no-cache`。
  - `GET /live/<id>/<file>.m4s`：從磁碟串流回傳，`Content-Type: video/mp4`，設 `Content-Length`。檔名只允許 `^[A-Za-z0-9_]+\.m4s$`，防止路徑穿越。
  - 其他 404。session dispose 後該 id 回 404。
- **錄製迴圈**：
  - 每 1 秒（依遠端 `TARGETDURATION`）抓遠端 m3u8，用 `http` 或 `dio`，逾時 5 秒。
  - 解析 `#EXT-X-MAP:URI`、`#EXTINF`、片段 URI、`#EXT-X-MEDIA-SEQUENCE`。片段 URI 用遠端 m3u8 網址為基準 resolve（相對路徑）。
  - 依遠端 sequence 判斷新片段，依序下載寫入 `<temp>/live_timeshift/<id>/`。本機檔名使用本機自己遞增的編號（例如 `s<n>.m4s`），init 存成 `init<k>.m4s`。
  - 遠端 init URI 改變時，下載新 init，下一個片段標記 discontinuity。
  - 遠端 sequence 跳號（漏片段）、重新取流後 sequence 不連續，都標記 discontinuity。
  - 片段下載失敗重試 2 次；仍失敗就略過並標記 discontinuity。
  - m3u8 連續失敗 3 次，或遠端回 403／404：呼叫 `resolveUrl()` 取得新網址，退避 2、4、8… 秒，上限 30 秒；期間狀態為 `stalled`，恢復後 `recovered`。超過 60 秒仍失敗為 `fatal`，但仍持續重試。
- **本機播放清單**：
  ```
  #EXTM3U
  #EXT-X-VERSION:7
  #EXT-X-TARGETDURATION:<最大 EXTINF 無條件進位，至少 1>
  #EXT-X-MEDIA-SEQUENCE:<第一個保留片段的本機編號>
  #EXT-X-DISCONTINUITY-SEQUENCE:<已刪除片段中的 discontinuity 數>
  #EXT-X-MAP:URI="init<k>.m4s"
  #EXTINF:1.000,
  s<n>.m4s
  ...
  ```
  - 不加 `#EXT-X-ENDLIST`、不加 `PLAYLIST-TYPE`（一般 live 清單）。
  - 每個 discontinuity 片段前加 `#EXT-X-DISCONTINUITY`，若 init 改變，後面再加新的 `#EXT-X-MAP`。
  - 第一個保留片段使用的 init 必須出現在清單開頭。
- **刪除舊片段**：`bufferedDuration > maxBuffer` 時，從最舊的開始刪（記憶體結構與磁碟檔案都刪），累加 `droppedDuration` 與 discontinuity 計數。不再被引用的 init 檔也刪除。
- **dispose／cleanup**：取消計時器與進行中的請求，移除路由，刪除目錄；`cleanupStale()` 刪除整個 `live_timeshift` 目錄。所有 log 不記完整網址（只記 host 與狀態碼）。
- **單元測試**：播放清單解析（含 MAP、相對 URI resolve）、本機清單產生（MEDIA-SEQUENCE、DISCONTINUITY-SEQUENCE、MAP 位置）、刪除舊片段後數值正確。

## T-2 API、直播畫面、設定（AC-1～8、AC-13）

檔案：`lib/services/api/live_api.dart`、`lib/screens/live/live_player_screen.dart`、`lib/services/settings_service.dart`（只新增）、`lib/services/memory_budget.dart`（只新增）、`lib/screens/home/settings/tabs/playback_settings.dart`、`lib/main.dart`（啟動時呼叫 `LiveTimeshiftSession.cleanupStale()`，不 await）。

- **API**：`LiveApi.getRoomPlayInfo(roomId, {qn})` 打 `https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo?room_id=&protocol=0,1&format=0,1,2&codec=0,1&qn=&platform=web&ptype=8&dolby=5&panorama=1`，帶 Cookie。回傳 `data`；失敗回 null。保留 `getPlayUrl`（v1）作後備。
- **解析**（取代 `live_player_screen.dart` :397-462 的攤平邏輯）：
  - 從 `playurl_info.playurl.stream` 依 `protocol_name`／`format_name`／`codec_name` 選一個 codec 物件：
    - 時移開啟：`http_hls` + `fmp4` + `avc`。沒有就關閉時移、照一般流程播放並 toast「此直播不支援時移」。
    - 時移關閉：維持現行偏好（`http_hls` 優先，其次 `http_stream`），codec 選 `avc`。
  - 線路 `_lines` = 該 codec 的 `url_info`，名稱「線路 1」「線路 2」…，網址 `host + base_url + extra`。
  - 畫質清單 = `accept_qn` 對應 `g_qn_desc` 的 `desc`（經 `ZhConvert`），目前畫質 = `current_qn`。
  - v2 失敗或沒有 `playurl_info` 時退回 v1（現有程式）。
- **時移播放**：
  - 設定 `SettingsService.liveTimeshiftMinutes`（int，0=關閉，可選 5、10、30），實際上限 = `MemoryBudget.liveTimeshiftMinutes(tier)`：high／mid 不限、low 最多 5、critical 為 0。
  - 開啟時建立 `LiveTimeshiftSession`，`resolveUrl` 重新呼叫 `getRoomPlayInfo` 並用相同 qn 與目前線路 index 組網址。`start()` 回傳的本機網址交給 `VideoPlayerController.networkUrl(..., formatHint: VideoFormat.hls)`，不帶 Cookie 標頭。
  - 換畫質、換線路、離開畫面、`fatal` 持續、時移設定關閉：dispose session。換畫質與線路時重新建立 session（AC-13）。
  - 看門狗：時移模式下，只有 `hasError` 才重建播放器；卡在緩衝且落後直播 < 3 秒，視為等待新片段，不重連（錄製端自己會重新取流）。
  - 暫停／繼續：時移模式只 `pause()`／`play()`，不重新連線；App 回前景也只在未暫停時 `play()`。若繼續時位置早於暫存起點，ExoPlayer 會 BEHIND_LIVE_WINDOW 並自動 `seekToDefaultPosition`（已有處理），可接受；為了符合 AC-9，繼續前先檢查，位置 < 0 時 seek 到 0。
- **進度條**（擴充現有 `_buildLiveBar`）：
  - 時移開啟：進度條範圍 = 暫存範圍，已播放部分填色，顯示目前位置的圓點；右側文字：在直播最新位置（落後 < 5 秒）時「已開播 H:MM:SS」，落後時「-mm:ss」，LIVE 標記變灰。
  - 時移關閉：維持現有只顯示的行為。
  - 進度條可取得焦點：按鈕列按上鍵到進度條（只在時移開啟時），進度條按下鍵回按鈕列。焦點在進度條時有明顯框線。
- **按鍵**：
  - 控制列隱藏時：時移開啟則左右鍵直接 ±10 秒並顯示控制列（焦點放在進度條）；時移關閉維持現狀（任何鍵只叫出控制列）。
  - 進度條：左右 ±10 秒（長按連續），OK 回到 LIVE。
  - 媒體鍵 `mediaRewind`／`mediaFastForward` 在時移開啟時也是 ±10 秒。
- **設定頁**：`playback_settings.dart` 新增 `SettingPickerRow<int>`「直播時移」，選項 0／5／10／30，標籤「關閉」「5 分鐘」「10 分鐘」「30 分鐘」，副標題說明「在本機暫存直播，可倒退與快轉；會占用儲存空間」。

## AC 驗證

| AC | 驗證 |
|---|---|
| 1～3 | 程式碼審查、模擬器開直播看線路／畫質清單 |
| 5～13 | T-1 單元測試、程式碼審查、模擬器操作（開時移、倒退、回 LIVE、暫停繼續、換畫質） |
| 全部 | `flutter analyze` 無新增問題、`flutter test` 通過、建置成功 |

## 風險與回退

- ExoPlayer 對本機 live 清單的視窗位置有延遲，換算有 1～2 秒誤差。
- 長時間錄製的磁碟用量：原畫約 4～8 Mbps，30 分鐘約 1～2GB。設定副標題要說明；低記憶體裝置限制 5 分鐘。
- 回退：時移預設關閉；v2 失敗會退回 v1。

## 審查紀錄（Sonnet 規格審查，全部採用；以下補充覆蓋上文）

**位置與 seek（T-2）**
- `VideoPlayerController.seekTo`（video_player 2.9.5 :650）會夾在 `value.duration`，而 duration 只在初始化送一次，所以時移模式**不可用** `controller.seekTo` 與 `value.position`。
- 改用 `VideoPlayerPlatform.instance.seekTo(controller.textureId, pos)`（需要時在 pubspec 加 `video_player_platform_interface` 直接依賴，版本與 lock 檔現有版本相同），位置用 `await controller.position`（原生 `getCurrentPosition`，不夾限）。
- 時移模式的看門狗、進度條、暫停記錄都用這個未夾限的位置，每秒取一次存成 `_tsPosition`。
- 起播後呼叫 `setPlaybackSpeed(1.0)`。ExoPlayer live 速度控制可能讓倒退後的位置慢慢追近，若模擬器實測仍會漂，接受誤差並記在驗證文件。

**換算集中在 session（T-1 介面補充）**
- 新增 `Duration absoluteOf(Duration playerPos)` = `droppedDuration + playerPos`。
- 新增 `Duration playerPosFor(Duration absolute)`：夾在 `[0, bufferedDuration - liveEdgeOffset]` 後換成播放器位置。
- 新增 `Duration get liveEdgeOffset`（= 3 × 本機 TARGETDURATION）、`Duration get liveAbsolute`（= droppedDuration + bufferedDuration）。
- T-2 一律使用這些 helper，不自己換算。

**暫停繼續（AC-9）**
- 暫停時記下絕對位置 `_pausedAbs = session.absoluteOf(pos)`。繼續時 `seekTo(session.playerPosFor(_pausedAbs))` 後再 `play()`（暫存已被刪掉時自然夾到最舊位置）。

**錄製端（T-1）**
- 片段合併：每 4 個遠端片段（約 4 秒）的 moof+mdat 直接 byte 串接成一個本機片段，EXTINF 為加總；init 改變或 discontinuity 時立刻結束目前合併中的片段。30 分鐘約 450 個片段。
- 輪詢間隔 = 0.5 × 遠端 TARGETDURATION（最少 500ms）；片段最多 3 個並行下載、依 sequence 順序寫入；待下載佇列上限 20，超過丟最舊的並標 discontinuity。
- 刪除舊片段：先從清單移除，磁碟檔延遲 15 秒再刪。
- 寫檔失敗（含磁碟滿 `FileSystemException`）：狀態 `fatal` 並停止錄製；T-2 收到 `fatal` 時 toast「直播時移已停止，改為一般播放」並退回一般播放。網路類失敗才是 `stalled`／持續重試；網路失敗超過 60 秒也發 `fatal`，T-2 同樣處理。
- `dispose()`：設 `_disposed`，`HttpClient.close(force: true)` 取消請求，每個 await 後檢查 `_disposed`，不重建目錄；`start()` 進行中被 dispose 則丟例外。
- `cleanupStale()`：整個 App 只執行一次（static Future 快取），`start()` 先 await 它，避免刪到新 session 的目錄。
- 本機清單字串在片段有變化時才重建並快取。
- 單元測試補：本機 server 路由（路徑穿越回 404、dispose 後 404）、遠端 sequence 跳號與 init 變更產生 discontinuity、刪除後 MEDIA-SEQUENCE／DISCONTINUITY-SEQUENCE、用假的 `resolveUrl` 與假遠端（本機 HttpServer）測試重新取流。

**按鍵（T-2）**
- 新增 `_barFocused` 獨立狀態，不放進 `_focusedControlIndex`。
- 處理順序：彈窗放行 → 彈幕長按判定 → 媒體鍵（`mediaPlayPause`、`mediaPlay`、`mediaPause`、`mediaRewind`、`mediaFastForward`）→ `!_showControls` 時（時移開啟才）左右鍵 seek → 設定面板 → 進度條焦點（左右 seek、OK 回 LIVE、下鍵回按鈕列）→ 按鈕列。
- 左右 seek 要處理 `KeyDownEvent` 與 `KeyRepeatEvent`（長按連續）。每次 seek 重啟控制列自動隱藏計時器。

**AC 門檻（補充需求）**
- 「在直播最新位置」= 落後 < 5 秒；否則 LIVE 標記灰色並顯示「-mm:ss」。
- seek 上限 = `liveAbsolute - liveEdgeOffset`。
- 補 AC：低記憶體裝置選項最多 5 分鐘、critical 時不啟用時移（照一般播放）；v2 失敗退回 v1；不支援時移的直播 toast「此直播不支援時移」；離開畫面後暫存目錄被刪除。

**工作樹**：`live_player_screen.dart`、`settings_service.dart`、`playback_settings.dart` 有本次對話先前未 commit 的修改（#44～#48、#50），T-2 在其上繼續改，不要還原。
