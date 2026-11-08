# 需求：分區修正、番劇支援、QR 登入提示

日期：2026-11-08

## 使用者回報與查證

1. 只有「推薦」「熱門」有內容，番劇、影視等分區空白：`/x/web-interface/dynamic/region` 已停用，一律回 `-404 啥都木有`（curl 驗證）。新 API `/x/web-interface/region/feed/rcmd?display_id=<頁>&request_cnt=<數>&from_region=<新分區 ID>` 可用。
2. 手機掃 QR 無法登入：使用者截圖顯示手機已掃到並進入「云视听小电视」登入頁，顯示「检测到该手机号已经注册账号…登录地点：中国-台湾…是我的账号，验证登录」，是 B站的新地點驗證，需在手機上完成；手機 B站 App 版本 6.8.0（很舊）。程式本身與 PiliBTR 相同，模擬器可登入。
3. 剖析套件有問題：電視為 Android 11（Google TV，Realtek RT51）。Release APK 已驗證正常（v2 簽章、zipalign、resources.arsc 未壓縮、大小與 GitHub 一致）。推測下載不完整；本次不改程式，僅在 Release 加上分架構 APK（另議）。

## 番劇 API 查證（台灣 IP）

- `/pgc/web/rank/list?season_type=1` 的日本番劇多數回 `-10403 抱歉您所在地区不可观看！`；`season_type=4`（國創）可播。
- `/pgc/season/index/result?season_type=1&type=1&order=3&sort=0&st=1&page=&pagesize=` 回傳的熱門番劇前 10 部皆可播。
- 季資訊：`/pgc/view/web/season?season_id=`，`result.episodes[]` 含 `id`(ep_id)、`aid`、`bvid`、`cid`、`title`、`long_title`、`badge`。
- 播放：`/pgc/player/web/v2/playurl?ep_id=&cid=&qn=&fnval=4048&fnver=0&fourk=1`，回傳 `result.video_info`（DASH）。

## 驗收條件

- **AC-1**：首頁分區（影視、遊戲、知識、科技、音樂、舞蹈、生活、美食、動畫）都有影片，可捲動載入下一頁，可播放。
- **AC-2**：番劇分頁顯示番劇（封面、標題、集數資訊），來源為番劇索引熱門排序，可捲動載入。
- **AC-3**：點番劇進入播放器，播放第一集（若有觀看紀錄則從紀錄的集數與進度開始）；選集面板列出所有集數（「第 N 話 標題」），可切換。
- **AC-4**：番劇播放走 BTR 加速（MPD 流程同一般影片），可切畫質。
- **AC-5**：番劇播完自動播下一集（自動連播開啟時）；最後一集播完不跳到推薦影片。
- **AC-6**：番劇觀看進度回報（heartbeat 帶 `epid`、`sid`、`type=4`）。
- **AC-7**：地區限制或需大會員的集數，播放器顯示 B站回傳的錯誤訊息（例如「抱歉您所在地區不可觀看！」），不無限轉圈。
- **AC-8**：QR 登入頁：
  - 說明文字改為「請用 B站手機 App（建議更新至最新版）掃描；若手機要求驗證，請按『是我的帳號，驗證登入』完成驗證」。
  - 掃描後顯示「已掃描，請在手機上確認」。
  - QR Code 過期時自動產生新的。
  - 失敗時顯示 B站回傳的錯誤碼與訊息。
- **AC-9**：`flutter analyze` 無問題；模擬器驗證 AC-1～AC-5、AC-7、AC-8 的畫面。

## 不做

- 電影、電視劇、紀錄片等其他 PGC 類型（之後可沿用同一流程）。
- 解除地區限制。
- Android 5／6 相容版（待使用者回覆）。

## 限制

- 文字使用台灣繁體；與伺服器比對的簡體字串保留原文並加註解。
- 遙控器可操作。
