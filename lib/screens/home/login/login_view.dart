import 'dart:async';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../services/bilibili_api.dart';
import '../../../services/auth_service.dart';

class LoginView extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onLoginSuccess;

  const LoginView({super.key, this.sidebarFocusNode, this.onLoginSuccess});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  String? _qrUrl;
  String? _authCode;
  String _status = 'loading';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _generateQrCode();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _generateQrCode() async {
    setState(() => _status = 'loading');
    final result = await BilibiliApi.generateTvQrCode();
    if (!mounted) return;

    if (result != null) {
      setState(() {
        _qrUrl = result['url'];
        _authCode = result['auth_code'];
        _status = 'waiting';
      });
      _startPolling();
    } else {
      setState(() => _status = 'error');
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_authCode == null) {
        timer.cancel();
        return;
      }
      final result = await BilibiliApi.pollTvLogin(_authCode!);
      final status = result['status'] as String?;

      if (!mounted) {
        timer.cancel();
        return;
      }

      switch (status) {
        case 'success':
          timer.cancel();
          // 儲存登入憑證
          await AuthService.saveLoginCredentials(
            accessToken: result['access_token'] ?? '',
            refreshToken: result['refresh_token'] ?? '',
            mid: result['mid'] ?? 0,
            cookieInfo: result['cookie_info'],
          );
          // 獲取使用者資訊
          await BilibiliApi.fetchAndSaveUserInfo();
          if (!mounted) return;
          setState(() => _status = 'success');
          widget.onLoginSuccess?.call();
          break;
        case 'scanned':
          setState(() => _status = 'scanned');
          break;
        case 'expired':
          timer.cancel();
          setState(() => _status = 'expired');
          break;
        case 'waiting':
        default:
          break;
      }
    });
  }

  Widget _buildQrContent() {
    if (_status == 'loading') {
      return Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_status == 'error' || _qrUrl == null) {
      return Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(Icons.error_outline, size: 60, color: Colors.red),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: QrImageView(
        data: _qrUrl!,
        size: 180,
        backgroundColor: Colors.white,
      ),
    );
  }

  Widget _buildStatusText() {
    String text;
    Color color;

    switch (_status) {
      case 'loading':
        text = '正在載入...';
        color = Colors.white54;
        break;
      case 'waiting':
        text = '請使用 Bilibili 手機客戶端掃描二維碼';
        color = Colors.white54;
        break;
      case 'scanned':
        text = '已掃描，請在手機上確認登入';
        color = const Color(0xFF4CAF50);
        break;
      case 'success':
        text = '登入成功！';
        color = const Color(0xFF4CAF50);
        break;
      case 'expired':
        text = '二維碼已過期，請重新整理';
        color = Colors.orange;
        break;
      case 'error':
      default:
        text = '載入失敗，請重試';
        color = Colors.red;
        break;
    }

    return Text(
      text,
      style: TextStyle(color: color, fontSize: 16),
      textAlign: TextAlign.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'TV 掃碼登入',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 30),
          _buildQrContent(),
          const SizedBox(height: 20),
          _buildStatusText(),
          const SizedBox(height: 30),
          if (_status == 'expired' || _status == 'error')
            Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.select)) {
                  _generateQrCode();
                  return KeyEventResult.handled;
                }
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  widget.sidebarFocusNode?.requestFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final isFocused = Focus.of(context).hasFocus;
                  return GestureDetector(
                    onTap: _generateQrCode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isFocused
                            ? const Color(0xFFfb7299)
                            : const Color(0xFFfb7299).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: isFocused
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                      child: const Text(
                        '重新整理二維碼',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
