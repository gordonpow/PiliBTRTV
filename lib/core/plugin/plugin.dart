import 'package:bili_tv_app/widgets/zh_widgets.dart';

/// BiliTV 外掛基礎抽象類
/// 所有外掛必須繼承此類
abstract class Plugin {
  /// 唯一識別符號，建議使用反向域名風格，如 "com.example.plugin"
  String get id;

  /// 顯示名稱
  String get name;

  /// 外掛描述
  String get description;

  /// 版本號
  String get version;

  /// 作者
  String get author;

  /// 外掛圖示 (可選)
  IconData? get icon => null;

  /// 外掛啟用時呼叫
  Future<void> onEnable() async {}

  /// 外掛停用時呼叫
  Future<void> onDisable() async {}

  /// 外掛是否有設定介面
  bool get hasSettings => false;

  /// 外掛設定介面 (可選)
  Widget? get settingsWidget => null;
}
