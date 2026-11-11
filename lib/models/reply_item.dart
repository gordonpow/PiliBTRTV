/// 留言資料模型（B 站 reply/wbi/main API）
class ReplyItem {
  final int rpid;
  final String uname;
  final int ctime; // Unix timestamp (seconds)
  final int like;
  final String message;
  final int replyCount;
  final bool isTop;

  const ReplyItem({
    required this.rpid,
    required this.uname,
    required this.ctime,
    required this.like,
    required this.message,
    required this.replyCount,
    required this.isTop,
  });
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
    final paginationReply = cursor?['pagination_reply'] as Map<String, dynamic>?;
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
    return ReplyItem(
      rpid: rpid,
      uname: uname,
      ctime: ctime,
      like: like,
      message: message,
      replyCount: replyCount,
      isTop: isTop,
    );
  } catch (_) {
    return null;
  }
}
