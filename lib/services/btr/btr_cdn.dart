// Ported from PiliBTR / PiliPlus (GPL v3). Behaviour is modelled on
// Bilibili-thread-ripper-desktop (MIT,
// https://github.com/MrTangLuyao/Bilibili-thread-ripper-desktop).

import 'dart:io' show HttpClient;

import 'package:bili_tv_app/services/btr/btr_config.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart' show IOHttpClientAdapter;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Plain HTTP/1.1 client (default adapter, no timeouts) for passthrough.
final Dio http11Dio = Dio();

/// HTTP client for BTR requests: short connect timeout so a dead node is
/// left quickly, and a stall timeout between data chunks.
final Dio btrDio =
    Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 5),
        ),
      )
      ..httpClientAdapter = IOHttpClientAdapter(
        // idle 連線保留 90 秒，開播時可重用 TLS 連線；
        // 每個主機的連線上限不少於多執行緒下載的併發數（最多 128 緒分散在多個節點）。
        createHttpClient: () => HttpClient()
          ..idleTimeout = const Duration(seconds: 90)
          ..maxConnectionsPerHost = 32,
      );

/// One CDN address for a media file.
class BtrNode {
  final String url;
  late final String host = Uri.tryParse(url)?.host ?? url;

  int strikes = 0;
  bool banned = false;
  int inflight = 0;

  /// Total bytes received from this node.
  int bytes = 0;

  /// Measured speed in bytes per millisecond (moving average). 0 = unknown.
  double speed = 0;

  BtrNode(this.url);
}

/// CDN nodes for one media file, with the BTR rules:
/// - a node that returns 0 bytes [strikeLimit] times in a row is banned for
///   this file; when every node is banned, all nodes are used again;
/// - requests go to nodes by measured speed and current load; a node slower
///   than 1/12 of the fastest one is skipped.
class BtrNodePool {
  BtrNodePool(String url, {List<String> backups = const []})
    : nodes = _build(url, backups);

  static const int strikeLimit = 2;

  /// Times all nodes may be enabled again before [pick] throws.
  static const int maxResets = 3;

  static final _mediaHost = RegExp(
    r'\.(?:bilivideo\.(?:com|cn|net)|akamaized\.net)$',
  );

  final List<BtrNode> nodes;
  int _turn = 0;
  int _resets = 0;

  /// 跨影片的節點健康紀錄（本次 App 執行期間）。
  /// 某節點在任一影片被封鎖後，[_globalBanTime] 內新影片直接跳過它；
  /// 量到的速度也帶到新影片，讓第一個請求就選快的節點，
  /// 不必每部影片都重新踩一次連不上的節點（DNS 失敗、連線逾時 4 秒）。
  static const Duration _globalBanTime = Duration(minutes: 10);
  static final Map<String, DateTime> _bannedUntil = {};
  static final Map<String, double> _knownSpeed = {};

  static bool _globallyBanned(String host) {
    final until = _bannedUntil[host];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _bannedUntil.remove(host);
      return false;
    }
    return true;
  }

  /// [host] 是否正被全域封鎖（供開頭主機排名排除）
  static bool isGloballyBanned(String host) => _globallyBanned(host);

  static List<BtrNode> _build(String url, List<String> backups) {
    final urls = <String>[url];
    for (final b in backups) {
      if (b.isNotEmpty && !urls.contains(b)) urls.add(b);
    }
    final uri = Uri.tryParse(url);
    // Like BTR swapOrdinaryHost: the URL moves to another host and keeps its
    // path and query (with the signature). Relay URLs (mcdn host,
    // /v1/resource/ path, os=mcdn) stay on their host. Akamai never is a
    // target, because its URLs use their own signature.
    if (uri != null &&
        _mediaHost.hasMatch(uri.host) &&
        !uri.host.contains('mcdn') &&
        uri.path.contains('/upgcxcode/') &&
        !uri.path.contains('/v1/resource/') &&
        uri.queryParameters['os'] != 'mcdn') {
      for (final host in BtrConfig.hosts) {
        if (host != uri.host && !host.contains('akamai')) {
          final swapped = uri.replace(host: host).toString();
          if (!urls.contains(swapped)) urls.add(swapped);
        }
      }
    }
    final built = <BtrNode>[];
    for (var i = 0; i < urls.length; i++) {
      final node = BtrNode(urls[i]);
      // 原始網址（第一個）一定保留；其他節點若近期被封鎖就跳過
      if (i > 0 && _globallyBanned(node.host)) continue;
      node.speed = _knownSpeed[node.host] ?? 0;
      built.add(node);
    }
    return built;
  }

  /// Selects a node for one request and counts it as in flight.
  /// Call [report] when the request ends.
  BtrNode pick() {
    var usable = nodes.where((n) => !n.banned).toList();
    if (usable.isEmpty) {
      if (++_resets > maxResets) {
        throw Exception('BTR: all CDN nodes failed');
      }
      if (kDebugMode) debugPrint('BTR: all nodes banned, using all again');
      for (final n in nodes) {
        n
          ..banned = false
          ..strikes = 0;
      }
      usable = nodes;
    }

    BtrNode node;
    // Try each node once before measured speeds decide.
    final untested = usable.where((n) => n.speed == 0 && n.inflight == 0);
    if (untested.isNotEmpty) {
      node = untested.elementAt(_turn++ % untested.length);
    } else {
      final top = usable.fold<double>(0, (m, n) => n.speed > m ? n.speed : m);
      var candidates = usable.where((n) => n.speed >= top / 12).toList();
      if (candidates.isEmpty) candidates = usable;
      // Highest speed per request in flight; unknown speed counts as top.
      node = candidates.reduce(
        (a, b) =>
            ((a.speed == 0 ? top : a.speed) / (a.inflight + 1)) >=
                ((b.speed == 0 ? top : b.speed) / (b.inflight + 1))
            ? a
            : b,
      );
    }
    node.inflight++;
    return node;
  }

  /// Reports the end of a request on [node]: [bytes] received in [elapsed].
  /// For a cancelled request pass `cancelled: true`; it does not count as a
  /// strike.
  void report(
    BtrNode node, {
    required int bytes,
    Duration? elapsed,
    bool cancelled = false,
  }) {
    if (node.inflight > 0) node.inflight--;
    if (bytes > 0) node.bytes += bytes;
    if (bytes >= 64 * 1024 && elapsed != null) {
      final sample = bytes / (elapsed.inMilliseconds + 1);
      node.speed = node.speed == 0 ? sample : node.speed * 0.7 + sample * 0.3;
      _knownSpeed[node.host] = node.speed;
    }
    if (cancelled) return;
    if (bytes > 0) {
      node.strikes = 0;
      _resets = 0;
      return;
    }
    // A failed request also lowers the measured speed.
    node.speed *= 0.5;
    if (++node.strikes >= strikeLimit && !node.banned) {
      node.banned = true;
      _bannedUntil[node.host] = DateTime.now().add(_globalBanTime);
      _knownSpeed.remove(node.host);
      if (kDebugMode) debugPrint('BTR: node banned ${node.host}');
    }
  }
}
