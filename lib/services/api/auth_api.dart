import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_sign.dart';
import 'base_api.dart';
import '../auth_service.dart';

/// Cookie 值是否安全（避免標頭注入）：不可含空白、分號、引號、反斜線或控制字元
bool isSafeCookieValue(String v) =>
    RegExp(r'^[^\s;"\\\x00-\x1f\x7f]+$').hasMatch(v);

const _webLoginFields = ['SESSDATA', 'bili_jct', 'DedeUserID'];

/// 手動切分網址原始 query（不做 URL 解碼），只取登入需要的欄位
Map<String, String> _rawWebLoginQuery(String url) {
  final q = url.indexOf('?');
  final result = <String, String>{};
  if (q < 0) return result;
  for (final part in url.substring(q + 1).split('&')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    final name = part.substring(0, i);
    if (_webLoginFields.contains(name) && !result.containsKey(name)) {
      result[name] = part.substring(i + 1);
    }
  }
  return result;
}

/// 解析網頁版掃碼成功後 `data.url` 的 Cookie。
/// 不做 URL 解碼，保留 `%2C` 等原樣（與瀏覽器 Cookie 值一致）。
/// 缺欄位、值不安全或 DedeUserID 非數字時回傳 null。
Map<String, String>? parseWebLoginCookies(String url) =>
    validateWebLoginCookies(_rawWebLoginQuery(url));

/// 驗證登入 Cookie：三個欄位都要有、值安全、DedeUserID 為數字。
/// 通過回傳只含三個欄位的新 Map，否則回傳 null。
Map<String, String>? validateWebLoginCookies(Map<String, String> m) {
  final result = <String, String>{};
  for (final f in _webLoginFields) {
    final v = m[f];
    if (v == null || v.isEmpty || !isSafeCookieValue(v)) return null;
    result[f] = v;
  }
  if (!RegExp(r'^\d+$').hasMatch(result['DedeUserID']!)) return null;
  return result;
}

/// nav 檢查結果：ok 正常、invalid 伺服器回 -101（登入失效）、unknown 其他（網路錯誤等）
enum NavCheck { ok, invalid, unknown }

/// refresh_token 結果：ok 成功、rejected 伺服器明確拒絕、unknown 網路錯誤或限流
enum RefreshResult { ok, rejected, unknown }

/// 啟動時登入狀態驗證結果
enum SessionCheck { valid, expired, unknown }

/// 認證相關 API
class AuthApi {
  /// 呼叫 /x/web-interface/nav（cookie），回傳三態結果與 data（僅 ok 時有值）。
  static Future<(NavCheck, Map<String, dynamic>?)> _checkNav() async {
    if (!AuthService.isLoggedIn) return (NavCheck.unknown, null);
    try {
      final response = await http.get(
        Uri.parse('${BaseApi.apiBase}/x/web-interface/nav'),
        headers: BaseApi.getHeaders(withCookie: true),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] is Map) {
          return (NavCheck.ok, Map<String, dynamic>.from(json['data'] as Map));
        }
        debugPrint(
          'TvLogin: 取得使用者資訊失敗 code=${json['code']} message=${json['message']}',
        );
        if (json['code'] == -101) return (NavCheck.invalid, null);
      } else {
        debugPrint('TvLogin: 取得使用者資訊失敗 HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('TvLogin: 取得使用者資訊例外 ${e.runtimeType}');
    }
    return (NavCheck.unknown, null);
  }

  /// 呼叫 /x/web-interface/nav（cookie），成功回傳 data，失敗回傳 null。
  /// 個人頁與 [fetchAndSaveUserInfo] 共用，避免各自解析。
  static Future<Map<String, dynamic>?> fetchNavData() async =>
      (await _checkNav()).$2;

  /// 獲取使用者資訊 (頭像、暱稱等)
  static Future<void> fetchAndSaveUserInfo() async {
    final data = await fetchNavData();
    await _saveNavData(data);
  }

