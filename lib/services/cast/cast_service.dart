import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bili_tv_app/main.dart' show appNavigatorKey;
import 'package:bili_tv_app/services/local_server.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';

import 'cast_playback.dart';

/// 已配對的手機
class CastPairedDevice {
  final String deviceId;
  final String deviceName;
  final String token;
  final int pairedAt;

  const CastPairedDevice({
    required this.deviceId,
    required this.deviceName,
    required this.token,
    required this.pairedAt,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'token': token,
    'pairedAt': pairedAt,
  };
}

class _CastResult {
  final bool ok;
  final String? token;
  final DateTime at;
  _CastResult(this.ok, this.token) : at = DateTime.now();
}

/// 一鍵投放：電視端的 HTTP 路由、配對與詢問框（協定 v1）
class CastService {
  CastService._();
  static final CastService instance = CastService._();

  static const _tvIdKey = 'cast_tv_id';
  static const _pairedKey = 'cast_paired';
  static const _channel = MethodChannel('com.bili.tv/update');

  static const _askTimeout = Duration(seconds: 30);
  static const _denyCooldown = Duration(seconds: 60);
  static const _ipWindow = Duration(minutes: 10);
  static const _ipMaxPrompts = 3;
  static const _resultKeep = Duration(seconds: 60);
  static const _maxBody = 8 * 1024;
  static final _bvidRe = RegExp(r'^BV[0-9A-Za-z]{10}$');

  /// 已配對清單變動時通知（設定頁用）
  final ValueNotifier<int> pairedChanged = ValueNotifier(0);

  String? _tvName;
  String? _pendingId;
  final Map<String, _CastResult> _results = {};
  final Map<String, DateTime> _deniedAt = {};
  final Map<String, List<DateTime>> _ipPrompts = {};

  // ---------- TV 身分 ----------

  /// 電視 id（第一次使用時產生 UUID）
  String get tvId {
    final prefs = SettingsService.prefs;
    var id = prefs.getString(_tvIdKey);
    if (id == null || id.isEmpty) {
      id = _newUuid();
      prefs.setString(_tvIdKey, id);
    }
    return id;
  }

  /// 電視名稱：「製造商 型號」
  Future<String> tvName() async {
    final cached = _tvName;
    if (cached != null) return cached;
    var name = 'Android TV';
    try {
      final info = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getDeviceInfo',
      );
      if (info != null) {
        final n = '${info['manufacturer'] ?? ''} ${info['model'] ?? ''}'.trim();
        if (n.isNotEmpty) name = n;
      }
    } catch (_) {}
    return _tvName = name;
  }

