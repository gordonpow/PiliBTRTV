// Ported from PiliBTR / PiliPlus (GPL v3).
//
// Multi-CDN acceleration for playback ("BTR", thread ripper).
//
// The player (ExoPlayer) reads media through a local HTTP proxy. For each Range
// request from the player, the proxy splits the range into pieces and
// fetches them in parallel from several Bilibili CDN nodes. Pieces are
// returned to the player in order, as soon as the next piece is complete.
// Behaviour is modelled on Bilibili-thread-ripper-desktop (MIT,
// https://github.com/MrTangLuyao/Bilibili-thread-ripper-desktop).

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bili_tv_app/services/btr/btr_cdn.dart'
    show BtrNode, BtrNodePool, btrDio, http11Dio;
import 'package:bili_tv_app/services/btr/btr_config.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

String _http2https(String url) =>
    url.replaceFirst(RegExp('^(http:)?//', caseSensitive: false), 'https://');

abstract final class BtrProxy {
  static HttpServer? _server;
  static Future<HttpServer>? _starting;

  static final Map<String, _BtrSource> _sources = {};
  static final Map<String, String> _idByUrl = {};
  static int _seq = 0;

  /// Forgets the URL to source mapping so the next [wrap] creates new
  /// sources with the current CDN settings. Existing sources stay, so a
  /// playing MPD keeps working. The server stays up.
  static void reset() {
    _idByUrl.clear();
  }

  /// Max number of media URLs kept. Older ones are removed first.
  static const int _maxSources = 64;

  static final _mediaHost = RegExp(
    r'(?:^|\.)(?:bilivideo\.(?:com|cn|net)|akamaized\.net)$',
  );
  static final _mediaPath = RegExp(r'\.(?:m4s|mp4|flv)$');

  static bool isEligible(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        _mediaHost.hasMatch(uri.host) &&
        _mediaPath.hasMatch(uri.path);
  }

  /// Returns a local proxy URL for [url] when playback acceleration is
  /// enabled and [url] is a Bilibili media file. Otherwise returns [url].
  static Future<String> wrap(
    String url, {
    List<String> backups = const [],
    int bandwidth = 0,
  }) async {
    try {
      if (!BtrConfig.playback || !isEligible(url)) return url;
      final server = await _ensureServer();
      final src = _http2https(url);
      var id = _idByUrl[src];
      final existing = id == null ? null : _sources.remove(id);
      if (existing != null) {
        // LRU: move the reused source to the end.
        _sources[id!] = existing;
        if (bandwidth > existing.bandwidth) existing.bandwidth = bandwidth;
      } else {
        id = (++_seq).toString();
        _idByUrl[src] = id;
        _sources[id] = _BtrSource(src, backups)..bandwidth = bandwidth;
        while (_sources.length > _maxSources) {
          final oldest = _sources.keys.first;
          final evicted = _sources.remove(oldest)!;
          if (_idByUrl[evicted.url] == oldest) _idByUrl.remove(evicted.url);
        }
      }
      final ext = _mediaPath.firstMatch(Uri.parse(src).path)?.group(0) ?? '';
      return 'http://127.0.0.1:${server.port}/btr/$id$ext';
    } catch (e) {
      if (kDebugMode) debugPrint('BTR: proxy unavailable: $e');
      return url;
    }
  }

  /// Bytes served to the player and CDN nodes for [originalUrl], or null when
  /// that URL is not proxied.
  static ({int served, List<BtrNode> nodes})? statsFor(String originalUrl) {
    final id = _idByUrl[_http2https(originalUrl)];
    final source = id == null ? null : _sources[id];
    if (source == null) return null;
    return (served: source.served, nodes: source.pool.nodes);
  }

  /// Sources that served data within the last 5 minutes (also while paused).
  static List<({int served, List<BtrNode> nodes})> activeStats() {
    final now = DateTime.now();
    return [
      for (final s in _sources.values)
        if (s.lastServedAt != null &&
            now.difference(s.lastServedAt!) < const Duration(minutes: 5))
          (served: s.served, nodes: s.pool.nodes),
    ];
  }

