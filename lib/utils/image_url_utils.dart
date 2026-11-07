class ImageUrlUtils {
  /// 獲取最佳化後的圖片 URL
  ///
  /// [url] 原始圖片 URL
  /// [width] 目標寬度
  /// [height] 目標高度 (可選)
  ///
  /// Bilibili 圖片處理引數格式: @{width}w_{height}h_1c.webp
  /// 1c 表示啟用裁剪
  static String getResizedUrl(
    String url, {
    int? width,
    int? height,
    int quality = 90,
  }) {
    if (url.isEmpty) return url;
    if (url.contains('@')) return url; // 已經包含處理引數，不再處理

    // 只需要 webp 格式 (B站支援)
    String suffix = '';

    if (width != null && height != null) {
      suffix = '@${width}w_${height}h_1c.webp';
    } else if (width != null) {
      suffix = '@${width}w.webp';
    } else {
      // 如果沒有指定尺寸，預設轉為 webp 以減小體積
      suffix = '@.webp';
    }

    return '$url$suffix';
  }
}
