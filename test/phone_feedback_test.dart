import 'package:bili_tv_app/services/phone_feedback_service.dart';
import 'package:bili_tv_app/services/report_send_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('composeFeedbackReport', () {
    const log = '== 最近的執行紀錄 ==\nsome log line';

    test('建議只含文字、版本與裝置，不含 log', () {
      final r = composeFeedbackReport(
        type: FeedbackType.suggestion,
        text: '想要新功能',
        version: 'v1.0',
        device: 'Foo Bar',
        fullReport: log,
      );
      expect(r, contains('使用者建議：\n想要新功能'));
      expect(r, contains('版本：v1.0'));
      expect(r, contains('裝置：Foo Bar'));
      expect(r.contains('some log line'), isFalse);
    });

    test('問題附上完整報告', () {
      final r = composeFeedbackReport(
        type: FeedbackType.issue,
        text: '會卡住',
        version: 'v1.0',
        device: 'Foo Bar',
        fullReport: log,
      );
      expect(r, startsWith('使用者描述：\n會卡住\n\n'));
      expect(r, contains('some log line'));
    });
  });

  group('PhoneFeedbackService token', () {
    late DateTime now;
    late PhoneFeedbackService service;

    setUp(() {
      now = DateTime(2026, 1, 1, 12);
      service = PhoneFeedbackService.forTest(clock: () => now);
    });

    String tokenOf(String url) => Uri.parse(url).queryParameters['t']!;

    test('start 回傳網址，代碼為 16 碼', () {
      final url = service.start()!;
      expect(url, startsWith('http://127.0.0.1:3322/feedback?t='));
      expect(tokenOf(url).length, 16);
    });

    test('沒有區網位址時回傳 null', () {
      final s = PhoneFeedbackService.forTest(addressProvider: () => null);
      expect(s.start(), isNull);
      expect(s.checkToken('x'), isFalse);
    });

    test('正確代碼通過，錯誤、空值、未啟動都拒絕', () {
      expect(service.checkToken('abc'), isFalse);
      final t = tokenOf(service.start()!);
      expect(service.checkToken(t), isTrue);
      expect(service.checkToken('wrong'), isFalse);
      expect(service.checkToken(null), isFalse);
      expect(service.checkToken(t), isTrue);
    });

    test('15 分鐘後到期', () {
      final t = tokenOf(service.start()!);
      now = now.add(const Duration(minutes: 14, seconds: 59));
      expect(service.checkToken(t), isTrue);
      now = now.add(const Duration(seconds: 1));
      expect(service.checkToken(t), isFalse);
      expect(service.hasToken, isFalse);
    });

    test('錯誤次數達上限後代碼作廢', () {
      final t = tokenOf(service.start()!);
      for (var i = 0; i < PhoneFeedbackService.maxBadTokens; i++) {
        expect(service.checkToken('bad'), isFalse);
      }
      expect(service.checkToken(t), isFalse);
    });

    test('stop 後代碼失效', () {
      final t = tokenOf(service.start()!);
      service.stop();
      expect(service.checkToken(t), isFalse);
    });
  });

  group('PhoneFeedbackService submit', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('成功：代碼失效、通知電視、寫入紀錄並帶分類', () async {
      String? gotReport;
      String? gotLabel;
      final s = PhoneFeedbackService.forTest(
        deviceProvider: () async => 'Dev',
        sender: ({required report, required categoryLabel}) async {
          gotReport = report;
          gotLabel = categoryLabel;
          return const ReportSendResult.ok('ABC234');
        },
      );
      final t = Uri.parse(s.start()!).queryParameters['t']!;
      final out = await s.submit(FeedbackType.suggestion, '好用');
      expect(out, {'ok': true, 'id': 'ABC234'});
      expect(gotLabel, '建議');
      expect(gotReport, contains('裝置：Dev'));
      expect(s.lastSent.value?.id, 'ABC234');
      expect(s.checkToken(t), isFalse);
      final history = await ReportHistory.load();
      expect(history.first.id, 'ABC234');
      expect(history.first.category, '建議');
    });

    test('失敗：錯誤訊息原樣回傳，代碼保留', () async {
      final s = PhoneFeedbackService.forTest(
        sender: ({required report, required categoryLabel}) async =>
            const ReportSendResult.fail('回報太頻繁，請稍後再試'),
      );
      final t = Uri.parse(s.start()!).queryParameters['t']!;
      final out = await s.submit(FeedbackType.issue, '壞了');
      expect(out, {'ok': false, 'error': '回報太頻繁，請稍後再試'});
      expect(s.lastSent.value, isNull);
      expect(s.checkToken(t), isTrue);
    });
  });
}
