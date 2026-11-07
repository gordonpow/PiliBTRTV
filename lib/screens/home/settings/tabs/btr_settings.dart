import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import '../../../../services/btr/btr_config.dart';
import '../../../../services/btr/btr_proxy.dart';
import '../../../../services/settings_service.dart';
import '../widgets/setting_action_row.dart';
import '../widgets/setting_dropdown_row.dart';
import '../widgets/setting_toggle_row.dart';

/// 線程撕裂者（BTR）播放加速設定
class BtrSettings extends StatefulWidget {
  final VoidCallback onMoveUp;
  final FocusNode? sidebarFocusNode;

  const BtrSettings({super.key, required this.onMoveUp, this.sidebarFocusNode});

  @override
  State<BtrSettings> createState() => _BtrSettingsState();
}

class _BtrSettingsState extends State<BtrSettings> {
  static const _emptyHostsMsg = '請至少輸入一個 CDN 節點';

  /// Persist done: reset proxy, toast, rebuild.
  void _saved() {
    BtrProxy.reset();
    if (!mounted) return;
    SettingsService.toast(context, '已儲存，下一部影片生效');
    setState(() {});
  }

  /// Opens the custom node dialog. Returns the parsed list, or null if cancelled.
  Future<List<String>?> _editCustomHosts() {
    return showDialog<List<String>>(
      context: context,
      builder: (_) => _CustomCdnDialog(initial: BtrConfig.customCdn),
    );
  }

  Future<void> _onCustomTap() async {
    final hosts = await _editCustomHosts();
    if (hosts == null || !mounted) return;
    if (hosts.isEmpty && BtrConfig.cdnMode == BtrCdnMode.custom) {
      SettingsService.toast(context, _emptyHostsMsg);
      return;
    }
    await BtrConfig.setCustomCdn(hosts);
    _saved();
  }

  Future<void> _onModeChanged(BtrCdnMode? mode) async {
    if (mode == null) return;
    if (mode == BtrCdnMode.custom && BtrConfig.customCdn.isEmpty) {
      final hosts = await _editCustomHosts();
      if (!mounted) return;
      if (hosts == null || hosts.isEmpty) {
        SettingsService.toast(context, _emptyHostsMsg);
        return;
      }
      await BtrConfig.setCustomCdn(hosts);
    }
    await BtrConfig.setCdnMode(mode);
    _saved();
  }

  @override
  Widget build(BuildContext context) {
    final customCount = BtrConfig.customCdn.length;
    final threads = BtrConfig.threads;
    final auto = BtrConfig.autoThreads;
    final String threadsSubtitle = auto
        ? '自動執行緒數開啟時不使用'
        : (threads > 32 ? '執行緒過多可能被 CDN 限流，建議 8 到 32' : '每個播放請求使用的執行緒數');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingToggleRow(
          label: '播放加速',
          subtitle: '播放時從多個 CDN 節點並行下載，減少卡頓',
          value: BtrConfig.playback,
          autofocus: true,
          isFirst: true,
          onMoveUp: widget.onMoveUp,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await BtrConfig.setPlayback(value);
            _saved();
          },
        ),
        const SizedBox(height: 16),
        SettingDropdownRow<BtrCdnMode>(
          label: 'CDN 模式',
          subtitle: '${BtrConfig.hosts.length} 個節點輪換使用，連續兩次 0 KiB 的節點會被停用',
          value: BtrConfig.cdnMode,
          items: BtrCdnMode.values,
          itemLabel: (m) => m.label,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: _onModeChanged,
        ),
        const SizedBox(height: 16),
        SettingActionRow(
          label: '自訂 CDN 節點',
          value: customCount > 0 ? '$customCount 個' : '未設定',
          buttonLabel: '編輯',
          sidebarFocusNode: widget.sidebarFocusNode,
          onTap: _onCustomTap,
        ),
        const SizedBox(height: 16),
        SettingToggleRow(
          label: '自動執行緒數（推薦）',
          subtitle: '播放使用 8 個執行緒',
          value: auto,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await BtrConfig.setAutoThreads(value);
            _saved();
          },
        ),
        const SizedBox(height: 16),
        SettingDropdownRow<int>(
          label: '執行緒數',
          subtitle: threadsSubtitle,
          value: BtrConfig.threadSteps.contains(threads)
              ? threads
              : BtrConfig.defaultThreads,
          items: BtrConfig.threadSteps,
          itemLabel: (n) => '$n',
          isLast: true,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (n) async {
            if (n == null) return;
            await BtrConfig.setThreads(n);
            _saved();
          },
        ),
      ],
    );
  }
}

/// Multi-line editor for custom CDN hosts, usable with a TV remote.
class _CustomCdnDialog extends StatefulWidget {
  final List<String> initial;
  const _CustomCdnDialog({required this.initial});

  @override
  State<_CustomCdnDialog> createState() => _CustomCdnDialogState();
}

class _CustomCdnDialogState extends State<_CustomCdnDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial.join('\n'),
  );
  late final FocusNode _fieldNode = FocusNode(onKeyEvent: _onFieldKey);

  /// D-pad down at the end of the text leaves the field for the buttons.
  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final sel = _controller.selection;
      final atEnd =
          !sel.isValid ||
          (sel.isCollapsed &&
              !_controller.text.substring(sel.end).contains('\n'));
      if (atEnd) {
        node.nextFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      title: const Text('自訂 CDN 節點', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          focusNode: _fieldNode,
          autofocus: true,
          minLines: 4,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: ZhConvert.convert('每行一個，例如\nupos-sz-mirrorali.bilivideo.com'),
            helperText: ZhConvert.convert('最多 32 個，原始位址會一併使用'),
            hintStyle: TextStyle(color: Colors.white38),
            helperStyle: TextStyle(color: Colors.white54),
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(BtrConfig.parseHosts(_controller.text)),
          child: const Text('儲存', style: TextStyle(color: Color(0xFFfb7299))),
        ),
      ],
    );
  }
}
