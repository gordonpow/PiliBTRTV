Android TV 版第三方 B站用戶端，基於 BiliTV，加上「線程撕裂者」（BTR）多 CDN 播放加速。
An unofficial third-party Bilibili client for Android TV with BTR multi-CDN acceleration.

## 下載哪一個？ / Which APK?
- `PiliBTRTV-v1.2.2-btr.19-arm64-v8a.apk`：64 位元，大多數較新的電視盒和電視用這個。Most modern TVs and boxes.
- `PiliBTRTV-v1.2.2-btr.19-armeabi-v7a.apk`：32 位元，64 位元版裝不上時改用這個。Older 32-bit systems.
- 從 App 內更新時，會自動選擇符合裝置的版本。In-app update picks the right one automatically.

## 變更
- 錯誤回報加入音質的詳細紀錄（#35）：電視是否支援杜比（解碼或 HDMI 直通）、每部影片提供的音軌、實際使用的音軌與原因、杜比播放失敗的錯誤訊息。杜比播不出聲音時，請在「設定 → 其他設定」送出錯誤回報。

## Changes
- Error reports now include detailed audio information: Dolby support (decoder or HDMI passthrough), available and selected audio tracks, and Dolby playback errors. If Dolby audio doesn't play, please send an error report.

## 注意
- APK 使用與 btr.6 以前相同的金鑰簽署，可以直接覆蓋安裝。
- 64 位元版的版本號比較大。電視裝過 64 位元版之後，若要改裝 32 位元版，要先解除安裝。
