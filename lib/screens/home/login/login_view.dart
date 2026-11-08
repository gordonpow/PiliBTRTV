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
  String _errorText = '';
  int _expiredCount = 0;
  static const int _maxAutoRegenerate = 5;

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

    if (result != null && (result['auth_code'] ?? '').isNotEmpty) {
      setState(() {
        _qrUrl = result['url'];
        _authCode = result['auth_code'];
        _status = 'waiting';
      });
      _startPolling();
    } else {
      setState(() {
        _errorText = '載入失敗，請重試';
        _status = 'error';
      });
    }
  }

  void _manualRegenerate() {
    _expiredCount = 0;
    _generateQrCode();
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
            mid: (result['mid'] as int?) ?? 0,
            cookieInfo: result['cookie_info'],
          );
          // 獲取使用者資訊
          await BilibiliApi.fetchAndSaveUserInfo();
          if (!mounted) return;
          setState(() => _status = 'success');
          widget.onLoginSuccess?.call();
          break;
        case 'scanned':
          _expiredCount = 0;
          setState(() => _status = 'scanned');
          break;
        case 'expired':
          timer.cancel();
          if (_expiredCount < _maxAutoRegenerate) {
            _expiredCount++;
            _generateQrCode();
          } else {
            setState(() => _status = 'expired');
          }
          break;
        case 'error':
          timer.cancel();
          final code = result['code'];
          final message = result['message'] ?? '';
          setState(() {
            _errorText = '錯誤：$message（$code）';
            _status = 'error';
          });
          break;
        case 'network':
          setState(() => _status = 'network');
          break;
        case 'waiting':
        default:
          if (_status == 'network') setState(() => _status = 'waiting');
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
        text = '等待掃描';
        color = Colors.white54;
        break;
      case 'network':
        text = '網路錯誤，重試中…';
        color = Colors.orange;
        break;
      case 'scanned':
        text = '已掃描，請在手機上確認';
        color = const Color(0xFF4CAF50);
        break;
      case 'success':
        text = '登入成功！';
        color = const Color(0xFF4CAF50);
        break;
      case 'expired':
        text = 'QR Code 已過期，按確認鍵重新產生';
        color = Colors.orange;
        break;
      case 'error':
      default:
        text = _errorText.isEmpty ? '載入失敗，請重試' : _errorText;
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
          const SizedBox(height: 16),
          const Text(
            '請用 B站手機 App 掃描（建議更新至最新版）',
            style: TextStyle(color: Colors.white70, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            '若手機顯示驗證頁，請按「是我的帳號，驗證登入」完成驗證',
            style: TextStyle(color: Colors.white70, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _buildStatusText(),
          const SizedBox(height: 20),
          if (_status == 'expired' || _status == 'error')
            Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.select)) {
                  _manualRegenerate();
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
                    onTap: _manualRegenerate,
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
                        '重新產生 QR Code',
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
