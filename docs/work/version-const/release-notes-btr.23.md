Android TV 版第三方 B站用戶端，基於 BiliTV，加上「線程撕裂者」（BTR）多 CDN 播放加速。
An unofficial third-party Bilibili client for Android TV with BTR multi-CDN acceleration.

## 下載哪一個？ / Which APK?
- `PiliBTRTV-v1.2.2-btr.23-arm64-v8a.apk`：64 位元，大多數較新的電視盒和電視用這個。Most modern TVs and boxes.
- `PiliBTRTV-v1.2.2-btr.23-armeabi-v7a.apk`：32 位元，64 位元版裝不上時改用這個。Older 32-bit systems.
- 從 App 內更新或 F-Droid 套件庫更新時，會自動選擇符合裝置的版本。In-app update and the F-Droid repo pick the right one automatically.

## 修正
- **更新提示一直出現**（#42）：btr.21、btr.22 的 App 內版本號仍顯示 btr.20，所以裝了新版還是一直提示更新，錯誤回報的版本也不對。更新到這版後就會恢復正常。
- 功能與 btr.22 相同（遙控器操作整理、過場動畫）。

## Fixes
- **Update prompt kept appearing**: btr.21 and btr.22 still reported themselves as btr.20, so the app kept offering an update and error reports showed the wrong version. Installing this version fixes it.
- Features are the same as btr.22.

## 注意
- APK 使用與之前相同的金鑰簽署，可以直接覆蓋安裝。
- 64 位元版的版本號比較大。電視裝過 64 位元版之後，若要改裝 32 位元版，要先解除安裝。
