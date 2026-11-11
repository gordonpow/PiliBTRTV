# 杜比全景聲與 Hi-Res 音軌（#33）＋字幕位置（#32）

日期：2026-11-11。使用者回報：大會員影片有杜比音效，App 沒有選項。直接做（未逐條確認 AC）。

## 需求（AC）
- AC-1：播放器設定面板新增「音質」子選單，列出本影片可用的音軌：「標準」、有 `dash.dolby.audio` 時「杜比全景聲」、有 `dash.flac.audio` 時「Hi-Res 無損」。目前使用的項目有標示。
- AC-2：裝置不支援的音軌仍列出但變暗，副標「此裝置不支援」，不能選。
- AC-3：選擇後從目前位置重新載入，使用選定音軌；選擇會記住（`SettingsService`），下次影片若有該音軌且裝置支援就自動使用，否則用標準。
- AC-4：預設「標準」（不自動切換到杜比，避免不支援的裝置出錯）。
- AC-5：杜比／Hi-Res 播放失敗（播放器錯誤）時自動退回標準，toast「此裝置無法播放杜比音軌，已改用標準音質」，本次影片不再嘗試。
- AC-6：MPD 只放一條音訊 Representation（選定的那條），避免 ExoPlayer 自動挑到裝置不支援的高位元率音軌。預取／暖機用同一個選擇邏輯。
- AC-7（#32）：CC 字幕在控制列隱藏時位於畫面底部（距底 48），控制列顯示時位於進度條上方。
- 英文介面字串加入 `i18n/en.json`。
- 不做：杜比視界畫質（已有 HDR 處理，不動）、彈幕。不改 `auth_api.dart`、`live_api.dart`、`btr_config.dart`、`app_restart.dart`。

## 現況（探索結果）
- `fnval=4048` 已含 256（杜比音訊），不用改請求（`lib/services/api/playback_api.dart:129`）。
- `playback_api.dart:384-393` 依 bandwidth 選 `audioUrl`，但 `:447-450` 的 `dashData` 保留整個 `audio` 陣列，實際由 ExoPlayer 自己挑。`dolby`／`flac` 沒有被讀取。
- `lib/services/mpd_generator.dart:47-55` 產生音訊 AdaptationSet（`audio/mp4`，codecs 原樣寫入，`ec-3`／`fLaC` 可用）。
- 播放器設定面板：`lib/screens/player/widgets/settings_panel.dart`（enum `:9`、主選單 `:181-245`、`_buildPlayEndSettingsList` `:323` 可當模板）；按鍵：`player_event_mixin.dart:578-691`；套用：`player_action_mixin.dart:2872`；換畫質重新載入流程參考 `player_action_mixin.dart:1113`、`:1407`。
- 原生 codec channel `MainActivity.kt:79-109` 只查影片解碼器。
- 預取 `lib/services/prefetch_service.dart:200-216` 用 `audioUrl` 對 `dash['audio']` 暖機。

## 設計
1. **音軌模型**（新檔 `lib/services/audio_track.dart`）：`enum AudioKind { standard, dolby, hires }`；純函式 `List<AudioOption> parseAudioOptions(Map dash)`（標準 = `audio` 中 bandwidth 最高；杜比 = `dolby.audio[0]`；Hi-Res = `flac.audio`，單一物件，可能為 null）與 `Map selectAudio(Map dash, AudioKind want, {required bool dolbyOk, required bool hiresOk})`（回傳選定的 stream，不可用時退回標準）。
2. **playback_api.dart**：`dashData['audio']` 改為只含選定的那一條；回傳結果加 `audioKind`（實際使用）與 `audioOptions`（給設定面板）。`audioUrl` 與選定的一致。選擇依 `SettingsService.preferredAudio` 與裝置支援，呼叫端可傳 `AudioKind? audioOverride`（播放中切換、退回標準時用）。
3. **裝置支援**：`MainActivity.kt` codec channel 新增 `getAudioSupport`，回傳 `{eac3, eac3Joc, flac}`：`MediaCodecList` 有對應解碼器，或（API 23+）`AudioManager.getDevices(GET_DEVICES_OUTPUTS)` 有輸出裝置的 encodings 含 `ENCODING_E_AC3`／`ENCODING_E_AC3_JOC`（直通）。Dart 端在 `DeviceProfile` 或新的 `AudioSupport` 啟動時查一次並快取；查詢失敗 → 杜比 false、flac true（Android 8.1+ 內建軟體解碼）。杜比可用 = eac3 或 eac3Joc。
4. **SettingsService**：`preferredAudio`（key `preferred_audio`，存 `AudioKind.index`，預設 standard），寫法照 `preferredCodec`（`settings_service.dart:285-315`）。
5. **設定面板**：`SettingsMenuType` 加 `audio`；主選單在「畫質」後新增「音質」項目，副標顯示目前音軌名稱；子選單照 `playEnd` 的寫法；左右鍵、返回、最大索引同步更新（`player_event_mixin.dart:578-691`）。注意主選單索引位移（字幕是條件項目）——檢查所有寫死的主選單索引。
6. **切換與退回**：套用時寫入設定並以目前位置重新載入（照換畫質流程）。播放器錯誤時若目前是 dolby／hires，改用 `audioOverride: standard` 重新載入並 toast，本影片記一個旗標不再嘗試。
7. **預取／暖機**：`prefetch_service.dart:200-216` 改用同一個 `selectAudio`。
8. **#32**：`lib/screens/player/widgets/subtitle_layer.dart` 已移除包在 `Align` 內的 `Center`（它在有邊界的區域內會撐滿，讓字幕垂直置中）。實作者不用再改，只需確認。
9. **測試**：`test/audio_track_test.dart`：解析（有／無 dolby、flac 為 null／物件）、選擇與退回。