  static Future<HttpServer> _ensureServer() {
    if (_server case final server?) return Future.value(server);
    return _starting ??= HttpServer.bind(InternetAddress.loopbackIPv4, 0).then(
      (server) {
        _server = server;
        server.listen(_handle, onError: (_) {});
        if (kDebugMode) debugPrint('BTR: proxy on port ${server.port}');
        return server;
      },
      onError: (Object e) {
        _starting = null;
        throw e;
      },
    );
  }

  static Future<void> _handle(HttpRequest req) async {
    final segments = req.uri.pathSegments;
    final id = segments.length == 2 && segments[0] == 'btr'
        ? segments[1].split('.').first
        : null;
    final source = id == null ? null : _sources[id];
    if (source == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close().catchError((_) {});
      return;
    }
    try {
      await source.serve(req);
    } catch (e) {
      if (kDebugMode) debugPrint('BTR: serve error: $e');
      try {
        await req.response.close();
      } catch (_) {}
    }
  }
}

class _BtrSource {
  _BtrSource(this.url, List<String> backups)
    : pool = BtrNodePool(url, backups: backups);

  final String url;
  final BtrNodePool pool;

  /// Stream bandwidth in bits per second (0 = unknown).
  int bandwidth = 0;

  /// Threads per player request: high-bitrate streams use 16 in auto mode.
  int get threads => BtrConfig.autoThreads && bandwidth >= 8000000
      ? 16
      : BtrConfig.playbackThreads;

  /// Bytes written to the player's responses.
  int served = 0;

  /// Last time bytes were written to the player.
  DateTime? lastServedAt;

  static const _firstPiece = 128 * 1024;
  static const _maxWindowBytes = 64 * 1024 * 1024;
  static const _pieceAttempts = 6;

  int? _total;
  bool _probed = false;
  DateTime? _probeFailedAt;
  Future<void>? _probing;
  String _contentType = 'video/mp4';
  late Map<String, String> _headers;

  static final _rangeRegex = RegExp(r'bytes=(\d*)-(\d*)');

  Future<void> serve(HttpRequest req) async {
    if (!_probed) {
      _headers = {
        'user-agent': req.headers.value('user-agent') ?? 'Mozilla/5.0',
        'referer': req.headers.value('referer') ?? 'https://www.bilibili.com/',
        'accept-encoding': 'identity',
        'cookie': ?req.headers.value('cookie'),
        'origin': ?req.headers.value('origin'),
      };
      final failedAt = _probeFailedAt;
      if (failedAt == null ||
          DateTime.now().difference(failedAt) >= const Duration(seconds: 10)) {
        await (_probing ??= _probe());
      }
    }

    final total = _total;
    final range = req.headers.value('range');
    if (total == null) {
      return _passthrough(req.response, range, head: req.method == 'HEAD');
    }

    int start = 0;
    int end = total - 1;
    if (range != null) {
      final m = _rangeRegex.firstMatch(range);
      if (m != null) {
        final a = m.group(1)!;
        final b = m.group(2)!;
        if (a.isEmpty && b.isNotEmpty) {
          start = math.max(0, total - int.parse(b));
        } else {
          if (a.isNotEmpty) start = int.parse(a);
          if (b.isNotEmpty) end = math.min(int.parse(b), total - 1);
        }
      }
    }

    final res = req.response;
    if (start >= total || start > end) {
      res
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set('content-range', 'bytes */$total');
      await res.close();
      return;
    }

    res
      ..statusCode = range == null ? HttpStatus.ok : HttpStatus.partialContent
      ..contentLength = end - start + 1
      ..headers.set('content-type', _contentType)
      ..headers.set('accept-ranges', 'bytes');
    if (range != null) {
      res.headers.set('content-range', 'bytes $start-$end/$total');
    }
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }

