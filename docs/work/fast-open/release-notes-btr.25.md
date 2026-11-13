Android TV 版第三方 B站用戶端，基於 BiliTV，加上「線程撕裂者」（BTR）多 CDN 播放加速。
An unofficial third-party Bilibili client for Android TV with BTR multi-CDN acceleration.

## 下載哪一個？ / Which APK?
- `PiliBTRTV-v1.2.2-btr.25-arm64-v8a.apk`：64 位元，大多數較新的電視盒和電視用這個。Most modern TVs and boxes.
- `PiliBTRTV-v1.2.2-btr.25-armeabi-v7a.apk`：32 位元，64 位元版裝不上時改用這個。Older 32-bit systems.
- 從 App 內更新或 F-Droid 套件庫更新時，會自動選擇符合裝置的版本。In-app update and the F-Droid repo pick the right one automatically.

## 改進
- **點影片秒開**（#58）：焦點停在卡片上、預覽準備好之後按 OK，會直接接手預覽的播放器，幾乎立刻出畫面（「原生」畫面模式也一樣）。4K、HDR、杜比視界和直式影片仍用原生畫面重新開啟。沒有預覽時也會沿用已抓好的資料，少等一些時間。進播放頁的轉場改成短淡入。
- **播放更順**（#59）：播放中不再每 0.1 秒重繪整個畫面，彈幕改成平均加入，相關影片列不再跟著重建，減少彈幕捲動和選相關影片時的掉幀。

## Improvements
- **Instant start**: after the card preview is ready, pressing OK reuses its player and shows the video almost immediately, also in the native view mode (except 4K, HDR, Dolby Vision and portrait videos). Without a preview, already-fetched data is reused. The page transition is now a short fade.
- **Smoother playback**: the player no longer rebuilds the whole screen every 0.1 seconds, danmaku are added evenly, and the related-videos row no longer rebuilds during playback.

## 注意
- APK 使用與之前相同的金鑰簽署，可以直接覆蓋安裝。
- 64 位元版的版本號比較大。電視裝過 64 位元版之後，若要改裝 32 位元版，要先解除安裝。
