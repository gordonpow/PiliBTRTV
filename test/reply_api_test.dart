import 'package:bili_tv_app/models/reply_item.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _reply(int rpid, {String msg = 'hi', int rcount = 0}) => {
  'rpid': rpid,
  'ctime': 1700000000,
  'like': 5,
  'rcount': rcount,
  'member': {'uname': 'u$rpid'},
  'content': {'message': msg},
};

void main() {
  test('解析留言欄位', () {
    final page = parseReplyPage({
      'code': 0,
      'data': {
        'replies': [_reply(1, msg: '你好', rcount: 3)],
        'cursor': {
          'is_end': false,
          'pagination_reply': {'next_offset': 'abc'},
        },
      },
    }, firstPage: true)!;
    expect(page.items.length, 1);
    final r = page.items.first;
    expect(r.rpid, 1);
    expect(r.uname, 'u1');
    expect(r.message, '你好');
    expect(r.like, 5);
    expect(r.ctime, 1700000000);
    expect(r.replyCount, 3);
    expect(r.isTop, false);
    expect(page.nextOffset, 'abc');
    expect(page.isEnd, false);
  });

  test('置頂留言排最前並去重', () {
    final page = parseReplyPage({
      'code': 0,
      'data': {
        'replies': [_reply(2), _reply(9), _reply(3)],
        'top_replies': [_reply(9)],
        'upper': {'top': _reply(9)},
        'cursor': {
          'pagination_reply': {'next_offset': 'x'},
        },
      },
    }, firstPage: true)!;
    expect(page.items.map((e) => e.rpid), [9, 2, 3]);
    expect(page.items.first.isTop, true);
    expect(page.items.skip(1).every((e) => !e.isTop), true);
  });

  test('非第一頁不加入置頂留言', () {
    final page = parseReplyPage({
      'code': 0,
      'data': {
        'replies': [_reply(2)],
        'top_replies': [_reply(9)],
      },
    })!;
    expect(page.items.map((e) => e.rpid), [2]);
  });

  test('is_end 或 offset 為空代表沒有下一頁', () {
    final a = parseReplyPage({
      'code': 0,
      'data': {
        'replies': [_reply(1)],
        'cursor': {
          'is_end': true,
          'pagination_reply': {'next_offset': 'abc'},
        },
      },
    })!;
    expect(a.isEnd, true);
    final b = parseReplyPage({
      'code': 0,
      'data': {
        'replies': [_reply(1)],
        'cursor': {
          'is_end': false,
          'pagination_reply': {'next_offset': ''},
        },
      },
    })!;
    expect(b.isEnd, true);
    final c = parseReplyPage({
      'code': 0,
      'data': {'replies': <dynamic>[]},
    })!;
    expect(c.isEnd, true);
    expect(c.items, isEmpty);
  });

  test('欄位缺漏略過該則；code 非 0 回傳 null', () {
    final page = parseReplyPage({
      'code': 0,
      'data': {
        'replies': [
          {'ctime': 1},
          _reply(4),
        ],
      },
    })!;
    expect(page.items.map((e) => e.rpid), [4]);
    expect(parseReplyPage({'code': -400}), isNull);
  });
}
