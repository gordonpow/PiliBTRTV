import 'dart:async' show Timer;
import 'dart:io' show Directory, File, Platform;

import 'package:bili_tv_app/btr_version.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, kDebugMode;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';

import 'settings_service.dart';

/// GitHub 上比目前版本新的 release。
class UpdateInfo {
  const UpdateInfo({
    required this.tag,
    required this.body,
    required this.htmlUrl,
    required this.assets,
  });

  final String tag;
  final String body;
  final String htmlUrl;

  /// release 內每個檔案的名稱與下載網址。
  final List<({String name, String url})> assets;
}

/// 檢查 GitHub 上的 PiliBTRTV release。不會自己彈出對話框：
/// 有新版本時只設定 [available]，由介面顯示紅點。
abstract final class UpdateService {
  static final available = ValueNotifier<UpdateInfo?>(null);
  static final checking = ValueNotifier<bool>(false);

  /// 下載進度 0 到 1；沒有下載時為 null。
  static final progress = ValueNotifier<double?>(null);

  static const _channel = MethodChannel('com.bili.tv/update');
  static const _releasesUrl =
      'https://api.github.com/repos/gordonpow/PiliBTRTV/releases';
  static const _abis = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'];

  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      headers: {
        'accept': 'application/vnd.github+json',
        'user-agent': 'PiliBTRTV',
      },
    ),
  );

  /// 解析 `v2.2.0-btr.7` 這類 tag 的版本數字。
  static List<int> _parse(String tag) {
    final m = RegExp(r'(\d+)\.(\d+)\.(\d+)(?:-btr\.(\d+))?').firstMatch(tag);
    if (m == null) return const [0, 0, 0, 0];
    return [for (var i = 1; i <= 4; i++) int.tryParse(m[i] ?? '') ?? 0];
  }

  static bool _isNewer(String tag, String current) {
    final a = _parse(tag), b = _parse(current);
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  /// 上次檢查的開始時間（自動或手動）。
  static DateTime? _lastCheck;
  static Timer? _timer;

  /// 啟動或更新自動檢查。距上次檢查已超過間隔（或 App 啟動後還沒檢查過）
  /// 就立即檢查，之後每隔一個間隔再檢查。App 啟動、回到前景
  /// （背景時計時器不會跑）與設定變更時呼叫。自動更新關閉時會停止。
  static void startAuto() {
    _timer?.cancel();
    _timer = null;
    if (!SettingsService.autoUpdate) return;
    final interval = Duration(hours: SettingsService.updateIntervalHours);
    final last = _lastCheck;
    final wait = last == null
        ? Duration.zero
        : last.add(interval).difference(DateTime.now());
    if (wait <= Duration.zero) {
      check();
      _timer = Timer(interval, startAuto);
    } else {
      _timer = Timer(wait, startAuto);
    }
  }

  /// 檢查新版本。[silent] 為 true 時不顯示訊息。
  static Future<void> check({bool silent = true}) async {
    if (checking.value) return;
    checking.value = true;
    _lastCheck = DateTime.now();
    try {
      final res = await _dio.get(_releasesUrl);
      final data = res.data;
      if (data is! List) throw const FormatException('no release list');
      Map? release;
      for (final e in data.cast<Map>()) {
        if (e['draft'] != true && e['prerelease'] != true) {
          release = e;
          break;
        }
      }
      final tag = release?['tag_name'] as String?;
      if (release == null || tag == null || !_isNewer(tag, btrVersion)) {
        available.value = null;
        _deleteDownloads();
        if (!silent) SettingsService.toast(null, '已是最新版本');
        return;
      }
      available.value = UpdateInfo(
        tag: tag,
        body: (release['body'] as String?)?.trim() ?? '',
        htmlUrl:
            release['html_url'] as String? ??
            'https://github.com/gordonpow/PiliBTRTV/releases/latest',
        assets: [
          for (final Map a in (release['assets'] as List? ?? const []))
            (
              name: a['name'] as String,
              url: a['browser_download_url'] as String,
            ),
        ],
      );
      if (!silent) SettingsService.toast(null, '發現新版本 $tag');
    } catch (e) {
      if (kDebugMode) debugPrint('failed to check update: $e');
      if (!silent) SettingsService.toast(null, '檢查更新失敗，請檢查網路');
    } finally {
      checking.value = false;
    }
  }

  /// 刪除已下載的 APK：目前版本已是最新，舊檔不再需要。
  static Future<void> _deleteDownloads() async {
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/update');
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// 選擇此裝置的 APK：檔名含 ABI 者優先（依裝置支援順序），
  /// 否則選檔名不含任何 ABI 字樣的通用 APK。
  static ({String name, String url})? _pickAsset(
    UpdateInfo info,
    List<String> abis,
  ) {
    final apks = info.assets.where((e) => e.name.endsWith('.apk')).toList();
    for (final abi in abis) {
      for (final a in apks) {
        if (a.name.contains(abi)) return a;
      }
    }
    for (final a in apks) {
      if (!_abis.any(a.name.contains)) return a;
    }
    return null;
  }

  /// 下載此裝置的 APK 並開啟系統安裝程式。
  static Future<void> downloadAndInstall(UpdateInfo info) async {
    if (progress.value != null) return;
    if (!Platform.isAndroid) return;
    List<String> abis = const [];
    try {
      final r = await _channel.invokeListMethod<String>('getSupportedAbis');
      abis = r ?? const [];
    } catch (_) {}
    final asset = _pickAsset(info, abis);
    if (asset == null) {
      SettingsService.toast(null, '找不到適用此裝置的安裝檔');
      return;
    }
    // 安裝程式透過 FileProvider 的 cache-path 讀檔（file_paths.xml 涵蓋 cache/update/）。
    final dir = Directory('${(await getTemporaryDirectory()).path}/update');
    final file = File('${dir.path}/${asset.name}');
    progress.value = 0;
    try {
      // 完整檔案會保留（例如使用者要先允許安裝來源），再次使用即可。
      if (!file.existsSync()) {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        dir.createSync(recursive: true);
        final part = '${file.path}.part';
        await _dio.download(
          asset.url,
          part,
          onReceiveProgress: (received, total) {
            if (total > 0) progress.value = received / total;
          },
        );
        File(part).renameSync(file.path);
      }
      progress.value = null;
      final result = await _channel.invokeMethod<String>('installApk', {
        'path': file.path,
      });
      if (result == 'permission') {
        SettingsService.toast(null, '請允許 PiliBTRTV 安裝應用程式，再按一次安裝');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('update download error: $e');
      SettingsService.toast(null, '下載更新失敗');
    } finally {
      progress.value = null;
    }
  }
}
