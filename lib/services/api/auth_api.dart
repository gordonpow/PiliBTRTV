import 'dart:convert';
import 'package:http/http.dart' as http;
import 'base_api.dart';
import 'sign_utils.dart';
import '../auth_service.dart';

/// 認證相關 API
class AuthApi {
  /// 獲取使用者資訊 (頭像、暱稱等)
  static Future<void> fetchAndSaveUserInfo() async {
    if (!AuthService.isLoggedIn) return;

    try {
      final response = await http.get(
        Uri.parse('${BaseApi.apiBase}/x/web-interface/nav'),
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'];
          final face = data['face'] as String? ?? '';
          final uname = data['uname'] as String? ?? '';

          // 解析 VIP 狀態
          // vipStatus: 0=無, 1=大會員
          // vipType: 0=無, 1=月度, 2=年度及以上
          final vipData = data['vip'];
          final isVip = (vipData != null && (vipData['status'] == 1));

          if (face.isNotEmpty) {
            await AuthService.saveUserInfo(
              face: face,
              uname: uname,
              isVip: isVip,
            );
          }
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
  }

  /// 生成 TV 登入二維碼
  static Future<Map<String, String>?> generateTvQrCode() async {
    try {
      final params = SignUtils.signForTvLogin({'local_id': '0'});

      final uri = Uri.parse(
        '${BaseApi.passportBase}/x/passport-tv-login/qrcode/auth_code',
      ).replace(queryParameters: params);

      final response = await http.post(uri, headers: BaseApi.getHeaders());

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          return {
            'url': json['data']['url'] ?? '',
            'auth_code': json['data']['auth_code'] ?? '',
          };
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return null;
  }

  /// 輪詢 TV 登入狀態
  /// 返回: {'status': 'success'|'waiting'|'scanned'|'expired'|'error'|'network', ...}
  static Future<Map<String, dynamic>> pollTvLogin(String authCode) async {
    try {
      final params = SignUtils.signForTvLogin({
        'auth_code': authCode,
        'local_id': '0',
      });

      final uri = Uri.parse(
        '${BaseApi.passportBase}/x/passport-tv-login/qrcode/poll',
      ).replace(queryParameters: params);

      final response = await http.post(uri, headers: BaseApi.getHeaders());

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
            return {
              'status': 'error',
              'code': code,
              'message': json['message'] ?? '',
            };
        }
      }
      return {
        'status': 'error',
        'code': response.statusCode,
        'message': 'HTTP ${response.statusCode}',
      };
    } catch (e) {
      // 網路錯誤，呼叫端會繼續輪詢
      return {'status': 'network'};
    }
  }
}
