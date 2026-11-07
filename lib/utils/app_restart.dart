import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart' show MethodChannel;

/// 套用只在啟動時生效的設定後，重新啟動 App。
abstract final class AppRestart {
  static const _channel = MethodChannel('com.bili.tv/update');

  /// 關閉 App 並重新開啟。失敗時提示使用者手動重新啟動。
  static Future<void> restart() async {
    try {
      // 呼叫後程序會立刻結束，設定已在呼叫端 await 寫入
      await _channel.invokeMethod('restart');
    } catch (_) {
      SettingsService.toast(null, '請手動重新啟動 App');
    }
  }

  /// 詢問使用者要立即還是稍後重新啟動。
  static Future<void> ask(BuildContext context) async {
    final now = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          '需要重新啟動',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          '設定需要重新啟動 App 才會生效。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('稍後', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              '立即重新啟動',
              style: TextStyle(color: Color(0xFFfb7299)),
            ),
          ),
        ],
      ),
    );
    if (now == true) await restart();
  }
}
