import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'base_api.dart';
import '../../models/video.dart';

/// 番劇 (PGC) 相關 API：索引與季資訊。
/// 播放網址走 PlaybackApi.getVideoPlayUrl(epId: ...)。
class PgcApi {
  /// 番劇索引 (熱門排序)
  static Future<List<Video>> getBangumiIndex({int page = 1}) async {
    try {
      final uri = Uri.parse('${BaseApi.apiBase}/pgc/season/index/result')
          .replace(
            queryParameters: {
              'season_type': '1',
              'type': '1',
              'order': '3',
              'sort': '0',
              'st': '1',
              'page': page.toString(),
              'pagesize': '20',
            },
          );
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        if (json['code'] == 0 && json['data'] != null) {
          final list = json['data']['list'] as List? ?? [];
          return list
              .where((item) => BaseApi.toInt(item['season_id']) > 0)
              .map((item) => Video.fromBangumiIndex(item))
              .toList();
        }
        debugPrint(
          'getBangumiIndex failed: code=${json['code']} message=${json['message']}',
        );
      }
    } catch (e) {
      debugPrint('getBangumiIndex error: $e');
    }
    return [];
  }

  /// 季資訊。回傳：
  /// {'seasonId', 'title', 'episodes': List<Map>, 'lastEpId', 'lastTime'}
  /// 失敗時回傳 {'error': 訊息}。
  /// episodes 的 key 與 UGC 分 P 對齊：cid、part、page，另帶 ep_id、bvid、aid、badge、is_pgc。
  static Future<Map<String, dynamic>> getSeason({required int seasonId}) async {
    try {
      final uri = Uri.parse(
        '${BaseApi.apiBase}/pgc/view/web/season',
      ).replace(queryParameters: {'season_id': seasonId.toString()});
      final response = await http.get(
        uri,
        headers: BaseApi.getHeaders(withCookie: true),
      );
      if (response.statusCode != 200) {
        return {'error': '取得番劇資訊失敗（HTTP ${response.statusCode}）'};
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json['code'] != 0 || json['result'] == null) {
        return {'error': '${json['message'] ?? '取得番劇資訊失敗'}（${json['code']}）'};
      }
      final result = json['result'] as Map<String, dynamic>;

      // 部分番劇 episodes 為空，正片放在 section(s)[].episodes
      var rawEpisodes = result['episodes'] as List? ?? [];
      if (rawEpisodes.isEmpty) {
        final sections =
            (result['sections'] ?? result['section']) as List? ?? [];
        for (final sec in sections) {
          final eps = (sec is Map ? sec['episodes'] : null) as List? ?? [];
          if (eps.isNotEmpty) {
            rawEpisodes = eps;
            break;
          }
        }
      }

      final episodes = <Map<String, dynamic>>[];
      for (int i = 0; i < rawEpisodes.length; i++) {
        final ep = rawEpisodes[i] as Map<String, dynamic>;
        final cid = BaseApi.toInt(ep['cid']);
        if (cid <= 0) continue;
        final rawTitle = (ep['title'] ?? '').toString();
        final longTitle = (ep['long_title'] ?? '').toString();
        final isNumber = int.tryParse(rawTitle) != null;
        // 數字集數顯示「第 N 話 標題」，其他 (SP、劇場版…) 直接顯示原標題
        final label = isNumber ? '第 $rawTitle 話' : rawTitle;
        final part = [label, longTitle].where((e) => e.isNotEmpty).join(' ');
        episodes.add({
          'cid': cid,
          'part': part.isEmpty ? '第 ${i + 1} 話' : part,
          'page': i + 1,
          'ep_id': BaseApi.toInt(ep['id'] ?? ep['ep_id']),
          'bvid': (ep['bvid'] ?? '').toString(),
          'aid': BaseApi.toInt(ep['aid']),
          'badge': (ep['badge'] ?? '').toString(),
          'is_pgc': true,
        });
      }

      final userStatus = result['user_status'];
      final progress =
          (userStatus is Map ? userStatus['progress'] : null) as Map? ?? {};
      return {
        'seasonId': BaseApi.toInt(result['season_id']),
        'title': (result['title'] ?? '').toString(),
        'cover': (result['cover'] ?? '').toString(),
        'episodes': episodes,
        'lastEpId': BaseApi.toInt(progress['last_ep_id']),
        'lastTime': BaseApi.toInt(progress['last_time']),
      };
    } catch (e) {
      debugPrint('getSeason error: $e');
      return {'error': '取得番劇資訊失敗：$e'};
    }
  }
}
