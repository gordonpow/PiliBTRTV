import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// 裝置音訊能力（杜比 E-AC3／Atmos、FLAC），第一次使用時查詢並快取。
class AudioSupport {
  AudioSupport._();

  static const _channel = MethodChannel('com.bili.tv/codec');

  static bool _dolbyOk = false;
  // 查詢失敗時 FLAC 視為支援（Android 8.1+ 內建軟體解碼）
  static bool _hiresOk = true;
  static Future<void>? _loading;

  /// 杜比可用：E-AC3 或 E-AC3-JOC 其一支援即可
  static bool get dolbyOk => _dolbyOk;
  static bool get hiresOk => _hiresOk;

  /// 確保已查詢過一次（可重複呼叫）
  static Future<void> ensure() => _loading ??= _query();

  /// 測試用：直接指定結果
  static void setForTest({required bool dolby, required bool hires}) {
    _dolbyOk = dolby;
    _hiresOk = hires;
    _loading = Future.value();
  }

  static Future<void> _query() async {
    try {
      final r = await _channel
          .invokeMethod<Map>('getAudioSupport')
          .timeout(const Duration(seconds: 2));
      if (r != null) {
        _dolbyOk = r['eac3'] == true || r['eac3Joc'] == true;
        _hiresOk = r['flac'] != false;
      }
      debugPrint('🔊 [AudioSupport] dolby=$_dolbyOk hires=$_hiresOk');
    } catch (e) {
      debugPrint('🔊 [AudioSupport] query failed: $e');
      _dolbyOk = false;
      _hiresOk = true;
    }
  }
}
