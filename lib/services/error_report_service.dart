import 'dart:ui' show PlatformDispatcher;

import 'package:bili_tv_app/btr_version.dart';
import 'package:bili_tv_app/services/auth_service.dart';
import 'package:bili_tv_app/services/btr/btr_config.dart';
import 'package:bili_tv_app/services/log_service.dart';
import 'package:bili_tv_app/services/perf_log.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:flutter/services.dart';

/// 組出去識別化的錯誤報告。
class ErrorReportService {
  ErrorReportService._();

  static const MethodChannel _channel = MethodChannel('com.bili.tv/update');

  /// 裝置摘要（給回報用）：device 為「廠牌 型號」，android 為「版本 (SDK n)」。
  static Future<Map<String, String>> deviceSummary() async {
    try {
      final info = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getDeviceInfo',
      );
      if (info != null) {
        return {
          'device': '${info['manufacturer']} ${info['model']}',
          'android': '${info['release']} (SDK ${info['sdk']})',
        };
      }
    } catch (_) {}
    return {'device': '', 'android': ''};
  }

  static Future<String> buildReport({String? crashSection}) async {
    final b = StringBuffer();
    if (crashSection != null && crashSection.trim().isNotEmpty) {
      b.writeln(crashSection.trim());
      b.writeln();
    }
    b.writeln('== App ==');
    b.writeln('版本: $btrVersion');

    Map<dynamic, dynamic>? info;
    try {
      info = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getDeviceInfo',
      );
    } catch (_) {}
    if (info != null) {
      b.writeln('Android: ${info['release']} (SDK ${info['sdk']})');
      b.writeln('裝置: ${info['manufacturer']} ${info['model']}');
      final abis = info['abis'];
      b.writeln('CPU 架構: ${abis is List ? abis.join(', ') : abis}');
    } else {
      b.writeln('裝置資訊: 無法取得');
    }

    final views = PlatformDispatcher.instance.views;
    if (views.isNotEmpty) {
      final v = views.first;
      b.writeln(
        '螢幕: ${v.physicalSize.width.round()}x${v.physicalSize.height.round()}'
        ' (dpr ${v.devicePixelRatio.toStringAsFixed(2)})',
      );
    }
    b.writeln('系統語言: ${PlatformDispatcher.instance.locale.toLanguageTag()}');
    b.writeln(
      'App 語言設定: ${SettingsService.appLanguage} (0 跟隨系統, 1 繁體, 2 簡體, 3 English)',
    );

    b.writeln();
    b.writeln('== 設定摘要 ==');
    b.writeln('BTR 多執行緒播放: ${BtrConfig.playback ? '開' : '關'}');
    b.writeln('CDN 模式: ${BtrConfig.cdnMode.name}');
    b.writeln(
      '執行緒: ${BtrConfig.autoThreads ? '自動' : '手動'} (${BtrConfig.playbackThreads})',
    );
    b.writeln(
      '畫面模式: ${SettingsService.playerTextureView ? 'textureView' : 'platformView'}',
    );
    b.writeln('硬體解碼: ${SettingsService.useHardwareDecode ? '開' : '關'}');
    b.writeln('隧道播放: ${SettingsService.playerTunneling ? '開' : '關'}');
    b.writeln('首選編碼: ${SettingsService.preferredCodec.name}');
    b.writeln('已登入: ${AuthService.isLoggedIn ? '是' : '否'}');

    b.writeln();
    b.writeln('== 播放效能 ==');
    for (final line in PerfLog.lines) {
      b.writeln(line);
    }

    b.writeln();
    b.writeln('== 最近 log ==');
    for (final line in await LogService.recentLines()) {
      b.writeln(line);
    }
    return b.toString();
  }
}
