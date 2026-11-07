import 'dart:convert';
import 'dart:io';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/env.dart';

/// 更新資訊模型
class UpdateInfo {
  final String version;
  final int versionCode;
  final String downloadUrl;
  final String changelog;
  final bool forceUpdate;

  UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    required this.changelog,
    required this.forceUpdate,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] ?? '',
      versionCode: json['versionCode'] ?? 0,
      downloadUrl: json['download_url'] ?? '',
      changelog: json['changelog'] ?? '',
      forceUpdate: json['force_update'] ?? false,
    );
  }
}

/// 更新檢查結果
class UpdateCheckResult {
  final bool hasUpdate;
  final UpdateInfo? updateInfo;
  final String? error;

  UpdateCheckResult({required this.hasUpdate, this.updateInfo, this.error});
}

/// 更新服務
class UpdateService {
  static const String _serverUrlKey = 'update_server_url';
  static const String _apiKeyKey = 'update_api_key';

  // 固定配置 (開源版本留空，需要更新功能請自行配置伺服器)
  static const String defaultServerUrl = Env.updateServerUrl;
  static const String defaultApiKey = Env.updateApiKey;

  static SharedPreferences? _prefs;

  /// 初始化
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 獲取更新伺服器地址
  static String get serverUrl {
    return _prefs?.getString(_serverUrlKey) ?? defaultServerUrl;
  }

  /// 設定更新伺服器地址
  static Future<void> setServerUrl(String url) async {
    await init();
    await _prefs!.setString(_serverUrlKey, url);
  }

  /// 獲取 API Key
  static String get apiKey {
    return _prefs?.getString(_apiKeyKey) ?? defaultApiKey;
  }

  /// 設定 API Key
  static Future<void> setApiKey(String key) async {
    await init();
    await _prefs!.setString(_apiKeyKey, key);
  }

  /// 獲取裝置 CPU 架構
  static String _getDeviceArch() {
    // Android 裝置架構檢測
    // arm64-v8a 對應 64 位 ARM
    // armeabi-v7a 對應 32 位 ARM
    final arch = Platform.version;
    if (arch.contains('arm64') || arch.contains('aarch64')) {
      return 'arm64-v8a';
    } else if (arch.contains('arm')) {
      return 'armeabi-v7a';
    }
    // 預設返回 arm64-v7a
    return 'arm64-v7a';
  }

  /// 檢查更新
  static Future<UpdateCheckResult> checkForUpdate() async {
    try {
      await init();

      // 如果未配置伺服器地址，跳過更新檢查
      if (serverUrl.isEmpty) {
        return UpdateCheckResult(hasUpdate: false, error: null);
      }

      // 獲取伺服器版本資訊
      final response = await http
          .get(Uri.parse('$serverUrl/version'), headers: {'X-API-Key': apiKey})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return UpdateCheckResult(
          hasUpdate: false,
          error: '伺服器響應錯誤: ${response.statusCode}',
        );
      }

      final json = jsonDecode(response.body);
      final updateInfo = UpdateInfo.fromJson(json);

      // 獲取當前 App 版本
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;

      // 比較版本號
      final hasUpdate = updateInfo.versionCode > currentVersionCode;

      return UpdateCheckResult(hasUpdate: hasUpdate, updateInfo: updateInfo);
    } catch (e) {
      return UpdateCheckResult(hasUpdate: false, error: '檢查更新失敗: $e');
    }
  }

  /// 下載並安裝更新
  static Future<void> downloadAndInstall(
    UpdateInfo updateInfo, {
    Function(double)? onProgress,
    Function(String)? onError,
    VoidCallback? onComplete,
  }) async {
    try {
      await init();

      // 請求儲存許可權
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        // 部分 Android 版本 (11+) 不需要 WRITE_EXTERNAL_STORAGE，而是 scoped storage
        // 但為了相容舊版本，還是建議請求。如果請求失敗，嘗試繼續（以防是 scoped storage 的情況）
        // 或者請求 REQUEST_INSTALL_PACKAGES (在安裝時會觸發)

        // 嘗試請求 manageExternalStorage (Android 11+)
        if (await Permission.manageExternalStorage.isGranted == false) {
          // 簡單的相容處理: 即使 denied 也嘗試繼續，因為可能是 Scoped Storage
        }
      }

      // 獲取裝置架構
      final arch = _getDeviceArch();

      // 下載 APK（帶架構引數）
      final downloadUrl = Uri.parse(
        '$serverUrl/download',
      ).replace(queryParameters: {'arch': arch});
      final request = http.Request('GET', downloadUrl);
      request.headers['X-API-Key'] = apiKey;

      final streamedResponse = await request.send();

      if (streamedResponse.statusCode != 200) {
        onError?.call('下載失敗: ${streamedResponse.statusCode}');
        return;
      }

      final contentLength = streamedResponse.contentLength ?? 0;
      final bytes = <int>[];
      var received = 0;

      await for (final chunk in streamedResponse.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          onProgress?.call(received / contentLength);
        }
      }

      // 儲存到本地
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        onError?.call('無法獲取儲存目錄');
        return;
      }

      final apkFile = File('${dir.path}/bilitv_update.apk');
      await apkFile.writeAsBytes(bytes);

      // 通知下載完成
      onComplete?.call();

      // 稍等一下確保檔案寫入完成
      await Future.delayed(const Duration(milliseconds: 500));

      // 呼叫 Android Intent 安裝 APK
      await _installApk(apkFile.path);
    } catch (e) {
      onError?.call('下載安裝失敗: $e');
    }
  }

  /// 呼叫系統安裝 APK
  static Future<void> _installApk(String apkPath) async {
    const platform = MethodChannel('com.bili.tv/update');
    try {
      await platform.invokeMethod('installApk', {'path': apkPath});
    } catch (e) {
      // 如果原生方法不存在，使用備用方案
      throw Exception('安裝 APK 需要原生程式碼支援: $e');
    }
  }

  /// 獲取當前版本資訊
  static Future<String> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return '${packageInfo.version} (${packageInfo.buildNumber})';
  }

  /// 顯示更新對話方塊
  static void showUpdateDialog(
    BuildContext context,
    UpdateInfo updateInfo, {
    VoidCallback? onUpdate,
    VoidCallback? onCancel,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !updateInfo.forceUpdate,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(
          '發現新版本 ${updateInfo.version}',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '更新內容:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              updateInfo.changelog,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          if (!updateInfo.forceUpdate)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onCancel?.call();
              },
              child: const Text(
                '稍後再說',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onUpdate?.call();
            },
            child: const Text(
              '立即更新',
              style: TextStyle(color: Color(0xFFfb7299)),
            ),
          ),
        ],
      ),
    );
  }

  /// 顯示下載進度對話方塊
  static void showDownloadProgress(
    BuildContext context,
    UpdateInfo updateInfo,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadProgressDialog(updateInfo: updateInfo),
    );
  }
}

/// 下載進度對話方塊
class _DownloadProgressDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const _DownloadProgressDialog({required this.updateInfo});

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  void _startDownload() {
    UpdateService.downloadAndInstall(
      widget.updateInfo,
      onProgress: (progress) {
        if (mounted) {
          setState(() => _progress = progress);
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() => _error = error);
        }
      },
      onComplete: () {
        if (mounted) {
          // 下載完成，關閉對話方塊，系統會彈出安裝介面
          Navigator.of(context).pop();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      title: const Text('正在下載更新', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ] else ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 16),
            Text(
              '${(_progress * 100).toStringAsFixed(1)}%',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('關閉', style: TextStyle(color: Colors.white54)),
          ),
      ],
    );
  }
}
