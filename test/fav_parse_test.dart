import 'package:bili_tv_app/models/video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Video.fromFav 解析欄位', () {
    final v = Video.fromFav({
      'bvid': 'BV1fav',
      'title': '收藏影片',
      'cover': '//i0.hdslb.com/c.jpg',
      'upper': {'name': 'UP', 'mid': 7},
      'duration': 125,
      'cnt_info': {'play': 12000, 'danmaku': 30},
      'pubtime': 1700000000,
    });
    expect(v.bvid, 'BV1fav');
    expect(v.pic, 'https://i0.hdslb.com/c.jpg');
    expect(v.ownerName, 'UP');
    expect(v.ownerMid, 7);
    expect(v.view, 12000);
    expect(v.duration, 125);
    expect(v.pubdate, 1700000000);
  });

  test('Video.fromFav 缺欄位不拋錯', () {
    final v = Video.fromFav({});
    expect(v.bvid, '');
    expect(v.view, 0);
  });

  test('Video.fromToView 解析欄位', () {
    final v = Video.fromToView({
      'bvid': 'BV1late',
      'cid': 99,
      'title': '稍後',
      'pic': 'http://i0.hdslb.com/p.jpg',
      'owner': {'name': 'O', 'mid': 5, 'face': '//f.jpg'},
      'duration': 60,
      'stat': {'view': 321, 'danmaku': 4},
      'pubdate': 1600000000,
    });
    expect(v.bvid, 'BV1late');
    expect(v.cid, 99);
    expect(v.ownerName, 'O');
    expect(v.ownerFace, 'https://f.jpg');
    expect(v.view, 321);
    expect(v.danmaku, 4);
    expect(v.pubdate, 1600000000);
  });
}
