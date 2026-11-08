import 'package:bili_tv_app/btr_version.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import '../../../../services/settings_service.dart';
import '../../../../services/update_service.dart';
import '../../../../widgets/error_report_dialog.dart';
import '../widgets/setting_action_row.dart';
import '../widgets/setting_dropdown_row.dart';
import '../widgets/setting_toggle_row.dart';

class AboutSettings extends StatefulWidget {
  final VoidCallback onMoveUp;
  final FocusNode? sidebarFocusNode;

  const AboutSettings({
    super.key,
    required this.onMoveUp,
    this.sidebarFocusNode,
  });

  @override
  State<AboutSettings> createState() => _AboutSettingsState();
}

class _AboutSettingsState extends State<AboutSettings> {
  bool _autoUpdate = SettingsService.autoUpdate;
  int _interval = SettingsService.updateIntervalHours;

  static String _intervalLabel(int hours) =>
      hours >= 48 ? '${hours ~/ 24} 天' : '$hours 小時';

  Future<void> _onCheckTap() async {
    final info = UpdateService.available.value;
    if (info != null) {
      showUpdateDialog(context, info);
    } else {
      await UpdateService.check(silent: false);
    }
  }

  Future<void> _setAutoUpdate(bool value) async {
    setState(() => _autoUpdate = value);
    await SettingsService.setAutoUpdate(value);
    UpdateService.startAuto();
  }

  Future<void> _setInterval(int? value) async {
    if (value == null) return;
    setState(() => _interval = value);
    await SettingsService.setUpdateIntervalHours(value);
    UpdateService.startAuto();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '目前版本',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
              Text(
                btrVersion,
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: UpdateService.checking,
          builder: (_, checking, _) => ValueListenableBuilder<UpdateInfo?>(
            valueListenable: UpdateService.available,
            builder: (_, info, _) => SettingActionRow(
              label: '檢查更新',
              value: checking
                  ? '檢查中…'
                  : (info != null ? '有新版本 ${info.tag}' : '已是最新'),
              showDot: !checking && info != null,
              buttonLabel: info != null ? '查看' : '檢查',
              autofocus: true,
              isFirst: true,
              onMoveUp: widget.onMoveUp,
              sidebarFocusNode: widget.sidebarFocusNode,
              onTap: checking ? null : _onCheckTap,
            ),
          ),
        ),
        SettingToggleRow(
          label: '自動檢查更新',
          value: _autoUpdate,
          onChanged: _setAutoUpdate,
          sidebarFocusNode: widget.sidebarFocusNode,
        ),
        SettingDropdownRow<int>(
          label: '檢查間隔',
          value: _interval,
          items: SettingsService.updateIntervalOptions,
          itemLabel: _intervalLabel,
          onChanged: _setInterval,
          sidebarFocusNode: widget.sidebarFocusNode,
        ),
        SettingActionRow(
          label: '回報問題',
          value: '上傳去除個人資訊的錯誤報告',
          buttonLabel: '回報',
          isLast: true,
          sidebarFocusNode: widget.sidebarFocusNode,
          onTap: () => showErrorReportDialog(context),
        ),
      ],
    );
  }
}

/// 顯示更新對話框。
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    builder: (_) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // 上下鍵捲動版本說明；焦點在按鈕上，事件會冒泡到這裡。
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final delta = key == LogicalKeyboardKey.arrowDown ? 80.0 : -80.0;
    final target = (_scroll.offset + delta).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.jumpTo(target);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return ValueListenableBuilder<double?>(
      valueListenable: UpdateService.progress,
      builder: (context, progress, _) {
        final downloading = progress != null;
        return PopScope(
          canPop: !downloading,
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: _onKey,
            child: AlertDialog(
              backgroundColor: const Color(0xFF2A2A2A),
              title: Text(
                '發現新版本 ${info.tag}',
                style: const TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 480,
                height: 220,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Text(
                    info.body.isEmpty ? '（無版本說明）' : info.body,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: downloading
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text(
                    '稍後',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                TextButton(
                  autofocus: true,
                  onPressed: downloading
                      ? null
                      : () => UpdateService.downloadAndInstall(info),
                  child: Text(
                    downloading
                        ? '下載中 ${(progress * 100).toStringAsFixed(0)}%'
                        : '下載並安裝',
                    style: const TextStyle(color: Color(0xFFfb7299)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
