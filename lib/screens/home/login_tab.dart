import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../services/auth_service.dart';
import 'login/login_view.dart';
import 'settings/settings_view.dart';

/// 登入 Tab / 使用者設定 Tab
class LoginTab extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onLoginSuccess;

  const LoginTab({super.key, this.sidebarFocusNode, this.onLoginSuccess});

  @override
  State<LoginTab> createState() => LoginTabState();
}

class LoginTabState extends State<LoginTab> {
  final GlobalKey<SettingsViewState> _settingsKey =
      GlobalKey<SettingsViewState>();

  /// 是否顯示登入畫面（未登入時由設定頁的「登入」按鈕觸發）
  bool _showLogin = false;

  /// 請求第一個分類標籤的焦點（用於從側邊欄導航）
  void focusFirstCategory() {
    if (!_showLogin) {
      _settingsKey.currentState?.focusFirstCategory();
    }
  }

  /// 返回鍵處理：登入畫面回到設定頁。回傳 true 表示已處理。
  bool handleBack() {
    if (_showLogin) {
      setState(() => _showLogin = false);
      widget.sidebarFocusNode?.requestFocus();
      return true;
    }
    return false;
  }

  void _handleLoginSuccess() {
    setState(() => _showLogin = false); // 回到設定頁
    widget.onLoginSuccess?.call();
  }

  Future<void> _handleLogout() async {
    await AuthService.logout();
    if (mounted) {
      setState(() => _showLogin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showLogin && !AuthService.isLoggedIn) {
      return LoginView(
        sidebarFocusNode: widget.sidebarFocusNode,
        onLoginSuccess: _handleLoginSuccess,
      );
    }

    return SettingsView(
      key: _settingsKey,
      sidebarFocusNode: widget.sidebarFocusNode,
      onLogout: _handleLogout,
      onLogin: () => setState(() => _showLogin = true),
    );
  }
}
