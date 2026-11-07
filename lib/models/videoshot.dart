import 'dart:typed_data';

/// 影片快照(雪碧圖)資料模型
class VideoshotData {
  final List<String> images;
  final int imgXLen; // 對應 JS 中的 i
  final int imgYLen; // 對應 JS 中的 n
  final int imgXSize; // 對應 JS 中的 a (perImgW)
  final int imgYSize; // 對應 JS 中的 s (perImgH)
  final String? pvdataUrl;
  List<int>? _frameTimestamps;

  int get framesPerImage => imgXLen * imgYLen; // 對應 JS 中的 l

  VideoshotData({
    required this.images,
    required this.imgXLen,
    required this.imgYLen,
    required this.imgXSize,
    required this.imgYSize,
    this.pvdataUrl,
  });

  factory VideoshotData.fromJson(Map<String, dynamic> json) {
    return VideoshotData(
      images:
          (json['image'] as List?)
              ?.map((e) => _fixUrl(e.toString()))
              .toList() ??
          [],
      imgXLen: json['img_x_len'] as int? ?? 10,
      imgYLen: json['img_y_len'] as int? ?? 10,
      imgXSize: json['img_x_size'] as int? ?? 160,
      imgYSize: json['img_y_size'] as int? ?? 90,
      pvdataUrl: json['pvdata'] != null ? _fixUrl(json['pvdata']) : null,
    );
  }

  static String _fixUrl(String url) {
    if (url.startsWith('//')) return 'https:$url';
    return url;
  }

  void setTimestamps(List<int> timestamps) {
    _frameTimestamps = timestamps;
  }

  /// 1. 還原 getIndex 演算法
  /// 對應 JS: getIndex = function(t) { ... i = o - 1; ... return i >= 0 && i || 0; }
  int getIndex(Duration position) {
    if (_frameTimestamps == null || _frameTimestamps!.isEmpty) return 0;

    final double seconds = position.inMilliseconds / 1000.0;
    final timestamps = _frameTimestamps!;

    // 預設值：JS 中 i = t.length - 2
    int resultIdx = timestamps.length - 2;

    // 對應 JS 迴圈: for (var o = 0; o < t.length - 1; o++)
    for (int o = 0; o < timestamps.length - 1; o++) {
      if (seconds >= timestamps[o] && seconds < timestamps[o + 1]) {
        resultIdx = o - 1; // 關鍵：B站邏輯是索引再減1
        break;
      }
    }

    // 對應 JS: return i >= 0 && i || 0;
    return resultIdx >= 0 ? resultIdx : 0;
  }

  /// 2. 還原座標計算邏輯
  /// 對應 JS: d = r % l % i * a; (X座標)
  /// 對應 JS: u = Math.floor(r % l / n) * s; (Y座標)
  FrameInfo? getFrameAt(Duration position) {
    if (images.isEmpty) return null;

    // 獲取幀索引 r
    final int r = getIndex(position);

    // 每張大圖的總幀數 l
    final int l = framesPerImage;

    // 計算在大圖列表中的圖片索引 (第幾張大圖)
    // 對應 JS: c = t[Math.floor(r / l)]
    int imageIndex = (r / l).floor();
    if (imageIndex >= images.length) imageIndex = images.length - 1;

    // 計算在單張大圖內部的偏移
    // 對應 JS X座標: d = r % l % i * a
    // i 是 imgXLen (列數), a 是 imgXSize (寬)
    final int x = (r % l % imgXLen) * imgXSize;

    // Y座標: 標準行主序佈局，除以列數 (xLen)
    // Python: y = math.floor((r % l) / self.x_len) * self.per_img_h
    final int y = ((r % l) ~/ imgXLen) * imgYSize;

    return FrameInfo(
      imageUrl: images[imageIndex],
      x: x,
      y: y,
      width: imgXSize,
      height: imgYSize,
    );
  }

  /// 獲取最接近給定位置的幀時間戳
  /// 用於時間吸附功能，確保預覽位置對齊到實際幀
  Duration getClosestTimestamp(Duration position) {
    if (_frameTimestamps == null || _frameTimestamps!.isEmpty) {
      return position;
    }

    final double seconds = position.inMilliseconds / 1000.0;
    final timestamps = _frameTimestamps!;

    // 找到最接近的時間戳
    int closestIdx = 0;
    double minDiff = (timestamps[0] - seconds).abs();

    for (int i = 1; i < timestamps.length; i++) {
      final diff = (timestamps[i] - seconds).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestIdx = i;
      }
    }

    return Duration(seconds: timestamps[closestIdx]);
  }

  /// 3. 解析 pvdata.bin
  /// 嚴格按照 JS 的 Uint8 移位解析（Big-Endian）
  static List<int> parsePvdata(Uint8List bytes) {
    final timestamps = <int>[];
    for (var i = 0; i < bytes.length - 1; i += 2) {
      // 對應 JS: var r = i.getUint8(s) << 8 | i.getUint8(s + 1);
      final value = (bytes[i] << 8) | bytes[i + 1];
      timestamps.add(value);
    }
    return timestamps;
  }
}

class FrameInfo {
  final String imageUrl;
  final int x;
  final int y;
  final int width;
  final int height;

  FrameInfo({
    required this.imageUrl,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}
