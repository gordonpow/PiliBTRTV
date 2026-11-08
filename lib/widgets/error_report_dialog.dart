import 'package:bili_tv_app/services/error_report_service.dart';
import 'package:bili_tv_app/services/report_send_service.dart';
import 'package:bili_tv_app/services/report_share_service.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 顯示「回報問題」確認對話框；報告只會在同一個 Wi-Fi 的手機網頁上顯示。
Future<void> showErrorReportDialog(
  BuildContext context, {
  String? crashSection,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ErrorReportDialog(crashSection: crashSection),
  );
}

enum _Stage { select, sending, sent, failed, confirm, share }

class _ErrorReportDialog extends StatefulWidget {
  final String? crashSection;

  const _ErrorReportDialog({this.crashSection});

  @override
  State<_ErrorReportDialog> createState() => _ErrorReportDialogState();
}

class _ErrorReportDialogState extends State<_ErrorReportDialog> {
  late _Stage _stage = ReportSendService.enabled
      ? _Stage.select
      : _Stage.confirm;
  String _sentId = '';
  String _failMessage = '';
  ReportCategory? _lastCategory;
  String? _shareUrl;
  bool _shareReady = false;

  static const _pink = Color(0xFFfb7299);

  bool get _hasCrash =>
      widget.crashSection != null && widget.crashSection!.trim().isNotEmpty;

  @override
  void dispose() {
    ReportShareService.instance.stop();
    super.dispose();
  }

  /// 產生手機查看網址；沒有區網位址時 _shareUrl 為 null
  Future<void> _prepareShare(String text) async {
    String? url;
    try {
      url = await ReportShareService.instance.start(text);
    } catch (_) {
      url = null;
    }
    if (!mounted) return;
    setState(() {
      _shareUrl = url;
      _shareReady = true;
    });
  }

  Future<void> _send(ReportCategory category) async {
    if (_stage == _Stage.sending) return;
    setState(() {
      _stage = _Stage.sending;
      _lastCategory = category;
    });
    String text;
    try {
      text = await ErrorReportService.buildReport(
        crashSection: widget.crashSection,
      );
    } catch (e) {
      final dev = await ErrorReportService.deviceSummary();
      text =
          '（報告產生失敗：${e.runtimeType}）\n'
          '裝置: ${dev['device']}\n'
          'Android: ${dev['android']}';
    }
    final result = await ReportSendService.send(
      category: category,
      report: text,
    );
    if (!mounted) return;
    setState(() {
      if (result.ok) {
        _sentId = result.id;
        _stage = _Stage.sent;
      } else {
        _failMessage = result.message;
        _stage = _Stage.failed;
      }
    });
  }

  Future<void> _share() async {
    setState(() {
      _stage = _Stage.share;
      _shareReady = false;
      _shareUrl = null;
    });
    final text = await ErrorReportService.buildReport(
      crashSection: widget.crashSection,
    );
    if (!mounted) return;
    await _prepareShare(text);
  }