  static Future<void> _saveNavData(Map<String, dynamic>? data) async {
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

  /// 啟動時驗證登入狀態：
  /// nav 正常則更新使用者資訊；-101 時嘗試 refresh_token，
  /// 失敗（被拒絕或沒有 refresh_token）則登出並回傳 expired；
  /// 其他錯誤（網路、限流）一律不動登入狀態。
  static Future<SessionCheck> validateSession() async {
    if (!AuthService.isLoggedIn) return SessionCheck.unknown;
    final (check, data) = await _checkNav();
    switch (check) {
      case NavCheck.ok:
        await _saveNavData(data);
        return SessionCheck.valid;
      case NavCheck.unknown:
        return SessionCheck.unknown;
      case NavCheck.invalid:
        break;
    }

    final access = AuthService.accessToken;
    final refresh = AuthService.refreshToken;
    if (access == null ||
        access.isEmpty ||
        refresh == null ||
        refresh.isEmpty) {
      debugPrint('TvLogin: 登入失效且無 refresh_token，清除登入狀態');
      await AuthService.logout();
      return SessionCheck.expired;
    }

    final result = await refreshTvToken();
    if (result == RefreshResult.unknown) return SessionCheck.unknown;
    if (result == RefreshResult.rejected) {
      await AuthService.logout();
      return SessionCheck.expired;
    }

    // refresh 成功，用新 Cookie 再查一次
    final (check2, data2) = await _checkNav();
    switch (check2) {
      case NavCheck.ok:
        await _saveNavData(data2);
        return SessionCheck.valid;
      case NavCheck.unknown:
        return SessionCheck.unknown;
      case NavCheck.invalid:
        await AuthService.logout();
        return SessionCheck.expired;
    }
  }

  /// 以 refresh_token 換新 access_token 與 Cookie（TV 登入）。
  /// log 只記 code 與 message，不記任何 token 或 Cookie 值。
  static Future<RefreshResult> refreshTvToken() async {
    final access = AuthService.accessToken;
    final refresh = AuthService.refreshToken;
    if (access == null || access.isEmpty || refresh == null || refresh.isEmpty) {
      return RefreshResult.rejected;
    }
    try {
      final params = AppSign.appSign({
        'access_key': access,
        'refresh_token': refresh,
        'local_id': '0',
        'mobi_app': 'android_hd',
        'platform': 'android',
        'build': '2001100',
      }).map((k, v) => MapEntry(k, v.toString()));

      final response = await http
          .post(
            Uri.parse(
              '${BaseApi.passportBase}/x/passport-login/oauth2/refresh_token',
            ),
            headers: _hdHeaders(),
            body: params,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('TvLogin: refresh 失敗 HTTP ${response.statusCode}');
        return RefreshResult.unknown;
      }
      final json = jsonDecode(response.body);
      final code = json['code'];
      if (code != 0) {
        debugPrint('TvLogin: refresh 失敗 code=$code message=${json['message']}');
        // 限流類錯誤不代表憑證失效
        if (code == -412 || code == -509 || code == -799) {
          return RefreshResult.unknown;
        }
        return RefreshResult.rejected;
      }

      final data = json['data'];
      final tokenInfo = data is Map ? data['token_info'] : null;
      final cookieInfo = data is Map ? data['cookie_info'] : null;
      if (tokenInfo is! Map || cookieInfo is! Map) {
        debugPrint('TvLogin: refresh 回應缺少 token_info 或 cookie_info');
        return RefreshResult.rejected;
      }
      final newAccess = tokenInfo['access_token'];
      final newRefresh = tokenInfo['refresh_token'];
      final mid = BaseApi.toInt(tokenInfo['mid']);
      final cookies = cookieInfo['cookies'];
      var hasSess = false;
      if (cookies is List) {
        for (final c in cookies) {
          if (c is Map &&
              c['name'] == 'SESSDATA' &&
              c['value'] is String &&
              (c['value'] as String).isNotEmpty) {
            hasSess = true;
          }
        }
      }
      if (newAccess is! String ||
          newAccess.isEmpty ||
          newRefresh is! String ||
          newRefresh.isEmpty ||
          mid <= 0 ||
          !hasSess) {
        debugPrint('TvLogin: refresh 回應欄位缺漏');
        return RefreshResult.rejected;
      }

      await AuthService.saveLoginCredentials(
        accessToken: newAccess,
        refreshToken: newRefresh,
        mid: mid,
        cookieInfo: Map<String, dynamic>.from(cookieInfo),
      );
      debugPrint('TvLogin: refresh 成功');
      return RefreshResult.ok;
    } catch (e) {
      debugPrint('TvLogin: refresh 例外 ${e.runtimeType}');
      return RefreshResult.unknown;
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

  // ========== 網頁版掃碼登入 ==========

  static Map<String, String> _webQrHeaders() => {
    ...BaseApi.getHeaders(),
    'Referer': 'https://www.bilibili.com/',
  };

  /// 生成網頁版登入二維碼，回傳 {'url', 'qrcode_key'}，失敗回傳 null
  static Future<Map<String, String>?> generateWebQrCode() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${BaseApi.passportBase}/x/passport-login/web/qrcode/generate',
            ),
            headers: _webQrHeaders(),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final data = json['data'];
        if (json['code'] == 0 && data is Map) {
          final url = data['url'];
          final key = data['qrcode_key'];
          if (url is String &&
              url.isNotEmpty &&
              key is String &&
              key.isNotEmpty) {
            debugPrint('WebLogin: 產生 QR 成功');
            return {'url': url, 'qrcode_key': key};
          }
        }
        debugPrint('WebLogin: 產生 QR 失敗 code=${json['code']}');
      } else {
        debugPrint('WebLogin: 產生 QR 失敗 HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('WebLogin: 產生 QR 例外 ${e.runtimeType}');
    }
    return null;
  }

  /// 輪詢網頁版登入狀態。status：waiting / scanned / expired / success / error / network
  static Future<Map<String, dynamic>> pollWebQrLogin(String key) async {
    try {
      final uri = Uri.parse(
        '${BaseApi.passportBase}/x/passport-login/web/qrcode/poll',
      ).replace(queryParameters: {'qrcode_key': key});
      // 改用 dart:io HttpClient：http 套件會把多個 Set-Cookie 以逗號合併
      // （Expires 本身也含逗號），無法可靠切分，因此直接讀 response.cookies
      final client = HttpClient();
      final int statusCode;
      final String body;
      final headerCookies = <String, String>{};
      try {
        final result = await () async {
          final req = await client.getUrl(uri);
          _webQrHeaders().forEach((k, v) => req.headers.set(k, v));
          final res = await req.close();
          final text = await res.transform(utf8.decoder).join();
          return (res, text);
        }().timeout(const Duration(seconds: 15));
        final res = result.$1;
        statusCode = res.statusCode;
        body = result.$2;
        try {
          // Cookie.value 不做解碼，%2C 等保留原樣
          for (final c in res.cookies) {
            if (_webLoginFields.contains(c.name) &&
                c.value.isNotEmpty &&
                !headerCookies.containsKey(c.name)) {
              headerCookies[c.name] = c.value;
            }
          }
        } catch (e) {
          debugPrint('WebLogin: 讀取 Set-Cookie 例外 ${e.runtimeType}');
        }
      } finally {
        client.close(force: true);
      }
      if (statusCode != 200) {
        debugPrint('WebLogin: 輪詢失敗 HTTP $statusCode');
        return {'status': 'network'};
      }
      final json = jsonDecode(body);
      final data = json['data'];
      if (json['code'] != 0 || data is! Map) {
        debugPrint(
          'WebLogin: 輪詢錯誤 code=${json['code']} message=${json['message']}',
        );
        return {
          'status': 'error',
          'code': json['code'],
          'message': json['message'] ?? '',
        };
      }
      final code = data['code'];
      switch (code) {
        case 86101:
          return {'status': 'waiting'};
        case 86090:
          return {'status': 'scanned'};
        case 86038:
          return {'status': 'expired'};
        case 0:
          final url = data['url'];
          final raw = url is String ? url : '';
          final q = _rawWebLoginQuery(raw);
          // 優先用 Set-Cookie，缺的欄位再用 data.url 補
          final merged = <String, String>{};
          for (final f in _webLoginFields) {
            final v = headerCookies[f] ?? q[f];
            if (v != null) merged[f] = v;
          }
          final cookies = validateWebLoginCookies(merged);
          if (cookies == null) {
            final missing = _webLoginFields
                .where((f) => (merged[f] ?? '').isEmpty)
                .toList();
            final detail = missing.isEmpty
                ? '欄位格式不正確'
                : '缺少 ${missing.join('、')}';
            // 只記欄位名稱，不記任何值、qrcode_key 或完整網址
            final parsed = Uri.tryParse(raw);
            final where = parsed == null ? '?' : '${parsed.host}${parsed.path}';
            final urlNames = raw.contains('?')
                ? raw
                      .substring(raw.indexOf('?') + 1)
                      .split('&')
                      .map((p) => p.split('=').first)
                      .toList()
                : <String>[];
            debugPrint(
              'WebLogin: 解析 Cookie 失敗 $detail；'
              'url 欄位=[${urlNames.join(',')}]；'
              'Set-Cookie=[${headerCookies.keys.join(',')}]；'
              'url 主機=$where',
            );
            return {
              'status': 'error',
              'code': 0,
              'message': 'Cookie 解析失敗：$detail',
            };
          }
          return {'status': 'success', 'cookies': cookies};
        default:
          debugPrint('WebLogin: 輪詢錯誤 code=$code message=${data['message']}');
          return {
            'status': 'error',
            'code': code,
            'message': data['message'] ?? '',
          };
      }
    } catch (e) {
      debugPrint('WebLogin: 輪詢例外 ${e.runtimeType}');
      return {'status': 'network'};
    }
  }

  /// 帶 Cookie 呼叫 /x/member/web/account，確認 mid 與 DedeUserID 相符。任何失敗回傳 false。
  static Future<bool> verifyWebCookies(Map<String, String> cookies) async {
    try {
      final headers = BaseApi.getHeaders();
      headers['Cookie'] = [
        ?headers['Cookie'],
        'SESSDATA=${cookies['SESSDATA']}',
        'bili_jct=${cookies['bili_jct']}',
        'DedeUserID=${cookies['DedeUserID']}',
      ].join('; ');
      final res = await http
          .get(
            Uri.parse('${BaseApi.apiBase}/x/member/web/account'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));
      final json = jsonDecode(res.body);
      if (json is! Map) return false;
      final data = json['data'];
      return json['code'] == 0 &&
          data is Map &&
          data['mid'].toString() == cookies['DedeUserID'];
    } catch (e) {
      debugPrint('WebLogin: 驗證 Cookie 例外 ${e.runtimeType}');
      return false;
    }
  }
}