    await _Pump(this, res, start, end).run();
  }

  Future<void> _probe() async {
    final watch = Stopwatch()..start();
    for (final node in pool.nodes.take(2)) {
      if (watch.elapsed > const Duration(seconds: 6)) break;
      try {
        final response = await btrDio.get<ResponseBody>(
          node.url,
          options: Options(
            headers: {..._headers, 'range': 'bytes=0-0'},
            responseType: ResponseType.stream,
          ),
        );
        await response.data?.stream.drain<void>().catchError((_) {});
        final contentRange = response.headers.value('content-range');
        final slash = contentRange?.lastIndexOf('/') ?? -1;
        if (response.statusCode == 206 && slash != -1) {
          _total = int.tryParse(contentRange!.substring(slash + 1).trim());
          _contentType = response.headers.value('content-type') ?? _contentType;
          if (_total != null) break;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('BTR: probe failed ${node.host}: $e');
      }
    }
    _probing = null;
    if (_total != null) {
      _probed = true;
      _probeFailedAt = null;
    } else {
      _probeFailedAt = DateTime.now();
    }
    if (kDebugMode) {
      debugPrint(
        'BTR: play ${Uri.parse(url).pathSegments.last} '
        'host=${Uri.parse(url).host} os=${Uri.parse(url).queryParameters['os']} '
        'total=$_total '
        'nodes=${pool.nodes.length} threads=$threads',
      );
    }
  }

  /// Fetches bytes [start]..[end] (inclusive). Moves to another node when a
  /// request fails or stalls, and keeps the bytes already received.
  Future<Uint8List> fetchPiece(int start, int end, CancelToken cancel) async {
    final length = end - start + 1;
    final builder = BytesBuilder(copy: false);
    Object? lastError;
    for (int attempt = 0; attempt < _pieceAttempts; attempt++) {
      if (cancel.isCancelled) throw 'cancelled';
      final node = pool.pick();
      final from = start + builder.length;
      final watch = Stopwatch()..start();
      int got = 0;
      try {
        final response = await btrDio.get<ResponseBody>(
          node.url,
          options: Options(
            headers: {..._headers, 'range': 'bytes=$from-$end'},
            responseType: ResponseType.stream,
          ),
          cancelToken: cancel,
        );
        if (response.statusCode != 206) {
          await response.data?.stream.drain<void>().catchError((_) {});
          throw Exception('status ${response.statusCode}');
        }
        await for (final data in response.data!.stream) {
          final remain = length - builder.length;
          final bytes = data.length > remain ? data.sublist(0, remain) : data;
          builder.add(bytes);
          got += bytes.length;
          if (builder.length >= length) break;
        }
        pool.report(node, bytes: got, elapsed: watch.elapsed);
        if (builder.length >= length) return builder.takeBytes();
        lastError = Exception('connection closed early');
      } catch (e) {
        pool.report(
          node,
          bytes: got,
          elapsed: watch.elapsed,
          cancelled: cancel.isCancelled,
        );
        if (cancel.isCancelled) rethrow;
        lastError = e;
        if (kDebugMode) {
          debugPrint('BTR: piece $start retry on ${node.host}: $e');
        }
      }
      await Future.delayed(Duration(milliseconds: 150 * (attempt + 1)));
    }
    throw lastError ?? Exception('BTR: piece failed');
  }

  /// Pipes [range] from the original URL with one connection.
  Future<void> _passthrough(
    HttpResponse res,
    String? range, {
    bool head = false,
  }) async {
    final response = await http11Dio.get<ResponseBody>(
      url,
      options: Options(
        headers: {..._headers, 'range': ?range},
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
      ),
    );
    res.statusCode = response.statusCode ?? HttpStatus.badGateway;
    for (final key in const [
      'content-type',
      'content-length',
      'content-range',
      'accept-ranges',
    ]) {
      if (response.headers.value(key) case final value?) {
        res.headers.set(key, value);
      }
    }
    if (head) {
      await response.data?.stream.drain<void>().catchError((_) {});
      await res.close();
      return;
    }
    await res.addStream(
      response.data!.stream.map((c) {
        served += c.length;
        lastServedAt = DateTime.now();
        return c;
      }),
    );
    await res.close();
  }

  /// Pipes [start]..[end] from the original URL into an open response.
  Future<void> pipeRemaining(HttpResponse res, int start, int end) async {
    final response = await http11Dio.get<ResponseBody>(
      url,
      options: Options(
        headers: {..._headers, 'range': 'bytes=$start-$end'},
        responseType: ResponseType.stream,
      ),
    );
    if (response.statusCode != 206) {
      throw Exception('fallback status ${response.statusCode}');
    }
    await res.addStream(
      response.data!.stream.map((c) {
        served += c.length;
        lastServedAt = DateTime.now();
        return c;
      }),
    );
  }
}

