# 需求：官方授權番劇「獲取影片資訊失敗」與 4K 卡頓

日期：2026-11-08

## 目標

使用者回報兩個問題：

1. 觀看官方授權影片（例如《銀魂》）時，畫面顯示「獲取影片資訊失敗」。
2. 觀看 4K 畫質影片時很卡頓。

本次讓番劇影片從任何入口都能以番劇模式播放，並讓自動選擇的畫質與編碼不超過裝置的硬體解碼能力，同時改善 4K 高碼率時的 BTR 代理下載。

## 已確認的事實

- 「獲取影片資訊失敗」只出現在一般影片（UGC）路徑：`lib/screens/player/mixins/player_action_mixin.dart:118-123`，原因是 `cid == null`。
- 番劇的 `Video` 只有番劇索引（`Video.fromBangumiIndex`）會設定 `seasonId`。歷史紀錄（`Video.fromHistory`）沒有處理 `history.business == 'pgc'`，所以會把番劇當成一般影片開啟。
- 以台灣 IP 測試：`x/web-interface/view?bvid=BV1aD4y1D7Fa`（銀魂第 1 集）回傳 `code 0`，並帶 `redirect_url: https://www.bilibili.com/bangumi/play/ep326317`；`pgc/view/web/season?ep_id=326317` 回傳 `season_id 33577`。
- 大會員進入影片時，程式一律自動升到 `accept_quality` 的最高畫質（`player_action_mixin.dart:207-248`），可能是 4K、HDR、杜比視界或 8K，不檢查裝置能否解碼。
- 硬體解碼器偵測（`MainActivity.kt:94-122`）只看是否有該編碼的硬體解碼器，不看支援的最大解析度與幀率。
- BTR 播放加速預設開啟，自動執行緒數固定 8（`btr_config.dart:62`），與影片碼率無關。

## 使用者決定（2026-11-08）

- 4K 卡頓原因不明（網路或解碼），兩種都處理。
- 大會員自動升級畫質：保留，但上限為裝置能硬體解碼的畫質。

## 驗收條件

- **AC-1**：在歷史紀錄點選番劇項目（`business == 'pgc'`），以番劇模式播放（有選集列表、走 PGC playurl），不顯示「獲取影片資訊失敗」。
- **AC-2**：從任何入口（熱門、推薦、搜尋、相關影片、動態、歷史）開啟一個 view API 帶 `redirect_url` 指向 `/bangumi/play/ep<id>` 或 `/bangumi/play/ss<id>` 的 bvid 時，播放器改以番劇模式開啟該番劇。
- **AC-3**：番劇資訊可用 `ep_id` 查詢（沒有 `season_id` 時）。
- **AC-4**：自動編碼（設定為「自動」）時，只選擇硬體解碼器支援該串流解析度與幀率的編碼；同一畫質都不支援時，維持現有的兜底行為。
- **AC-5**：大會員自動升級畫質時，目標畫質不超過裝置能硬體解碼的最高畫質；HDR（125）與杜比視界（126）只在顯示器支援 HDR 時才自動升級。升級後的串流不能硬解時，改用升級前的結果。
- **AC-6**：BTR 自動執行緒模式下，碼率 ≥ 8 Mbps 的串流使用 16 個執行緒，其他維持 8 個。
- **AC-7**：`flutter analyze` 沒有新增問題，release APK 可以建置。

## 不做的範圍

- 使用者在畫質選單手動選的畫質：不限制（使用者自己的選擇）。
- 使用者在設定中指定編碼（非「自動」）：不改行為。
- BTR 代理搬到背景 isolate：本次不做，列為後續選項。
- 搜尋結果加入番劇（`media_bangumi`）類型：不做。
- 功能測試（實機／模擬器）：由使用者做。

## 限制

- Android TV，minSdk 依專案設定；`MediaCodecInfo.isHardwareAccelerated` 需要 API 29，以下用名稱判斷。
- 介面文字與註解使用繁體中文（台灣用語）。
- 伺服器回傳的簡體字串比對保留原文並加註解。
