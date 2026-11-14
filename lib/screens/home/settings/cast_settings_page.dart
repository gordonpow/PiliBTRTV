import 'package:bili_tv_app/services/cast/cast_service.dart';
import 'package:bili_tv_app/services/local_server.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'widgets/setting_action_row.dart';

/// 投放配對頁：顯示 QR code 與已配對的手機
class CastSettingsPage extends StatefulWidget {
  const CastSettingsPage({super.key});

  @override
  State<CastSettingsPage> createState() => _CastSettingsPageState();
}

class _CastSettingsPageState extends State<CastSettingsPage> {
  List<String> _ips = LocalServer.instance.localIps;
  String _name = '';
  String _id = '';
  bool _loading = true;
  final _refreshNode = FocusNode();
  final Map<String, FocusNode> _rowNodes = {};

  FocusNode _nodeFor(String id) => _rowNodes.putIfAbsent(id, FocusNode.new);

  Future<void> _remove(List<CastPairedDevice> list, int index) async {
    // 移除後把焦點移到相鄰列；沒有相鄰列就回到「重新整理」
    final neighbor = index + 1 < list.length
        ? list[index + 1].deviceId
        : (index > 0 ? list[index - 1].deviceId : null);
    await CastService.instance.removePaired(list[index].deviceId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = neighbor == null ? _refreshNode : _nodeFor(neighbor);
      node.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    CastService.instance.pairedChanged.addListener(_onPaired);
    _load();
  }

  @override
  void dispose() {
    CastService.instance.pairedChanged.removeListener(_onPaired);
    _refreshNode.dispose();
    for (final n in _rowNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _onPaired() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    // IP 可能在啟動後才變動，開頁時重新抓取
    await LocalServer.instance.refreshAddress();
    final name = await CastService.instance.tvName();
    if (!mounted) return;
    setState(() {
      _ips = LocalServer.instance.localIps;
      _name = name;
      _id = CastService.instance.tvId;
      _loading = false;
    });
  }

  String _qrData(String ip) =>
      'pilibtrtv://cast?host=$ip&port=${LocalServer.instance.port}'
      '&id=$_id&name=${Uri.encodeComponent(_name)}';

  String _fmt(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final paired = CastService.instance.pairedList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('投放配對'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '用手機 App 掃描 QR code，即可一鍵投放影片到這台電視。',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_ips.isEmpty)
            const Text(
              '未連上區網',
              style: TextStyle(color: Colors.orange, fontSize: 16),
            )
          else
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [for (final ip in _ips) _qrCard(ip)],
            ),
          const SizedBox(height: 16),
          SettingActionRow(
            label: '重新整理',
            value: '重新抓取區網 IP',
            buttonLabel: '重新整理',
            autofocus: true,
            isFirst: true,
            isLast: paired.isEmpty,
            focusNode: _refreshNode,
            onTap: _load,
          ),
          const SizedBox(height: 16),
          const Text(
            '已配對的手機',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (paired.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                '尚無已配對的手機',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            )
          else
            for (var i = 0; i < paired.length; i++)
              SettingActionRow(
                key: ValueKey(paired[i].deviceId),
                label: paired[i].deviceName,
                value: '配對時間 ${_fmt(paired[i].pairedAt)}',
                buttonLabel: '移除',
                focusNode: _nodeFor(paired[i].deviceId),
                isLast: i == paired.length - 1,
                onTap: () => _remove(paired, i),
              ),
        ],
      ),
    );
  }

  Widget _qrCard(String ip) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: _qrData(ip),
            size: 180,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$ip:${LocalServer.instance.port}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        Text(
          _name,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ],
    );
  }
}
