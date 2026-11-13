Android TV 版第三方 B站用戶端，基於 BiliTV，加上「線程撕裂者」（BTR）多 CDN 播放加速。
An unofficial third-party Bilibili client for Android TV with BTR multi-CDN acceleration.

## 下載哪一個？ / Which APK?
- `PiliBTRTV-v1.2.2-btr.24-arm64-v8a.apk`：64 位元，大多數較新的電視盒和電視用這個。Most modern TVs and boxes.
- `PiliBTRTV-v1.2.2-btr.24-armeabi-v7a.apk`：32 位元，64 位元版裝不上時改用這個。Older 32-bit systems.
- 從 App 內更新或 F-Droid 套件庫更新時，會自動選擇符合裝置的版本。In-app update and the F-Droid repo pick the right one automatically.

## 新功能
- **直播時移**（#51、#54）：設定 → 播放設定 →「直播時移」可選 5／10／30 分鐘。控制列收起時按左右鍵預覽倒退或快轉，會顯示前後多張縮圖，跟一般影片一樣；按住會加速，OK 或停 1.5 秒就跳過去。進度條依設定的長度按比例顯示。
- **彈出式留言**（#53）：直播留言改為從畫面下方浮現的小氣泡（最多 6 則，8 秒後淡出），不擋畫面。長按「留言」鈕可設定顯示、樣式（彈出式／列表）和位置（左側／右側）。
- **直播控制列**（#46、#50、#52）：改成跟一般影片一樣：播放/暫停、彈幕（長按開設定）、留言、畫質、線路、關注。上方顯示 LIVE 標記和已開播時間。按上鍵可以收起控制列。
- **多線路**（#49）：直播改用新版介面取得多個 CDN 線路與畫質。
- **設定頁**（#44）：左右切換的選項改成按 OK 開選單選值，不會再誤觸。

## 修正
- **登入失效**（#43）：伺服器端登入失效時，App 會自動刷新登入；刷新失敗就登出並提示重新登入，不再一直顯示已登入卻只有 480P。
- **直播自動重連**（#47、#57）：斷線時自動重新連線，移除「重新整理」按鈕。彈幕連線不再每 20 秒斷一次。
- **時移畫面卡住**（#56）：畫面停住 8 秒會自動跳到最新畫面，再停就重建播放器。
- **彈幕設定面板**（#45）：按左鍵會退出面板，數值項目改用選單選值。
- **長按**（#55）：長按確認鍵開設定更穩定。

## New
- **Live timeshift**: keep 5/10/30 minutes locally. With the control bar hidden, press left/right to preview with thumbnails, like normal videos.
- **Popup live chat**: small bubbles from the bottom (max 6, fade after 8 seconds). Long-press the chat button to set visibility, style and side.
- **Live control bar** matches normal videos, shows LIVE and uptime, and hides with the up key.
- **Multiple CDN lines** for live streams.
- **Settings**: left/right options now open a picker with OK.

## Fixes
- Expired logins are refreshed automatically, or you are logged out with a prompt.
- Live streams reconnect automatically; danmaku no longer disconnects every 20 seconds.
- A frozen timeshift picture now recovers by itself.
- The danmaku settings panel closes with the left key.
- Long-press on the OK key is more reliable.

## 注意
- APK 使用與之前相同的金鑰簽署，可以直接覆蓋安裝。
- 直播時移會占用儲存空間；低記憶體裝置最多 5 分鐘。
- 64 位元版的版本號比較大。電視裝過 64 位元版之後，若要改裝 32 位元版，要先解除安裝。
