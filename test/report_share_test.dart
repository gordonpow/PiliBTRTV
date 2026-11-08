import 'package:bili_tv_app/services/report_share_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('代碼正確通過，錯誤、空值被拒', () async {
    final s = ReportShareService.forTest();
    final url = await s.start('hello');
    expect(url, isNotNull);
    final token = Uri.parse(url!).queryParameters['t']!;
    expect(token.length, 16);
    expect(s.checkToken(token), isTrue);
    expect(s.text, 'hello');
    expect(s.checkToken('wrong'), isFalse);
    expect(s.checkToken(null), isFalse);
    expect(s.checkToken(''), isFalse);
  });

  test('超過 30 分鐘過期', () async {
    var now = DateTime(2026, 1, 1);
    final s = ReportShareService.forTest(clock: () => now);
    final token = Uri.parse((await s.start('x'))!).queryParameters['t']!;
    now = now.add(const Duration(minutes: 29));
    expect(s.checkToken(token), isTrue);
    now = now.add(const Duration(minutes: 2));
    expect(s.checkToken(token), isFalse);
  });

  test('stop 之後代碼失效', () async {
    final s = ReportShareService.forTest();
    final token = Uri.parse((await s.start('x'))!).queryParameters['t']!;
    s.stop();
    expect(s.checkToken(token), isFalse);
    expect(s.text, '');
  });

  test('沒有區網位址回傳 null', () async {
    final s = ReportShareService.forTest(addressProvider: () => null);
    expect(await s.start('x'), isNull);
    expect(s.checkToken('anything'), isFalse);
  });
}
