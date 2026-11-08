import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bili_tv_app/btr_version.dart';
import 'package:bili_tv_app/config/report_config.dart';
import 'package:bili_tv_app/services/error_report_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 問題類型。
enum ReportCategory {
  stutter('播放卡頓／畫面問題'),
  login('無法登入'),
  crash('閃退／當機'),
  playback('無法播放'),
  other('其他');

  final String label;
  const ReportCategory(this.label);
}

/// 送出結果。
class ReportSendResult {
  final bool ok;
  final String id;
  final String message;

  const ReportSendResult.ok(this.id) : ok = true, message = '';
  const ReportSendResult.fail(this.message) : ok = false, id = '';
}

const String kReportIdChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const int kReportMaxBytes = 400 * 1024;
const int kReportHeadBytes = 20 * 1024;
const String kReportTruncMarker = '\n…（中略）…\n';

/// 產生 6 碼回報編號。
String generateReportId([Random? rng]) {
  final r = rng ?? Random.secure();
  return String.fromCharCodes(
    List.generate(
      6,
      (_) => kReportIdChars.codeUnitAt(r.nextInt(kReportIdChars.length)),
    ),
  );
}

bool _isCont(int b) => (b & 0xC0) == 0x80;

/// 以 UTF-8 位元組數截斷：保留開頭 [headBytes] 與結尾，中間以標記取代。
String truncateReportBytes(
  String report, {
  int maxBytes = kReportMaxBytes,
  int headBytes = kReportHeadBytes,
}) {
  final bytes = utf8.encode(report);
  if (bytes.length <= maxBytes) return report;
  final marker = utf8.encode(kReportTruncMarker);
  var headEnd = min(headBytes, maxBytes - marker.length);
  while (headEnd > 0 && headEnd < bytes.length && _isCont(bytes[headEnd])) {
    headEnd--;
  }
  var tailStart = bytes.length - (maxBytes - headEnd - marker.length);
  while (tailStart < bytes.length && _isCont(bytes[tailStart])) {
    tailStart++;
  }
  return utf8.decode(bytes.sublist(0, headEnd)) +
      kReportTruncMarker +
      utf8.decode(bytes.sublist(tailStart));
}

/// 腳本錯誤碼對應的使用者訊息。
String reportErrorMessage(String code) {
  switch (code) {
    case 'rate':
      return '回報太頻繁，請稍後再試';
    case 'quota':
      return '今日回報已達上限，請改用手機查看';
    default:
      return '送出失敗（$code）';
  }
}

/// 解析腳本回應 JSON。非 JSON 視為腳本未公開。
ReportSendResult parseScriptResponse(
  String body, {
  required String fallbackId,
}) {
  Object? json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    return const ReportSendResult.fail('送出失敗（腳本未公開）');
  }
  if (json is! Map) return const ReportSendResult.fail('送出失敗（腳本未公開）');
  if (json['ok'] == true) {
    final id = json['id'];
    return ReportSendResult.ok(id is String && id.isNotEmpty ? id : fallbackId);
  }
  return ReportSendResult.fail(reportErrorMessage('${json['error'] ?? '未知'}'));
}

bool isRedirectStatus(int s) =>
    s == 301 || s == 302 || s == 303 || s == 307 || s == 308;

class ReportSendService {
  ReportSendService._();

  static bool get enabled => kReportScriptUrl.isNotEmpty;

  static Future<String> installId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('report_install_id');
    if (id == null || id.length < 16) {
      final r = Random.secure();
      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
      id = String.fromCharCodes(
        List.generate(16, (_) => chars.codeUnitAt(r.nextInt(chars.length))),
      );
      await prefs.setString('report_install_id', id);
    }
    return id;
  }

  static String newReportId() => generateReportId();

  static Future<ReportSendResult> send({
    required ReportCategory category,
    required String report,
    String? reportId,
  }) async {
    final id = reportId ?? newReportId();
    final client = http.Client();
    try {
      final dev = await ErrorReportService.deviceSummary();
      final payload = jsonEncode({
        'id': id,
        'installId': await installId(),
        'category': category.label,
        'version': btrVersion,
        'device': dev['device'] ?? '',
        'android': dev['android'] ?? '',
        'report': truncateReportBytes(report),
      });
      final uri = Uri.parse(kReportScriptUrl);
      final req = http.Request('POST', uri)
        ..followRedirects = false
        ..headers['Content-Type'] = 'text/plain;charset=utf-8'
        ..body = payload;
      final streamed = await client
          .send(req)
          .timeout(const Duration(seconds: 20));
      final resp = await http.Response.fromStream(streamed);
      if (isRedirectStatus(resp.statusCode)) {
        final loc = resp.headers['location'];
        if (loc == null || loc.isEmpty) {
          return const ReportSendResult.fail('送出失敗（無回應）');
        }
        // POST 已被腳本收到；echo GET 失敗視為已送出（未收到確認）
        try {
          final r2 = await client
              .get(uri.resolve(loc))
              .timeout(const Duration(seconds: 10));
          final parsed = parseScriptResponse(r2.body, fallbackId: id);
          if (!parsed.ok && parsed.message == '送出失敗（腳本未公開）') {
            debugPrint('回報：echo 回應非 JSON，HTTP ${r2.statusCode}');
          }
          return parsed;
        } catch (e) {
          debugPrint('回報：echo GET 失敗 $e');
          return ReportSendResult.ok(id);
        }
      }
      if (resp.statusCode == 200) {
        final parsed = parseScriptResponse(resp.body, fallbackId: id);
        if (!parsed.ok && parsed.message == '送出失敗（腳本未公開）') {
          debugPrint('回報：回應非 JSON，HTTP ${resp.statusCode}');
        }
        return parsed;
      }
      debugPrint('回報：HTTP ${resp.statusCode}');
      return ReportSendResult.fail('送出失敗（HTTP ${resp.statusCode}）');
    } on SocketException {
      return const ReportSendResult.fail('無法連線，請確認網路');
    } on TimeoutException {
      return const ReportSendResult.fail('連線逾時，請稍後再試');
    } on http.ClientException {
      return const ReportSendResult.fail('無法連線，請確認網路');
    } catch (e) {
      return ReportSendResult.fail('送出失敗（${e.runtimeType}）');
    } finally {
      client.close();
    }
  }
}