  /// 手機查看的 QR 與提示
  Widget _shareBody(TextStyle body) {
    if (!_shareReady) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(width: 16),
          Text('準備中…', style: TextStyle(color: Colors.white70)),
        ],
      );
    }
    final url = _shareUrl;
    if (url == null) {
      return Text('請把電視連上 Wi-Fi 或有線網路', style: body);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.white,
          child: QrImageView(data: url, size: 150),
        ),
        const SizedBox(width: 20),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('用手機掃描 QR 碼，或開啟網址：', style: body),
              const SizedBox(height: 6),
              Text(
                url,
                style: const TextStyle(
                  color: _pink,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text('手機需與電視連接同一個 Wi-Fi。', style: body),
              Text('網頁可複製全部或下載 .txt，30 分鐘內有效。', style: body),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _preview() async {
    final text = await ErrorReportService.buildReport(
      crashSection: widget.crashSection,
    );
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
    bool wide = false,
  }) {
    final button = TextButton(
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
    return wide ? SizedBox(width: double.infinity, child: button) : button;
  }

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(color: Colors.white70, fontSize: 15, height: 1.5);
    final Widget content;
    final List<Widget> actions;

    switch (_stage) {
      case _Stage.select:
        final defaultCat = _hasCrash
            ? ReportCategory.crash
            : ReportCategory.values.first;
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('請選擇問題類型，按下後會立即送出報告給開發者（Email）：', style: body),
            const SizedBox(height: 8),
            for (final c in ReportCategory.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _btn(
                  c.label,
                  () => _send(c),
                  primary: true,
                  autofocus: c == defaultCat,
                  wide: true,
                ),
              ),
            const SizedBox(height: 8),
            const Text('報告包含：', style: body),
            if (_hasCrash) const Text('・上次閃退的原因與堆疊', style: body),
            const Text('・App 版本、Android 版本、裝置型號、CPU 架構、螢幕解析度、語言', style: body),
            const Text('・BTR 與畫質等設定摘要、是否已登入', style: body),
            const Text('・App 最近的執行紀錄（log），用來找出哪裡出錯', style: body),
            const Text('・匿名安裝 ID（用來限制回報次數，不含帳號資訊）', style: body),
            const SizedBox(height: 8),
            const Text('不包含：帳號、UID、Cookie、登入憑證、觀看與搜尋紀錄、IP 位址。', style: body),
          ],
        );
        actions = [
          _btn('改用手機查看', _share),
          _btn('取消', () => Navigator.of(context).pop()),
        ];
      case _Stage.sending:
        content = const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 16),
            Text('正在送出…', style: TextStyle(color: Colors.white70)),
          ],
        );
        actions = [_btn('送出中…', null)];
      case _Stage.sent:
        content = Text('已送出，回報編號 $_sentId。開發者會透過 Email 收到這份報告。', style: body);
        actions = [
          _btn(
            '完成',
            () => Navigator.of(context).pop(),
            primary: true,
            autofocus: true,
          ),
        ];
      case _Stage.failed:
        content = Text(_failMessage, style: body);
        actions = [
          _btn(
            '重試',
            () => _send(_lastCategory ?? ReportCategory.other),
            primary: true,
            autofocus: true,
          ),
          _btn('改用手機查看', _share),
          _btn('關閉', () => Navigator.of(context).pop()),
        ];
      case _Stage.confirm:
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '報告會顯示在電視上的網頁，只有連到同一個 Wi-Fi 的裝置才能開啟，可以複製內容或在 GitHub 回報問題。報告包含：',
              style: body,
            ),
            const SizedBox(height: 8),
            if (_hasCrash) const Text('・上次閃退的原因與堆疊', style: body),
            const Text('・App 版本、Android 版本、裝置型號、CPU 架構、螢幕解析度、語言', style: body),
            const Text('・BTR 與畫質等設定摘要、是否已登入', style: body),
            const Text('・App 最近的執行紀錄（log），用來找出哪裡出錯', style: body),
            const SizedBox(height: 8),
            const Text('不包含：帳號、UID、Cookie、登入憑證、觀看與搜尋紀錄、IP 位址。', style: body),
          ],
        );
        actions = [
          _btn('取消', () => Navigator.of(context).pop(), autofocus: true),
          _btn('預覽', _preview),
          _btn('用手機查看', _share),
        ];
      case _Stage.share:
        content = _shareBody(body);
        actions = [
          _btn(
            '關閉',
            () => Navigator.of(context).pop(),
            primary: true,
            autofocus: true,
          ),
        ];
    }

    final String titleText;
    if (_hasCrash) {
      titleText = '上次 App 異常結束，是否回報錯誤？';
    } else {
      titleText = '回報問題';
    }

    return PopScope(
      canPop: _stage != _Stage.sending,
      child: AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(titleText, style: const TextStyle(color: Colors.white)),
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
