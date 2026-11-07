import 'package:bili_tv_app/utils/zh_convert.dart';
import 'dart:convert';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/plugin/plugin_types.dart';
import '../services/local_server.dart';

/// 彈幕遮蔽外掛
///
/// 功能：遮蔽包含指定關鍵詞的彈幕
class DanmakuEnhancePlugin extends DanmakuPlugin {
  @override
  String get id => 'danmaku_enhance';

  @override
  String get name => '彈幕遮蔽';

  @override
  String get description => '遮蔽包含指定關鍵詞的彈幕';

  @override
  String get version => '2.1.0';

  @override
  String get author => 'YangY (Ported)';

  @override
  IconData? get icon => Icons.block_outlined;

  DanmakuBlockConfig _config = DanmakuBlockConfig();

  @override
  bool get hasSettings => true;

  @override
  Widget? get settingsWidget => _DanmakuBlockSettings(plugin: this);

  @override
  Future<void> onEnable() async {
    await _loadConfig();
    debugPrint('✅ 彈幕遮蔽已啟用');
    debugPrint('📋 遮蔽詞: ${_config.blockKeywords}');
  }

  @override
  Future<void> onDisable() async {
    debugPrint('🔴 彈幕遮蔽已停用');
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('plugin_config_$id');
    if (jsonStr != null) {
      try {
        _config = DanmakuBlockConfig.fromJson(jsonDecode(jsonStr));
      } catch (e) {
        debugPrint('Error loading config: $e');
      }
    }
  }

  Future<void> saveConfig(DanmakuBlockConfig config) async {
    _config = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plugin_config_$id', jsonEncode(config.toJson()));
  }

  // 新增遮蔽詞
  void addBlockKeyword(String keyword) {
    if (keyword.isNotEmpty && !_config.blockKeywords.contains(keyword)) {
      _config.blockKeywords.add(keyword);
      saveConfig(_config);
    }
  }

  // 移除遮蔽詞
  void removeBlockKeyword(String keyword) {
    if (_config.blockKeywords.contains(keyword)) {
      _config.blockKeywords.remove(keyword);
      saveConfig(_config);
    }
  }

  // 獲取遮蔽詞列表 (API 使用)
  List<String> getBlockKeywords() => List.unmodifiable(_config.blockKeywords);

  // 獲取配置 (API 使用)
  DanmakuBlockConfig getConfig() => _config;

  // 設定開關
  void setEnableFilter(bool value) {
    _config.enableFilter = value;
    saveConfig(_config);
  }

  // 新增全詞遮蔽詞
  void addFullKeyword(String keyword) {
    if (keyword.isNotEmpty && !_config.fullKeywords.contains(keyword)) {
      _config.fullKeywords.add(keyword);
      saveConfig(_config);
    }
  }

  // 移除全詞遮蔽詞
  void removeFullKeyword(String keyword) {
    if (_config.fullKeywords.contains(keyword)) {
      _config.fullKeywords.remove(keyword);
      saveConfig(_config);
    }
  }

  // 獲取全詞遮蔽詞列表
  List<String> getFullKeywords() => List.unmodifiable(_config.fullKeywords);

  @override
  dynamic filterDanmaku(dynamic item) {
    if (item is! Map) return item;
    if (!_config.enableFilter) return item;

    final content = item['content'] as String? ?? '';

    // 1. 部分匹配檢測 (contains)
    for (var keyword in _config.blockKeywords) {
      if (keyword.isNotEmpty && content.contains(keyword)) {
        return null; // 遮蔽
      }
    }

    // 2. 全詞匹配檢測 (equals)
    for (var keyword in _config.fullKeywords) {
      if (keyword.isNotEmpty && content == keyword) {
        return null; // 遮蔽
      }
    }

    return item;
  }

  @override
  DanmakuStyle? styleDanmaku(dynamic item) {
    return null;
  }
}

/// 彈幕遮蔽配置
class DanmakuBlockConfig {
  bool enableFilter; // 啟用遮蔽
  List<String> blockKeywords; // 部分匹配關鍵詞
  List<String> fullKeywords; // 全詞匹配關鍵詞

