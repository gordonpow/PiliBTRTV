import 'package:shared_preferences/shared_preferences.dart';

/// 搜尋歷史記錄服務
class SearchHistoryService {
  static const String _key = 'search_history';
  static const int _maxHistory = 10;

  static SharedPreferences? _prefs;

  /// 初始化
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 新增搜尋記錄
  static Future<void> add(String query) async {
    if (query.trim().isEmpty) return;
    await init();

    final history = getAll();
    // 如果已存在，先移除舊的
    history.remove(query);
    // 新增到最前面
    history.insert(0, query);
    // 保持最多 10 條
    if (history.length > _maxHistory) {
      history.removeRange(_maxHistory, history.length);
    }

    await _prefs!.setStringList(_key, history);
  }

  /// 獲取所有搜尋記錄
  static List<String> getAll() {
    if (_prefs == null) return [];
    return List<String>.from(_prefs!.getStringList(_key) ?? []);
  }

  /// 清除所有搜尋記錄
  static Future<void> clear() async {
    await init();
    await _prefs!.remove(_key);
  }

  /// 是否有搜尋記錄
  static bool get hasHistory => getAll().isNotEmpty;
}
