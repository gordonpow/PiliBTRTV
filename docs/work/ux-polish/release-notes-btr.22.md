Android TV 版第三方 B站用戶端，基於 BiliTV，加上「線程撕裂者」（BTR）多 CDN 播放加速。
An unofficial third-party Bilibili client for Android TV with BTR multi-CDN acceleration.

## 下載哪一個？ / Which APK?
- `PiliBTRTV-v1.2.2-btr.22-arm64-v8a.apk`：64 位元，大多數較新的電視盒和電視用這個。Most modern TVs and boxes.
- `PiliBTRTV-v1.2.2-btr.22-armeabi-v7a.apk`：32 位元，64 位元版裝不上時改用這個。Older 32-bit systems.
- 從 App 內更新或 F-Droid 套件庫更新時，會自動選擇符合裝置的版本。In-app update and the F-Droid repo pick the right one automatically.

## 改善
- **遙控器操作更直覺**（#40）：播放時的簡介面板在「簡介」分頁按左鍵即可關閉；登出等確認對話框開啟時有預設焦點；另外整理了多處按鍵方向與焦點位置不符合直覺的地方。
- **過場動畫**（#41）：面板、對話框、分頁切換等原本瞬間出現的畫面加上淡入與滑入效果。記憶體較少的裝置會自動關閉動畫，避免卡頓。

## Improvements
- **More intuitive remote control**: press Left on the Description tab to close the info panel; confirmation dialogs (such as sign-out) now have a default focus; several other focus and direction quirks are fixed.
- **Transitions**: panels, dialogs and tab switches now fade and slide in. Animations are turned off automatically on low-memory devices.

## 注意
- APK 使用與之前相同的金鑰簽署，可以直接覆蓋安裝。
- 64 位元版的版本號比較大。電視裝過 64 位元版之後，若要改裝 32 位元版，要先解除安裝。