  DanmakuBlockConfig({
    this.enableFilter = true,
    List<String>? blockKeywords,
    List<String>? fullKeywords,
  // 與伺服器回傳的簡體文字比對，保留原文
  }) : blockKeywords = blockKeywords ?? ['剧透', '前方高能'],
       fullKeywords = fullKeywords ?? [];

  factory DanmakuBlockConfig.fromJson(Map<String, dynamic> json) {
    return DanmakuBlockConfig(
      enableFilter: json['enableFilter'] ?? true,
      // 與伺服器回傳的簡體文字比對，保留原文
      blockKeywords: List<String>.from(json['blockKeywords'] ?? ['剧透', '前方高能']),
      fullKeywords: List<String>.from(json['fullKeywords'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
    'enableFilter': enableFilter,
    'blockKeywords': blockKeywords,
    'fullKeywords': fullKeywords,
  };
}

class _DanmakuBlockSettings extends StatefulWidget {
  final DanmakuEnhancePlugin plugin;
  const _DanmakuBlockSettings({required this.plugin});

  @override
  State<_DanmakuBlockSettings> createState() => _DanmakuBlockSettingsState();
}

class _DanmakuBlockSettingsState extends State<_DanmakuBlockSettings> {
  final TextEditingController _partialInputController = TextEditingController();
  final TextEditingController _fullInputController = TextEditingController();

  @override
  void dispose() {
    _partialInputController.dispose();
    _fullInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.plugin._config;
    final serverAddress = LocalServer.instance.address ?? 'http://TV_IP:3322';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 提示資訊
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.phone_android, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '推薦使用手機訪問 $serverAddress 進行管理',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 開關
          SwitchListTile(
            title: const Text('啟用彈幕遮蔽', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              '遮蔽包含指定關鍵詞的彈幕',
              style: TextStyle(color: Colors.white70),
            ),
            value: config.enableFilter,
            onChanged: (val) {
              setState(() => widget.plugin.setEnableFilter(val));
            },
          ),

          const Divider(color: Colors.white24),
          const SizedBox(height: 16),

          // 部分匹配關鍵詞
          _buildKeywordSection(
            title: '部分匹配關鍵詞',
            subtitle: '包含即遮蔽（如 "第一" 會遮蔽 "我是第一名"）',
            controller: _partialInputController,
            keywords: config.blockKeywords,
            onAdd: (k) => widget.plugin.addBlockKeyword(k),
            onRemove: (k) => widget.plugin.removeBlockKeyword(k),
          ),

          const SizedBox(height: 24),

          // 全詞匹配關鍵詞
          _buildKeywordSection(
            title: '全詞匹配關鍵詞',
            subtitle: '完全一致才遮蔽（如 "第一" 只遮蔽 "第一"）',
            controller: _fullInputController,
            keywords: config.fullKeywords,
            onAdd: (k) => widget.plugin.addFullKeyword(k),
            onRemove: (k) => widget.plugin.removeFullKeyword(k),
          ),
        ],
      ),
    );
  }

  Widget _buildKeywordSection({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required List<String> keywords,
    required Function(String) onAdd,
    required Function(String) onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: ZhConvert.convert('輸入關鍵詞'),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white12,
                  isDense: true,
                ),
                style: const TextStyle(color: Colors.white),
                onSubmitted: (_) {
                  final val = controller.text.trim();
                  if (val.isNotEmpty) {
                    setState(() {
                      onAdd(val);
                      controller.clear();
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                final val = controller.text.trim();
                if (val.isNotEmpty) {
                  setState(() {
                    onAdd(val);
                    controller.clear();
                  });
                }
              },
              icon: const Icon(Icons.add, color: Colors.blue),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 關鍵詞列表
        keywords.isEmpty
            ? const Text(
                '暫無遮蔽詞',
                style: TextStyle(
                  color: Colors.white38,
                  fontStyle: FontStyle.italic,
                ),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: keywords
                    .map(
                      (k) => Chip(
                        label: Text(k),
                        backgroundColor: Colors.red.withValues(alpha: 0.2),
                        onDeleted: () {
                          setState(() {
                            onRemove(k);
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
      ],
    );
  }
}
