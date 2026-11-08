import 'package:bili_tv_app/services/api/app_sign.dart';
import 'package:bili_tv_app/services/phone_login_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appSign', () {
    test('matches PiliPlus algorithm for a fixed input and ts', () {
      final params = <String, dynamic>{
        'b': '2',
        'a': 'hello world',
        // 與 PiliPlus 一樣，dt 先 encodeComponent 再進 appSign
        'dt': Uri.encodeComponent('a+b/c=='),
      };
      AppSign.appSign(params, ts: 1700000000);
      expect(params['appkey'], 'dfca71928277209b');
      expect(params['ts'], '1700000000');
      // 簽名原文：
      // a=hello%20world&appkey=dfca71928277209b&b=2
      //   &dt=a%252Bb%252Fc%253D%253D&ts=1700000000 + appsec
      expect(params['sign'], 'c53a719c778ba46a617468bb35513149');
    });
  });

  group('token check', () {
    test('rejects wrong token, accepts right one', () {
      final s = PhoneLoginService.forTest();
      final url = s.start()!;
      final token = Uri.parse(url).queryParameters['t']!;
      expect(token.length, 16);
      expect(s.checkToken(token), isTrue);
      expect(s.checkToken('wrong-token-0000'), isFalse);
      expect(s.checkToken(null), isFalse);
      expect(s.checkToken(''), isFalse);
      s.stop();
      expect(s.checkToken(token), isFalse);
    });

    test('rejects expired token', () {
      var now = DateTime(2026, 1, 1, 12);
      final s = PhoneLoginService.forTest(clock: () => now);
      final token = Uri.parse(s.start()!).queryParameters['t']!;
      now = now.add(const Duration(minutes: 14));
      expect(s.checkToken(token), isTrue);
      now = now.add(const Duration(minutes: 2));
      expect(s.checkToken(token), isFalse);
      s.stop();
    });

    test('10 bad tokens regenerate the token', () {
      final s = PhoneLoginService.forTest();
      final first = Uri.parse(s.start()!).queryParameters['t']!;
      for (var i = 0; i < PhoneLoginService.maxBadTokens; i++) {
        expect(s.checkToken('bad'), isFalse);
      }
      expect(s.checkToken(first), isFalse);
      final second = Uri.parse(s.url.value!).queryParameters['t']!;
      expect(second, isNot(first));
      expect(s.checkToken(second), isTrue);
      s.stop();
    });

    test('no address gives null url', () {
      final s = PhoneLoginService.forTest(addressProvider: () => null);
      expect(s.start(), isNull);
      expect(s.checkToken('anything'), isFalse);
    });

    test('constantTimeEquals', () {
      expect(constantTimeEquals('abc', 'abc'), isTrue);
      expect(constantTimeEquals('abc', 'abd'), isFalse);
      expect(constantTimeEquals('abc', 'abcd'), isFalse);
    });
  });

  group('parseLoginCookie', () {
    test('splits on first = and keeps only the three keys', () {
      final c = parseLoginCookie(
        'SESSDATA=abc%2Cdef=ghi; bili_jct=jct123 ; DedeUserID=42; other=x',
      );
      expect(c, {
        'SESSDATA': 'abc%2Cdef=ghi',
        'bili_jct': 'jct123',
        'DedeUserID': '42',
      });
    });

    test('ignores malformed parts', () {
      expect(parseLoginCookie('novalue; =x; SESSDATA='), isEmpty);
    });
  });
}
