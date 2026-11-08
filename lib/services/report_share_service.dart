import 'dart:math';

import 'package:flutter/foundation.dart';

import 'local_server.dart';
import 'phone_login_service.dart' show constantTimeEquals;

/// 把錯誤報告暫存在記憶體，讓同一個 Wi-Fi 的手機透過 LocalServer 查看。
class ReportShareService {
  static final ReportShareService instance = ReportShareService._(
    addressProvider: () => LocalServer.instance.address,
    isRunning: () => LocalServer.instance.isRunning,
    refresh: () => LocalServer.instance.refreshAddress(),
  );

  ReportShareService._({
    required String? Function() addressProvider,
    required bool Function() isRunning,
    required Future<void> Function() refresh,
    DateTime Function()? clock,
  }) : _addressProvider = addressProvider,
       _isRunning = isRunning,
       _refresh = refresh,
       _now = clock ?? DateTime.now;

  @visibleForTesting
  ReportShareService.forTest({
    String? Function()? addressProvider,
    DateTime Function()? clock,
  }) : _addressProvider = addressProvider ?? (() => 'http://127.0.0.1:3322'),
       _isRunning = (() => true),
       _refresh = (() async {}),
       _now = clock ?? DateTime.now;

  static const Duration tokenLifetime = Duration(minutes: 30);
  static const String _chars =
      'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 去掉 0 O 1 l I 等易混淆字元

  final String? Function() _addressProvider;
  final bool Function() _isRunning;
  final Future<void> Function() _refresh;
  final DateTime Function() _now;

  String? _token;
  String? _text;
  DateTime? _expiry;

  /// 開始分享；沒有區網位址或服務沒在跑時回傳 null。
  Future<String?> start(String text) async {
    await _refresh();
    final addr = _addressProvider();
    if (!_isRunning() || addr == null) {
      stop();
      return null;
    }
    final rnd = Random.secure();
    final token = List.generate(
      16,
      (_) => _chars[rnd.nextInt(_chars.length)],
    ).join();
    _token = token;
    _text = text;
    _expiry = _now().add(tokenLifetime);
    return '$addr/report?t=$token';
  }

  /// 停止分享並清除報告內容。
  void stop() {
    _token = null;
    _text = null;
    _expiry = null;
  }

  /// 代碼正確且未過期才回 true。
  bool checkToken(String? candidate) {
    final token = _token;
    final expiry = _expiry;
    if (token == null || expiry == null || _text == null) return false;
    if (!_now().isBefore(expiry)) {
      stop();
      return false;
    }
    return constantTimeEquals(candidate ?? '', token);
  }

  /// 目前的報告文字（需先通過 checkToken）。
  String get text => _text ?? '';
}
