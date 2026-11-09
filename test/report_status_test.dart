import 'dart:async';

import 'package:bili_tv_app/services/report_status_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _good =
    '{"version":1,"reports":{"abc123":{"status":"resolved","note":"ok"}}}';

void main() {
  group('decodeReportStatus', () {
    test('正常解析', () {
      final m = decodeReportStatus(
        '{"version":1,"reports":{"A":{"status":"resolved","note":"x"},'
        '"B":{"status":"in_progress"},"C":{"status":"cannot_reproduce"}}}',
      );
      expect(m['A']!.kind, ReportStatusKind.resolved);
      expect(m['A']!.note, 'x');
      expect(m['B']!.kind, ReportStatusKind.inProgress);
      expect(m['B']!.note, isNull);
      expect(m['C']!.kind, ReportStatusKind.cannotReproduce);
      expect(ReportStatusKind.resolved.label, '已解決');
    });

    test('未知狀態忽略該筆', () {
      final m = decodeReportStatus(
        '{"reports":{"A":{"status":"weird"},"B":{"status":"resolved"}}}',
      );
      expect(m.containsKey('A'), isFalse);
      expect(m.containsKey('B'), isTrue);
    });

    test('單筆型別錯只跳過該筆', () {
      final m = decodeReportStatus(
        '{"reports":{"A":{"status":1},"B":"str","C":{"status":"resolved"},'
        '"D":{"status":"resolved","note":123}}}',
      );
      expect(m.keys.toSet(), {'C', 'D'});
      expect(m['D']!.note, isNull);
    });

    test('reports 非 Map', () {
      expect(decodeReportStatus('{"reports":[1,2]}'), isEmpty);
      expect(tryDecodeReportStatus('{"reports":"x"}'), isNull);
    });

    test('壞 JSON', () {
      expect(decodeReportStatus('not json'), isEmpty);
      expect(tryDecodeReportStatus('not json'), isNull);
      expect(tryDecodeReportStatus('[1]'), isNull);
    });

    test('version 缺少仍可解析', () {
      final m = decodeReportStatus('{"reports":{"A":{"status":"resolved"}}}');
      expect(m.length, 1);
    });

    test('編號轉大寫並去空白', () {
      final m = decodeReportStatus(
        '{"reports":{" ekakjq ":{"status":"resolved"}}}',
      );
      expect(m.containsKey('EKAKJQ'), isTrue);
    });

    test('note 以 runes 截到 80 字不切斷 emoji', () {
      final long = '😀' * 100;
      final m = decodeReportStatus(
        '{"reports":{"A":{"status":"resolved","note":"$long"}}}',
      );
      final note = m['A']!.note!;
      expect(note.runes.length, 80);
      expect(note, '😀' * 80);
    });
  });

  group('ReportStatusService.load', () {
    test('200 合法存快取', () async {
      String? written;
      final m = await ReportStatusService.load(
        fetch: (_) async => const ReportFetchResult(200, _good),
        readCache: () async => null,
        writeCache: (raw) async => written = raw,
        clearCache: () async {},
      );
      expect(written, _good);
      expect(m['ABC123']!.kind, ReportStatusKind.resolved);
    });

    test('網址帶 ?t= 時間戳', () async {
      Uri? seen;
      await ReportStatusService.load(
        fetch: (u) async {
          seen = u;
          return const ReportFetchResult(200, _good);
        },
        readCache: () async => null,
        writeCache: (_) async {},
        clearCache: () async {},
      );
      expect(seen!.queryParameters.containsKey('t'), isTrue);
    });

    test('404 清快取回空', () async {
      var cleared = false;
      final m = await ReportStatusService.load(
        fetch: (_) async => const ReportFetchResult(404, 'Not Found'),
        readCache: () async => _good,
        writeCache: (_) async {},
        clearCache: () async => cleared = true,
      );
      expect(cleared, isTrue);
      expect(m, isEmpty);
    });

    test('200 壞內容不覆蓋快取並回快取', () async {
      var wrote = false;
      final m = await ReportStatusService.load(
        fetch: (_) async => const ReportFetchResult(200, 'garbage'),
        readCache: () async => _good,
        writeCache: (_) async => wrote = true,
        clearCache: () async {},
      );
      expect(wrote, isFalse);
      expect(m.containsKey('ABC123'), isTrue);
    });

    test('逾時回快取', () async {
      final m = await ReportStatusService.load(
        fetch: (_) async => throw TimeoutException('t'),
        readCache: () async => _good,
        writeCache: (_) async {},
        clearCache: () async {},
      );
      expect(m.containsKey('ABC123'), isTrue);
    });

    test('無快取回空', () async {
      final m = await ReportStatusService.load(
        fetch: (_) async => throw TimeoutException('t'),
        readCache: () async => null,
        writeCache: (_) async {},
        clearCache: () async {},
      );
      expect(m, isEmpty);
    });
  });
}
