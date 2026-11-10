你是 Android 影片播放與 MediaCodec 專家。請用繁體中文（台灣用語）回答，800 字以內。只讀檔案，不要修改任何檔案。

## 背景
Flutter Android TV App（C:\presonal_project\PiliBTRTV）。播放器是 ExoPlayer（覆寫套件 packages/video_player_android），使用 MediaCodec 硬體解碼。使用者的電視是 Sony BRAVIA 4K VH22：Android 12、32 位元（armeabi-v7a）、4 核、MediaTek 晶片。播 B 站 4K60 影片會嚴重掉幀。同一台電視上的 B 站官方 App 播 4K（含 HDR）很順。

## 使用者回報的效能資料（兩份報告內容相同，節錄）
```
== 播放效能 ==
16:16:07 32 位元裝置 4K 略過 BTR
16:16:10 播放開始 abi=android_arm cores=4 memClass=192MB lowRam=false display=3840x2160@60.0Hz hdr=true 視圖=相容 btr=不用 彈幕=開
16:16:10 支援螢幕模式 3840x2160@60.0
16:16:10 串流 qn=120 codec=av01.0.00M.x.x.x.x.01.01.0 3840x2160@59.94fps bw=13243kbps decoder=OMX.MTK.VIDEO.DECODER.AV1 hw=true
16:16:20 事件 開始緩衝 累計=1次
16:16:20 事件 解碼器初始化 name=OMX.MTK.VIDEO.DECODER.AV1 hw=true 耗時=1392ms
16:16:20 事件 影片格式改變 3840x2160@-1.0
16:16:20 事件 結束緩衝 持續=2612ms 累計=1次
16:16:20 事件 開始緩衝 累計=2次
16:16:20 事件 結束緩衝 持續=5462ms 累計=2次
16:16:20 t=793s drop=100/100 (16.7%) offset=0us rendered=49 buf=39.8s bw=110Mbps cpu=18%
16:16:30 t=803s drop=538/638 (89.8%) offset=0us rendered=131 buf=52.2s bw=117Mbps cpu=11%
16:16:30 事件 自動降畫質 120->116 區間掉幀率=16.7%,89.8%
16:16:31 播放開始 abi=android_arm cores=4 memClass=192MB lowRam=false display=3840x2160@60.0Hz hdr=true 視圖=相容 btr=用 彈幕=開
16:16:31 支援螢幕模式 3840x2160@60.0
16:16:31 串流 qn=116 codec=av01.0.00M.x.x.x.x.01.01.0 1920x1080@59.94fps bw=3563kbps decoder=OMX.MTK.VIDEO.DECODER.AV1 hw=true
16:16:41 事件 開始緩衝 累計=1次
16:16:41 事件 解碼器初始化 name=OMX.MTK.VIDEO.DECODER.AV1 hw=true 耗時=149ms
16:16:41 事件 影片格式改變 1920x1080@-1.0
16:16:41 事件 結束緩衝 持續=304ms 累計=1次
16:16:41 事件 開始緩衝 累計=2次
16:16:41 事件 結束緩衝 持續=1617ms 累計=2次
16:16:41 t=811s drop=0/0 (0.0%) offset=0us rendered=505 buf=33.9s bw=515Mbps cpu=23%
16:16:51 t=821s drop=0/0 (0.0%) offset=0us rendered=1105 buf=53.9s bw=19Mbps cpu=24%
16:17:30 32 位元裝置 4K 略過 BTR
16:17:36 播放開始 abi=android_arm cores=4 memClass=192MB lowRam=false display=3840x2160@60.0Hz hdr=true 視圖=原生 btr=不用 彈幕=開
16:17:36 支援螢幕模式 3840x2160@60.0
16:17:36 串流 qn=120 codec=av01.0.00M.x.x.x.x.01.01.0 3840x2160@59.94fps bw=13243kbps decoder=OMX.MTK.VIDEO.DECODER.AV1 hw=true
16:17:46 事件 開始緩衝 累計=1次
16:17:46 事件 解碼器初始化 name=OMX.MTK.VIDEO.DECODER.AV1 hw=true 耗時=4566ms
16:17:46 事件 影片格式改變 3840x2160@-1.0
16:17:46 事件 結束緩衝 持續=5118ms 累計=1次
16:17:46 事件 開始緩衝 累計=2次
16:17:46 事件 結束緩衝 持續=2804ms 累計=2次
16:17:46 事件 開始緩衝 累計=3次
16:17:56 事件 結束緩衝 持續=6850ms 累計=3次
16:17:56 t=807s drop=278/324 (46.4%) offset=0us rendered=94 buf=53.5s bw=45Mbps cpu=14%
16:18:06 t=817s drop=519/843 (86.6%) offset=0us rendered=176 buf=52.7s bw=38Mbps cpu=11%
16:18:06 事件 自動降畫質 120->116 區間掉幀率=46.4%,86.6%
16:18:07 播放開始 abi=android_arm cores=4 memClass=192MB lowRam=false display=3840x2160@60.0Hz hdr=true 視圖=原生 btr=用 彈幕=開
16:18:07 支援螢幕模式 3840x2160@60.0
16:18:07 串流 qn=116 codec=av01.0.00M.x.x.x.x.01.01.0 1920x1080@59.94fps bw=3563kbps decoder=OMX.MTK.VIDEO.DECODER.AV1 hw=true
```
欄位說明：
- drop＝區間掉幀數／總幀數
- rendered＝累計顯示幀數
- 視圖＝相容（TextureView）或原生（SurfaceView/platform view）

