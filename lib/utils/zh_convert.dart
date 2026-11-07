import 'dart:ui' show PlatformDispatcher;

import 'package:bili_tv_app/services/settings_service.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/painting.dart' show InlineSpan, TextSpan;
import 'package:flutter/services.dart' show rootBundle;

enum ZhScript { traditional, simplified }

/// Converts text between Traditional and Simplified Chinese when it is
/// shown. Data (server responses, user input, values compared in code)
/// is never changed: only the widgets that draw text call [convert].
///
/// Tables come from OpenCC (see tool/gen_zh_dict.py):
/// traditional mode uses s2tw, simplified mode uses tw2sp.
abstract final class ZhConvert {
  static ZhScript script = ZhScript.traditional;

  static Map<String, String> _table = const {};

  /// Longest key that starts with a code unit. A code unit that is not
  /// here starts no key, so it is copied as is.
  static Map<int, int> _maxLenByFirst = const {};

  static const _cacheSize = 4096;
  static const _cacheMaxLength = 200;
  // Map literals keep insertion order, which makes this an LRU cache.
  static final _cache = <String, String>{};

  /// Script for the language setting ([SettingsService.appLanguage]).
  static ZhScript resolve(int language) => switch (language) {
    1 => ZhScript.traditional,
    2 => ZhScript.simplified,
    _ => systemScript,
  };

  /// Simplified for a Simplified Chinese system language, else Traditional.
  static ZhScript get systemScript {
    final locale = PlatformDispatcher.instance.locale;
    if (locale.languageCode != 'zh') return ZhScript.traditional;
    final scriptCode = locale.scriptCode;
    if (scriptCode == 'Hans') return ZhScript.simplified;
    if (scriptCode == 'Hant') return ZhScript.traditional;
    return switch (locale.countryCode) {
      'CN' || 'SG' => ZhScript.simplified,
      _ => ZhScript.traditional,
    };
  }

  /// Simplified mode only: whole UI strings with their full OpenCC
  /// tw2sp result. [_table] leaves out Taiwan phrases that would also
  /// change Simplified server text (影片 -> 视频); a known UI string can
  /// use them.
  static Map<String, String> _exact = const {};

  static Map<String, String> _parse(String raw, [Map<int, int>? maxLen]) {
    final table = <String, String>{};
    for (final line in raw.split('\n')) {
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      final key = line.substring(0, tab);
      table[key] = line.substring(tab + 1);
      if (maxLen != null) {
        final first = key.codeUnitAt(0);
        final old = maxLen[first];
        if (old == null || old < key.length) maxLen[first] = key.length;
      }
    }
    return table;
  }

  /// Loads the tables for the current setting. Call once on start, after
  /// the settings storage is open.
  static Future<void> init() async {
    script = resolve(SettingsService.appLanguage);
    try {
      final simplified = script == ZhScript.simplified;
      final raw = await rootBundle.loadString(
        simplified ? 'assets/zh/t2s.txt' : 'assets/zh/s2t.txt',
      );
      final maxLen = <int, int>{};
      final table = _parse(raw, maxLen);
      if (simplified) {
        _exact = _parse(await rootBundle.loadString('assets/zh/t2s_ui.txt'));
      }
      _table = table;
      _maxLenByFirst = maxLen;
    } catch (e) {
      if (kDebugMode) debugPrint('ZhConvert: no table: $e');
    }
  }

  static String convert(String text) {
    if (text.isEmpty || _table.isEmpty) return text;
    final cacheable = text.length <= _cacheMaxLength;
    if (cacheable) {
      final hit = _cache.remove(text);
      if (hit != null) {
        _cache[text] = hit;
        return hit;
      }
    }
    final result = _exact[text] ?? _convert(text);
    if (cacheable) {
      if (_cache.length >= _cacheSize) _cache.remove(_cache.keys.first);
      _cache[text] = result;
    }
    return result;
  }

  /// Longest match from left to right: phrases first, then characters.
  static String _convert(String text) {
    StringBuffer? out;
    var copied = 0; // text before this index is already in [out]
    var i = 0;
    final length = text.length;
    while (i < length) {
      final unit = text.codeUnitAt(i);
      final maxLen = _maxLenByFirst[unit];
      if (maxLen != null) {
        for (var n = maxLen < length - i ? maxLen : length - i; n > 0; n--) {
          final value = _table[text.substring(i, i + n)];
          if (value != null) {
            (out ??= StringBuffer())
              ..write(text.substring(copied, i))
              ..write(value);
            i += n;
            copied = i;
            break;
          }
          if (n == 1) i++;
        }
        continue;
      }
      // Keep a surrogate pair together.
      i += (unit & 0xFC00) == 0xD800 && i + 1 < length ? 2 : 1;
    }
    if (out == null) return text;
    out.write(text.substring(copied));
    return out.toString();
  }

  /// Converts the text of [span] and of its [TextSpan] children. Other
  /// spans (for example WidgetSpan) stay as they are: the widgets in them
  /// convert their own text.
  static InlineSpan span(InlineSpan span) {
    if (_table.isEmpty || span.runtimeType != TextSpan) return span;
    span as TextSpan;
    return TextSpan(
      text: span.text == null ? null : convert(span.text!),
      children: span.children?.map(ZhConvert.span).toList(),
      style: span.style,
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel: span.semanticsLabel,
      semanticsIdentifier: span.semanticsIdentifier,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }
}
