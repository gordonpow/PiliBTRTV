import 'dart:convert';
import 'package:http/http.dart' as http;
import 'base_api.dart';
import 'sign_utils.dart';
import '../auth_service.dart';

/// 使用者互動相關 API (點贊/投幣/收藏/關注)
class InteractionApi {
  /// 點贊/取消點贊
  static Future<bool> likeVideo({required int aid, required bool like}) async {
    if (!AuthService.isLoggedIn) return false;
    try {
      final csrf = AuthService.biliJct ?? '';
      if (csrf.isEmpty) return false;

      final response = await http.post(
        Uri.parse('${BaseApi.apiBase}/x/web-interface/archive/like'),
        headers: {
          ...BaseApi.getHeaders(withCookie: true),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'aid=$aid&like=${like ? 1 : 2}&csrf=$csrf',
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['code'] == 0;
      }
    } catch (e) {
      // 忽略錯誤
    }
    return false;
  }

  /// 檢查是否已點贊
  static Future<bool> checkLikeStatus(int aid) async {
    if (!AuthService.isLoggedIn) return false;
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/archive/has/like',
      ).replace(queryParameters: {'aid': aid.toString()});
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['code'] == 0 && json['data'] == 1;
      }
    } catch (e) {
      // 忽略錯誤
    }
    return false;
  }

  /// 投幣 (APP介面，需簽名)
  static Future<String?> coinVideo({required int aid, int count = 1}) async {
    if (!AuthService.isLoggedIn) return '請先登入';
    try {
      final accessKey = AuthService.accessToken;
      if (accessKey == null || accessKey.isEmpty) {
        return 'Cookie 登入不支援投幣，請改用掃碼或密碼登入';
      }

      final params = {
        'access_key': accessKey,
        'aid': aid.toString(),
        'multiply': count.toString(),
        'select_like': '0',
      };

      final signedParams = SignUtils.signForTvLogin(params);

      final queryString = signedParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final uri = Uri.parse('https://app.bilibili.com/x/v2/view/coin/add');

      final response = await http.post(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: queryString,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          return null; // 成功
        } else {
          return json['message'] ?? '投幣失敗 (${json['code']})';
        }
      }
      return 'HTTP ${response.statusCode}';
    } catch (e) {
      return '網路錯誤: $e';
    }
  }

  /// 檢查已投幣數
  static Future<int> checkCoinStatus(int aid) async {
    if (!AuthService.isLoggedIn) return 0;
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/archive/coins',
      ).replace(queryParameters: {'aid': aid.toString()});
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          return json['data']['multiply'] ?? 0;
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return 0;
  }

  /// 收藏/取消收藏
  static Future<bool> favoriteVideo({
    required int aid,
    required bool favorite,
  }) async {
    if (!AuthService.isLoggedIn) return false;
    try {
      final csrf = AuthService.biliJct ?? '';
      if (csrf.isEmpty) return false;

      final folderId = await _getDefaultFolderId();
      if (folderId == null) return false;

      final addIds = favorite ? folderId.toString() : '';
      final delIds = favorite ? '' : folderId.toString();

      final response = await http.post(
        Uri.parse('${BaseApi.apiBase}/x/v3/fav/resource/deal'),
        headers: {
          ...BaseApi.getHeaders(withCookie: true),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body:
            'rid=$aid&type=2&add_media_ids=$addIds&del_media_ids=$delIds&csrf=$csrf',
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['code'] == 0;
      }
    } catch (e) {
      // 忽略錯誤
    }
    return false;
  }

  /// 獲取預設收藏夾 ID
  static Future<int?> _getDefaultFolderId() async {
    try {
      final mid = AuthService.mid;
      if (mid == null) return null;

      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/v3/fav/folder/created/list-all',
      ).replace(queryParameters: {'up_mid': mid.toString()});
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final list = json['data']['list'] as List?;
          if (list != null && list.isNotEmpty) {
            return list[0]['id'];
          }
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return null;
  }

  /// 檢查是否已收藏
  static Future<bool> checkFavoriteStatus(int aid) async {
    if (!AuthService.isLoggedIn) return false;
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/v2/fav/video/favoured',
      ).replace(queryParameters: {'aid': aid.toString()});
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          return json['data']['favoured'] == true;
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return false;
  }

  /// 關注/取消關注 UP主
  static Future<bool> followUser({
    required int mid,
    required bool follow,
  }) async {
    if (!AuthService.isLoggedIn) return false;
    try {
      final csrf = AuthService.biliJct ?? '';
      if (csrf.isEmpty) return false;

      final response = await http.post(
        Uri.parse('${BaseApi.apiBase}/x/relation/modify'),
        headers: {
          ...BaseApi.getHeaders(withCookie: true),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'fid=$mid&act=${follow ? 1 : 2}&csrf=$csrf',
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['code'] == 0;
      }
    } catch (e) {
      // 忽略錯誤
    }
    return false;
  }

  /// 檢查是否已關注
  static Future<bool> checkFollowStatus(int mid) async {
    if (!AuthService.isLoggedIn) return false;
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/relation',
      ).replace(queryParameters: {'fid': mid.toString()});
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final attribute = json['data']['attribute'] ?? 0;
          return attribute == 2 || attribute == 6;
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return false;
  }
}
