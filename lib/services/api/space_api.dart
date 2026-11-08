import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/space_data.dart';
import '../../models/video.dart';
import 'app_sign.dart';
import 'base_api.dart';
import 'sign_utils.dart';
import 'video_api.dart';

/// UP主 空間頁（主頁／動態／投稿）使用的 API。
///
/// App API 不帶 access_key：所需資料皆為公開資料，
/// 且 TV 登入取得的 token 與此 appkey 不相容。
abstract final class SpaceApi {
  static const String _appBase = 'https://app.bilibili.com';
  static const String _appUserAgent =
      'Mozilla/5.0 BiliDroid/8.43.0 (bbcallen@gmail.com)';
  static const int pageSize = 20;

  /// 呼叫 app.bilibili.com 的簽名 API，回傳 `data`；失敗回傳 null。
  static Future<Map<String, dynamic>?> _appGet(
    String path,
    Map<String, String> query,
  ) async {
    try {
      final params = <String, dynamic>{
        ...query,
        'build': '8430300',
        'mobi_app': 'android',
        'platform': 'android',
      };
      AppSign.appSign(params);
      final uri = Uri.parse('$_appBase$path').replace(
        queryParameters: params.map((k, v) => MapEntry(k, v.toString())),
      );
      final response = await http.get(
        uri,
        headers: {'User-Agent': _appUserAgent},
      );
      if (response.statusCode != 200) {
        debugPrint('SpaceApi $path: HTTP ${response.statusCode}');
        return null;
      }
      final json = jsonDecode(response.body);
      if (json['code'] == 0 && json['data'] is Map) {
        return Map<String, dynamic>.from(json['data'] as Map);
      }
      debugPrint('SpaceApi $path: code=${json['code']} ${json['message']}');
    } catch (e) {
      debugPrint('SpaceApi $path error: $e');
    }
    return null;
  }

  /// UP主 空間總覽（名片、分頁、主頁區塊資料）。失敗回傳 null。
  static Future<SpaceData?> getSpace(int mid) async {
    final data = await _appGet('/x/v2/space', {'vmid': mid.toString()});
    if (data == null) return null;
    try {
      return SpaceData.fromJson(data);
    } catch (e) {
      debugPrint('SpaceApi.getSpace parse error: $e');
      return null;
    }
  }

  /// UP主 投稿影片（App API 游標分頁，不受 Web 風控影響）。失敗回傳 null。
  ///
  /// [order] 為 `pubdate`（最新）或 `click`（最多播放）；[cursor] 為上一頁回傳的 `nextCursor`。
  static Future<({List<Video> videos, bool hasMore, String nextCursor})?>
  getArchives(int mid, {String order = 'pubdate', String cursor = ''}) async {
    final data = await _appGet('/x/v2/space/archive/cursor', {
      'vmid': mid.toString(),
      'ps': pageSize.toString(),
      'order': order == 'click' ? 'click' : '',
      if (cursor.isNotEmpty) 'aid': cursor,
    });
    if (data == null) return null;
    final raw = data['item'] is List ? data['item'] as List : const [];
    final videos = <Video>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final item = Map<String, dynamic>.from(e);
      if ((item['bvid']?.toString() ?? '').isEmpty) continue;
      videos.add(Video.fromSpaceApp(item, ownerMid: mid));
    }
    final next = data['next_cursor']?.toString() ?? '';
    return (
      videos: videos,
      hasMore: data['has_next'] == true && next.isNotEmpty,
      nextCursor: next,
    );
  }

  /// 合集／系列的影片（每頁 20 筆）。失敗回傳 null。
  static Future<({List<Video> videos, bool hasMore})?> getCollectionVideos(
    SpaceCollection collection, {
    required int mid,
    int pn = 1,
  }) async {
    final data = collection.isSeries
        ? await _appGet('/x/v2/space/series', {
            'series_id': collection.id.toString(),
            'vmid': mid.toString(),
            'ps': pageSize.toString(),
            'pn': pn.toString(),
          })
        : await _appGet('/x/v2/space/season/videos', {
            'season_id': collection.id.toString(),
            'ps': pageSize.toString(),
            'pn': pn.toString(),
          });
    if (data == null) return null;

    final raw = data['item'] is List ? data['item'] as List : const [];
    final videos = <Video>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final item = Map<String, dynamic>.from(e);
      if ((item['bvid']?.toString() ?? '').isEmpty) continue;
      videos.add(Video.fromSpaceApp(item, ownerMid: mid));
    }

    var hasMore = raw.length >= pageSize;
    if (collection.isSeries && hasMore) {
      final total = BaseApi.toInt(data['total']);
      if (total > 0) hasMore = pn * pageSize < total;
    }
    return (videos: videos, hasMore: hasMore);
  }

  /// UP主 動態（只取影片動態，含轉發中的影片）。失敗回傳 null。
  static Future<({List<Video> videos, String offset, bool hasMore})?>
  getSpaceDynamics(
    int mid, {
    String offset = '',
    bool riskRetried = false,
  }) async {
    try {
      await BaseApi.ensureWbiKeys();

      Map<String, String> params = {
        'host_mid': mid.toString(),
        'offset': offset,
        'timezone_offset': '-480',
        'platform': 'web',
        'web_location': '333.1387',
        'features': 'itemOpusStyle',
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
        '${BaseApi.apiBase}/x/polymer/web-dynamic/v1/feed/space',
      ).replace(queryParameters: params);
      final headers = BaseApi.getHeaders(withCookie: true);
      headers['Referer'] = 'https://space.bilibili.com/$mid/dynamic';
      headers['Origin'] = 'https://space.bilibili.com';
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final code = json['code'];
        if (code == 0 && json['data'] != null) {
          final data = json['data'];
          final items = data['items'] as List? ?? [];
          final videos = <Video>[];
          for (final item in items) {
            if (item is! Map) continue;
            final video = VideoApi.archiveFromDynamicItem(
              Map<String, dynamic>.from(item),
            );
            if (video != null) videos.add(video);
          }
          return (
            videos: videos,
            offset: data['offset']?.toString() ?? '',
            hasMore: data['has_more'] as bool? ?? false,
          );
        }
        debugPrint('getSpaceDynamics code=$code message=${json['message']}');
        if ((code == -351 || code == -352) && !riskRetried) {
          BaseApi.wbiKeysTime = null;
          await BaseApi.ensureWbiKeys();
          return await getSpaceDynamics(mid, offset: offset, riskRetried: true);
        }
      } else {
        debugPrint('getSpaceDynamics: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('getSpaceDynamics error: $e');
    }
    return null;
  }
}