## 程式現況
- 編碼選擇在 lib/services/api/playback_api.dart 約 :200-280。選「自動」時，順序是 AV1 > HEVC > AVC。
- 能否硬解的判斷在 android/app/src/main/kotlin/com/bili/tv/bili_tv_app/MainActivity.kt 的 `canHwDecode`（約 :165），只用 `VideoCapabilities.areSizeAndRateSupported`。
- 掉幀過多時會自動降一級畫質（player_action_mixin.dart 的「自動降畫質」）。

## 新資料：改用 HEVC 後一樣卡
```
串流 qn=120 codec=hev1.1.6.L153.90 3840x2160@59.94fps bw=15919kbps decoder=OMX.MTK.VIDEO.DECODER.HEVC hw=true
視圖=相容：drop=276/276 (46.0%)、517/793 (86.3%)
視圖=原生：drop=144/145 (24.0%)、544/689 (90.8%)，rendered 約 8–15fps，cpu 11–16%，buf 20–52s
1080p60 HEVC：drop 0%
```
「原生」用的是 `PlatformViewsService.initSurfaceAndroidView` 包一個 SurfaceView（`exoPlayer.setVideoSurfaceView`）；「相容」用的是 Flutter Texture（SurfaceTexture）。

## 我的初步判斷
AV1 和 HEVC 的 4K60 都只能顯示約 10fps，兩種視圖都一樣，CPU 很低，緩衝也充足。我懷疑 MTK 電視晶片在非隧道（non-tunneled）路徑上，4K60 輸出跟不上；官方 App 可能用了 tunneled playback。另一種可能：Flutter 的 platform view 實際上仍然經過 GPU 合成（TLHC 或 HC）。

## 請回答
1. 你同意這個判斷嗎？有沒有其他可能？例如：
   - AV1 film grain
   - 10-bit／HDR 轉換
   - tunneled playback（ExoPlayer `setTunnelingEnabled`，需要 SurfaceView 與 audio session）
   - 輸出 Surface 的格式
   - 顯示模式切換（4K60 輸出）
   - ExoPlayer 的 `MediaCodecVideoRenderer` 設定
   - OMX 與 Codec2 的差異
2. 官方 App 可能用了什麼做法才會順暢？例如：
   - 偏好 HEVC
   - tunneling
   - 直接用 SurfaceView
3. 建議怎麼修？
   - 「自動」選編碼的策略。
   - `getAchievableFrameRatesFor`／`PerformancePoint` 是否可靠。
   - 掉幀時，先換編碼還是先降畫質。
   - 有沒有該開的 ExoPlayer 選項。
4. 要確認你的判斷，還需要從使用者的裝置收集哪些資料？
