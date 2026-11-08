### 1. `img_x_size` / `img_y_size` 與更高解析度參數
* **一般尺寸**：橫向（16:9）影片固定為 **160x90**，直向影片為 **90x160**。
* **能否取得更大縮圖**：**沒有任何參數可取得更大解析度**（查無 480x270 來源）。因為雪碧圖是影片上傳後由轉碼伺服器預先切片拼版，並固化為靜態檔案儲存於 BFS CDN（`//i0.hdslb.com/bfs/videoshot/`），伺服器不支援即時縮放。

---

### 2. 是否有其他高解析度端點？
* **結論：查無更高解析度的官方雪碧圖來源。**
* **`x/player/v2/videoshot`**：官方並不存在此端點。
* **`index=1`**：僅控制回傳資料中是否附加 JSON 格式的 `index` 陣列，圖檔 URL 與 160x90 解析度完全不變。
* **APP 端 / PGC 番劇**：APP 端與 PGC 取得各話 `cid` 後，底層皆共用同一個 `x/player/videoshot` 接口與相同的靜態圖檔，沒有獨立的高畫質預覽圖來源。

---

### 3. pvdata.bin 格式與「索引再減 1」
* **資料格式**：二進位檔案每 2 位元組（2 Bytes）為一組，代表一個 16-bit 無符號整數（**大端序 Big-Endian**，單位為秒）。
* **為什麼要減 1**：**確實必須減 1**。因 B 站輸出的時間戳陣列開頭固定有兩個 0（例如 `[0, 0, 8, 14, ...]`）。網頁播放器比對區間 `seconds >= timestamps[o] && seconds < timestamps[o+1]` 時，第 0 幀（0～8 秒）匹配到的下標是 `o = 1`。因此必須計算 `o - 1 = 0`，才能精準對應至雪碧圖第 0 張小圖。

---

### 參考來源
* [bilibili-API-collect 鏡像 - snapshot.md](https://github.com/SocialSisterYi/bilibili-API-collect)
* [Bilibili API 參考文件 (snapshot.html)](https://bili.s1f.ren/docs/video/snapshot.html)
