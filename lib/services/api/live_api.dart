import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../auth_service.dart';
import 'base_api.dart';

/// Bilibili 直播 API
class LiveApi {
  /// 獲取直播間資訊 (包含真實 RoomID)
  static Future<Map<String, dynamic>?> getRoomInfo(int roomId) async {
    try {
      final url =
          'https://api.live.bilibili.com/room/v1/Room/get_info?room_id=$roomId';
      final response = await http.get(
        Uri.parse(url),
        headers: BaseApi.getHeaders(),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          return json['data'];
        }
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  /// 獲取直播播放地址 (New API)
  /// [roomId] 房間號
  /// [qn] 畫質 10000=原畫
  static Future<Map<String, dynamic>?> getPlayUrl(
    int roomId, {
    int qn = 10000,
  }) async {
    try {
      final url =
          'https://api.live.bilibili.com/xlive/web-room/v1/playUrl/playUrl?cid=$roomId&qn=$qn&platform=web&https_url_req=1&ptype=16';

      final response = await http.get(
        Uri.parse(url),
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          return json['data'];
        }
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  /// v2 取流：多線路、HLS fmp4、畫質表。回傳 `data`；失敗回 null。
  static Future<Map<String, dynamic>?> getRoomPlayInfo(
    int roomId, {
    int qn = 10000,
  }) async {
    try {
      final url =
          'https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo?room_id=$roomId&protocol=0,1&format=0,1,2&codec=0,1&qn=$qn&platform=web&ptype=8&dolby=5&panorama=1';
      final response = await http
          .get(Uri.parse(url), headers: BaseApi.getHeaders(withCookie: true))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          return json['data'];
        }
      }
    } catch (e) {
      debugPrint('LiveApi: getRoomPlayInfo error: $e');
    }
    return null;
  }

  /// 獲取彈幕伺服器配置
  static Future<Map<String, dynamic>?> getDanmakuConf(int roomId) async {
    // 1. Try XLIVE API (New)
    try {
      final url =
          'https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo?id=$roomId&type=0';
      final headers = BaseApi.getHeaders(withCookie: true);
      headers['Referer'] = 'https://live.bilibili.com/$roomId';

      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          debugPrint('LiveApi: XLIVE Danmaku Conf Success');
          return json['data'];
        } else {
          debugPrint(
            'LiveApi: XLIVE API Error: ${json['message']} (${json['code']}) - Trying Fallback...',
          );
        }
      }
    } catch (e) {
      debugPrint('LiveApi: XLIVE Exception: $e');
    }

    // 2. Try Legacy API (V1) - Fallback for -352 or other errors
    try {
      final url =
          'https://api.live.bilibili.com/room/v1/Danmu/getConf?room_id=$roomId&platform=pc&player=web';
      final headers = BaseApi.getHeaders(withCookie: true);
      headers['Referer'] = 'https://live.bilibili.com/$roomId';

      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          debugPrint('LiveApi: Legacy Danmaku Conf Success');
          final data = json['data'];
          // Normalize field names
          if (data['host_server_list'] != null) {
            data['host_list'] = data['host_server_list'];
          }
          return data;
        } else {
          debugPrint(
            'LiveApi: Legacy API Error: ${json['message']} (${json['code']})',
          );
        }
      }
    } catch (e) {
      debugPrint('LiveApi: Legacy Exception: $e');
    }

    return null;
  }

  /// 獲取推薦直播列表
  static Future<List<dynamic>> getRecommended({
    int page = 1,
    int pageSize = 30,
    int parentId = 0,
    int areaId = 0,
  }) async {
    try {
      if (parentId > 0) {
        // 使用 v3 介面獲取指定父分區的內容 (v1 介面忽略 parent_area_id)
        final url =
            'https://api.live.bilibili.com/room/v3/area/getRoomList?parent_area_id=$parentId&area_id=$areaId&sort_type=online&page=$page&page_size=$pageSize';

        final response = await http.get(
          Uri.parse(url),
          headers: BaseApi.getHeaders(),
        );
        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          if (json['code'] == 0 && json['data'] != null) {
            return json['data']['list'] as List;
          }
        }
      } else {
        // 使用 v1 介面獲取推薦 (全部/預設)
        final url =
            'https://api.live.bilibili.com/room/v1/Area/getListByAreaID?areaId=$areaId&sort=online&pageSize=$pageSize&page=$page&parent_area_id=$parentId';

        final response = await http.get(
          Uri.parse(url),
          headers: BaseApi.getHeaders(),
        );
        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          if (json['code'] == 0 && json['data'] != null) {
            return json['data'] as List;
          }
        }
      }
    } catch (e) {
      // ignore
    }
    return [];
  }

  /// 獲取我的關注正在直播
  static Future<List<dynamic>> getFollowedLive({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final url =
          'https://api.live.bilibili.com/relation/v1/feed/feed_list?page=$page&pagesize=$pageSize';
      final response = await http.get(
        Uri.parse(url),
        headers: BaseApi.getHeaders(withCookie: true),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final list = json['data']['list'] as List? ?? [];
          if (list.isNotEmpty) {
            debugPrint('LiveApi: Feed Item Raw: ${list.first}');
          }
          // feed_list returns "your following who are live", so no need to filter by status
          return list;
        }
      }
      debugPrint(
        'getFollowedLive: HTTP ${response.statusCode} ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
    } catch (e) {
      debugPrint('getFollowedLive error: $e');
    }
    return [];
  }

  /// 獲取直播分區列表 (父分區)
  /// 如: 網遊, 手遊, 單機, 娛樂
  static Future<List<dynamic>> getParentAreas() async {
    // 簡化版：手動定義幾個常用分區，或者呼叫 API
    // https://api.live.bilibili.com/room/v1/Area/getList?need_entrance=1&parent_area_id=0
    try {
      final url =
          'https://api.live.bilibili.com/room/v1/Area/getList?need_entrance=1&parent_area_id=0';
      final response = await http.get(
        Uri.parse(url),
        headers: BaseApi.getHeaders(),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          return json['data'] as List;
        }
      }
    } catch (e) {
      // ignore
    }
    return [];
  }

  /// 獲取與使用者的關係 (關注狀態)
  /// [fid] 目標使用者 UID
  static Future<Map<String, dynamic>?> getRelation(int fid) async {
    try {
      final url = 'https://api.bilibili.com/x/relation?fid=$fid';
      final response = await http.get(
        Uri.parse(url),
        headers: BaseApi.getHeaders(withCookie: true),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          return json['data'];
        }
      }
    } catch (e) {
      debugPrint('LiveApi: Get Relation Error: $e');
    }
    return null;
  }

  /// 修改關注關係
  /// [fid] 目標使用者 UID
  /// [act] 1=關注, 2=取消關注
  static Future<bool> modifyRelation(int fid, int act) async {
    try {
      final url = 'https://api.bilibili.com/x/relation/modify';
      final body = {
        'fid': fid.toString(),
        'act': act.toString(),
        're_src': '11',
        'csrf': AuthService.biliJct ?? '',
      };

      final response = await http.post(
        Uri.parse(url),
        headers: BaseApi.getHeaders(withCookie: true),
        body: body,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          return true;
        } else {
          debugPrint('LiveApi: Modify Relation Failed: ${json['message']}');
        }
      }
    } catch (e) {
      debugPrint('LiveApi: Modify Relation Error: $e');
    }
    return false;
  }
}
