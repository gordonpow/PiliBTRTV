import 'package:bili_tv_app/services/error_report_service.dart';
import 'package:bili_tv_app/services/local_server.dart';
import 'package:bili_tv_app/services/phone_feedback_service.dart';
import 'package:bili_tv_app/services/report_send_service.dart';
import 'package:bili_tv_app/services/report_share_service.dart';
import 'package:bili_tv_app/services/report_status_service.dart';
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

enum _Stage { select, sending, sent, failed, confirm, share, phone }

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
  bool _fromPhone = false;
  String? _phoneUrl;
  bool _phoneReady = false;

  static const _pink = Color(0xFFfb7299);

  bool get _hasCrash =>
      widget.crashSection != null && widget.crashSection!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    PhoneFeedbackService.instance.lastSent.addListener(_onPhoneSent);
  }

  @override
  void dispose() {
    PhoneFeedbackService.instance.lastSent.removeListener(_onPhoneSent);
    PhoneFeedbackService.instance.stop();
    ReportShareService.instance.stop();
    super.dispose();
  }

  /// 手機送出成功：電視顯示編號（回報紀錄已由 service 寫入，下次開啟即可看到）
  void _onPhoneSent() {
    final event = PhoneFeedbackService.instance.lastSent.value;
    if (event == null || !mounted) return;
    setState(() {
      _sentId = event.id;
      _fromPhone = true;
      _stage = _Stage.sent;
    });
  }

  /// 產生手機輸入網址
  Future<void> _startPhoneInput() async {
    setState(() {
      _stage = _Stage.phone;
      _phoneReady = false;
      _phoneUrl = null;
    });
    String? url;
    try {
      await LocalServer.instance.refreshAddress();
      // 等待期間對話框可能已關閉；這時不能再產生有效的代碼
      if (!mounted) return;
      url = PhoneFeedbackService.instance.start();
    } catch (_) {
      url = null;
    }
    if (!mounted) return;
    setState(() {
      _phoneUrl = url;
      _phoneReady = true;
    });
  }

  Widget _phoneBody(TextStyle body) {
    if (!_phoneReady) {
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
    final url = _phoneUrl;
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
              Text('用同一個 Wi-Fi 的手機掃描 QR 碼，或開啟網址：', style: body),
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
              Text('在手機選擇「問題」或「建議」並輸入內容後送出。', style: body),
              Text('網址 15 分鐘內有效，送出一次後即失效。', style: body),
            ],
          ),
        ),
      ],
    );
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
    if (result.ok) {
      await ReportHistory.add(id: result.id, category: category);
    }
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
      // 帶入階段，切換階段時重新建立按鈕，autofocus 才會重新生效
      key: ValueKey('$_stage-$label'),
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
        // 閃退後自動跳出時，預設焦點放在「取消」，避免誤送；手動開啟則停在第一個類別
        final defaultCat = _hasCrash ? null : ReportCategory.values.first;
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
          _btn('用手機輸入', _startPhoneInput),
          _btn('改用手機查看', _share),
          _btn('取消', () => Navigator.of(context).pop(), autofocus: _hasCrash),
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
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _fromPhone
                  ? '已收到回報（編號 $_sentId）。開發者會透過 Email 收到。'
                  : '已送出，回報編號 $_sentId。開發者會透過 Email 收到這份報告。',
              style: body,
            ),
            const Text('可在「設定 → 關於 → 回報紀錄」再次查看編號。', style: body),
          ],
        );
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
      case _Stage.phone:
        content = _phoneBody(body);
        actions = [
          _btn(
            '關閉',
            () => Navigator.of(context).pop(),
            primary: true,
            autofocus: true,
          ),
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
      titleText = '回報問題/建議';
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

/// 回報紀錄對話框。
Future<void> showReportHistoryDialog(BuildContext context) async {
  final records = await ReportHistory.load();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _ReportHistoryDialog(records: records),
  );
}

String formatReportTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

class _ReportHistoryDialog extends StatefulWidget {
  final List<ReportRecord> records;
  const _ReportHistoryDialog({required this.records});

  @override
  State<_ReportHistoryDialog> createState() => _ReportHistoryDialogState();
}

class _ReportHistoryDialogState extends State<_ReportHistoryDialog> {
  // 只建立一次，避免重建時重新下載；無紀錄時不下載
  late final Future<Map<String, ReportStatus>>? _statusFuture =
      widget.records.isEmpty ? null : ReportStatusService.load();

  @override
  Widget build(BuildContext context) {
    const pink = Color(0xFFfb7299);
    final records = widget.records;
    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      title: const Text('回報紀錄', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 480,
        height: records.isEmpty ? 60 : 340,
        child: records.isEmpty
            ? const Text('尚無回報紀錄', style: TextStyle(color: Colors.white70))
            : FutureBuilder<Map<String, ReportStatus>>(
                future: _statusFuture,
                builder: (context, snap) {
                  final statuses = snap.data ?? const <String, ReportStatus>{};
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var i = 0; i < records.length; i++)
                          _ReportRecordTile(
                            record: records[i],
                            autofocus: i == 0,
                            status:
                                statuses[records[i].id.trim().toUpperCase()],
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          autofocus: records.isEmpty,
          onPressed: () => Navigator.of(context).pop(),
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.focused)
                  ? pink
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: const Text('關閉', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _ReportRecordTile extends StatelessWidget {
  final ReportRecord record;
  final bool autofocus;
  final ReportStatus? status;
  const _ReportRecordTile({
    required this.record,
    required this.autofocus,
    this.status,
  });

  static Color _badgeColor(ReportStatusKind k) {
    switch (k) {
      case ReportStatusKind.resolved:
        return const Color(0xFF4CAF50);
      case ReportStatusKind.inProgress:
        return const Color(0xFFFFB74D);
      case ReportStatusKind.cannotReproduce:
        return const Color(0xFF9E9E9E);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: autofocus,
      onFocusChange: (f) {
        if (f) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 150),
            alignment: 0.5,
          );
        }
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: focused ? const Color(0xFFfb7299) : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      record.id,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        letterSpacing: 2,
                      ),
                    ),
                    if (status != null) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _badgeColor(status!.kind),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status!.kind.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${formatReportTime(record.time)}　${record.category}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                if (status?.note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      status!.note!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
