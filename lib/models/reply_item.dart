/// 留言資料模型（B 站 reply/wbi/main API）
class ReplyItem {
  final int rpid;
  final String uname;
  final int ctime; // Unix timestamp (seconds)
  final int like;
  final String message;
  final int replyCount;
  final bool isTop;

  /// 表情代碼（例如 `[笑哭]`）對應的圖片網址與大小（content.emote）。
  final Map<String, ReplyEmote> emotes;

  /// 留言附圖網址（content.pictures[].img_src）。
  final List<String> pictures;

  const ReplyItem({
    required this.rpid,
    required this.uname,
    required this.ctime,
    required this.like,
    required this.message,
    required this.replyCount,
    required this.isTop,
    this.emotes = const {},
    this.pictures = const [],
  });
}

/// 留言中的表情圖片。
class ReplyEmote {
  final String url;

  /// B 站 meta.size：1 小表情（與文字同高），2 大表情。
  final bool large;

  const ReplyEmote({required this.url, required this.large});
}

/// 補上協定並改用 https（B 站有時回傳 `//` 或 `http://` 開頭的網址）。
String normalizeImageUrl(String url) {
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('http://')) return 'https://${url.substring(7)}';
  return url;
}

/// 一頁留言資料
class ReplyPage {
  final List<ReplyItem> items;
  final String nextOffset;
  final bool isEnd;

  const ReplyPage({
    required this.items,
    required this.nextOffset,
    required this.isEnd,
  });
}

/// 純函式解析留言頁（供測試）
ReplyPage? parseReplyPage(Map<String, dynamic> json, {bool firstPage = false}) {
  try {
    final code = json['code'];
    if (code != 0) return null;

    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return null;

    // Parse replies
    final replies = data['replies'] as List? ?? [];
    final items = <ReplyItem>[];

    // Collect rpid set for dedup
    final seen = <int>{};

    // Top replies (first page only)
    if (firstPage) {
      // upper.top
      final upper = data['upper'] as Map<String, dynamic>?;
      final upperTop = upper?['top'] as Map<String, dynamic>?;
      if (upperTop != null) {
        final item = _parseItem(upperTop, isTop: true);
        if (item != null && seen.add(item.rpid)) {
          items.add(item);
        }
      }
      // top_replies
      final topReplies = data['top_replies'] as List? ?? [];
      for (final r in topReplies) {
        if (r is Map<String, dynamic>) {
          final item = _parseItem(r, isTop: true);
          if (item != null && seen.add(item.rpid)) {
            items.add(item);
          }
        }
      }
    }

    // Normal replies
    for (final r in replies) {
      if (r is Map<String, dynamic>) {
        final item = _parseItem(r, isTop: false);
        if (item != null && seen.add(item.rpid)) {
          items.add(item);
        }
      }
    }

    // Pagination
    final cursor = data['cursor'] as Map<String, dynamic>?;
    final paginationReply =
        cursor?['pagination_reply'] as Map<String, dynamic>?;
    final nextOffset = paginationReply?['next_offset'] as String? ?? '';
    final isEnd = cursor?['is_end'] == true || nextOffset.isEmpty;

    return ReplyPage(items: items, nextOffset: nextOffset, isEnd: isEnd);
  } catch (_) {
    return null;
  }
}

ReplyItem? _parseItem(Map<String, dynamic> r, {required bool isTop}) {
  try {
    final rpid = r['rpid'] as int?;
    if (rpid == null) return null;
    final member = r['member'] as Map<String, dynamic>?;
    final uname = member?['uname'] as String? ?? '';
    final ctime = r['ctime'] as int? ?? 0;
    final like = r['like'] as int? ?? 0;
    final content = r['content'] as Map<String, dynamic>?;
    final message = content?['message'] as String? ?? '';
    final replyCount = r['rcount'] as int? ?? 0;
    final emotes = <String, ReplyEmote>{};
    final emoteJson = content?['emote'];
    if (emoteJson is Map) {
      emoteJson.forEach((key, value) {
        if (key is! String || value is! Map) return;
        final url = value['url'];
        if (url is! String || url.isEmpty) return;
        final meta = value['meta'];
        final size = meta is Map ? meta['size'] : null;
        emotes[key] = ReplyEmote(url: normalizeImageUrl(url), large: size == 2);
      });
    }
    final pictures = <String>[];
    final picJson = content?['pictures'];
    if (picJson is List) {
      for (final p in picJson) {
        final src = p is Map ? p['img_src'] : null;
        if (src is String && src.isNotEmpty) {
          pictures.add(normalizeImageUrl(src));
        }
      }
    }
    return ReplyItem(
      rpid: rpid,
      uname: uname,
      ctime: ctime,
      like: like,
      message: message,
      replyCount: replyCount,
      isTop: isTop,
      emotes: emotes,
      pictures: pictures,
    );
  } catch (_) {
    return null;
  }
}
