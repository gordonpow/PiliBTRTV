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

  /// 總幀數
  int get frameCount {
    if (_frameTimestamps != null && _frameTimestamps!.isNotEmpty) {
      final count = _frameTimestamps!.length - 1;
      return count > 0 ? count : 0;
    }
    return images.length * framesPerImage;
  }

  /// 依播放位置獲取幀索引 (等同 getIndex)
  /// 尚未載入 pvdata 時間戳時，依 [total] 均勻換算（[total] 未提供則回傳 0）。
  int indexAt(Duration pos, [Duration? total]) {
    if (_frameTimestamps != null && _frameTimestamps!.isNotEmpty) {
      return getIndex(pos);
    }
    final count = frameCount;
    if (count <= 0 || total == null || total <= Duration.zero) return 0;
    final k = (pos.inMilliseconds * count / total.inMilliseconds).floor();
    return k.clamp(0, count - 1);
  }

  /// 依幀索引計算對應的影片時間
  Duration timeOfIndex(int k, Duration total) {
    if (frameCount == 0 || total <= Duration.zero) {
      return Duration.zero;
    }
    final clampedK = k.clamp(0, frameCount - 1);
    if (_frameTimestamps != null && _frameTimestamps!.length > 1) {
      return Duration(seconds: _frameTimestamps![clampedK + 1]);
    }
    return Duration(
      milliseconds: (total.inMilliseconds * clampedK / frameCount).round(),
    );
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

  /// 2. 依幀索引計算雪碧圖位置
  FrameInfo? frameAtIndex(int k) {
    if (images.isEmpty || k < 0 || k >= frameCount) return null;

    final int l = framesPerImage;
    if (l <= 0 || imgXLen <= 0) return null;

    int imageIndex = k ~/ l;
    if (imageIndex >= images.length) imageIndex = images.length - 1;

    final int x = (k % l % imgXLen) * imgXSize;
    final int y = ((k % l) ~/ imgXLen) * imgYSize;

    return FrameInfo(
      imageUrl: images[imageIndex],
      x: x,
      y: y,
      width: imgXSize,
      height: imgYSize,
    );
  }

  /// 獲取指定播放位置的快照資訊
  FrameInfo? getFrameAt(Duration position) {
    return frameAtIndex(indexAt(position));
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
