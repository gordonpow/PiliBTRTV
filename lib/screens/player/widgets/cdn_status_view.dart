import 'dart:async';

import 'package:bili_tv_app/widgets/zh_material.dart';

import '../../../services/btr/btr_config.dart';
import '../../../services/btr/btr_proxy.dart';

/// 單一 CDN 節點（依 host 合併）的顯示資料
class _NodeRow {
  final String host;
  int bytes = 0;
  double speed = 0; // bytes/s
  bool banned = true;

  _NodeRow(this.host);
}

/// CDN 狀態唯讀檢視：每秒取樣 BtrProxy.activeStats()
class CdnStatusView extends StatefulWidget {
  const CdnStatusView({super.key});

  @override
  State<CdnStatusView> createState() => _CdnStatusViewState();
}

class _CdnStatusViewState extends State<CdnStatusView> {
  Timer? _timer;

  /// 上次取樣各來源的 served（以 nodes 清單的 identity 當作來源識別）
  Map<List<Object>, int> _lastServed = Map.identity();
  double _totalSpeed = 0; // bytes/s
  List<_NodeRow> _rows = const [];
  bool _hasData = false;

  @override
  void initState() {
    super.initState();
    _sample();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
  }

  void _sample() {
    final stats = BtrProxy.activeStats();
    final nextServed = Map<List<Object>, int>.identity();
    var total = 0.0;
    final merged = <String, _NodeRow>{};

    for (final s in stats) {
      final key = s.nodes as List<Object>;
      nextServed[key] = s.served;
      final last = _lastServed[key];
      if (last != null && s.served >= last) total += (s.served - last).toDouble();

      for (final n in s.nodes) {
        final row = merged.putIfAbsent(n.host, () => _NodeRow(n.host));
        row.bytes += n.bytes;
        row.speed += n.speed * 1000;
        if (!n.banned) row.banned = false;
      }
    }

    final rows = merged.values.toList()
      ..sort((a, b) => b.speed.compareTo(a.speed));
    _lastServed = nextServed;

    if (!mounted) return;
    setState(() {
      _totalSpeed = total;
      _rows = rows;
      _hasData = stats.isNotEmpty;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _fmtSpeed(double bytesPerSec) {
    if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / 1024 / 1024).toStringAsFixed(2)} MB/s';
    }
    return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          BtrConfig.playback ? 'BTR 已開啟，等待資料…' : '未使用 BTR（直連）',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 15,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '總速度 ${_fmtSpeed(_totalSpeed)}',
            style: const TextStyle(
              color: Color(0xFFfb7299),
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final row in _rows) _buildRow(row),
      ],
    );
  }

  Widget _buildRow(_NodeRow row) {
    final dim = row.banned ? 0.4 : 0.9;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: dim),
                    fontSize: 13,
                  ),
                ),
              ),
              if (row.banned)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '已停用',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${_fmtSpeed(row.speed)}  ·  已接收 '
            '${(row.bytes / 1024 / 1024).toStringAsFixed(1)} MB',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
