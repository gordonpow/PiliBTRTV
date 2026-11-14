Android TV 版第三方 B站用戶端，基於 BiliTV，加上「線程撕裂者」（BTR）多 CDN 播放加速。
An unofficial third-party Bilibili client for Android TV with BTR multi-CDN acceleration.

## 下載哪一個？ / Which APK?
- `PiliBTRTV-v1.2.2-btr.26-arm64-v8a.apk`：64 位元，大多數較新的電視盒和電視用這個。Most modern TVs and boxes.
- `PiliBTRTV-v1.2.2-btr.26-armeabi-v7a.apk`：32 位元，64 位元版裝不上時改用這個。Older 32-bit systems.
- 從 App 內更新或 F-Droid 套件庫更新時，會自動選擇符合裝置的版本。In-app update and the F-Droid repo pick the right one automatically.

## 新功能
- **手機一鍵投放**（#61）：在 PiliBTR 手機版（v2.2.14 以上）的影片頁按「投放」，選這台電視，電視就從手機目前的進度接著播同一部影片（同一 P／同一集），正在播別的影片時也會直接切換。
  - 第一次投放時電視會詢問「允許 <手機名稱>（IP）投放影片到這臺電視？」，預設焦點在「拒絕」，30 秒沒回應視為拒絕。允許後這支手機之後投放不再詢問。
  - 設定 → 外掛中心 → **投放配對**：顯示 QR code 與 IP，手機找不到電視時可以掃描或手動輸入；也可以在這裡移除已配對的手機。

## 改進
- **切換卡片更順**（#60）：在影片列表移動焦點時，關閉上一張卡片的預覽不再卡住畫面（原本每次約停 0.1～0.3 秒），焦點動畫不會瞬間掉幀。彈幕改在背景解析，預載時不占用畫面執行緒。

## New
- **Cast from phone**: in PiliBTR (v2.2.14 or later), tap Cast on the video page and pick this TV. The TV plays the same video and part or episode from the phone's position, and switches even if something else is playing. The first cast asks for permission on the TV (default: deny, 30-second timeout). Settings → Plugins → 投放配對 shows a QR code and the IP for phones that cannot find the TV, and lets you remove paired phones.
- **Smoother card navigation**: closing the previous card's preview no longer freezes the screen for 0.1–0.3 seconds, so the focus animation stays smooth. Danmaku is now parsed in the background.

## 注意
- 投放使用區網內的 http。只有在電視上允許過的手機能讓電視播放；路由器開啟裝置隔離時無法投放。
- APK 使用與之前相同的金鑰簽署，可以直接覆蓋安裝。
- 64 位元版的版本號比較大。電視裝過 64 位元版之後，若要改裝 32 位元版，要先解除安裝。
