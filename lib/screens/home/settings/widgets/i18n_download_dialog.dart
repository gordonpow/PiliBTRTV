import 'package:bili_tv_app/utils/i18n_pack.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';

/// 顯示語言包下載進度對話框。下載完成後自動關閉。
///
/// 成功回傳語言包版本；失敗回傳 null。下載中不能用返回鍵關閉。
Future<String?> showI18nDownloadDialog(BuildContext context) async {
  final progress = ValueNotifier<double?>(null);
  final nav = Navigator.of(context, rootNavigator: true);
  var closed = false;
  void close() {
    if (closed) return;
    closed = true;
    nav.pop();
  }

  // 對話框先顯示，下載與它並行；結束時關閉對話框。
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('下載語言包', style: TextStyle(color: Colors.white)),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: value,
                color: const Color(0xFFfb7299),
                backgroundColor: Colors.white12,
              ),
              const SizedBox(height: 12),
              Text(
                value == null ? '連線中…' : '${(value * 100).round()}%',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String? version;
  try {
    version = await I18nPack.download(
      onProgress: (received, total) {
        if (total > 0) progress.value = received / total;
      },
    );
  } catch (_) {
    version = null;
  }
  close();
  await dialog;
  progress.dispose();
  return version;
}
