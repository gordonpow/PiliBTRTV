Android TV 版第三方 B站用戶端，基於 BiliTV，加上「線程撕裂者」（BTR）多 CDN 播放加速。
An unofficial third-party Bilibili client for Android TV with BTR multi-CDN acceleration.

## 下載哪一個？ / Which APK?
- `PiliBTRTV-v1.2.2-btr.27-arm64-v8a.apk`：64 位元，大多數較新的電視盒和電視用這個。Most modern TVs and boxes.
- `PiliBTRTV-v1.2.2-btr.27-armeabi-v7a.apk`：32 位元，64 位元版裝不上時改用這個。Older 32-bit systems.
- 從 App 內更新或 F-Droid 套件庫更新時，會自動選擇符合裝置的版本。In-app update and the F-Droid repo pick the right one automatically.

## 新功能
- **App 未開啟時也能投放**（#62）：設定 → 外掛中心 → 投放配對 →「App 未開啟時也接收投放」（預設關閉）。開啟後電視會常駐一個小服務，開機和更新後自動啟動。已配對的手機投放時，電視會自動開啟 App 並從手機的進度接著播；App 在背景（按了 Home 鍵）時也會回到前景播放。
  - Android 10 以上要授權「顯示在其他應用程式上層」，App 才能從背景開啟畫面。設定頁有「前往授權」按鈕；電視沒有這個授權頁時，會顯示用電腦執行的 adb 指令。
  - 未配對的手機只會把 App 叫起來，手機再投放一次後，照原本的方式在電視上按「允許」配對。
  - App 開著時，投放的行為跟之前一樣。

## New
- **Cast while the app is closed**: Turn on the new switch in the cast pairing page under the plugin settings (off by default). A small background service starts at boot and after updates. When a paired phone casts, the TV opens the app and continues from the phone's position. If the app is in the background, it comes back to the front.
  - Android 10 and later need the "Display over other apps" permission. The settings page has a button for it, or shows an adb command if the TV has no such page.
  - An unpaired phone only wakes the app; cast again to pair as before.

## 注意
- APK 使用與之前相同的金鑰簽署，可以直接覆蓋安裝。
- 新增權限：前景服務、開機啟動、顯示在其他應用程式上層。功能關閉時不會啟動服務。
- 電視待機時，系統可能關閉網路或停止服務，此時無法投放。
- 64 位元版的版本號比較大。電視裝過 64 位元版之後，若要改裝 32 位元版，要先解除安裝。
