import 'package:bili_tv_app/services/error_report_service.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 顯示「回報問題」確認對話框；使用者同意後才上傳。
Future<void> showErrorReportDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ErrorReportDialog(),
  );
}

enum _Stage { confirm, uploading, done, failed }

class _ErrorReportDialog extends StatefulWidget {
  const _ErrorReportDialog();

  @override
  State<_ErrorReportDialog> createState() => _ErrorReportDialogState();
}

class _ErrorReportDialogState extends State<_ErrorReportDialog> {
  _Stage _stage = _Stage.confirm;
  String? _url;
  String _error = '';

  static const _pink = Color(0xFFfb7299);

  Future<void> _upload() async {
    setState(() => _stage = _Stage.uploading);
    try {
      final text = await ErrorReportService.buildReport();
      final url = await ErrorReportService.upload(text);
      if (!mounted) return;
      setState(() {
        _url = url;
        _stage = _Stage.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _stage = _Stage.failed;
      });
    }
  }

  Future<void> _preview() async {
    final text = await ErrorReportService.buildReport();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _PreviewDialog(text: text),
    );
  }

  Widget _btn(
    String label,
    VoidCallback? onPressed, {
    bool primary = false,
    bool autofocus = false,
  }) {
    return TextButton(
      autofocus: autofocus,
      onPressed: onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.focused)
              ? _pink
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: primary ? Colors.white : Colors.white70,
          fontWeight: primary ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(color: Colors.white70, fontSize: 15, height: 1.5);
    final Widget content;
    final List<Widget> actions;

    switch (_stage) {
      case _Stage.confirm:
        content = const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('將上傳以下內容到公開的貼文服務（dpaste.com），30 天後自動刪除：', style: body),
            SizedBox(height: 8),
            Text('・App 版本、Android 版本、裝置型號、CPU 架構、螢幕解析度、語言', style: body),
            Text('・BTR 與畫質等設定摘要、是否已登入', style: body),
            Text('・App 最近的執行紀錄（log），用來找出哪裡出錯', style: body),
            SizedBox(height: 8),
            Text('不會上傳：帳號、UID、Cookie、登入憑證、觀看與搜尋紀錄、IP 位址。', style: body),
          ],
        );
        actions = [
          _btn('預覽內容', _preview),
          _btn('取消', () => Navigator.of(context).pop()),
          _btn('同意並上傳', _upload, primary: true, autofocus: true),
        ];
      case _Stage.uploading:
        content = const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 16),
            Text('上傳中…', style: body),
          ],
        );
        actions = const [];
      case _Stage.done:
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.white,
              child: QrImageView(data: _url!, size: 150),
            ),
            const SizedBox(width: 20),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('上傳完成，報告網址：', style: body),
                  const SizedBox(height: 6),
                  Text(
                    _url!,
                    style: const TextStyle(
                      color: _pink,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('請把網址傳給開發者（Threads 或 GitHub issue）。', style: body),
                ],
              ),
            ),
          ],
        );
        actions = [
          _btn(
            '關閉',
            () => Navigator.of(context).pop(),
            primary: true,
            autofocus: true,
          ),
        ];
      case _Stage.failed:
        content = Text(_error, style: body.copyWith(color: Colors.redAccent));
        actions = [
          _btn('關閉', () => Navigator.of(context).pop()),
          _btn('重試', _upload, primary: true, autofocus: true),
        ];
    }

    return PopScope(
      canPop: _stage != _Stage.uploading,
      child: AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(
          _stage == _Stage.failed ? '上傳失敗' : '回報問題',
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: content),
        ),
        actions: actions,
      ),
    );
  }
}

class _PreviewDialog extends StatefulWidget {
  final String text;
  const _PreviewDialog({required this.text});

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // 焦點在按鈕上，上下鍵捲動內容
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final delta = key == LogicalKeyboardKey.arrowDown ? 120.0 : -120.0;
    _scroll.jumpTo(
      (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _onKey,
      child: AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('預覽內容', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 640,
          height: 280,
          child: SingleChildScrollView(
            controller: _scroll,
            child: Text(
              widget.text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('關閉', style: TextStyle(color: Color(0xFFfb7299))),
          ),
        ],
      ),
    );
  }
}
