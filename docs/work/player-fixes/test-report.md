I have launched the application and am waiting for the splash screen initialization to complete.
I have reopened the video and am waiting for playback to initialize and controls to hide.
I have opened the search result video and am waiting for it to play.
### 測試結果總覽

| 測試項目 | 結果 | 截圖 / 檔案名稱 | 備註說明 |
| :--- | :---: | :--- | :--- |
| **1. 分區 Tabs** | **PASS** | [`t1-game.png`](file:///C:/presonal_project/PiliBTRTV/docs/work/player-fixes/screens/t1-game.png) | 遊戲與科技分區皆正常載入影片列表，非空狀態。 |
| **2. 番劇 Tab** | **PASS** | [`t2-bangumi.png`](file:///C:/presonal_project/PiliBTRTV/docs/work/player-fixes/screens/t2-bangumi.png) | 正常列出《小林家的龍女僕》、《工作細胞》等多張番劇卡片。 |
| **3. 第一部番劇播放** | **PASS** | [`t3-play.png`](file:///C:/presonal_project/PiliBTRTV/docs/work/player-fixes/screens/t3-play.png) | 開啟《小林家的龍女僕》第 1 話，20 秒內順利起播且彈幕正常捲動。 |
| **4. 番劇選集切換** | **FAIL** | [`t4-episodes.png`](file:///C:/presonal_project/PiliBTRTV/docs/work/player-fixes/screens/t4-episodes.png)<br>[`t4b.png`](file:///C:/presonal_project/PiliBTRTV/docs/work/player-fixes/screens/t4b.png) | 選集面板正常展示「第 N 話 …」；但切換至第 2 話時因會員專屬限制及 playurl 解析拋出「切換失敗: Exception: 獲取播放地址失敗」。 |
| **5. Netflix 式快進快退** | **PASS** | [`t5-seek.png`](file:///C:/presonal_project/PiliBTRTV/docs/work/player-fixes/screens/t5-seek.png)<br>[`t5b.png`](file:///C:/presonal_project/PiliBTRTV/docs/work/player-fixes/screens/t5b.png)<br>[`t5c.png`](file:///C:/presonal_project/PiliBTRTV/docs/work/player-fixes/screens/t5c.png) | 連按右鍵 3 次出現進度預覽條且未立即跳轉；按確認鍵後跳轉播放；按左鍵 2 次後按返回鍵成功取消跳轉並恢復原位播放。 |
| **6. 一般影片搜尋與播放** | **PASS** | [`t6.png`](file:///C:/presonal_project/PiliBTRTV/docs/work/player-fixes/screens/t6.png) | 搜尋「lol」並開啟首項結果（T1 vs KC），影片正常載入並順暢播放。 |
| **7. Logcat 收集** | **PASS** | [`logcat-test.txt`](file:///C:/presonal_project/PiliBTRTV/docs/work/player-fixes/logcat-test.txt) | 已完整過濾 `flutter|Exception|BTR` 並輸出至指定文字檔。 |

---

### 例外與錯誤日誌節錄 (Verbatim)

```log
11-08 05:21:06.986 18912 18912 I flutter : BTR: node banned upos-sz-mirror08c.bilivideo.com
11-08 05:21:06.986 18912 18912 I flutter : BTR: piece 663325 retry on upos-sz-mirror08c.bilivideo.com: DioException [connection error]: The connection errored: Failed host lookup: 'upos-sz-mirror08c.bilivideo.com' This indicates an error which most likely cannot be solved by the library.
11-08 05:21:06.986 18912 18912 I flutter : Error: SocketException: Failed host lookup: 'upos-sz-mirror08c.bilivideo.com' (OS Error: No address associated with hostname, errno = 7)
11-08 05:21:10.292 18912 18912 I flutter : BTR: node banned upos-sz-mirrorali.bilivideo.com
11-08 05:21:10.292 18912 18912 I flutter : BTR: piece 977638 retry on upos-sz-mirrorali.bilivideo.com: DioException [connection timeout]: The request connection took longer than 0:00:04.000000 and it was aborted.
11-08 05:37:34.318 18912 18938 E flutter : [ERROR:flutter/impeller/entity/contents/contents.cc(119)] Break on 'ImpellerValidationBreak' to inspect point of failure: Contents::SetInheritedOpacity should never be called when Contents::CanAcceptOpacity returns false.
```