/// One piece of a player request. It can run a second copy on another node
/// (hedge) when it blocks the player for too long.
class _Piece {
  _Piece(this.source, this.start, this.end) {
    // ignore(): a piece that fails after the player disconnects is not
    // awaited; do not report it as an unhandled error.
    _primary = source.fetchPiece(start, end, _token)..ignore();
  }

  final _BtrSource source;
  final int start;
  final int end;
  final _watch = Stopwatch()..start();
  final _token = CancelToken();
  CancelToken? _hedgeToken;
  late final Future<Uint8List> _primary;

  Duration get age => _watch.elapsed;

  /// Waits for the piece. When it is not done after [hedgeAfter] (counted
  /// from the piece start), a copy runs on another node and the first one to
  /// finish is used.
  Future<Uint8List> result(Duration hedgeAfter) {
    final completer = Completer<Uint8List>();
    int running = 1;
    int failed = 0;

    void onValue(Uint8List value) {
      if (completer.isCompleted) return;
      completer.complete(value);
      cancel();
    }

    void onError(Object e) {
      if (++failed >= running && !completer.isCompleted) {
        completer.completeError(e);
      }
    }

    _primary.then(onValue, onError: onError);

    final wait = hedgeAfter - age;
    final timer = Timer(wait.isNegative ? Duration.zero : wait, () {
      if (completer.isCompleted || _token.isCancelled) return;
      running++;
      if (kDebugMode) debugPrint('BTR: hedge piece $start');
      final token = _hedgeToken = CancelToken();
      source.fetchPiece(start, end, token).then(onValue, onError: onError);
    });
    return completer.future.whenComplete(timer.cancel);
  }

  void cancel() {
    if (!_token.isCancelled) _token.cancel();
    if (_hedgeToken case final t? when !t.isCancelled) t.cancel();
  }
}

/// Serves one player request: keeps up to `threads` pieces in flight and
/// writes them to the player in order.
class _Pump {
  _Pump(this.source, this.res, this.start, this.end);

  final _BtrSource source;
  final HttpResponse res;
  final int start;
  final int end;

  final _queue = Queue<_Piece>();
  late int _next = start;
  bool _closed = false;

  /// Moving average of the time a piece needs, in ms.
  double _pieceMs = 0;

  /// Like BTR: hedge after 1.5x the usual piece time, within limits.
  Duration get _hedgeAfter => Duration(
    milliseconds: _pieceMs == 0
        ? 1500
        : (_pieceMs * 1.5).round().clamp(700, 2500),
  );

  Future<void> run() async {
    res.done.then((_) => _stop(), onError: (_) => _stop());

    final threads = source.threads;
    final pieceSize = (threads > 32 ? 256 : 512) * 1024;
    final window = math.min(
      threads,
      _BtrSource._maxWindowBytes ~/ pieceSize,
    );

    void fill() {
      while (!_closed && _queue.length < window && _next <= end) {
        final size = _next == start ? _BtrSource._firstPiece : pieceSize;
        final s = _next;
        final e = math.min(s + size - 1, end);
        _next = e + 1;
        _queue.add(_Piece(source, s, e));
      }
    }

    int position = start;
    fill();
    try {
      while (_queue.isNotEmpty && !_closed) {
        final head = _queue.first;
        final Uint8List bytes;
        try {
          bytes = await head.result(_hedgeAfter);
        } catch (e) {
          if (_closed) return;
          // Every node failed for this piece: continue with one connection.
          if (kDebugMode) debugPrint('BTR: fallback to original URL: $e');
          _stop();
          await source.pipeRemaining(res, position, end);
          break;
        }
        _queue.removeFirst();
        if (_closed) return;
        final ms = head.age.inMilliseconds.toDouble();
        _pieceMs = _pieceMs == 0 ? ms : _pieceMs * 0.8 + ms * 0.2;
        res.add(bytes);
        source.served += bytes.length;
        source.lastServedAt = DateTime.now();
        position += bytes.length;
        fill();
        await res.flush();
      }
      await res.close();
    } catch (_) {
      // Player closed the connection (seek or stop), or the fallback failed.
      _stop();
      try {
        await res.close();
      } catch (_) {}
    }
  }

  void _stop() {
    if (_closed) return;
    _closed = true;
    for (final piece in _queue) {
      piece.cancel();
    }
  }
}
