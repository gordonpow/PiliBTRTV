Android TV 版第三方 B站用戶端，基於 BiliTV，加上「線程撕裂者」（BTR）多 CDN 播放加速。
An unofficial third-party Bilibili client for Android TV with BTR multi-CDN acceleration.

## 下載哪一個？ / Which APK?
- `PiliBTRTV-v1.2.2-btr.16-arm64-v8a.apk`：64 位元，大多數較新的電視盒和電視用這個。Most modern TVs and boxes.
- `PiliBTRTV-v1.2.2-btr.16-armeabi-v7a.apk`：32 位元，64 位元版裝不上時改用這個。Older 32-bit systems.
- 從 App 內更新時，會自動選擇符合裝置的版本。In-app update picks the right one automatically.

## 新增
- **English 介面**（#15）：
  - 「設定 → 介面設定 → 語言」新增 English。第一次選擇時會從 GitHub 下載語言包（需要網路），之後每 7 天自動檢查更新。
  - 「跟隨系統」在非中文系統會使用英文。
  - B 站的內容（影片標題、彈幕、留言）不翻譯。
- **語言改為選單一次選定**（#15）：按確定開啟清單，選好後才提示一次重新啟動，不會每切換一次就跳出提示。
- **README 提供英文版與繁體中文版**。

## New
- **English UI**: Settings → Interface → Language → English. The language pack is downloaded from GitHub on first use and updated automatically. Restart the app to apply. Bilibili content (titles, danmaku, comments) is not translated.

## 修正
- 側邊欄「觀看歷史」按右鍵，焦點改到左上角第一張卡片，不再跳到中間（#12）。
- 搜尋結果頁可以直接重新搜尋：在排序列按上到搜尋框，按確定回到鍵盤，並帶入上次的關鍵字；對側邊欄「搜尋」再按確定也可以（#13）。
- 側邊欄「設定」按右鍵，焦點改到「播放設定」，不再跳到上次停留的分類（#14）。

## 注意
- APK 使用與 btr.6 以前相同的金鑰簽署，可以直接覆蓋安裝。
- 64 位元版的版本號比較大。電視裝過 64 位元版之後，若要改裝 32 位元版，要先解除安裝。
