import 'package:flutter/foundation.dart';
import 'plugin.dart';
import 'plugin_store.dart';

class PluginManager {
  // 單例模式
  static final PluginManager _instance = PluginManager._internal();
  factory PluginManager() => _instance;
  PluginManager._internal();

  // 所有註冊的外掛
  final List<Plugin> _plugins = [];
  List<Plugin> get plugins => List.unmodifiable(_plugins);

  // 狀態通知
  final ValueNotifier<List<Plugin>> enabledPluginsNotifier = ValueNotifier([]);

  // 初始化 (預留)
  Future<void> init() async {
    // 可以在這裡載入初始狀態
    await _refreshEnabledPlugins();
  }

  // 註冊外掛
  void register(Plugin plugin) {
    if (_plugins.any((p) => p.id == plugin.id)) {
      debugPrint('Warning: Plugin ${plugin.id} already registered.');
      return;
    }
    _plugins.add(plugin);
    debugPrint(
      'PluginManager: Registered ${plugin.name} (${plugin.id}). Total: ${_plugins.length}',
    );
    // 檢查並自動啟用（如果記錄是啟用的）
    _checkAndEnable(plugin);
  }

  // 檢查並啟用外掛
  Future<void> _checkAndEnable(Plugin plugin) async {
    bool enabled = await PluginStore.isEnabled(plugin.id);
    if (enabled) {
      try {
        await plugin.onEnable();
        _refreshEnabledPlugins();
        debugPrint('Plugin enabled: ${plugin.name}');
      } catch (e) {
        debugPrint('Error enabling plugin ${plugin.name}: $e');
      }
    }
  }

  // 設定外掛啟用/停用
  Future<void> setEnabled(Plugin plugin, bool enabled) async {
    await PluginStore.setEnabled(plugin.id, enabled);

    if (enabled) {
      try {
        await plugin.onEnable();
      } catch (e) {
        debugPrint('Error enabling plugin ${plugin.name}: $e');
        // 如果啟用失敗，回滾狀態? 暫時不回滾，允許重試
      }
    } else {
      try {
        await plugin.onDisable();
      } catch (e) {
        debugPrint('Error disabling plugin ${plugin.name}: $e');
      }
    }
    await _refreshEnabledPlugins();
  }

  // 重新整理已啟用外掛列表通知
  Future<void> _refreshEnabledPlugins() async {
    List<Plugin> enabledList = [];
    for (var plugin in _plugins) {
      if (await PluginStore.isEnabled(plugin.id)) {
        enabledList.add(plugin);
      }
    }
    enabledPluginsNotifier.value = enabledList;
  }

  // 獲取特定型別的已啟用外掛
  List<T> getEnabledPlugins<T extends Plugin>() {
    return enabledPluginsNotifier.value.whereType<T>().toList();
  }

  // 根據 ID 獲取特定外掛
  T? getPlugin<T extends Plugin>(String id) {
    try {
      return _plugins.whereType<T>().firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }
}
