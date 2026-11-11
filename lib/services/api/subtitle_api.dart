import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../grpc/dm_grpc.dart';
import '../../grpc/dm_view.pb.dart';
import '../../models/subtitle.dart';
import 'app_sign.dart';
import 'base_api.dart';
import 'sign_utils.dart';

/// CC 字幕 API（x/player/wbi/v2）
class SubtitleApi {
  /// 解析 v2 回應 JSON（已 decode）；過濾 subtitle_url 為空的軌（R-9）。
  static List<SubtitleTrack> parseTracks(dynamic json) {
    if (json is! Map || json['code'] != 0) return const [];
    final list = json['data']?['subtitle']?['subtitles'];
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map<String, dynamic>) ?SubtitleTrack.fromJson(e),
    ];
  }

  /// 解析 gRPC DmViewReply 的字幕清單；subtitle_url 為空的軌略過，url 補 https:。
  static List<SubtitleTrack> parseDmView(DmViewReply reply) {
    if (!reply.hasSubtitle()) return const [];
    return [
      for (final i in reply.subtitle.subtitles)
        if (i.subtitleUrl.isNotEmpty)
          SubtitleTrack(
            id: i.id.toInt(),
            lan: i.lan,
            lanDoc: i.lanDoc.isEmpty ? i.lan : i.lanDoc,
            url: i.subtitleUrl.startsWith('//')
                ? 'https:${i.subtitleUrl}'
                : i.subtitleUrl.replaceFirst(RegExp('^http:'), 'https:'),
            isAi: i.type == SubtitleType.AI,
          ),
    ];
  }

  static String? _anonBuvid;

  /// 未登入也能用的 gRPC DmView；失敗回空清單、不丟例外。
  static Future<List<SubtitleTrack>> getSubtitlesGrpc({
    required int aid,
    required int cid,
  }) async {
    try {
      final b3 = BaseApi.buvid3;
      final buvid = (b3 != null && b3.isNotEmpty)
          ? b3
          : (_anonBuvid ??= AppSign.generateBuvid());
      final reply = await DmGrpc.dmView(aid: aid, cid: cid, buvid: buvid);
      return parseDmView(reply);
    } catch (e) {
      debugPrint('Failed to load subtitle via grpc: $e');
      return const [];
    }
  }

  /// 取得字幕軌清單；v2 沒有可用字幕（常見於未登入）時改走 gRPC DmView。
  /// 失敗回空清單。
  /// PGC 以 aid＋cid 為主，ep_id／season_id 有就帶（R-13）。
  static Future<List<SubtitleTrack>> getSubtitles({
    int? aid,
    required int cid,
    String? bvid,
    int? epId,
    int? seasonId,
  }) async {
    final tracks = await _getSubtitlesV2(
      aid: aid,
      cid: cid,
      bvid: bvid,
      epId: epId,
      seasonId: seasonId,
    );
    if (tracks.isNotEmpty || aid == null || aid <= 0) return tracks;
    return getSubtitlesGrpc(aid: aid, cid: cid);
  }

  static Future<List<SubtitleTrack>> _getSubtitlesV2({
    int? aid,
    required int cid,
    String? bvid,
    int? epId,
    int? seasonId,
  }) async {
    try {
      await BaseApi.ensureWbiKeys();
      final params = <String, String>{
        if (aid != null && aid > 0) 'aid': aid.toString(),
        if ((aid == null || aid <= 0) && bvid != null && bvid.isNotEmpty)
          'bvid': bvid,
        'cid': cid.toString(),
        if (epId != null && epId > 0) 'ep_id': epId.toString(),
        if (seasonId != null && seasonId > 0) 'season_id': seasonId.toString(),
      };
      final signed = SignUtils.signWithWbi(
        params,
        BaseApi.imgKey!,
        BaseApi.subKey!,
      );
      final qs = signed.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final response = await http
          .get(
            Uri.parse('https://api.bilibili.com/x/player/wbi/v2?$qs'),
            headers: BaseApi.getHeaders(withCookie: true),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];
      return parseTracks(jsonDecode(response.body));
    } catch (e) {
      debugPrint('Failed to load subtitle tracks: $e');
      return const [];
    }
  }

  /// 下載字幕 body；網址缺 scheme 時補 https:。失敗回空清單。
  static Future<List<SubtitleLine>> getSubtitleBody(String url) async {
    try {
      final full = url.startsWith('//') ? 'https:$url' : url;
      final response = await http
          .get(Uri.parse(full), headers: BaseApi.getHeaders())
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      return parseSubtitleBody(json is Map ? json['body'] as List? : null);
    } catch (e) {
      debugPrint('Failed to load subtitle body: $e');
      return const [];
    }
  }
}
