正在執行 `flutter analyze`，請稍候。
正在等待 `flutter analyze` 靜態檢查完成...
root agent idle; waiting for 1 background task(s) to finish
正在等待 `flutter analyze` 重新檢查...
正在編譯 Debug APK（`flutter build apk --debug`），請稍候。
已啟動 App，等待 30 秒載入完成後進行測試。
### 修改內容摘要

1. [playback_api.dart](file:///C:/presonal_project/PiliBTRTV/lib/services/api/playback_api.dart) (`getVideoPlayUrl`):
   - 處理番劇（PGC, `epId != null`）在無 `dash` 但含有 `durl` 時的情況：解析為非 DASH 播放資訊（提取 `durl[0].url` 及備用節點網址），並回傳 `'isPreview': true`、畫質列表（`qualities`）與當前畫質（`currentQuality`）。
   - 當 `dash` 與 `durl` 皆不存在時，回傳 `{'error': '此集需要大會員或無法播放（${json['code']}）', 'apiError': true}`，確保 API 回傳 code 0 時絕不返回 null。

2. [player_action_mixin.dart](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart):
   - [`initializePlayer`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L55)、[`switchEpisode`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L1385) 與 [`switchQuality`](file:///C:/presonal_project/PiliBTRTV/lib/screens/player/mixins/player_action_mixin.dart#L1565) 統一支援非 DASH `url`，並透過 [`BtrProxy.wrap`](file:///C:/presonal_project/PiliBTRTV/lib/services/btr/btr_proxy.dart#L60) 進行本地代理與備用 CDN 封裝。
   - 統一在 `isPreview == true` 時顯示提示「此集為大會員專屬，目前僅提供試看」，試看結束不自動連播下一集。
   - 當 `playInfo == null` 時統一顯示「無法取得播放網址，請稍後再試」，替換原有的通用例外文字。

---

### 提交與檢查結果

- **Commit Hash**: `5f21da3` ("Fix: 番劇大會員集改播試看片段並顯示提示")
- **`flutter analyze`**: **PASS**（`No issues found!`）
- **`flutter build apk --debug` & `adb install`**: **PASS**（成功編譯並安裝至 `emulator-5554`）

---

### 模擬器驗證結果

- **驗證狀態**: **PASS**
- **測試截圖**:
  - [fix-ep2.png](file:///C:/presonal_project/PiliBTRTV/docs/work/player-fixes/screens/fix-ep2.png)：切換至《小林家的龍女僕》第 2 話，畫面顯示提示「此集為大會員專屬，目前僅提供試看」。
  - [fix-ep2b.png](file:///C:/presonal_project/PiliBTRTV/docs/work/player-fixes/screens/fix-ep2b.png)：5 秒後正常播放試看片段（時長 06:00，畫質 480P），無報錯中斷。
