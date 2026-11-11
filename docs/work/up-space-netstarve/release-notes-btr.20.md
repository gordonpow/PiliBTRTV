Android TV 版第三方 B站用戶端，基於 BiliTV，加上「線程撕裂者」（BTR）多 CDN 播放加速。
An unofficial third-party Bilibili client for Android TV with BTR multi-CDN acceleration.

## 下載哪一個？ / Which APK?
- `PiliBTRTV-v1.2.2-btr.20-arm64-v8a.apk`：64 位元，大多數較新的電視盒和電視用這個。Most modern TVs and boxes.
- `PiliBTRTV-v1.2.2-btr.20-armeabi-v7a.apk`：32 位元，64 位元版裝不上時改用這個。Older 32-bit systems.
- 從 App 內更新，或從 [F-Droid 套件庫](https://gordonpow.github.io/fdroid/) 安裝更新。In-app update or the F-Droid repo.

## 修正
- 從關注列表或我的空間進 UP 主頁，選影片會跳回上一頁（#36）。
- 網路速度不足時一直緩衝（#37）：
  - 32 位元電視播 4K 不再自動改成直連，BTR 只依「設定 → 線程撕裂者」的開關。
  - 播放中網路不足時，若 CPU 還有餘裕且執行緒為「自動」，會先自動增加 BTR 執行緒；仍不足才降一級畫質（最低 1080P，手動選過畫質只會提示）。

## 變更
- 版本名稱改為帶 btr 編號（例如 1.2.2-btr.20），在系統的 App 資訊與 F-Droid 中可以分辨版本。

## Fixes
- Selecting a video on an uploader's page opened from the following list jumped back instead of playing.
- Constant buffering on slow networks: 4K on 32-bit TVs no longer bypasses BTR automatically; when the network can't keep up, BTR threads are increased first (auto mode, CPU permitting), then quality is lowered one step.

## 注意
- APK 使用與 btr.6 以前相同的金鑰簽署，可以直接覆蓋安裝。
- 64 位元版的版本號比較大。電視裝過 64 位元版之後，若要改裝 32 位元版，要先解除安裝。
