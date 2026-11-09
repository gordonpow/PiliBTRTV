// 開頭連線用的 CDN 主機排名：App 啟動後背景測量候選主機的延遲，
// 開播階段的單一連線轉送與 prefetchHead 改走最快的主機。
// 多節點下載（BtrNodePool）不使用這裡的結果。

import 'dart:async';

import 'package:bili_tv_app/services/btr/btr_cdn.dart' show BtrNodePool, btrDio;
import 'package:bili_tv_app/services/btr/btr_config.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

class BtrHostRanker {
  BtrHostRanker._();
  static final BtrHostRanker instance = BtrHostRanker._();

  static const Duration _ttl = Duration(minutes: 10);
  static const Duration _timeout = Duration(seconds: 3);
  static const Duration _demoteTime = Duration(minutes: 10);
  static const int _maxSeen = 16;

  static final _mediaHost = RegExp(
    r'\.(?:bilivideo\.(?:com|cn|net)|akamaized\.net)$',
  );

  /// 主機 -> TTFB（毫秒）；測量失敗的主機不在表內
  final Map<String, int> _latency = {};
  final Map<String, DateTime> _demotedUntil = {};
  final Set<String> _seen = {};
  DateTime? _measuredAt;
  bool _measuring = false;

  /// App 啟動時呼叫；不阻塞，失敗靜默
  void warmUp() {
    unawaited(_measure());
  }

  /// 開播連線失敗時降級該主機，一段時間內不再選它
  void demote(String host) {
    _demotedUntil[host] = DateTime.now().add(_demoteTime);
    _latency.remove(host);
  }

  bool _demoted(String host) {
    final until = _demotedUntil[host];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _demotedUntil.remove(host);
      return false;
    }
    return true;
  }

  /// 與 BtrNodePool._build 相同的可換主機條件
  static bool swappable(Uri uri) =>
      _mediaHost.hasMatch(uri.host) &&
      !uri.host.contains('mcdn') &&
      uri.path.contains('/upgcxcode/') &&
      !uri.path.contains('/v1/resource/') &&
      uri.queryParameters['os'] != 'mcdn';

  List<String> _candidates() => [
    for (final h in BtrConfig.hosts)
      if (!h.contains('akamai')) h,
    ..._seen,
  ];

  Future<void> _measure() async {
    if (_measuring) return;
    _measuring = true;
    try {
      final hosts = _candidates().toSet().toList();
      final results = await Future.wait(hosts.map(_ping));
      _latency.clear();
      for (var i = 0; i < hosts.length; i++) {
        final ms = results[i];
        if (ms != null && !_demoted(hosts[i])) _latency[hosts[i]] = ms;
      }
      _measuredAt = DateTime.now();
      if (kDebugMode) {
        final sorted = _latency.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        debugPrint(
          'BTR: host ranking ${[for (final e in sorted) '${e.key}=${e.value}ms'].join(', ')}',
        );
      }
    } catch (_) {
      // 測量失敗：靜默
    } finally {
      _measuring = false;
    }
  }

  Future<int?> _ping(String host) async {
    final watch = Stopwatch()..start();
    try {
      final response = await btrDio.get<ResponseBody>(
        'https://$host/',
        options: Options(
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
          sendTimeout: _timeout,
          receiveTimeout: _timeout,
        ),
      );
      final ms = watch.elapsedMilliseconds;
      unawaited(response.data?.stream.drain<void>().catchError((_) {}));
      return ms;
    } catch (_) {
      return null;
    }
  }

  /// 可換主機且有明顯更快（快 30% 以上）的主機時，回傳換主機後的網址；否則 null
  String? bestFor(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !swappable(uri)) return null;
      if (_seen.length < _maxSeen) _seen.add(uri.host);
      final at = _measuredAt;
      if (at == null || DateTime.now().difference(at) > _ttl) {
        unawaited(_measure());
      }
      if (_latency.isEmpty) return null;

      String? best;
      int bestMs = 1 << 30;
      for (final e in _latency.entries) {
        if (e.key.contains('akamai') ||
            _demoted(e.key) ||
            BtrNodePool.isGloballyBanned(e.key)) {
          continue;
        }
        if (e.value < bestMs) {
          best = e.key;
          bestMs = e.value;
        }
      }
      if (best == null || best == uri.host) return null;
      // 原始主機未測過時視為慢
      final origMs = _latency[uri.host];
      if (origMs != null && bestMs > origMs * 0.7) return null;
      return uri.replace(host: best).toString();
    } catch (_) {
      return null;
    }
  }
}
