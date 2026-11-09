import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 回報處理狀態。
enum ReportStatusKind {
  resolved('resolved', '已解決'),
  inProgress('in_progress', '處理中'),
  cannotReproduce('cannot_reproduce', '無法重現');

  final String json;
  final String label;
  const ReportStatusKind(this.json, this.label);

  static ReportStatusKind? fromJson(Object? v) {
    if (v is! String) return null;
    for (final k in values) {
      if (k.json == v) return k;
    }
    return null;
  }
}

class ReportStatus {
  final ReportStatusKind kind;
  final String? note;
  const ReportStatus(this.kind, [this.note]);
}

/// 狀態檔網址，測試或驗證時可用 --dart-define=REPORT_STATUS_URL=... 覆寫。
const String reportStatusUrl = String.fromEnvironment(
  'REPORT_STATUS_URL',
  defaultValue:
      'https://raw.githubusercontent.com/gordonpow/PiliBTRTV/main/report_status.json',
);

const String _cacheKey = 'report_status_cache';
const int _noteMaxRunes = 80;

/// 解析狀態檔；頂層格式不合法回 null，單筆不合法只跳過該筆。
Map<String, ReportStatus>? tryDecodeReportStatus(String raw) {
  try {
    final root = jsonDecode(raw);
    if (root is! Map) return null;
    final reports = root['reports'];
    if (reports is! Map) return null;
    final result = <String, ReportStatus>{};
    reports.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final kind = ReportStatusKind.fromJson(value['status']);
      if (kind == null) return;
      final id = key.trim().toUpperCase();
      if (id.isEmpty) return;
      String? note;
      final n = value['note'];
      if (n is String) {
        final runes = n.trim().runes;
        if (runes.isNotEmpty) {
          note = String.fromCharCodes(runes.take(_noteMaxRunes));
        }
      }
      result[id] = ReportStatus(kind, note);
    });
    return result;
  } catch (_) {
    return null;
  }
}

/// 同 [tryDecodeReportStatus]，格式不合法時回空 Map。
Map<String, ReportStatus> decodeReportStatus(String raw) =>
    tryDecodeReportStatus(raw) ?? const {};

/// 下載結果（狀態碼與內文）。
class ReportFetchResult {
  final int statusCode;
  final String body;
  const ReportFetchResult(this.statusCode, this.body);
}

class ReportStatusService {
  static Future<ReportFetchResult> _defaultFetch(Uri url) async {
    final res = await http.get(url).timeout(const Duration(seconds: 8));
    return ReportFetchResult(res.statusCode, utf8.decode(res.bodyBytes));
  }

  static Future<String?> _defaultReadCache() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_cacheKey);
  }

  static Future<void> _defaultWriteCache(String raw) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_cacheKey, raw);
  }

  static Future<void> _defaultClearCache() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_cacheKey);
  }

  /// 取得處理狀態；任何失敗都不拋例外，最差回空 Map。
  static Future<Map<String, ReportStatus>> load({
    Future<ReportFetchResult> Function(Uri url)? fetch,
    Future<String?> Function()? readCache,
    Future<void> Function(String raw)? writeCache,
    Future<void> Function()? clearCache,
  }) async {
    final doFetch = fetch ?? _defaultFetch;
    final doRead = readCache ?? _defaultReadCache;
    final doWrite = writeCache ?? _defaultWriteCache;
    final doClear = clearCache ?? _defaultClearCache;

    try {
      // 加時間戳避開 raw CDN 快取
      final url = Uri.parse(
        '$reportStatusUrl?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final res = await doFetch(url);
      if (res.statusCode == 200) {
        final decoded = tryDecodeReportStatus(res.body);
        if (decoded != null) {
          try {
            await doWrite(res.body);
          } catch (e) {
            debugPrint('ReportStatus: 寫入快取失敗 ${e.runtimeType}');
          }
          return decoded;
        }
        debugPrint('ReportStatus: 狀態檔格式不合法，改用快取');
      } else if (res.statusCode == 404) {
        // 狀態檔已刪除，視為空狀態並清除快取
        try {
          await doClear();
        } catch (e) {
          debugPrint('ReportStatus: 清除快取失敗 ${e.runtimeType}');
        }
        return const {};
      } else {
        debugPrint('ReportStatus: HTTP ${res.statusCode}，改用快取');
      }
    } catch (e) {
      debugPrint('ReportStatus: 下載失敗 ${e.runtimeType}，改用快取');
    }

    try {
      final cached = await doRead();
      if (cached != null) return decodeReportStatus(cached);
    } catch (e) {
      debugPrint('ReportStatus: 讀取快取失敗 ${e.runtimeType}');
    }
    return const {};
  }
}
