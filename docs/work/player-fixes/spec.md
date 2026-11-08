# 規格：解碼失敗自動換編碼、Netflix 式快退快進（精簡版）

日期：2026-11-08

## A. 解碼失敗自動改用 H.264

使用者回報：搜尋的影片完全不能播放，畫面顯示
`播放器初始化失敗: PlatformException(VideoError, Video player had error Z.n: MediaCodecVideoRenderer error, index=0, format=Format(32, null, video/mp4, video/hevc, hvc1.1.6.L120.90, ... format_supported=YES ...)`
（裝置宣稱支援 HEVC，但硬體解碼器實際失敗）。

- **AC-A1**：`VideoPlayerController.initialize()` 或播放中出現含 `MediaCodec` 或 `Decoder` 的錯誤時，若目前編碼不是 AVC，自動改用 AVC（H.264）重新取得播放網址、重建 MPD 與播放器，從原本的進度繼續；畫面提示「此裝置無法解碼 H.265／AV1，已改用 H.264」。
- **AC-A2**：同一個 App 執行期間記住「HEVC／AV1 解碼失敗」，之後的影片直接用 AVC（可寫入設定 `codec_fallback_avc=true`，設定頁的首選編碼仍可手動改回）。
- **AC-A3**：AVC 也失敗時才顯示原本的錯誤訊息。
- 相關程式：`lib/screens/player/mixins/player_action_mixin.dart`（`initializePlayer` 的 codec 迴圈與 `VideoPlayerController` 初始化重試、`switchEpisode`、`switchQuality`）、`lib/services/codec_service.dart`、`lib/services/settings_service.dart`。

## B. Netflix 式快退快進

- **AC-B1**：播放中（控制列未顯示時）按左／右鍵：畫面下方出現進度條與時間（目前時間／總長），並在進度條上方顯示預覽卡片（雪碧圖縮圖；沒有縮圖時只顯示時間）。不會立刻跳轉。
- **AC-B2**：每按一次移動 10 秒；按住或連按時加速（例如連按超過 3 次後每次 30 秒，超過 8 次後每次 60 秒）。
- **AC-B3**：按確認鍵立即跳到預覽位置；1.5 秒內沒有再按方向鍵也自動跳轉；按返回鍵取消，回到原位置。
- **AC-B4**：跳轉時影片暫停預覽，跳轉後恢復播放（若原本在播放）。
- **AC-B5**：控制列顯示時，左右鍵維持原本的按鈕間移動行為。
- 原版已有「快進預覽模式」（`SettingsService.seekPreviewMode`、`lib/screens/player/widgets/seek_preview_thumbnail.dart`、`lib/services/api/videoshot_api.dart`）；在此基礎上改為上述行為，並把此模式預設開啟。
- 相關程式：`lib/screens/player/mixins/player_event_mixin.dart`（方向鍵處理）、`lib/screens/player/player_screen.dart`（疊加層）、`seek_preview_thumbnail.dart`。

## C. 其他

- 錯誤報告確認對話框（`lib/widgets/error_report_dialog.dart`）的預設焦點改到「取消」，避免誤按上傳。

## 驗證

`flutter analyze` 無問題；模擬器（Android TV API 36）確認快退快進的進度條與預覽卡片顯示。
