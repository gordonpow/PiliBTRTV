import 'package:bili_tv_app/services/api/auth_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = 'https://passport.biligame.com/x/passport-login/web/crossDomain';

  group('parseWebLoginCookies', () {
    test('成功並保留 %2C 與 * 原樣', () {
      final r = parseWebLoginCookies(
        '$base?DedeUserID=12345&DedeUserID__ckMd5=abc&Expires=1&'
        'SESSDATA=abc%2C123%2Cx*y&bili_jct=jct1&gourl=https%3A%2F%2Fwww.bilibili.com',
      );
      expect(r, {
        'SESSDATA': 'abc%2C123%2Cx*y',
        'bili_jct': 'jct1',
        'DedeUserID': '12345',
      });
    });

    test('缺欄位回傳 null', () {
      expect(parseWebLoginCookies('$base?DedeUserID=1&SESSDATA=a'), isNull);
    });

    test('不安全字元回傳 null', () {
      for (final bad in ['a b', 'a;b', 'a"b']) {
        expect(
          parseWebLoginCookies('$base?DedeUserID=1&bili_jct=j&SESSDATA=$bad'),
          isNull,
        );
      }
    });

    test('DedeUserID 非數字回傳 null', () {
      expect(
        parseWebLoginCookies('$base?DedeUserID=abc&bili_jct=j&SESSDATA=s'),
        isNull,
      );
    });

    test('沒有 ? 回傳 null', () {
      expect(parseWebLoginCookies(base), isNull);
    });

    test('忽略多餘參數', () {
      final r = parseWebLoginCookies(
        '$base?foo=1&DedeUserID=9&bar=2&bili_jct=j&SESSDATA=s&gourl=x',
      );
      expect(r, {'SESSDATA': 's', 'bili_jct': 'j', 'DedeUserID': '9'});
    });
  });

  group('validateWebLoginCookies', () {
    final ok = {'SESSDATA': 'a%2Cb', 'bili_jct': 'j', 'DedeUserID': '1'};

    test('完整通過', () {
      expect(validateWebLoginCookies(ok), ok);
    });

    test('缺欄位回傳 null', () {
      expect(validateWebLoginCookies({...ok}..remove('bili_jct')), isNull);
      expect(validateWebLoginCookies({...ok, 'SESSDATA': ''}), isNull);
    });

    test('不安全值回傳 null', () {
      expect(validateWebLoginCookies({...ok, 'SESSDATA': 'a;b'}), isNull);
    });

    test('DedeUserID 非數字回傳 null', () {
      expect(validateWebLoginCookies({...ok, 'DedeUserID': 'x1'}), isNull);
    });
  });

  test('isSafeCookieValue 拒絕分號、接受 %2C', () {
    expect(isSafeCookieValue('a;b'), isFalse);
    expect(isSafeCookieValue('a%2Cb'), isTrue);
  });
}
