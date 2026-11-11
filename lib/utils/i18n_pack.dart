import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:path_provider/path_provider.dart';

/// A template of the language pack, for example `{0}分鐘前` -> `{0} min ago`.
/// The Chinese key becomes an anchored [RegExp]; each `{n}` is `(.+?)`.
class I18nTemplate {
  I18nTemplate._(this.regex, this.groupNumbers, this.english, this.zhLength);

  final RegExp regex;

  /// The `{n}` number of each capture group, in order of appearance.
  final List<int> groupNumbers;
  final String english;

  /// Length of the Chinese part without placeholders. Longer goes first.
  final int zhLength;

  static final _placeholder = RegExp(r'\{(\d+)\}');

  /// Returns null when the template cannot be matched safely: two
  /// placeholders side by side, no Chinese part, or a Chinese part with
  /// fewer than 2 characters.
  static I18nTemplate? tryParse(String zh, String english) {
    final buf = StringBuffer('^');
    final numbers = <int>[];
    var last = 0;
    var zhLength = 0;
    var prevWasPlaceholder = false;
    for (final m in _placeholder.allMatches(zh)) {
      final literal = zh.substring(last, m.start);
      if (literal.isEmpty && prevWasPlaceholder) return null;
      buf
        ..write(RegExp.escape(literal))
        ..write('(.+?)');
      zhLength += literal.length;
      numbers.add(int.parse(m.group(1)!));
      prevWasPlaceholder = true;
      last = m.end;
    }
    final tail = zh.substring(last);
    buf
      ..write(RegExp.escape(tail))
      ..write(r'$');
    zhLength += tail.length;
    if (numbers.isEmpty || zhLength < 2) return null;
    return I18nTemplate._(
      RegExp(buf.toString(), dotAll: true),
      numbers,
      english,
      zhLength,
    );
  }

  /// English text with the captured fragments put in, or null if no match.
  String? apply(String text, String Function(String fragment) lookup) {
    final m = regex.firstMatch(text);
    if (m == null) return null;
    final fragments = <int, String>{};
    for (var i = 0; i < groupNumbers.length; i++) {
      fragments[groupNumbers[i]] = lookup(m.group(i + 1)!);
    }
    return english.replaceAllMapped(
      _placeholder,
      (p) => fragments[int.parse(p.group(1)!)] ?? p.group(0)!,
    );
  }
}

/// 下載語言包文字的函式（可在測試中換成假的）。
typedef I18nFetcher =
    Future<String> Function(
      String url,
      void Function(int received, int total)? onProgress,
    );

/// The English UI language pack (`i18n/en.json` of the repo). It is
/// downloaded when the user picks English and read from the app documents
/// folder at start. [translate] is called by `ZhConvert.convert`.
abstract final class I18nPack {
  static const url =
      'https://raw.githubusercontent.com/gordonpow/PiliBTRTV/main/i18n/en.json';
  static const _checkInterval = Duration(days: 7);
  static const _retryInterval = Duration(hours: 24);
  static const _cacheSize = 4096;
  static const _cacheMaxLength = 200;

  static Map<String, String> _strings = const {};
  static List<I18nTemplate> _templates = const [];
  static String _version = '';

  // Map literals keep insertion order, which makes this an LRU cache.
  static final _cache = <String, String>{};

  static final _cjk = RegExp(r'[㐀-鿿豈-﫿]');

  /// 存放語言包的資料夾。測試時可換成暫存資料夾。
  @visibleForTesting
  static Future<Directory> Function() directoryProvider = _defaultDirectory;

  /// 下載語言包文字。測試時可換成假的。
  @visibleForTesting
  static I18nFetcher fetcher = _dioFetch;

  /// 目前時間。測試時可換成假的。
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static Future<Directory> _defaultDirectory() async => Directory(
    '${(await getApplicationDocumentsDirectory()).path}'
    '${Platform.pathSeparator}i18n',
  );

  /// Version of the loaded pack, empty when none is loaded.
  static String get version => _version;
  static bool get isLoaded => _strings.isNotEmpty || _templates.isNotEmpty;

