Android TV 版第三方 B站用戶端，基於 BiliTV，加上「線程撕裂者」（BTR）多 CDN 播放加速。
An unofficial third-party Bilibili client for Android TV with BTR multi-CDN acceleration.

## 下載哪一個？ / Which APK?
- `PiliBTRTV-v1.2.2-btr.17-arm64-v8a.apk`：64 位元，大多數較新的電視盒和電視用這個。Most modern TVs and boxes.
- `PiliBTRTV-v1.2.2-btr.17-armeabi-v7a.apk`：32 位元，64 位元版裝不上時改用這個。Older 32-bit systems.
- 從 App 內更新時，會自動選擇符合裝置的版本。In-app update picks the right one automatically.

## 新增
- **CC 字幕**（#17）：
  - 播放器可以顯示 B 站的 CC 字幕與 AI 字幕。控制列彈幕旁新增「字幕」按鈕：短按開關，長按選擇字幕。設定面板也有「字幕」選單。
  - 未登入也能取得大部分字幕。會記住是否開啟字幕。
- **英文介面翻譯 B 站內容**（#17）：
  - 英文介面下，影片標題、UP 主名稱、直播標題、UP 主簽名與中文字幕會在電視上用 Google ML Kit 翻譯成英文，內容不會上傳。
  - 預設開啟，第一次使用會在背景下載約 30MB 的翻譯模型（需要 Google Play 服務），下載完成後標題會自動換成英文。可在「設定 → 介面設定 → 翻譯 B 站內容」關閉。
  - 影片沒有英文字幕時，字幕選單多一項「English（機器翻譯）」。
- **未登入也能收藏**（#20）：
  - 未登入時按☆會存到電視上的本機收藏夾，可以建立多個收藏夾，在「觀看歷史 → 收藏」管理與播放。
  - 登入後如果有本機收藏，會詢問是否加入帳號的預設收藏夾。

## 變更
- 控制列☆改為開啟收藏夾選單，套用後顯示收藏到哪些資料夾（#19）。
- 播放器設定「播放完畢後」改用次級選單（#16）。
- 控制列按鈕間距調整。

## New
- **CC subtitles**: Bilibili CC/AI subtitles with a subtitle button next to the danmaku button (press to toggle, hold to choose a track). Works without logging in for most videos.
- **Translate Bilibili content (English UI)**: video titles, uploader names, live titles and Chinese subtitles are translated on-device with Google ML Kit (about 30MB model, downloaded in the background; requires Google Play services). Can be turned off in Settings → Interface.
- **Local favorites**: without logging in, favorites are saved on the TV in your own folders; after logging in you can import them into your account.

## 注意
- 這版 APK 約增加 16～17MB（翻譯功能的原生程式庫）。
- APK 使用與 btr.6 以前相同的金鑰簽署，可以直接覆蓋安裝。
- 64 位元版的版本號比較大。電視裝過 64 位元版之後，若要改裝 32 位元版，要先解除安裝。
