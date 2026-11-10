import 'dart:convert';
import 'package:http/http.dart' as http;
import 'base_api.dart';
import 'package:flutter/foundation.dart';
import 'app_sign.dart';
import 'sign_utils.dart';
import '../auth_service.dart';
import '../../utils/fav_utils.dart';

/// 收藏夾與「此影片是否已在其中」
class FavFolderState {
  final int id;
  final String title;
  final int mediaCount;
  final bool faved;

  const FavFolderState({
    required this.id,
    required this.title,
    required this.mediaCount,
    required this.faved,
  });
}

/// 解析 fav/folder/created/list-all 回應；格式不符回傳 null
List<FavFolderState>? parseFavFolderStates(dynamic json) {
  if (json is! Map || json['code'] != 0) return null;
  final data = json['data'];
  if (data is! Map) return null;
  final list = data['list'];
  if (list == null) return <FavFolderState>[];
  if (list is! List) return null;
  final out = <FavFolderState>[];
  for (final e in list) {
    if (e is! Map) continue;
    final id = (e['id'] as num?)?.toInt() ?? 0;
    if (id == 0) continue;
    out.add(
      FavFolderState(
        id: id,
        title: (e['title'] ?? '').toString(),
        mediaCount: (e['media_count'] as num?)?.toInt() ?? 0,
        faved: ((e['fav_state'] as num?)?.toInt() ?? 0) == 1,
      ),
    );
  }
  return out;
}

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

      final uri = Uri.parse('https://app.bilibili.com/x/v2/view/coin/add');

      Future<http.Response> send(Map<String, dynamic> signed) {
        final queryString = signed.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}')
            .join('&');
        return http.post(
          uri,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: queryString,
        );
      }

      // 新登入的 token 來自 android_hd，優先用同一組 appkey 簽名
      var response = await send(AppSign.appSign(Map.of(params)));

      if (response.statusCode == 200) {
        var json = jsonDecode(response.body);
        final c = json['code'];
        if (c == -101 || c == -663) {
          // 舊版以 TV appkey 登入的 token，改用 TV appkey 重試一次
          debugPrint('Coin: android_hd 簽名被拒 code=$c，改用 TV 簽名重試');
          response = await send(SignUtils.signForTvLogin(Map.of(params)));
          if (response.statusCode != 200) {
            debugPrint('Coin: 重試 HTTP ${response.statusCode}');
            return 'HTTP ${response.statusCode}';
          }
          json = jsonDecode(response.body);
        }
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

  static const _formHeaders = {
    'Content-Type': 'application/x-www-form-urlencoded',
  };

  /// 取得收藏夾清單。[aid] > 0 時 fav_state 表示該影片是否已在其中；失敗回傳 null
  static Future<List<FavFolderState>?> getFavFoldersForVideo(int aid) async {
    try {
      final mid = AuthService.mid;
      if (mid == null) return null;
      final params = {'up_mid': mid.toString(), 'type': '2'};
      if (aid > 0) params['rid'] = aid.toString();
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/v3/fav/folder/created/list-all',
      ).replace(queryParameters: params);
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );
      if (response.statusCode == 200) {
        return parseFavFolderStates(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('getFavFoldersForVideo error: $e');
    }
    return null;
  }

  /// 加入／移出多個收藏夾。回傳 null 表示成功，否則為錯誤訊息
  static Future<String?> dealFavorite({
    required int aid,
    List<int> addIds = const [],
    List<int> delIds = const [],
  }) async {
    if (!AuthService.isLoggedIn) return '請先登入';
    if (addIds.isEmpty && delIds.isEmpty) return null;
    try {
      final csrf = AuthService.biliJct ?? '';
      if (csrf.isEmpty) return '登入資訊不完整，請重新登入';
      final response = await http.post(
        Uri.parse('${BaseApi.apiBase}/x/v3/fav/resource/deal'),
        headers: {...BaseApi.getHeaders(withCookie: true), ..._formHeaders},
        body:
            'rid=$aid&type=2&add_media_ids=${joinIds(addIds)}'
            '&del_media_ids=${joinIds(delIds)}&csrf=$csrf',
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) return null;
        return (json['message'] ?? '收藏失敗 (${json['code']})').toString();
      }
      return 'HTTP ${response.statusCode}';
    } catch (e) {
      return '網路錯誤';
    }
  }

  /// 加入稍後再看。回傳 null 表示成功，否則為錯誤訊息
  static Future<String?> addWatchLater(int aid) async {
    if (!AuthService.isLoggedIn) return '請先登入';
    try {
      final csrf = AuthService.biliJct ?? '';
      if (csrf.isEmpty) return '登入資訊不完整，請重新登入';
      final response = await http.post(
        Uri.parse('${BaseApi.apiBase}/x/v2/history/toview/add'),
        headers: {...BaseApi.getHeaders(withCookie: true), ..._formHeaders},
        body: 'aid=$aid&csrf=$csrf',
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) return null;
        return (json['message'] ?? '加入失敗 (${json['code']})').toString();
      }
      return 'HTTP ${response.statusCode}';
    } catch (e) {
      return '網路錯誤';
    }
  }

  /// 刪除觀看紀錄（kid 例如 archive_123、pgc_45）。回傳刪除失敗的筆數
  static Future<int> deleteHistory(List<String> kids) async {
    if (kids.isEmpty) return 0;
    if (!AuthService.isLoggedIn) return kids.length;
    final csrf = AuthService.biliJct ?? '';
    if (csrf.isEmpty) return kids.length;
    var failed = 0;
    for (var i = 0; i < kids.length; i += 50) {
      final batch = kids.sublist(
        i,
        i + 50 > kids.length ? kids.length : i + 50,
      );
      try {
        final response = await http.post(
          Uri.parse('${BaseApi.apiBase}/x/v2/history/delete'),
          headers: {...BaseApi.getHeaders(withCookie: true), ..._formHeaders},
          body: 'kid=${Uri.encodeQueryComponent(batch.join(','))}&csrf=$csrf',
        );
        var ok = false;
        if (response.statusCode == 200) {
          ok = jsonDecode(response.body)['code'] == 0;
        }
        if (!ok) failed += batch.length;
      } catch (e) {
        failed += batch.length;
      }
    }
    return failed;
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