  static String _newUuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int from, int to) => b
        .sublist(from, to)
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
  }

  static String _randomToken(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return String.fromCharCodes(
      List.generate(length, (_) => chars.codeUnitAt(r.nextInt(chars.length))),
    );
  }

  // ---------- 已配對清單 ----------

  List<CastPairedDevice> pairedList() {
    try {
      final raw = SettingsService.prefs.getString(_pairedKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <CastPairedDevice>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final id = e['deviceId'];
        final name = e['deviceName'];
        final token = e['token'];
        final at = e['pairedAt'];
        if (id is String && name is String && token is String && at is int) {
          out.add(
            CastPairedDevice(
              deviceId: id,
              deviceName: name,
              token: token,
              pairedAt: at,
            ),
          );
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePaired(List<CastPairedDevice> list) async {
    await SettingsService.prefs.setString(
      _pairedKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
    pairedChanged.value++;
  }

  Future<void> addPaired(CastPairedDevice d) async {
    final list = pairedList()..removeWhere((e) => e.deviceId == d.deviceId);
    list.add(d);
    await _savePaired(list);
  }

  Future<void> removePaired(String deviceId) async {
    final list = pairedList()..removeWhere((e) => e.deviceId == deviceId);
    await _savePaired(list);
  }

  /// constant-time 比對
  static bool _tokenEquals(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    var diff = x.length ^ y.length;
    final n = max(x.length, y.length);
    for (var i = 0; i < n; i++) {
      diff |= (i < x.length ? x[i] : 0) ^ (i < y.length ? y[i] : 0);
    }
    return diff == 0;
  }

  // ---------- HTTP ----------

  /// 處理 /api/cast/*；回傳是否已處理
  Future<bool> handle(HttpRequest request) async {
    final path = request.uri.path;
    if (!path.startsWith('/api/cast/')) return false;
    final res = request.response;
    try {
      final method = request.method;
      if (path == '/api/cast/info' && method == 'GET') {
        await _send(res, 200, {
          'app': 'PiliBTRTV',
          'v': 1,
          'id': tvId,
          'name': await tvName(),
          'port': LocalServer.instance.port,
        });
      } else if (path == '/api/cast/play' && method == 'POST') {
        await _handlePlay(request);
      } else if (path == '/api/cast/result' && method == 'GET') {
        await _handleResult(request);
      } else if (path == '/api/cast/info' ||
          path == '/api/cast/play' ||
          path == '/api/cast/result') {
        await _send(res, 405, {'ok': false, 'reason': 'method_not_allowed'});
      } else {
        await _send(res, 404, {'ok': false, 'reason': 'not_found'});
      }
    } catch (_) {
      await _send(res, 500, {'ok': false, 'reason': 'server_error'});
    }
    return true;
  }

  Future<void> _handlePlay(HttpRequest request) async {
    final res = request.response;
    if (request.headers.contentType?.mimeType != 'application/json') {
      await _send(res, 415, {'ok': false, 'reason': 'unsupported_media_type'});
      return;
    }
    if (appNavigatorKey.currentState == null) {
      await _send(res, 503, {'ok': false, 'reason': 'not_ready'});
      return;
    }
    final body = await _readJson(request);
    if (body == null) {
      await _send(res, 400, {'ok': false, 'reason': 'bad_request'});
      return;
    }

    final deviceId = body['deviceId'];
    final rawName = body['deviceName'];
    final bvid = body['bvid'];
    final epIdRaw = _asInt(body['epId']);
    final epId = epIdRaw != null && epIdRaw > 0 ? epIdRaw : null;
    if (deviceId is! String ||
        deviceId.isEmpty ||
        deviceId.length > 64 ||
        rawName is! String ||
        rawName.trim().isEmpty ||
        (epId == null && (bvid is! String || !_bvidRe.hasMatch(bvid)))) {
      await _send(res, 400, {'ok': false, 'reason': 'bad_request'});
      return;
    }
    // 移除控制字元並截到 40 字
    final deviceName = _truncate(
      rawName.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim(),
      40,
    );
    final title = body['title'];
    final cast = CastRequest(
      bvid: bvid is String && _bvidRe.hasMatch(bvid) ? bvid : null,
      aid: _asInt(body['aid']),
      cid: _asInt(body['cid']),
      epId: epId,
      seasonId: _asInt(body['seasonId']),
      positionMs: max(0, _asInt(body['positionMs']) ?? 0),
      title: title is String ? _truncate(title, 200) : '',
    );

    final token = body['token'];
    if (token is String && token.isNotEmpty) {
      final paired = pairedList().where((e) => e.deviceId == deviceId);
      if (paired.isNotEmpty && _tokenEquals(paired.first.token, token)) {
        // 詢問框顯示中時不可開播，否則會蓋掉詢問框
        if (_pendingId != null) {
          await _send(res, 409, {'ok': false, 'reason': 'busy'});
          return;
        }
        await _send(res, 200, {'ok': true});
        _startPlayback(cast);
      } else {
        await _send(res, 403, {'ok': false, 'reason': 'bad_token'});
      }
      return;
    }

    // 沒有 token：需要在電視上詢問
    final now = DateTime.now();
    if (_pendingId != null) {
      await _send(res, 409, {'ok': false, 'reason': 'busy'});
      return;
    }
    final denied = _deniedAt[deviceId];
    if (denied != null && now.difference(denied) < _denyCooldown) {
      await _send(res, 429, {'ok': false, 'reason': 'too_many'});
      return;
    }
    final ip = request.connectionInfo?.remoteAddress.address ?? '?';
    final times = (_ipPrompts[ip] ?? [])
      ..removeWhere((t) => now.difference(t) >= _ipWindow);
    if (times.length >= _ipMaxPrompts) {
      _ipPrompts[ip] = times;
      await _send(res, 429, {'ok': false, 'reason': 'too_many'});
      return;
    }
    times.add(now);
    _ipPrompts[ip] = times;
    _ipPrompts.removeWhere(
      (_, v) => v.isEmpty || now.difference(v.last) >= _ipWindow,
    );

    final reqId = _randomToken(16);
    _pendingId = reqId;
    await _send(res, 202, {'ok': true, 'pending': true, 'reqId': reqId});
    unawaited(_runPrompt(reqId, deviceId, deviceName, ip, cast));
  }

  Future<void> _handleResult(HttpRequest request) async {
    final res = request.response;
    final now = DateTime.now();
    _results.removeWhere((_, v) => now.difference(v.at) >= _resultKeep);
    final id = request.uri.queryParameters['id'];
    if (id == null || id.isEmpty) {
      await _send(res, 404, {'ok': false, 'reason': 'not_found'});
    } else if (id == _pendingId) {
      await _send(res, 200, {'pending': true});
    } else {
      final r = _results[id];
      if (r == null) {
        await _send(res, 404, {'ok': false, 'reason': 'not_found'});
      } else if (r.ok) {
        await _send(res, 200, {'ok': true, 'token': r.token});
      } else {
        await _send(res, 403, {'ok': false, 'reason': 'denied'});
      }
    }
  }

  // ---------- 詢問框 ----------

  Future<void> _runPrompt(
    String reqId,
    String deviceId,
    String deviceName,
    String ip,
    CastRequest cast,
  ) async {
    var expired = false;
    BuildContext? dialogCtx;
    Timer? timer;
    bool? answer; // true 允許、false 使用者按拒絕、null 其他原因關閉
    try {
      final ctx = appNavigatorKey.currentState?.overlay?.context;
      if (ctx != null) {
        // 逾時：不論詢問框狀態，都立即記為拒絕並釋放等待狀態
        timer = Timer(_askTimeout, () {
          expired = true;
          _results[reqId] = _CastResult(false, null);
          _deniedAt[deviceId] = DateTime.now();
          if (_pendingId == reqId) _pendingId = null;
          _closeDialog(dialogCtx);
        });
        answer = await showDialog<bool>(
          context: ctx,
          barrierDismissible: false,
          builder: (c) {
            dialogCtx = c;
            // 建構時已逾時：下一個 frame 立刻關閉
            if (expired) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _closeDialog(c),
              );
            }
            return AlertDialog(
              backgroundColor: const Color(0xFF2A2A2A),
              title: const Text('投放影片'),
              content: Text('允許 $deviceName（$ip）投放影片到這台電視？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(c).pop(true),
                  child: const Text('允許'),
                ),
                // 預設焦點在拒絕
                TextButton(
                  autofocus: true,
                  onPressed: () => Navigator.of(c).pop(false),
                  child: const Text('拒絕'),
                ),
              ],
            );
          },
        );
      }
    } catch (_) {
      answer = null;
    } finally {
      timer?.cancel();
    }

    // 已逾時：結果與狀態在 timer 內處理完畢
    if (expired) return;

    final allowed = answer == true;
    if (allowed) {
      final token = _randomToken(32);
      try {
        await addPaired(
          CastPairedDevice(
            deviceId: deviceId,
            deviceName: deviceName,
            token: token,
            pairedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      } catch (_) {}
      _results[reqId] = _CastResult(true, token);
    } else {
      _results[reqId] = _CastResult(false, null);
      // 只有使用者按拒絕才記冷卻；被其他原因關閉不記
      if (answer == false) _deniedAt[deviceId] = DateTime.now();
    }
    if (_pendingId == reqId) _pendingId = null;
    if (allowed) _startPlayback(cast);
  }

  /// 關閉詢問框（結果由呼叫端記為拒絕）
  void _closeDialog(BuildContext? c) {
    if (c == null || !c.mounted) return;
    final route = ModalRoute.of(c);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(c).pop();
    } else {
      route.navigator?.removeRoute(route);
    }
  }

  void _startPlayback(CastRequest cast) {
    CastPlayback.open(cast).catchError((Object e) {
      debugPrint('cast open failed: $e');
    });
  }

  // ---------- 工具 ----------

  Future<void> _send(
    HttpResponse res,
    int code,
    Map<String, dynamic> body,
  ) async {
    try {
      res.statusCode = code;
      res.headers.contentType = ContentType.json;
      res.headers.set('Cache-Control', 'no-store');
      res.write(jsonEncode(body));
      await res.close();
    } catch (_) {
      // 手機已斷線
    }
  }

  Future<Map<String, dynamic>?> _readJson(HttpRequest request) async {
    if (request.contentLength > _maxBody) return null;
    final bytes = <int>[];
    try {
      await (() async {
        await for (final chunk in request) {
          bytes.addAll(chunk);
          if (bytes.length > _maxBody) return;
        }
      })().timeout(const Duration(seconds: 5));
      if (bytes.length > _maxBody) return null;
      final decoded = jsonDecode(utf8.decode(bytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static String _truncate(String s, int n) =>
      s.runes.length <= n ? s : String.fromCharCodes(s.runes.take(n));
}
