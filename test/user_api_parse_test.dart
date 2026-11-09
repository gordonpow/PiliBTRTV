import 'package:bili_tv_app/services/api/user_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MyInfo.fromNav', () {
    test('解析完整欄位', () {
      final i = MyInfo.fromNav({
        'mid': 123,
        'uname': '測試',
        'face': '//i0.hdslb.com/a.jpg',
        'level_info': {
          'current_level': 5,
          'current_exp': 1200,
          'next_exp': 2000,
        },
        'money': 12.5,
        'wallet': {'bcoin_balance': 3},
        'vipStatus': 1,
        'vipDueDate': 1700000000000,
        'vip_label': {'text': '年度大會員'},
      });
      expect(i.mid, 123);
      expect(i.face, 'https://i0.hdslb.com/a.jpg');
      expect(i.level, 5);
      expect(i.nextExp, 2000);
      expect(i.coins, 12.5);
      expect(i.bcoin, 3.0);
      expect(i.isVip, true);
      expect(i.vipDueMs, 1700000000000);
      expect(i.vipLabel, '年度大會員');
    });

    test('next_exp 為 "--" 時為 null，缺欄位不拋錯', () {
      final i = MyInfo.fromNav({
        'level_info': {
          'current_level': 6,
          'current_exp': 99999,
          'next_exp': '--',
        },
      });
      expect(i.nextExp, isNull);
      expect(i.isVip, false);
      expect(i.coins, 0);
      expect(i.uname, '');
    });
  });

  test('MyStat.fromJson', () {
    final s = MyStat.fromJson({
      'following': 10,
      'follower': 2000,
      'dynamic_count': 3,
    });
    expect(s.following, 10);
    expect(s.follower, 2000);
    expect(s.dynamicCount, 3);
    expect(MyStat.fromJson({}).follower, 0);
  });

  group('FollowingPage.fromJson', () {
    test('解析清單與 total，略過壞資料', () {
      final p = FollowingPage.fromJson({
        'total': 42,
        'list': [
          {'mid': 1, 'uname': 'A', 'face': '//x/y.jpg', 'sign': 's'},
          {'uname': 'no mid'},
          'bad',
        ],
      });
      expect(p.total, 42);
      expect(p.list.length, 1);
      expect(p.list.first.face, 'https://x/y.jpg');
      expect(p.list.first.sign, 's');
    });

    test('空頁', () {
      final p = FollowingPage.fromJson({'list': []});
      expect(p.list, isEmpty);
      expect(p.total, 0);
    });
  });
}
