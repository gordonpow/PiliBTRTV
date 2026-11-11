import 'dart:convert';
import 'package:http/http.dart' as http;
import 'base_api.dart';
import 'sign_utils.dart';
import '../../models/reply_item.dart';

/// 留言 API（B 站 reply/wbi/main）
class ReplyApi {
  /// 取得熱門留言（WBI 簽章）
  ///
  /// [aid]：影片 aid；[offset]：分頁 offset（第一頁傳空字串）。
  /// 失敗或格式錯誤時回傳 null。
  static Future<ReplyPage?> getReplies({
    required int aid,
    String offset = '',
  }) async {
    try {
      await BaseApi.ensureWbiKeys();

      // Build pagination_str JSON
      final paginationStr = jsonEncode({'offset': offset});

      Map<String, String> params = {
        'oid': aid.toString(),
        'type': '1',
        'mode': '3',
        'pagination_str': paginationStr,
        'plat': '1',
        'web_location': '1315875',
      };

      if (BaseApi.imgKey != null && BaseApi.subKey != null) {
        params = SignUtils.signWithWbi(params, BaseApi.imgKey!, BaseApi.subKey!);
      }

      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/v2/reply/wbi/main',
      ).replace(queryParameters: params);

      final response = await http
          .get(uri, headers: BaseApi.getHeaders(withCookie: true))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return parseReplyPage(json, firstPage: offset.isEmpty);
      }
    } catch (_) {
      // 失敗回傳 null
    }
    return null;
  }
}
