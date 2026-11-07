import 'dart:convert';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/plugin/plugin_types.dart';
import '../core/plugin/plugin_store.dart';

class SponsorBlockPlugin extends PlayerPlugin {
  @override
  String get id => 'sponsor_block';

  @override
  String get name => '空降助手';

  @override
  String get description => '基於 SponsorBlock 資料庫自動跳過影片中的廣告、贊助、片頭片尾等片段。';

  @override
  String get version => '1.0.0';

  @override
  String get author => 'YangY (Ported)';

  @override
  IconData? get icon => Icons.rocket_launch_outlined;

  List<SponsorSegment> _segments = [];
  final Set<String> _skippedIds = {};
  int _lastPositionMs = 0;
  SponsorBlockConfig _config = SponsorBlockConfig();

  @override
  bool get hasSettings => true;

  @override
  Widget? get settingsWidget => _SponsorBlockSettings(plugin: this);

  @override
  Future<void> onEnable() async {
    _loadConfig();
    debugPrint('✅ 空降助手已啟用');
  }

  @override
  Future<void> onDisable() async {
    _segments = [];
    _skippedIds.clear();
    debugPrint('🔴 空降助手已停用');
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('plugin_config_$id');
    if (jsonStr != null) {
      try {
        _config = SponsorBlockConfig.fromJson(jsonDecode(jsonStr));
      } catch (e) {
        debugPrint('Error loading config: $e');
      }
    }
  }

  Future<void> saveConfig(SponsorBlockConfig config) async {
    _config = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plugin_config_$id', jsonEncode(config.toJson()));
  }

  @override
  Future<void> onVideoLoad(String bvid, int cid) async {
    _segments = [];
    _skippedIds.clear();
    _lastPositionMs = 0;

    // 如果沒有啟用，不請求
    if (!await PluginStore.isEnabled(id)) return;

    try {
      // 預設請求所有跳過型別
      // API: https://bsbsb.top/api/skipSegments?videoID={BVID}&category=sponsor&category=intro&...
      // 這裡簡化處理，請求常用的
      var url = Uri.parse(
        'https://bsbsb.top/api/skipSegments?videoID=$bvid&category=sponsor&category=intro&category=outro&category=interaction&category=selfpromo',
      );

      var response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _segments = data.map((json) => SponsorSegment.fromJson(json)).toList();
        debugPrint(
          '📦 SponsorBlock: Loaded ${_segments.length} segments for $bvid',
        );
      } else if (response.statusCode == 404) {
        debugPrint('SponsorBlock: No segments found for $bvid');
      }
    } catch (e) {
      debugPrint('SponsorBlock Error: $e');
    }
  }

  // 記錄手動跳過
  void manualSkip(String segmentId) {
    _skippedIds.add(segmentId);
  }

  @override
  Future<SkipAction> onPositionUpdate(int positionMs) async {
    if (_segments.isEmpty) return SkipActionNone();

    // 簡單防抖/回退檢測
    if (positionMs < _lastPositionMs - 2000) {
      // 回退超過2秒，重置相關片段的跳過狀態，允許再次跳過
      for (var seg in _segments) {
        if (_skippedIds.contains(seg.uuid) &&
            positionMs < seg.startTimeMs - 1000) {
          _skippedIds.remove(seg.uuid);
        }
      }
    }
    _lastPositionMs = positionMs;

    for (var seg in _segments) {
      if (_skippedIds.contains(seg.uuid)) continue;

      if (positionMs >= seg.startTimeMs && positionMs <= seg.endTimeMs) {
        // 命中片段
        if (_config.autoSkip) {
          _skippedIds.add(seg.uuid);
          return SkipActionSkipTo(
            seg.endTimeMs.toInt(),
            '已跳過: ${seg.category}',
          );
        } else {
          // 顯示按鈕
          return SkipActionShowButton(
            seg.endTimeMs.toInt(),
            '跳過${seg.category}',
            seg.uuid,
          );
        }
      }
    }

    return SkipActionNone();
  }

  @override
  void onVideoEnd() {
    _segments = [];
    _skippedIds.clear();
    _lastPositionMs = 0;
  }
}

class SponsorSegment {
  final String category;
  final String uuid;
  final double startTime; // seconds
  final double endTime; // seconds

  SponsorSegment({
    required this.category,
    required this.uuid,
    required this.startTime,
    required this.endTime,
  });

  // 轉換為毫秒方便比較
  int get startTimeMs => (startTime * 1000).toInt();
  int get endTimeMs => (endTime * 1000).toInt();

  factory SponsorSegment.fromJson(Map<String, dynamic> json) {
    // category map for better display names if needed
    // sponsor, intro, outro, interaction, selfpromo, music_offtopic, preview, poi_highlight, filler
    return SponsorSegment(
      category: json['category'] ?? 'unknown',
      uuid: json['UUID'] ?? '',
      startTime: (json['segment'][0] as num).toDouble(),
      endTime: (json['segment'][1] as num).toDouble(),
    );
  }
}

class SponsorBlockConfig {
  bool autoSkip;

  SponsorBlockConfig({this.autoSkip = true});

  factory SponsorBlockConfig.fromJson(Map<String, dynamic> json) {
    return SponsorBlockConfig(autoSkip: json['autoSkip'] ?? true);
  }

  Map<String, dynamic> toJson() => {'autoSkip': autoSkip};
}

class _SponsorBlockSettings extends StatefulWidget {
  final SponsorBlockPlugin plugin;
  const _SponsorBlockSettings({required this.plugin});

  @override
  State<_SponsorBlockSettings> createState() => _SponsorBlockSettingsState();
}

class _SponsorBlockSettingsState extends State<_SponsorBlockSettings> {
  late bool _autoSkip;

  @override
  void initState() {
    super.initState();
    _autoSkip = widget.plugin._config.autoSkip;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text('自動跳過', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              '關閉後將顯示手動跳過按鈕',
              style: TextStyle(color: Colors.white70),
            ),
            value: _autoSkip,
            onChanged: (val) {
              setState(() => _autoSkip = val);
              final newConfig = widget.plugin._config..autoSkip = val;
              widget.plugin.saveConfig(newConfig);
            },
          ),
        ],
      ),
    );
  }
}