  static Future<File> _file(String name) async {
    final dir = await directoryProvider();
    if (!dir.existsSync()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  /// Reads the saved pack into memory. Never throws: on any error the
  /// pack stays empty and the UI stays in Traditional Chinese.
  /// 檔案損毀時刪除它與檢查紀錄，下次背景檢查會立即重新下載。
  static Future<void> load() async {
    try {
      final file = await _file('en.json');
      if (!file.existsSync()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) throw const FormatException('not map');
      loadJson(json);
    } catch (e) {
      clear();
      if (kDebugMode) debugPrint('I18nPack.load: $e');
      try {
        final file = await _file('en.json');
        if (file.existsSync()) await file.delete();
        final meta = await _file('meta.json');
        if (meta.existsSync()) await meta.delete();
      } catch (_) {}
    }
  }

  /// Puts a decoded pack into memory.
  @visibleForTesting
  static void loadJson(Map<String, dynamic> json) {
    final strings = _stringMap(json['strings']);
    final templates = buildTemplates(_stringMap(json['templates']));
    _strings = strings;
    _templates = templates;
    _version = json['version']?.toString() ?? '';
    _cache.clear();
  }

  @visibleForTesting
  static void clear() {
    _strings = const {};
    _templates = const [];
    _version = '';
    _cache.clear();
  }

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.key is String &&
            e.value is String &&
            (e.value as String).isNotEmpty)
          e.key as String: e.value as String,
    };
  }

  /// Turns the template map into regexps, longest Chinese part first.
  @visibleForTesting
  static List<I18nTemplate> buildTemplates(Map<String, String> templates) {
    final list = <I18nTemplate>[];
    for (final e in templates.entries) {
      final t = I18nTemplate.tryParse(e.key, e.value);
      if (t != null) list.add(t);
    }
    list.sort((a, b) => b.zhLength.compareTo(a.zhLength));
    return list;
  }

  /// English text for [s], or [s] when the pack has none.
  static String translate(String s) {
    if (s.isEmpty || !isLoaded) return s;
    final exact = _strings[s];
    if (exact != null) return exact;
    if (!_cjk.hasMatch(s)) return s;
    final cacheable = s.length <= _cacheMaxLength;
    if (cacheable) {
      final hit = _cache.remove(s);
      if (hit != null) {
        _cache[s] = hit;
        return hit;
      }
    }
    final result = _templateTranslate(s, 0);
    if (cacheable) {
      if (_cache.length >= _cacheSize) _cache.remove(_cache.keys.first);
      _cache[s] = result;
    }
    return result;
  }

  static String _templateTranslate(String s, int depth) {
    for (final t in _templates) {
      final out = t.apply(s, (fragment) {
        // Captured fragment can be a fixed string: 進入 / 退出.
        final hit = _strings[fragment];
        if (hit != null) return hit;
        if (depth < 2 && _cjk.hasMatch(fragment)) {
          return _templateTranslate(fragment, depth + 1);
        }
        return fragment;
      });
      if (out != null) return out;
    }
    return s;
  }

  // ---- download and update ----

  static Future<String> _dioFetch(
    String url,
    void Function(int received, int total)? onProgress,
  ) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.plain,
      ),
    );
    final res = await dio.get<String>(url, onReceiveProgress: onProgress);
    final body = res.data;
    if (body == null) throw const FormatException('empty language pack');
    return body;
  }

  static const _downloadTimeout = Duration(seconds: 60);

  // 進行中的下載：同時呼叫 download 時共用同一個 Future。
  static Future<String>? _inflight;
  static final _progressListeners = <void Function(int, int)>[];
  // 成功下載的次數，用來避免背景失敗蓋掉較晚的成功紀錄。
  static int _successCount = 0;

  /// Downloads the pack and saves it. Returns the pack version. Throws on
  /// a network error, a timeout (60 seconds) or an invalid pack. Does not
  /// load it into memory. 進行中時共用同一次下載。
  static Future<String> download({
    void Function(int received, int total)? onProgress,
  }) {
    if (onProgress != null) _progressListeners.add(onProgress);
    final running = _inflight;
    if (running != null) return running;
    final future =
        _download((r, t) {
          for (final l in List.of(_progressListeners)) {
            l(r, t);
          }
        }).timeout(_downloadTimeout).whenComplete(() {
          _inflight = null;
          _progressListeners.clear();
        });
    _inflight = future;
    return future;
  }

  static Future<String> _download(
    void Function(int received, int total) onProgress,
  ) async {
    final body = await fetcher(url, onProgress);
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic> ||
        json['strings'] is! Map ||
        (json['strings'] as Map).isEmpty) {
      throw const FormatException('invalid language pack');
    }
    final file = await _file('en.json');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(body);
    try {
      // Android 與 Linux 的 rename 會直接覆蓋
      await tmp.rename(file.path);
    } catch (_) {
      // Windows cannot rename over an existing file.
      if (file.existsSync()) await file.delete();
      await tmp.rename(file.path);
    }
    _successCount++;
    await _saveCheckTime(ok: true);
    return json['version']?.toString() ?? '';
  }

  /// [appVersion] 為 null 時保留 meta.json 原本記錄的 `app`。
  static Future<void> _saveCheckTime({
    required bool ok,
    String? appVersion,
  }) async {
    try {
      final app = appVersion ?? (await _lastCheck()).app;
      final meta = await _file('meta.json');
      await meta.writeAsString(
        jsonEncode({
          'lastCheck': clock().millisecondsSinceEpoch,
          'ok': ok,
          if (app != null) 'app': app,
        }),
      );
    } catch (_) {}
  }

  /// 上次背景檢查的時間、是否成功與當時的 App 版本。沒有紀錄時回傳
  /// (0, false, null)。
  static Future<({int time, bool ok, String? app})> _lastCheck() async {
    try {
      final meta = await _file('meta.json');
      if (!meta.existsSync()) return (time: 0, ok: false, app: null);
      final json = jsonDecode(await meta.readAsString());
      if (json is! Map) return (time: 0, ok: false, app: null);
      return (
        time: json['lastCheck'] as int? ?? 0,
        ok: json['ok'] as bool? ?? true,
        app: json['app'] as String?,
      );
    } catch (_) {
      return (time: 0, ok: false, app: null);
    }
  }

  /// Downloads the pack when its version differs from the loaded one.
  /// Returns true if a new version was saved (used at next start). Throws
  /// on error.
  static Future<bool> checkUpdate() async {
    final old = _version;
    final latest = await download();
    return latest != old;
  }

  /// 背景檢查：已載入語言包且上次成功時，每 7 天檢查一次；
  /// 沒有語言包或上次失敗時，24 小時內不重試。成功與失敗都記錄檢查時間。
  /// 錯誤一律忽略。手動更新請直接呼叫 [download]，不受這裡的限制。
  /// [appVersion] 不是 null 且與 meta.json 記錄的 `app` 不同（App 剛更新）
  /// 時，略過上述間隔，立即檢查。
  static Future<void> maybeUpdateInBackground({String? appVersion}) async {
    try {
      final last = await _lastCheck();
      final appChanged = appVersion != null && appVersion != last.app;
      final elapsed = clock().difference(
        DateTime.fromMillisecondsSinceEpoch(last.time),
      );
      final wait = isLoaded && last.ok ? _checkInterval : _retryInterval;
      if (!appChanged && elapsed < wait) return;
      final before = _successCount;
      try {
        await checkUpdate();
        // download 成功時已寫入檢查時間；補上這次的 App 版本
        if (appVersion != null) {
          await _saveCheckTime(ok: true, appVersion: appVersion);
        }
      } catch (e) {
        // 這段期間若有別的下載成功，不要蓋掉它的紀錄
        if (_successCount == before) {
          await _saveCheckTime(ok: false, appVersion: appVersion);
        }
        rethrow;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('I18nPack update: $e');
    }
  }
}