## 驗證
- `flutter analyze`、`flutter test`。
- diff 審查：agy Opus（`claude-opus-4-6-thinking`），用量用完改 Claude Sonnet。
- 模擬器（Claude Sonnet）：音質選單出現、模擬器若無 eac3 則杜比變暗；字幕位置截圖。

## 實作偏差
- 主選單位置：「音質」放在索引 6（「播放完畢後」之後），字幕順延為索引 7（仍是條件項目），而不是放在「畫質」後；這樣 0-5 的寫死索引都不用動，只更新 6/7 相關處（event／action mixin 與 `_mainIndexAfterBack`、最大索引、`_clampSettingsFocus`）。
- 預取／暖機：`prefetch_service.dart` 的暖機邏輯不改，因為 `dashData['audio']` 與 `audioUrl` 現在已由 `selectAudio` 決定；只在快取 key 加入 `preferredAudio`，避免切換音質後吃到舊結果。
- `AudioSupport` 放在新檔 `lib/services/audio_support.dart`（不放 DeviceProfile），透過既有 codec channel 的 `getAudioSupport` 查詢。
- `audioOptions` 為 `List<AudioOption>`（含 `supported`），`parseAudioOptions` 多了 `dolbyOk`／`hiresOk` 參數；新增 `selectedAudioKind` 與 `audioKindLabel`。
- 切換與退回共用 `switchQuality`（新增 `doneMsg`、`resumeAt` 參數）；本影片覆寫旗標用 `audioOverrideNow`（以 bvid 綁定，換片自動失效），傳給播放器內所有 `getVideoPlayUrl` 呼叫。
- #32：已確認 `subtitle_layer.dart` 無 `Center`，不需再改。
- 依使用者要求「畫質跟音質要放一起」，「音質」移到主選單索引 1（畫質之後），其後順延：彈幕 2、播放速度 3、CDN 4、收藏 5、播放完畢後 6、字幕 7；已更新 settings_panel、event／action mixin、`_mainIndexAfterBack`（新增 speed→3）與返回焦點。另：音軌退回條件改為只看 `audioRelated`；`switchEpisode` 重設 `currentAudioKind`；`dashData` 移除 `dolby`／`flac` 鍵且無音軌時 `audio` 為空清單；MainActivity `getDevices` 改 null-safe。

- 使用者要求「畫質跟音質要放一起」：主選單改為 畫質0、音質1、彈幕2、速度3、CDN4、收藏5、播放完畢後6、字幕7（條件項目），所有寫死索引同步更新。

## 審查紀錄
- agy Opus 撞到 agy 用量上限（429），改由 Claude Sonnet 審查，7 條：
  - 採用 1：只有錯誤描述與音訊有關（audio／eac3／flac／joc），或影片退回 AVC 不適用時才退回標準音質，避免視訊解碼錯誤被誤判。
  - 採用 2：`switchAudio` 在 `stallSwitching` 時直接返回，避免偏好已寫入但沒重載。
  - 採用 3：`initializePlayer` 開頭把 `currentAudioKind` 重設為標準。
  - 採用 5：`AudioSupport` 查詢加 2 秒逾時。
  - 採用 6：`MediaCodecList` 只建一次。
  - 不改 4（偏好維持杜比，每部影片各退回一次，符合 AC-5）、7（`auto: true` 目前只影響 toast 與 userPicked）。
- Gemini Flash 審查：採用 #2、#3、#5（切集重設音質、dashData 清理 dolby／flac 與空 audio、audio fallback 只看 audioRelated）；#1、#4 無問題。另補 MainActivity `getDevices` null-safe。
- 模擬器（Claude Sonnet）：#32 字幕在底部／進度條上方 PASS；音質選單出現、選標準後播放不中斷、畫質與播放完畢後子選單索引正確 PASS；`[AudioSupport] dolby=false hires=true`；測試影片沒有杜比／Hi-Res 音軌，變暗顯示未能驗證。
- 第二次審查（agy Gemini 3.8 Flash，`review.md`）5 條：#1（索引）、#4（重載路徑）沒有問題；採用 #2（只有音訊相關錯誤才退回標準音質、`switchEpisode` 重設音軌）、#3（`dashData` 移除 `dolby`／`flac`，沒有音軌時 `audio` 為空）、#5（`getDevices` null 安全）。
- 選單順序與返回焦點的模擬器驗證被使用者中止，未完成。
