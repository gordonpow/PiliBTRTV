import 'dart:async';
import 'dart:math';

import 'package:bili_tv_app/btr_version.dart';
import 'package:flutter/foundation.dart';

import 'error_report_service.dart';
import 'local_server.dart';
import 'phone_login_service.dart' show constantTimeEquals;
import 'report_send_service.dart';

/// 手機回報的類型。
enum FeedbackType {
  issue('問題（手機輸入）'),
  suggestion('建議');

  final String label;
  const FeedbackType(this.label);

  static FeedbackType? parse(Object? v) {
    if (v == 'issue') return FeedbackType.issue;
    if (v == 'suggestion') return FeedbackType.suggestion;
    return null;
  }
}

/// 送出成功的事件，給電視端對話框顯示。
class FeedbackEvent {
  final String id;
  final FeedbackType type;
  const FeedbackEvent(this.id, this.type);
}

/// 手機回報文字的字數上限。
const int kFeedbackMaxChars = 2000;

/// 組出要寄給開發者的內容。
///
/// 「問題」附上完整診斷報告 [fullReport]；「建議」只附文字、版本與裝置，
/// 不含 log、設定與效能資料。
String composeFeedbackReport({
  required FeedbackType type,
  required String text,
  required String version,
  required String device,
  String fullReport = '',
}) {
  switch (type) {
    case FeedbackType.issue:
      return '使用者描述：\n$text\n\n$fullReport';
    case FeedbackType.suggestion:
      return '使用者建議：\n$text\n\n版本：$version\n裝置：$device';
  }
}

/// 送出單一回報的函式（測試時可替換）。
typedef FeedbackSender =
    Future<ReportSendResult> Function({
      required String report,
      required String categoryLabel,
    });

/// 手機輸入回報：一次性代碼與送出流程。
///
/// 代碼規則比照 [PhoneLoginService]：16 碼、15 分鐘到期、錯誤次數有上限。
/// 送出成功後代碼立即失效。
class PhoneFeedbackService {
  static final PhoneFeedbackService instance = PhoneFeedbackService._(
    addressProvider: () => LocalServer.instance.address,
  );

  PhoneFeedbackService._({
    required String? Function() addressProvider,
    DateTime Function()? clock,
    FeedbackSender? sender,
    Future<String> Function()? fullReportBuilder,
    Future<String> Function()? deviceProvider,
  }) : _addressProvider = addressProvider,
       _now = clock ?? DateTime.now,
       _sender = sender ?? _defaultSender,
       _fullReportBuilder = fullReportBuilder ?? _defaultFullReport,
       _deviceProvider = deviceProvider ?? _defaultDevice;

  @visibleForTesting
  PhoneFeedbackService.forTest({
    String? Function()? addressProvider,
    DateTime Function()? clock,
    FeedbackSender? sender,
    Future<String> Function()? fullReportBuilder,
    Future<String> Function()? deviceProvider,
  }) : _addressProvider = addressProvider ?? (() => 'http://127.0.0.1:3322'),
       _now = clock ?? DateTime.now,
       _sender = sender ?? _defaultSender,
       _fullReportBuilder = fullReportBuilder ?? (() async => ''),
       _deviceProvider = deviceProvider ?? (() async => '');

  static const Duration tokenLifetime = Duration(minutes: 15);
  static const int maxBadTokens = 10;
  static const String _chars =
      'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 去掉 0 O 1 l I 等易混淆字元

  final String? Function() _addressProvider;
  final DateTime Function() _now;
  final FeedbackSender _sender;
  final Future<String> Function() _fullReportBuilder;
  final Future<String> Function() _deviceProvider;

  /// 最近一次送出成功的事件；電視端對話框監聽它。
  final ValueNotifier<FeedbackEvent?> lastSent = ValueNotifier<FeedbackEvent?>(
    null,
  );

  String? _token;
  DateTime? _expiry;
  int _badCount = 0;
  bool _sending = false;

  /// 目前是否有可用的代碼（測試用）
  @visibleForTesting
  bool get hasToken => _token != null;

  /// 產生代碼並回傳完整網址；沒有區網位址時回傳 null。
  String? start() {
    stop();
    final address = _addressProvider();
    if (address == null) return null;
    final rnd = Random.secure();
    final token = String.fromCharCodes(
      Iterable.generate(
        16,
        (_) => _chars.codeUnitAt(rnd.nextInt(_chars.length)),
      ),
    );
    _token = token;
    _expiry = _now().add(tokenLifetime);
    lastSent.value = null;
    return '$address/feedback?t=$token';
  }

  /// 對話框關閉時呼叫：代碼立即失效。
  void stop() {
    _token = null;
    _expiry = null;
    _badCount = 0;
  }

  /// 檢查請求帶的代碼。錯誤、過期、已失效都回 false；連續錯誤太多時作廢代碼。
  bool checkToken(String? candidate) {
    final token = _token;
    if (token == null) return false;
    final expiry = _expiry;
    if (expiry != null && !_now().isBefore(expiry)) {
      stop();
      return false;
    }
    if (!constantTimeEquals(candidate ?? '', token)) {
      _badCount++;
      if (_badCount >= maxBadTokens) stop();
      return false;
    }
    return true;
  }

  /// 檢查並送出。回傳給手機頁的 JSON：`{ok: true, id}` 或 `{ok: false, error}`。
  ///
  /// 成功後代碼失效；失敗時代碼保留，手機可以再送。
  Future<Map<String, dynamic>> submit(FeedbackType type, String text) async {
    if (_sending) return {'ok': false, 'error': '正在送出，請稍候'};
    _sending = true;
    try {
      String fullReport = '';
      if (type == FeedbackType.issue) {
        try {
          fullReport = await _fullReportBuilder();
        } catch (e) {
          fullReport = '（報告產生失敗：${e.runtimeType}）';
        }
      }
      final device = type == FeedbackType.suggestion
          ? await _deviceProvider()
          : '';
      final report = composeFeedbackReport(
        type: type,
        text: text,
        version: btrVersion,
        device: device,
        fullReport: fullReport,
      );
      final result = await _sender(report: report, categoryLabel: type.label);
      if (!result.ok) {
        // 限流等錯誤訊息原樣回給手機頁
        return {'ok': false, 'error': result.message};
      }
      await ReportHistory.add(
        id: result.id,
        category: ReportCategory.other,
        categoryLabel: type.label,
      );
      stop();
      lastSent.value = FeedbackEvent(result.id, type);
      return {'ok': true, 'id': result.id};
    } finally {
      _sending = false;
    }
  }

  static Future<ReportSendResult> _defaultSender({
    required String report,
    required String categoryLabel,
  }) {
    if (!ReportSendService.enabled) {
      return Future.value(const ReportSendResult.fail('此版本未啟用回報功能'));
    }
    return ReportSendService.send(
      category: ReportCategory.other,
      categoryLabel: categoryLabel,
      report: report,
    );
  }

  static Future<String> _defaultFullReport() =>
      ErrorReportService.buildReport();

  static Future<String> _defaultDevice() async {
    final dev = await ErrorReportService.deviceSummary();
    return dev['device'] ?? '';
  }
}
