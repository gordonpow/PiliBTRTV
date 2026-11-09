import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/video.dart';
import '../auth_service.dart';
import 'base_api.dart';

/// 收藏夾資訊
class FavFolder {
  final int id;
  final String title;
  final int mediaCount;

  const FavFolder({
    required this.id,
    required this.title,
    required this.mediaCount,
  });
}

/// 我的收藏／稍後再看 API
class FavApi {
  /// 取得使用者建立的收藏夾（API 回傳順序第一個為預設收藏夾）
  static Future<List<FavFolder>> getFavFolders() async {
    try {
      final mid = AuthService.mid;
      if (mid == null) return [];
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
          final list = json['data']['list'] as List? ?? [];
          return list
              .map(
                (e) => FavFolder(
                  id: (e['id'] as num?)?.toInt() ?? 0,
                  title: (e['title'] ?? '').toString(),
                  mediaCount: (e['media_count'] as num?)?.toInt() ?? 0,
                ),
              )
              .where((f) => f.id != 0)
              .toList();
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return [];
  }

  /// 取得收藏夾內的影片，回傳 {list: List<Video>, hasMore: bool, ok: bool}
  static Future<Map<String, dynamic>> getFavVideos(int mediaId, int pn) async {
    try {
      final uri = Uri.parse('${BaseApi.apiBase}/x/v3/fav/resource/list')
          .replace(
            queryParameters: {
              'media_id': mediaId.toString(),
              'pn': pn.toString(),
              'ps': '20',
              'platform': 'web',
            },
          );
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final medias = json['data']['medias'] as List? ?? [];
          final videos = <Video>[];
          for (final m in medias) {
            if (m is! Map<String, dynamic>) continue;
            // 與伺服器回傳的簡體文字比對，保留原文
            if ((m['attr'] ?? 0) != 0 || m['title'] == '已失效视频') continue;
            final v = Video.fromFav(m);
            if (v.bvid.isNotEmpty) videos.add(v);
          }
          return {
            'list': videos,
            'hasMore': json['data']['has_more'] == true,
            'ok': true,
          };
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return {'list': <Video>[], 'hasMore': false, 'ok': false};
  }

  /// 取得稍後再看清單
  static Future<List<Video>> getWatchLater() async {
    try {
      final response = await http.get(
        Uri.parse('${BaseApi.apiBase}/x/v2/history/toview'),
        headers: BaseApi.getHeaders(withCookie: true),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final list = json['data']['list'] as List? ?? [];
          return list
              .whereType<Map<String, dynamic>>()
              .map(Video.fromToView)
              .where((v) => v.bvid.isNotEmpty)
              .toList();
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return [];
  }
}
