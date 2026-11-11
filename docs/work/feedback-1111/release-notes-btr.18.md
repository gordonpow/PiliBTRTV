Android TV 版第三方 B站用戶端，基於 BiliTV，加上「線程撕裂者」（BTR）多 CDN 播放加速。
An unofficial third-party Bilibili client for Android TV with BTR multi-CDN acceleration.

## 下載哪一個？ / Which APK?
- `PiliBTRTV-v1.2.2-btr.18-arm64-v8a.apk`：64 位元，大多數較新的電視盒和電視用這個。Most modern TVs and boxes.
- `PiliBTRTV-v1.2.2-btr.18-armeabi-v7a.apk`：32 位元，64 位元版裝不上時改用這個。Older 32-bit systems.
- 從 App 內更新時，會自動選擇符合裝置的版本。In-app update picks the right one automatically.

## 新增
- **音質選單**（#33）：播放器設定「畫質」下方新增「音質」，影片有提供時可選「杜比全景聲」或「Hi-Res 無損」（通常需要大會員）。電視不支援的音軌會變暗；選擇會記住；杜比播放失敗會自動改回標準音質。杜比需要電視本身支援，或透過 HDMI 接到支援杜比的音響。
- **長按快進**（#28）：播放時短按左右鍵移動 10 秒，按住會越來越快。
- **隱藏互動按鈕**（#29）：「設定 → 播放設定」可個別隱藏控制列的按讚、投幣、收藏按鈕。
- **依記憶體調整預載**（#27）：依電視的記憶體大小調整快取與預載；執行中記憶體不足時自動停止預覽並縮小快取。

## 修正
- 低記憶體裝置（例如 Google Chromecast）在首頁連續移動焦點時無回應（ANR）（#21）。
- 在手機調整過進度的影片，電視按播放從頭開始；現在以 B 站同步的進度為準（#30）。
- 掃碼登入時常卡在「已掃描，請在手機上確認」（#34）。
- CC 字幕跑到畫面中間（#32）。
- 切換頁面再回來時，焦點回到頂端但畫面停在底部（#31）。
- 英文介面分頁列最後一個分頁被時鐘蓋住（#22）；App 更新後英文語言包沒有跟著更新（#23）。
- 搜尋結果第一排卡片被裁切（#24）；觀看歷史卡片名稱與觀看時間沒有間隔（#25）。

## New
- **Audio quality menu**: choose Dolby Atmos or Hi-Res lossless when the video offers it (usually requires VIP). Unsupported tracks are dimmed; falls back to standard audio if Dolby fails to play.
- **Hold to fast-seek**: tap left/right for 10 seconds, hold to seek faster.
- **Hide like / coin / favorite buttons** individually in playback settings.
- **Memory-aware preloading**: cache and preload adapt to the device's memory.

## Fixes
- ANR when moving focus quickly on low-memory devices such as Google Chromecast.
- Resume position from your phone is now used on the TV.
- QR login stuck at "scanned, confirm on your phone".
- Subtitles shown in the middle of the screen; scroll position not reset when returning to a page; tab bar overlapped by the clock in English UI; language pack not updated after app update; clipped search results; history card spacing.

## 注意
- APK 使用與 btr.6 以前相同的金鑰簽署，可以直接覆蓋安裝。
- 64 位元版的版本號比較大。電視裝過 64 位元版之後，若要改裝 32 位元版，要先解除安裝。
