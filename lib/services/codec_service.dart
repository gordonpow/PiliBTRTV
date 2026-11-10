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

  /// 讀取播放器診斷統計（解碼器、輸入格式、掉幀數）；失敗回 null
  static Future<Map<String, dynamic>?> getPlayerStats({
    bool drain = true,
  }) async {
    try {
      final r = await _channel.invokeMethod('getPlayerStats', {'drain': drain});
      return r == null ? null : Map<String, dynamic>.from(r as Map);
    } catch (e) {
      return null;
    }
  }

  /// 解碼器能力診斷：隧道支援、可達幀率、效能點；失敗回 null。
  /// [decoderName] 有值時優先查該解碼器（目前播放中的）。
  static Future<Map<String, dynamic>?> getDecoderCaps({
    required String codec,
    required int width,
    required int height,
    required double fps,
    String? decoderName,
  }) async {
    try {
      final r = await _channel.invokeMethod('decoderCaps', {
        'codec': codec,
        'width': width,
        'height': height,
        'fps': fps,
        'decoderName': decoderName,
      });
      return r == null ? null : Map<String, dynamic>.from(r as Map);
    } catch (e) {
      return null;
    }
  }

  /// 效能記錄用裝置資訊（ABI、核心數、記憶體等級、螢幕模式、HDR）；失敗回 null
  static Future<Map<String, dynamic>?> getPerfDeviceInfo() async {
    try {
      final r = await _channel.invokeMethod('getDeviceInfo');
      return r == null ? null : Map<String, dynamic>.from(r as Map);
    } catch (e) {
      return null;
    }
  }

  /// App 行程累計 CPU jiffies 與取樣時間；失敗回 null
  static Future<Map<String, dynamic>?> getProcessCpu() async {
    try {
      final r = await _channel.invokeMethod('getProcessCpu');
      return r == null ? null : Map<String, dynamic>.from(r as Map);
    } catch (e) {
      return null;
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

  // 快取解析度／幀率檢查結果
  static final Map<String, bool> _hwDecodeCache = {};
  static bool? _hdrDisplay;

  /// 檢查是否有同一個硬體解碼器支援指定編碼、解析度與幀率
  /// [codec]: avc / hevc / av1；[fps] <= 0 表示不檢查幀率。失敗時回 true（不阻擋）
  static Future<bool> canHwDecode(
    String codec,
    int width,
    int height,
    double fps,
  ) async {
    final key = '$codec:$width:$height:$fps';
    final cached = _hwDecodeCache[key];
    if (cached != null) return cached;
    try {
      final result = await _channel.invokeMethod<bool>('canHwDecode', {
        'codec': codec,
        'width': width,
        'height': height,
        'fps': fps,
      });
      return _hwDecodeCache[key] = result ?? true;
    } catch (e) {
      return true;
    }
  }

  /// 顯示器是否支援 HDR；失敗時回 false
  static Future<bool> isHdrDisplay() async {
    final cached = _hdrDisplay;
    if (cached != null) return cached;
    try {
      final result = await _channel.invokeMethod<bool>('isHdrDisplay');
      return _hdrDisplay = result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 由 codecs 字串判斷編碼家族：avc / hevc / av1，其他回 null
  static String? codecFamily(String codecs) {
    final c = codecs.toLowerCase();
    if (c.startsWith('avc')) return 'avc';
    if (c.startsWith('hev') || c.startsWith('hvc') || c.startsWith('dvh')) {
      return 'hevc';
    }
    if (c.startsWith('av01') || c.startsWith('av1')) return 'av1';
    return null;
  }

  /// 解析幀率：接受 num 或字串（"29.970"、"30000/1001"），失敗回 0
  static double parseFps(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is! String) return 0;
    final s = v.trim();
    if (s.isEmpty) return 0;
    if (s.contains('/')) {
      final parts = s.split('/');
      final n = double.tryParse(parts[0].trim());
      final d = double.tryParse(parts[1].trim());
      if (n == null || d == null || d == 0) return 0;
      return n / d;
    }
    return double.tryParse(s) ?? 0;
  }
}
