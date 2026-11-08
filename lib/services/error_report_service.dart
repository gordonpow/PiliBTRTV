import 'dart:ui' show PlatformDispatcher;

import 'package:bili_tv_app/btr_version.dart';
import 'package:bili_tv_app/services/auth_service.dart';
import 'package:bili_tv_app/services/btr/btr_config.dart';
import 'package:bili_tv_app/services/log_service.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

/// 組出去識別化的錯誤報告並上傳到公開貼文服務。
class ErrorReportService {
  ErrorReportService._();

  static const MethodChannel _channel = MethodChannel('com.bili.tv/update');
  static const Duration _timeout = Duration(seconds: 15);

  static Future<String> buildReport() async {
    final b = StringBuffer();
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
    b.writeln('App 語言設定: ${SettingsService.appLanguage} (0 跟隨系統, 1 繁體, 2 簡體)');

    b.writeln();
    b.writeln('== 設定摘要 ==');
    b.writeln('BTR 多執行緒播放: ${BtrConfig.playback ? '開' : '關'}');
    b.writeln('CDN 模式: ${BtrConfig.cdnMode.name}');
    b.writeln(
      '執行緒: ${BtrConfig.autoThreads ? '自動' : '手動'} (${BtrConfig.playbackThreads})',
    );
    b.writeln('硬體解碼: ${SettingsService.useHardwareDecode ? '開' : '關'}');
    b.writeln('首選編碼: ${SettingsService.preferredCodec.name}');
    b.writeln('已登入: ${AuthService.isLoggedIn ? '是' : '否'}');

    b.writeln();
    b.writeln('== 最近 log ==');
    for (final line in await LogService.recentLines()) {
      b.writeln(line);
    }
    return b.toString();
  }

  /// 依序嘗試 dpaste.com、paste.rs，成功回傳網址，全部失敗則丟出例外。
  static Future<String> upload(String text) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: _timeout,
        sendTimeout: _timeout,
        receiveTimeout: _timeout,
        responseType: ResponseType.plain,
        headers: {'User-Agent': 'BiliTV-ErrorReport'},
      ),
    );
    Object? lastError;

    try {
      final res = await dio.post<String>(
        'https://dpaste.com/api/v2/',
        data: {'content': text, 'syntax': 'text', 'expiry_days': 30},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final url = res.data?.trim() ?? '';
      if (url.startsWith('http')) return url;
      lastError = '回應格式不正確';
    } catch (e) {
      lastError = e;
    }

    try {
      final res = await dio.post<String>(
        'https://paste.rs/',
        data: text,
        options: Options(contentType: 'text/plain; charset=utf-8'),
      );
      final url = res.data?.trim() ?? '';
      if (url.startsWith('http')) return url;
      lastError = '回應格式不正確';
    } catch (e) {
      lastError = e;
    }

    throw Exception('上傳失敗：$lastError');
  }
}
