import 'dart:convert';
import 'dart:math';

import 'package:bili_tv_app/services/report_send_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generateReportId', () {
    test('6 碼且只含允許字元', () {
      final rng = Random(1);
      for (var i = 0; i < 200; i++) {
        final id = generateReportId(rng);
        expect(id.length, 6);
        expect(RegExp('^[$kReportIdChars]{6}\$').hasMatch(id), isTrue);
        expect(id.contains(RegExp('[01OI]')), isFalse);
      }
    });
  });

  group('truncateReportBytes', () {
    test('未超過不變', () {
      expect(truncateReportBytes('abc', maxBytes: 100), 'abc');
    });

    test('超過時位元組數不超過上限，保留頭尾', () {
      final text = 'H' * 50 + 'M' * 1000 + 'T' * 50;
      final r = truncateReportBytes(text, maxBytes: 200, headBytes: 50);
      expect(utf8.encode(r).length, lessThanOrEqualTo(200));
      expect(r.startsWith('H' * 50), isTrue);
      expect(r.endsWith('T' * 50), isTrue);
      expect(r.contains('中略'), isTrue);
    });

    test('多位元組字元不會被截壞', () {
      final text = '中' * 5000;
      final r = truncateReportBytes(text, maxBytes: 1001, headBytes: 100);
      expect(utf8.encode(r).length, lessThanOrEqualTo(1001));
      expect(r.contains('�'), isFalse);
    });
  });

  group('parseScriptResponse', () {
    test('ok 回傳腳本編號', () {
      final r = parseScriptResponse(
        '{"ok":true,"id":"ABC234"}',
        fallbackId: 'XXXXXX',
      );
      expect(r.ok, isTrue);
      expect(r.id, 'ABC234');
    });

    test('ok 無 id 用備用編號', () {
      final r = parseScriptResponse('{"ok":true}', fallbackId: 'XXXXXX');
      expect(r.id, 'XXXXXX');
    });

    test('rate / quota / 其他錯誤', () {
      expect(
        parseScriptResponse(
          '{"ok":false,"error":"rate"}',
          fallbackId: 'A',
        ).message,
        '回報太頻繁，請稍後再試',
      );
      expect(
        parseScriptResponse(
          '{"ok":false,"error":"quota"}',
          fallbackId: 'A',
        ).message,
        '今日回報已達上限，請改用手機查看',
      );
      expect(
        parseScriptResponse(
          '{"ok":false,"error":"size"}',
          fallbackId: 'A',
        ).message,
        '送出失敗（size）',
      );
    });

    test('非 JSON 視為腳本未公開', () {
      final r = parseScriptResponse('<html>login</html>', fallbackId: 'A');
      expect(r.ok, isFalse);
      expect(r.message, '送出失敗（腳本未公開）');
    });
  });

  test('isRedirectStatus', () {
    expect(isRedirectStatus(302), isTrue);
    expect(isRedirectStatus(200), isFalse);
  });

  group('report history', () {
    ReportRecord rec(int n) => ReportRecord(
      id: 'ID$n',
      time: DateTime(2026, 11, 9, 10, n % 60),
      category: '其他',
    );

    test('最新在前且最多 20 筆', () {
      var raw = '[]';
      for (var i = 0; i < 25; i++) {
        raw = encodeReportHistory(rec(i), decodeReportHistory(raw));
      }
      final list = decodeReportHistory(raw);
      expect(list.length, kReportHistoryMax);
      expect(list.first.id, 'ID24');
      expect(list.last.id, 'ID5');
      expect(list.first.time, DateTime(2026, 11, 9, 10, 24));
    });

    test('壞 JSON 回傳空清單', () {
      expect(decodeReportHistory(null), isEmpty);
      expect(decodeReportHistory('not json'), isEmpty);
      expect(decodeReportHistory('{"a":1}'), isEmpty);
    });
  });
}
