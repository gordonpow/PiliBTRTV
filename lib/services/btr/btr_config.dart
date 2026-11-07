// BTR (thread ripper) playback settings, ported from PiliBTR / PiliPlus
// (GPL v3). Behaviour is modelled on Bilibili-thread-ripper-desktop (MIT,
// https://github.com/MrTangLuyao/Bilibili-thread-ripper-desktop).

import 'dart:ui' show PlatformDispatcher;

import 'package:bili_tv_app/services/settings_service.dart';

enum BtrCdnMode {
  mainland('大陸'),
  overseas('海外'),
  custom('自定義');

  final String label;
  const BtrCdnMode(this.label);
}

abstract final class BtrConfig {
  static const String _kPlayback = 'btr_playback';
  static const String _kCdnMode = 'btr_cdn_mode';
  static const String _kCustomCdn = 'btr_custom_cdn';
  static const String _kAutoThreads = 'btr_auto_threads';
  static const String _kThreads = 'btr_threads';
  static const String _kLocaleDefault = 'btr_cdn_locale_default_v1';

  /// Selectable thread counts.
  static const List<int> threadSteps = [4, 8, 16, 32, 64, 128];

  /// Max number of custom CDN hosts.
  static const int maxCustomCdn = 32;

  static const int defaultThreads = 16;

  // Host lists from BTR (shared/cdn-resolver.js).
  static const List<String> mainlandHosts = [
    'upos-sz-mirrorali.bilivideo.com',
    'upos-sz-mirrorhw.bilivideo.com',
    'upos-sz-mirrorbos.bilivideo.com',
    'upos-sz-mirror08c.bilivideo.com',
    'upos-sz-mirrorbd.bilivideo.com',
    'upos-sz-mirror14b.bilivideo.com',
    'upos-sz-estgoss.bilivideo.com',
    'upos-sz-mirrorcos.bilivideo.com',
    'upos-sz-mirrorcoso1.bilivideo.com',
  ];

  static const List<String> overseasHosts = [
    'upos-sz-mirrorcosov.bilivideo.com',
    'upos-sz-mirroraliov.bilivideo.com',
    'cn-hk-eq-01-01.bilivideo.com',
    'cn-hk-eq-01-03.bilivideo.com',
  ];

  /// Multi-CDN parallel fetch while watching (local proxy for the player).
  static bool get playback =>
      SettingsService.prefs.getBool(_kPlayback) ?? true;

  static Future<void> setPlayback(bool value) =>
      SettingsService.prefs.setBool(_kPlayback, value);

  /// Threads per player request. Auto uses 8, the BTR default.
  static int get playbackThreads => autoThreads ? 8 : threads;

  static BtrCdnMode get cdnMode {
    final int index =
        SettingsService.prefs.getInt(_kCdnMode) ?? BtrCdnMode.mainland.index;
    return BtrCdnMode.values[index.clamp(0, BtrCdnMode.values.length - 1)];
  }

  static Future<void> setCdnMode(BtrCdnMode mode) =>
      SettingsService.prefs.setInt(_kCdnMode, mode.index);

  /// First start only: pick the CDN mode by the system language. Simplified
  /// Chinese (mainland users) gets the mainland nodes; Traditional Chinese
  /// (Taiwan, Hong Kong, Macau) gets the overseas nodes, as mainland nodes
  /// often time out from there. A mode the user chose is kept.
  static void applyLocaleDefault() {
    final prefs = SettingsService.prefs;
    if (prefs.getBool(_kLocaleDefault) == true) return;
    if (!prefs.containsKey(_kCdnMode)) {
      final locale = PlatformDispatcher.instance.locale;
      final BtrCdnMode? mode;
      if (locale.scriptCode == 'Hant' ||
          const {'TW', 'HK', 'MO'}.contains(locale.countryCode)) {
        mode = BtrCdnMode.overseas;
      } else if (locale.languageCode == 'zh') {
        mode = BtrCdnMode.mainland;
      } else {
        mode = null;
      }
      if (mode != null) prefs.setInt(_kCdnMode, mode.index);
    }
    prefs.setBool(_kLocaleDefault, true);
  }

  static List<String> get customCdn =>
      SettingsService.prefs.getStringList(_kCustomCdn) ?? const [];

  static Future<void> setCustomCdn(List<String> hosts) =>
      SettingsService.prefs.setStringList(_kCustomCdn, hosts);

  static bool get autoThreads =>
      SettingsService.prefs.getBool(_kAutoThreads) ?? true;

  static Future<void> setAutoThreads(bool value) =>
      SettingsService.prefs.setBool(_kAutoThreads, value);

  static int get threads {
    final int value = SettingsService.prefs.getInt(_kThreads) ?? defaultThreads;
    return value.clamp(threadSteps.first, threadSteps.last);
  }

  static Future<void> setThreads(int value) =>
      SettingsService.prefs.setInt(_kThreads, value);

  /// CDN hosts used for the current mode.
  static List<String> get hosts => switch (cdnMode) {
    BtrCdnMode.mainland => mainlandHosts,
    BtrCdnMode.overseas => overseasHosts,
    BtrCdnMode.custom => customCdn,
  };

  /// Parses user input (one host or URL per line, or comma separated)
  /// into a clean host list.
  static List<String> parseHosts(String input) {
    final result = <String>[];
    for (var item in input.split(RegExp(r'[\s,，]+'))) {
      item = item.trim();
      if (item.isEmpty) continue;
      final host = item.contains('://')
          ? Uri.tryParse(item)?.host
          : Uri.tryParse('https://$item')?.host;
      if (host != null && host.isNotEmpty && !result.contains(host)) {
        result.add(host);
        if (result.length >= maxCustomCdn) break;
      }
    }
    return result;
  }
}
