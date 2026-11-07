import 'package:flutter/services.dart';

/// 編解碼器服務 - 查詢裝置硬體解碼能力
class CodecService {
  static const _channel = MethodChannel('com.bili.tv/codec');

  // 快取硬體解碼器列表
  static List<String>? _hardwareDecoders;

  /// 獲取裝置支援的硬體解碼格式
  /// 返回: ['avc', 'hevc', 'av1', 'vp9'] 等
  static Future<List<String>> getHardwareDecoders() async {
    if (_hardwareDecoders != null) {
      return _hardwareDecoders!;
    }

    try {
      final result = await _channel.invokeMethod('getHardwareDecoders');
      _hardwareDecoders = List<String>.from(result ?? []);
      return _hardwareDecoders!;
    } catch (e) {
      // 如果查詢失敗，返回空列表（將使用所有編碼器）
      return [];
    }
  }

  /// 檢查是否支援指定格式的硬體解碼
  static Future<bool> hasHardwareDecoder(String codec) async {
    final decoders = await getHardwareDecoders();
    return decoders.contains(codec.toLowerCase());
  }

  /// 檢查是否支援 H.264 硬解
  static Future<bool> hasAvcHardware() => hasHardwareDecoder('avc');

  /// 檢查是否支援 HEVC 硬解
  static Future<bool> hasHevcHardware() => hasHardwareDecoder('hevc');

  /// 檢查是否支援 AV1 硬解
  static Future<bool> hasAv1Hardware() => hasHardwareDecoder('av1');
}
