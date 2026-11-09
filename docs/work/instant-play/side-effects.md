# initializePlayer 副作用清單（重構前，UGC 路徑）

對照欄：重構後執行位置（P = PlaybackPreparer 只回傳資料；A = `_adoptPlayback` 接手端；I = initializePlayer）

| # | 副作用 | 重構後 |
|---|---|---|
| 1 | setState isLoading=true、errorMessage=null、hasHandledVideoComplete=false | I（不變） |
| 2 | 只有 epId 沒 seasonId 的轉番劇、getPgcSeason | I（不變） |
| 3 | getVideoInfo + mark('videoInfo') | P（未被接手時 I 先取，傳入 P）|
| 4 | redirect_url 轉番劇（_redirectToPgc） | I（未被接手時）；暖機的 P 回傳 redirect 並靜默丟棄 |
| 5 | PlaybackProgressCache.getCachedRecord | P |
| 6 | setState fullVideoInfo、episodes | A |
| 7 | cid 優先序（API history > 本地快取 > info.cid > pages[0] > getVideoCid）、debugPrint | P（cid 回傳，A 設定 state）|
| 8 | aid = videoInfo['aid'] | A |
| 9 | _fetchOnlineCount + onlineCountTimer 60 秒（videoInfo != null 才做） | A |
| 10 | mark('cid')；cid null -> errorMessage='獲取影片資訊失敗' | P 回傳 error；I 設定 |
| 11 | loadVideoshot() | A |
| 12 | focusedEpisodeIndex | A |
| 13 | getRelatedVideos -> relatedVideos | A |
| 14 | 編碼重試清單、codecFallbackAvc 略過 | P |
| 15 | takePlayUrl（只在 tryCodec==null）、resolvePlayInfo、mark('playInfo')、apiError break | P |
| 16 | isPreview、試看 toast | A |
| 17 | qualities、currentQuality、currentCodec、currentAudioUrl、previewFrameUrl | A（currentCodec/currentQuality 由 playInfo 取）|
| 18 | MpdGenerator + LocalServer.setMpdContent / BtrProxy.wrap | P（取消時不寫）|
| 19 | 建 controller（viewType 依設定）、initialize 重試 3 次、mark('initialize') | P（暖機固定 textureView、不重試）|
| 20 | 解碼器錯誤：setCodecFallbackAvc(true) + toast + continue codecLoop | P，warm 時不寫設定、不 toast、直接失敗 |
| 21 | _setupPlayerListeners | A |
| 22 | PluginManager onVideoLoad | A |
| 23 | setState isLoading=false | A |
| 24 | 續播進度計算（API history + cid 比對、本地快取、列表 progress、播完不續播） | P（回傳 resumeSeconds，並 seek）|
| 25 | initialProgress、seekTo、resetDanmakuIndex、「從xx繼續播放」toast | A（接手暖機時以目前位置為準）|
| 26 | play()、mark('play')、startHideTimer | A |
| 27 | loadDanmaku | A |
| 28 | catch：errorMessage、isLoading=false | I |
| 29 | 新增：mark('adopted')、setVolume(1.0)（接手暖機時）| A |
