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

  /// 獲取分區影片 (按 tid)
  static Future<List<Video>> getRegionVideos({
    required int tid,
    int page = 1,
  }) async {
    try {
      final uri = Uri.parse('${BaseApi.apiBase}/x/web-interface/dynamic/region')
          .replace(
            queryParameters: {
              'rid': tid.toString(),
              'pn': page.toString(),
              'ps': '20',
            },
          );

      final response = await http.get(uri, headers: BaseApi.getHeaders());

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final archives = json['data']['archives'] as List? ?? [];
          return archives.map((item) => Video.fromRecommend(item)).toList();
        }
      }
    } catch (e) {
      // 忽略錯誤
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
      debugPrint('getHistory: HTTP ${response.statusCode} ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
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
            debugPrint('searchVideos: empty result: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
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
            try {
              if (item['visible'] != true) continue;

              final modules = item['modules'] as Map<String, dynamic>? ?? {};
              final dynamicModule =
                  modules['module_dynamic'] as Map<String, dynamic>? ?? {};
              final major =
                  dynamicModule['major'] as Map<String, dynamic>? ?? {};

              if (major['type'] != 'MAJOR_TYPE_ARCHIVE') continue;

              final archive = major['archive'] as Map<String, dynamic>? ?? {};
              final author =
                  modules['module_author'] as Map<String, dynamic>? ?? {};
              final stat = archive['stat'] as Map<String, dynamic>? ?? {};

              final viewValue = stat['play'] ?? stat['view'] ?? 0;
              final danmakuValue = stat['danmaku'] ?? 0;

              videos.add(
                Video(
                  bvid: archive['bvid'] ?? '',
                  title: archive['title'] ?? '',
                  pic: BaseApi.fixPicUrl(archive['cover'] ?? ''),
                  ownerName: author['name'] ?? '',
                  ownerFace: BaseApi.fixPicUrl(author['face'] ?? ''),
                  ownerMid: BaseApi.toInt(author['mid']),
                  view: BaseApi.toInt(viewValue),
                  danmaku: BaseApi.toInt(danmakuValue),
                  duration: BaseApi.parseDuration(
                    archive['duration_text'] ?? '',
                  ),
                  pubdate: BaseApi.toInt(author['pub_ts']),
                  badge:
                      (archive['badge'] as Map<String, dynamic>?)?['text'] ??
                      '',
                ),
              );
            } catch (e) {
              debugPrint('getDynamicFeed item error: $e');
              continue;
            }
          }

          debugPrint('getDynamicFeed: items=${items.length} videos=${videos.length} hasMore=$hasMore');
          return DynamicFeed(
            videos: videos,
            offset: newOffset,
            hasMore: hasMore,
          );
        }
      }
      debugPrint('getDynamicFeed: HTTP ${response.statusCode} ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
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
  static Future<List<Video>> getSpaceVideos({
    required int mid,
    int page = 1,
    String order = 'pubdate',
  }) async {
    try {
      await BaseApi.ensureWbiKeys();

      Map<String, String> params = {
        'mid': mid.toString(),
        'pn': page.toString(),
        'ps': '30',
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
        '${BaseApi.apiBase}/x/space/wbi/arc/search',
      ).replace(queryParameters: params);
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final list = json['data']['list']?['vlist'] as List? ?? [];
          return list.map((item) => Video.fromSpaceVideo(item)).toList();
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return [];
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
