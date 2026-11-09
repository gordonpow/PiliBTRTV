import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_sign.dart';
import 'base_api.dart';
import '../auth_service.dart';

/// 認證相關 API
class AuthApi {
  /// 呼叫 /x/web-interface/nav（cookie），成功回傳 data，失敗回傳 null。
  /// 個人頁與 [fetchAndSaveUserInfo] 共用，避免各自解析。
  static Future<Map<String, dynamic>?> fetchNavData() async {
    if (!AuthService.isLoggedIn) return null;
    try {
      final response = await http.get(
        Uri.parse('${BaseApi.apiBase}/x/web-interface/nav'),
        headers: BaseApi.getHeaders(withCookie: true),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] is Map) {
          return Map<String, dynamic>.from(json['data'] as Map);
        }
        debugPrint(
          'TvLogin: 取得使用者資訊失敗 code=${json['code']} message=${json['message']}',
        );
      } else {
        debugPrint('TvLogin: 取得使用者資訊失敗 HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('TvLogin: 取得使用者資訊例外 ${e.runtimeType}');
    }
    return null;
  }

  /// 獲取使用者資訊 (頭像、暱稱等)
  static Future<void> fetchAndSaveUserInfo() async {
    final data = await fetchNavData();
    if (data == null) return;
    final face = data['face'] as String? ?? '';
    final uname = data['uname'] as String? ?? '';

    // vip.status: 0=無, 1=大會員
    final vipData = data['vip'];
    final isVip = (vipData != null && (vipData['status'] == 1));

    if (face.isNotEmpty) {
      await AuthService.saveUserInfo(face: face, uname: uname, isVip: isVip);
    }
  }

  /// TV 掃碼登入用的 android_hd User-Agent（與 PiliBTR 一致）
  static const String _hdUserAgent =
      'Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android model/android_hd mobi_app/android_hd build/2001100';

  static Map<String, String> _hdHeaders() => {
    ...BaseApi.getHeaders(),
    'User-Agent': _hdUserAgent,
  };

  /// 生成 TV 登入二維碼
  static Future<Map<String, String>?> generateTvQrCode() async {
    try {
      final params = AppSign.appSign({
        'local_id': '0',
        'platform': 'android',
        'mobi_app': 'android_hd',
      }).map((k, v) => MapEntry(k, v.toString()));

      final uri = Uri.parse(
        '${BaseApi.passportBase}/x/passport-tv-login/qrcode/auth_code',
      ).replace(queryParameters: params);

      final response = await http.post(uri, headers: _hdHeaders());

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          return {
            'url': json['data']['url'] ?? '',
            'auth_code': json['data']['auth_code'] ?? '',
          };
        }
        debugPrint(
          'TvLogin: 產生 QR 失敗 code=${json['code']} message=${json['message']}',
        );
      } else {
        debugPrint('TvLogin: 產生 QR 失敗 HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('TvLogin: 產生 QR 例外 ${e.runtimeType}');
    }
    return null;
  }

  /// 輪詢 TV 登入狀態
  /// 返回: {'status': 'success'|'waiting'|'scanned'|'expired'|'error'|'network', ...}
  static Future<Map<String, dynamic>> pollTvLogin(String authCode) async {
    try {
      final params = AppSign.appSign({
        'auth_code': authCode,
        'local_id': '0',
      }).map((k, v) => MapEntry(k, v.toString()));

      final uri = Uri.parse(
        '${BaseApi.passportBase}/x/passport-tv-login/qrcode/poll',
      ).replace(queryParameters: params);

      final response = await http.post(uri, headers: _hdHeaders());

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final code = json['code'] ?? -1;

        switch (code) {
          case 0:
            final data = json['data'];
            return {
              'status': 'success',
              'access_token': data['access_token'] ?? '',
              'refresh_token': data['refresh_token'] ?? '',
              'mid': BaseApi.toInt(data['mid']),
              'cookie_info': data['cookie_info'],
            };
          case 86039:
            return {'status': 'waiting'};
          case 86090:
            return {'status': 'scanned'};
          case 86038:
            return {'status': 'expired'};
          default:
            debugPrint('TvLogin: 輪詢結果 code=$code message=${json['message']}');
            return {
              'status': 'error',
              'code': code,
              'message': json['message'] ?? '',
            };
        }
      }
      debugPrint('TvLogin: 輪詢失敗 HTTP ${response.statusCode}');
      return {
        'status': 'error',
        'code': response.statusCode,
        'message': 'HTTP ${response.statusCode}',
      };
    } catch (e) {
      // 網路錯誤，呼叫端會繼續輪詢
      debugPrint('TvLogin: 輪詢例外 ${e.runtimeType}');
      return {'status': 'network'};
    }
  }
}
