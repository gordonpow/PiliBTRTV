import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'base_api.dart';
import 'sign_utils.dart';
import '../auth_service.dart';
import '../../models/video.dart';

/// 影片列表和搜尋相關 API
class VideoApi {
  /// 獲取熱門影片 (無需登入)
  static Future<List<Video>> getPopularVideos({int page = 1}) async {
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/popular',
      ).replace(queryParameters: {'pn': page.toString(), 'ps': '20'});

      final response = await http.get(uri, headers: BaseApi.getHeaders());

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final list = json['data']['list'] as List? ?? [];
          return list.map((item) => Video.fromRecommend(item)).toList();
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return [];
  }

  /// 獲取推薦影片 (需要 WBI 簽名)
  static Future<List<Video>> getRecommendVideos({int idx = 0}) async {
    try {
      await BaseApi.ensureWbiKeys();

      Map<String, String> params = {
        'fresh_idx': idx.toString(),
        'fresh_type': '4',
        'ps': '20',
      };

      if (BaseApi.imgKey != null && BaseApi.subKey != null) {
        params = SignUtils.signWithWbi(
          params,
          BaseApi.imgKey!,
          BaseApi.subKey!,
        );
      }

      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/wbi/index/top/feed/rcmd',
      ).replace(queryParameters: params);

      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final items = json['data']['item'] as List? ?? [];
          return items
              .where((item) => item['bvid'] != null)
              .map((item) => Video.fromRecommend(item))
              .toList();
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return [];
  }

  /// 獲取分區影片 (按新分區 ID，使用 region/feed/rcmd)
  static Future<List<Video>> getRegionVideos({
    required int tid,
    int page = 1,
  }) async {
    try {
      final uri =
          Uri.parse(
            '${BaseApi.apiBase}/x/web-interface/region/feed/rcmd',
          ).replace(
            queryParameters: {
              'display_id': page.toString(),
              'request_cnt': '20',
              'from_region': tid.toString(),
            },
          );

      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final archives = json['data']['archives'] as List? ?? [];
          return archives
              .where((item) => item['bvid'] != null)
              .map((item) => Video.fromRegionFeed(item))
              .toList();
        }
        debugPrint(
          'getRegionVideos failed: code=${json['code']} message=${json['message']}',
        );
      } else {
        debugPrint('getRegionVideos HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('getRegionVideos error: $e');
    }
    return [];
  }

  /// 獲取觀看歷史 (需要登入)
  /// 返回 { 'list': List<Video>, 'viewAt': int, 'max': int, 'hasMore': bool }
  static Future<Map<String, dynamic>> getHistory({
    int ps = 30,
    int viewAt = 0,
    int max = 0,
  }) async {
    if (!AuthService.isLoggedIn) {
      return {'list': <Video>[], 'viewAt': 0, 'max': 0, 'hasMore': false};
    }

    try {
      final params = {'ps': ps.toString()};
      if (viewAt > 0) params['view_at'] = viewAt.toString();
      if (max > 0) params['max'] = max.toString();

      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/history/cursor',
      ).replace(queryParameters: params);

      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final listData = json['data']['list'] as List? ?? [];
          final list = listData.map((item) => Video.fromHistory(item)).toList();

          final cursor = json['data']['cursor'];
          int nextViewAt = 0;
          int nextMax = 0;
          bool hasMore = false;

          if (cursor != null) {
            nextViewAt = cursor['view_at'] ?? 0;
            nextMax = cursor['max'] ?? 0;
            hasMore = list.isNotEmpty;
          }

          return {
            'list': list,
            'viewAt': nextViewAt,
            'max': nextMax,
            'hasMore': hasMore,
          };
        }
      }
      debugPrint(
        'getHistory: HTTP ${response.statusCode} ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
    } catch (e) {
      debugPrint('getHistory error: $e');
    }
    return {'list': <Video>[], 'viewAt': 0, 'max': 0, 'hasMore': false};
  }

  /// 獲取搜尋建議
  static Future<List<String>> getSearchSuggestions(String keyword) async {
    if (keyword.isEmpty) return [];

    try {
      final uri = Uri.parse('https://s.search.bilibili.com/main/suggest')
          .replace(
            queryParameters: {
              'term': keyword,
              'main_ver': 'v1',
              'highlight': '',
            },
          );

      final response = await http.get(uri, headers: BaseApi.getHeaders());

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        if (json['code'] == 0 && json['result'] != null) {
          final tags = json['result']['tag'] as List? ?? [];
          return tags
              .map((tag) => tag['value'] as String? ?? '')
              .where((v) => v.isNotEmpty)
              .toList();
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return [];
  }

  /// 搜尋影片 (需要 WBI 簽名)
  static Future<List<Video>> searchVideos(
    String keyword, {
    int page = 1,
    String order = 'totalrank',
  }) async {
    if (keyword.isEmpty) return [];

    try {
      await BaseApi.ensureWbiKeys();

      Map<String, String> params = {
        'keyword': keyword,
        'search_type': 'video',
        'page': page.toString(),
        'pagesize': '20',
        'order': order,
      };

      if (BaseApi.imgKey != null && BaseApi.subKey != null) {
        params = SignUtils.signWithWbi(
          params,
          BaseApi.imgKey!,
          BaseApi.subKey!,
        );
      }

      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/wbi/search/type',
      ).replace(queryParameters: params);

      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final result = json['data']['result'] as List? ?? [];
          if (result.isEmpty) {
            debugPrint(
              'searchVideos: empty result: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
            );
          }
          return result.map((item) => Video.fromSearch(item)).toList();
        }
        debugPrint('searchVideos: code=${json['code']} ${json['message']}');
      } else {
        debugPrint('searchVideos: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('searchVideos error: $e');
      // 忽略錯誤
    }
    return [];
  }

  /// 從動態項目解析影片；非影片動態或解析失敗回傳 null。
  ///
  /// [includeForward] 為 true 時，轉發動態（DYNAMIC_TYPE_FORWARD）取其 orig 內的影片。
  static Video? archiveFromDynamicItem(
    Map<String, dynamic> item, {
    bool includeForward = true,
  }) {
    try {
      if (item['visible'] != true) return null;

      var source = item;
      if (item['type'] == 'DYNAMIC_TYPE_FORWARD') {
        if (!includeForward) return null;
        final orig = item['orig'];
        if (orig is! Map) return null;
        source = Map<String, dynamic>.from(orig);
      }

      final modules = source['modules'] as Map<String, dynamic>? ?? {};
      final dynamicModule =
          modules['module_dynamic'] as Map<String, dynamic>? ?? {};
      final major = dynamicModule['major'] as Map<String, dynamic>? ?? {};
      if (major['type'] != 'MAJOR_TYPE_ARCHIVE') return null;

      final archive = major['archive'] as Map<String, dynamic>? ?? {};
      final author = modules['module_author'] as Map<String, dynamic>? ?? {};
      final stat = archive['stat'] as Map<String, dynamic>? ?? {};

      final viewValue = stat['play'] ?? stat['view'] ?? 0;
      final danmakuValue = stat['danmaku'] ?? 0;

      return Video(
        bvid: archive['bvid'] ?? '',
        title: archive['title'] ?? '',
        pic: BaseApi.fixPicUrl(archive['cover'] ?? ''),
        ownerName: author['name'] ?? '',
        ownerFace: BaseApi.fixPicUrl(author['face'] ?? ''),
        ownerMid: BaseApi.toInt(author['mid']),
        view: BaseApi.toInt(viewValue),
        danmaku: BaseApi.toInt(danmakuValue),
        duration: BaseApi.parseDuration(archive['duration_text'] ?? ''),
        pubdate: BaseApi.toInt(author['pub_ts']),
        badge: (archive['badge'] as Map<String, dynamic>?)?['text'] ?? '',
      );
    } catch (e) {
      debugPrint('archiveFromDynamicItem error: $e');
      return null;
    }
  }

  /// 獲取動態影片列表
  static Future<DynamicFeed> getDynamicFeed({String offset = ''}) async {
    try {
      await BaseApi.ensureWbiKeys();

      final response = await http.get(
        Uri.parse(
          '${BaseApi.apiBase}/x/polymer/web-dynamic/v1/feed/all?type=all&offset=$offset',
        ),
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'];
          final items = data['items'] as List? ?? [];
          final newOffset = data['offset'] as String? ?? '';
          final hasMore = data['has_more'] as bool? ?? false;

          final videos = <Video>[];

          for (final item in items) {
            if (item is! Map<String, dynamic>) continue;
            final video = archiveFromDynamicItem(item, includeForward: false);
            if (video != null) videos.add(video);
          }

          debugPrint(
            'getDynamicFeed: items=${items.length} videos=${videos.length} hasMore=$hasMore',
          );
          return DynamicFeed(
            videos: videos,
            offset: newOffset,
            hasMore: hasMore,
          );
        }
      }
      debugPrint(
        'getDynamicFeed: HTTP ${response.statusCode} ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
    } catch (e) {
      debugPrint('getDynamicFeed error: $e');
    }
    return DynamicFeed(videos: [], offset: '', hasMore: false);
  }

  /// 獲取相關影片
  static Future<List<Video>> getRelatedVideos(String bvid) async {
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/archive/related',
      ).replace(queryParameters: {'bvid': bvid});
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final list = json['data'] as List? ?? [];
          return list.map((item) => Video.fromRecommend(item)).toList();
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return [];
  }

  /// 獲取 UP主 投稿影片列表 (需要 WBI 簽名)
  ///
  /// 失敗（例外、HTTP 非 200、code != 0）回傳 null；total 為投稿總數。
  static Future<({List<Video> videos, int total})?> getSpaceVideos({
    required int mid,
    int page = 1,
    String order = 'pubdate',
    bool riskRetried = false,
  }) async {
    try {
      await BaseApi.ensureWbiKeys();

      // 帶上風控參數（同 PiliPlus searchArchive），避免首次請求被 -352
      Map<String, String> params = {
        'mid': mid.toString(),
        'pn': page.toString(),
        'ps': '30',
        'tid': '0',
        'order': order,
        'platform': 'web',
        'web_location': '333.1387',
        'order_avoided': 'true',
        'dm_img_list': '[]',
        'dm_img_str': BaseApi.randomBase64(16, 64),
        'dm_cover_img_str': BaseApi.randomBase64(32, 128),
        'dm_img_inter': '{"ds":[],"wh":[0,0,0],"of":[0,0,0]}',
      };

      if (BaseApi.imgKey != null && BaseApi.subKey != null) {
        params = SignUtils.signWithWbi(
          params,
          BaseApi.imgKey!,
          BaseApi.subKey!,
        );
      }

      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/space/wbi/arc/search',
      ).replace(queryParameters: params);
      final headers = BaseApi.getHeaders(withCookie: true);
      headers['Referer'] = 'https://space.bilibili.com/$mid';
      headers['Origin'] = 'https://space.bilibili.com';
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final code = json['code'];
        if (code == 0 && json['data'] != null) {
          final list = json['data']['list']?['vlist'] as List? ?? [];
          final total = (json['data']['page']?['count'] as num?)?.toInt() ?? 0;
          return (
            videos: list.map((item) => Video.fromSpaceVideo(item)).toList(),
            total: total,
          );
        }
        debugPrint('getSpaceVideos code=$code message=${json['message']}');
        if ((code == -351 || code == -352) && !riskRetried) {
          // 風控：重新取得 WBI keys 後重試一次
          BaseApi.wbiKeysTime = null;
          await BaseApi.ensureWbiKeys();
          return await getSpaceVideos(
            mid: mid,
            page: page,
            order: order,
            riskRetried: true,
          );
        }
      }
    } catch (e) {
      debugPrint('getSpaceVideos error: $e');
    }
    return null;
  }

  /// 獲取 UP主 名片資訊（名稱、頭像、簽名、粉絲數、投稿數）。失敗回傳 null。
  static Future<Map<String, dynamic>?> getUpCard(int mid) async {
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/web-interface/card',
      ).replace(queryParameters: {'mid': mid.toString(), 'photo': 'false'});
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'];
          final card = data['card'] as Map? ?? {};
          return {
            'name': card['name']?.toString() ?? '',
            'face': card['face']?.toString() ?? '',
            'sign': card['sign']?.toString() ?? '',
            'fans':
                (data['follower'] as num?)?.toInt() ??
                (card['fans'] as num?)?.toInt() ??
                0,
            'archiveCount': (data['archive_count'] as num?)?.toInt() ?? 0,
          };
        }
      }
    } catch (e) {
      debugPrint('getUpCard error: $e');
    }
    return null;
  }
}

/// 動態 Feed 資料結構
class DynamicFeed {
  final List<Video> videos;
  final String offset;
  final bool hasMore;

  DynamicFeed({
    required this.videos,
    required this.offset,
    required this.hasMore,
  });
}
