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

  /// 請求第一個分類標籤的焦點（用於從側邊欄導航）
  void focusFirstCategory() {
    if (AuthService.isLoggedIn) {
      _settingsKey.currentState?.focusFirstCategory();
    }
  }

  void _handleLoginSuccess() {
    setState(() {}); // Refresh to show SettingsView
    widget.onLoginSuccess?.call();
  }

  Future<void> _handleLogout() async {
    await AuthService.logout();
    if (mounted) {
      setState(() {}); // Refresh to show LoginView
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AuthService.isLoggedIn) {
      return SettingsView(
        key: _settingsKey,
        sidebarFocusNode: widget.sidebarFocusNode,
        onLogout: _handleLogout,
      );
    }

    return LoginView(
      sidebarFocusNode: widget.sidebarFocusNode,
      onLoginSuccess: _handleLoginSuccess,
    );
  }
}
