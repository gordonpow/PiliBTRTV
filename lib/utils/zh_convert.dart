import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/utils/i18n_pack.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, debugPrint, visibleForTesting;
import 'package:flutter/painting.dart' show InlineSpan, TextSpan;
import 'package:flutter/services.dart' show rootBundle;

/// [english] 顯示英文語言包（[I18nPack]）；語言包沒有的字串維持繁體中文。
enum ZhScript { traditional, simplified, english }

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

  /// 系統語言。測試時可換成假的。
  @visibleForTesting
  static Locale Function() localeProvider = () =>
      PlatformDispatcher.instance.locale;

  /// Script for the language setting ([SettingsService.appLanguage]):
  /// 0 follow system, 1 Traditional, 2 Simplified, 3 English.
  static ZhScript resolve(int language) => switch (language) {
    1 => ZhScript.traditional,
    2 => ZhScript.simplified,
    3 => ZhScript.english,
    _ => systemScript,
  };

  /// 這個語言設定是否需要英文語言包：選 English，或跟隨系統且系統語言
  /// 不是中文。與語言包是否已下載無關。
  static bool needsEnglishPack(int language) =>
      language == 3 || (language == 0 && _systemIsEnglish);

  static bool get _systemIsEnglish =>
      localeProvider().languageCode.toLowerCase() != 'zh';

  /// zh-Hant／TW／HK／MO 為繁體，zh-Hans／CN／SG 為簡體；其他語言（含
  /// 英文）為英文，但還沒有語言包時回傳繁體（背景下載後，下次啟動生效）。
  static ZhScript get systemScript {
    final locale = localeProvider();
    if (locale.languageCode.toLowerCase() != 'zh') {
      return I18nPack.isLoaded ? ZhScript.english : ZhScript.traditional;
    }
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
      // Strip the \r of CRLF line ends; it would show as a space.
      var value = line.substring(tab + 1);
      if (value.endsWith('\r')) value = value.substring(0, value.length - 1);
      table[key] = value;
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
    final language = SettingsService.appLanguage;
    final wantsEnglish = needsEnglishPack(language);
    if (wantsEnglish) {
      // 先載入語言包，resolve 才知道有沒有英文可用。load 不會丟例外。
      await I18nPack.load();
    }
    script = resolve(language);
    if (wantsEnglish) {
      // 沒有語言包（首次啟動或檔案損毀）或到了檢查時間：背景下載，
      // 失敗 24 小時內不重試，下次啟動生效。
      I18nPack.maybeUpdateInBackground();
    }
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

  /// 清除轉換快取（語言包更新後呼叫）。
  static void clearCache() => _cache.clear();

  /// 測試用：清除快取並回到繁體、沒有繁簡表的初始狀態。
  @visibleForTesting
  static void resetForTest() {
    script = ZhScript.traditional;
    _table = const {};
    _maxLenByFirst = const {};
    _exact = const {};
    _cache.clear();
  }

  static String convert(String text) {
    // 英文模式即使繁簡表載入失敗也要翻譯，所以先判斷這個。
    if (text.isEmpty) return text;
    if (_table.isEmpty && script != ZhScript.english) return text;
    final cacheable = text.length <= _cacheMaxLength;
    if (cacheable) {
      final hit = _cache.remove(text);
      if (hit != null) {
        _cache[text] = hit;
        return hit;
      }
    }
    String result;
    if (script == ZhScript.english) {
      // 語言包優先；沒有的字串維持繁體中文。
      final en = I18nPack.translate(text);
      result = en == text ? _convert(text) : en;
    } else {
      result = _exact[text] ?? _convert(text);
    }
    if (cacheable) {
      if (_cache.length >= _cacheSize) _cache.remove(_cache.keys.first);
      _cache[text] = result;
    }
    return result;
  }

  /// 轉換 B 站內容（標題、UP 主名稱、字幕）。繁體、簡體模式與 [convert]
  /// 相同；英文模式只轉繁體顯示，不查語言包字典（內容不是介面字串）。
  static String convertContent(String raw) {
    if (script != ZhScript.english) return convert(raw);
    if (raw.isEmpty || _table.isEmpty) return raw;
    // 與介面字串共用快取，key 加前綴避免和 convert 的結果混在一起。
    final cacheable = raw.length <= _cacheMaxLength;
    final key = '$raw';
    if (cacheable) {
      final hit = _cache.remove(key);
      if (hit != null) {
        _cache[key] = hit;
        return hit;
      }
    }
    final result = _convert(raw);
    if (cacheable) {
      if (_cache.length >= _cacheSize) _cache.remove(_cache.keys.first);
      _cache[key] = result;
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
    if ((_table.isEmpty && script != ZhScript.english) ||
        span.runtimeType != TextSpan) {
      return span;
    }
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
