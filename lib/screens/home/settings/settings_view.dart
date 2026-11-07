import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import '../../../services/auth_service.dart';
import '../../../services/update_service.dart';
import 'tabs/playback_settings.dart';
import 'tabs/btr_settings.dart';
import 'tabs/interface_settings.dart';
import 'tabs/plugins_settings.dart';
import 'tabs/storage_settings.dart';
import 'tabs/about_settings.dart';
import '../../../widgets/time_display.dart';
import '../../../widgets/vip_avatar_badge.dart';

/// 設定分類列舉
enum SettingsCategory {
  playback('播放設定'),
  btr('執行緒撕裂者'),
  interface_('介面設定'),
  plugins('外掛中心'),
  storage('其他設定'),
  about('關於軟體');

  const SettingsCategory(this.label);
  final String label;
}

class SettingsView extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback onLogout;
  final VoidCallback? onLogin;

  const SettingsView({
    super.key,
    this.sidebarFocusNode,
    required this.onLogout,
    this.onLogin,
  });

  @override
  State<SettingsView> createState() => SettingsViewState();
}

class SettingsViewState extends State<SettingsView> {
  int _selectedCategoryIndex = 0;
  late List<FocusNode> _categoryFocusNodes;
  late FocusNode _logoutFocusNode;

  @override
  void initState() {
    super.initState();
    _logoutFocusNode = FocusNode();
    _categoryFocusNodes = List.generate(
      SettingsCategory.values.length,
      (_) => FocusNode(),
    );
  }

  @override
  void dispose() {
    _logoutFocusNode.dispose();
    for (var node in _categoryFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// 請求第一個分類標籤的焦點（用於從側邊欄導航）
  void focusFirstCategory() {
    if (_categoryFocusNodes.isNotEmpty) {
      _categoryFocusNodes[0].requestFocus();
    }
  }

  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('確認', style: TextStyle(color: Color(0xFFfb7299))),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handleLogout() async {
    final confirmed = await _showConfirmDialog('確認退出', '確定要退出登入嗎？');
    if (confirmed) {
      widget.onLogout();
    }
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 50,
      height: 50,
      color: Colors.grey[700],
      child: const Icon(Icons.person, size: 30, color: Colors.white54),
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
    FocusNode? focusNode,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.select) {
          onTap();
          return KeyEventResult.handled;
        }
        // 阻止向上導航超出設定頁面 (如跳到搜尋框)
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: isFocused ? color : color.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
              border: isFocused
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isFocused ? Colors.white : color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 構建分類標籤
  Widget _buildCategoryTab({
    required String label,
    required bool isSelected,
    required FocusNode focusNode,
    required VoidCallback onTap,
    VoidCallback? onMoveLeft,
    bool showDot = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Focus(
        focusNode: focusNode,
        onFocusChange: (f) => f ? onTap() : null,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
              onMoveLeft != null) {
            onMoveLeft();
            return KeyEventResult.handled;
          }
          // 向上導航跳轉到退出按鈕
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _logoutFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (ctx) {
            final isFocused = Focus.of(ctx).hasFocus;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isFocused ? const Color(0xFFfb7299) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isFocused ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: isFocused
                              ? Colors.white
                              : (isSelected
                                    ? const Color(0xFFfb7299)
                                    : Colors.grey),
                          fontSize: 15,
                          fontWeight: isFocused || isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      if (showDot)
                        ValueListenableBuilder<UpdateInfo?>(
                          valueListenable: UpdateService.available,
                          builder: (_, info, _) => info == null
                              ? const SizedBox.shrink()
                              : Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 3,
                    width: 24,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFfb7299)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    void moveToCurrentTab() {
      if (_categoryFocusNodes.isNotEmpty) {
        _categoryFocusNodes[_selectedCategoryIndex].requestFocus();
      }
    }

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 頂部使用者資訊欄
            Container(
              padding: const EdgeInsets.fromLTRB(40, 30, 40, 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 頭像
                  if (AuthService.isLoggedIn &&
                      AuthService.face != null &&
                      AuthService.face!.isNotEmpty)
                    VipAvatarBadge(
                      size: 45,
                      child: ClipOval(
                        child: Image.network(
                          AuthService.face!,
                          width: 45,
                          height: 45,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _buildDefaultAvatar(),
                        ),
                      ),
                    )
                  else
                    _buildDefaultAvatar(),
                  const SizedBox(width: 15),
                  // 使用者名稱和 UID
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AuthService.isLoggedIn
                            ? (AuthService.uname ?? '已登入')
                            : '未登入',
                        style: TextStyle(
                          color: AuthService.isLoggedIn && AuthService.isVip
                              ? const Color(0xFFfb7299) // VIP 粉色
                              : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (AuthService.isLoggedIn)
                        Text(
                          'UID: ${AuthService.mid ?? ""}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 30),
                  // 登入 / 退出登入按鈕
                  _buildActionButton(
                    label: AuthService.isLoggedIn ? '退出登入' : '登入',
                    color: AuthService.isLoggedIn
                        ? Colors.red
                        : const Color(0xFFfb7299),
                    onTap: AuthService.isLoggedIn
                        ? _handleLogout
                        : () => widget.onLogin?.call(),
                    focusNode: _logoutFocusNode,
                  ),
                ],
              ),
            ),

            // 設定分類標籤欄
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                children: List.generate(SettingsCategory.values.length, (
                  index,
                ) {
                  final category = SettingsCategory.values[index];
                  final isSelected = _selectedCategoryIndex == index;
                  return _buildCategoryTab(
                    label: category.label,
                    isSelected: isSelected,
                    showDot: category == SettingsCategory.about,
                    focusNode: _categoryFocusNodes[index],
                    onTap: () => setState(() => _selectedCategoryIndex = index),
                    onMoveLeft: index == 0
                        ? () => widget.sidebarFocusNode?.requestFocus()
                        : null,
                  );
                }),
              ),
            ),

            const SizedBox(height: 20),

            // 設定內容區域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: _buildContent(moveToCurrentTab),
              ),
            ),
          ],
        ),

        // 常駐時間顯示 (與主介面位置保持一致)
        const Positioned(top: 20, right: 30, child: TimeDisplay()),
      ],
    );
  }

  Widget _buildContent(VoidCallback moveToCurrentTab) {
    switch (SettingsCategory.values[_selectedCategoryIndex]) {
      case SettingsCategory.playback:
        return PlaybackSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.btr:
        return BtrSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.interface_:
        return InterfaceSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.plugins:
        return PluginsSettingsTab(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.storage:
        return StorageSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
      case SettingsCategory.about:
        return AboutSettings(
          onMoveUp: moveToCurrentTab,
          sidebarFocusNode: widget.sidebarFocusNode,
        );
    }
  }
}
