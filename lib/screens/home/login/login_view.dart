import 'dart:async';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../services/bilibili_api.dart';
import '../../../services/auth_service.dart';
import '../../../services/local_server.dart';
import '../../../services/phone_login_service.dart';
import '../../../widgets/error_report_dialog.dart';

class LoginView extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onLoginSuccess;

  const LoginView({super.key, this.sidebarFocusNode, this.onLoginSuccess});

  @override
  State<LoginView> createState() => LoginViewState();
}

class LoginViewState extends State<LoginView> {
  /// 預設按鈕（回報問題或重新產生 QR Code）的焦點，供側邊欄按右鍵時進入
  final FocusNode _defaultButtonFocus = FocusNode(debugLabel: 'loginDefault');

  /// 從側邊欄導航進來時，把焦點移到預設按鈕
  void focusDefault() => _defaultButtonFocus.requestFocus();

  String? _qrUrl;
  String? _authCode;
  String _status = 'loading';
  Timer? _pollTimer;
  String _errorText = '';
  int _expiredCount = 0;
  static const int _maxAutoRegenerate = 5;

  // 手機登入
  final PhoneLoginService _phone = PhoneLoginService.instance;
  bool _phoneReady = false;
  bool _loginHandled = false;

  @override
  void initState() {
    super.initState();
    // 從設定頁按「登入」進來時，焦點還在設定頁的按鈕上（已被移除），移到預設按鈕
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusDefault();
    });
    _phone.loggedIn.addListener(_onPhoneLoggedIn);
    _generateQrCode();
    _startPhoneLogin();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _phone.loggedIn.removeListener(_onPhoneLoggedIn);
    _phone.stop();
    _defaultButtonFocus.dispose();
    super.dispose();
  }

  /// 重新抓區網位址並產生手機登入網址
  Future<void> _startPhoneLogin() async {
    await LocalServer.instance.start();
    await LocalServer.instance.refreshAddress();
    if (!mounted) return;
    final ready =
        LocalServer.instance.isRunning && LocalServer.instance.address != null;
    if (ready) {
      _phone.start();
    } else {
      _phone.stop();
    }
    setState(() => _phoneReady = ready && _phone.url.value != null);
  }

  /// 手機登入成功：憑證已由 PhoneLoginService 存好，沿用 QR 登入的收尾流程
  void _onPhoneLoggedIn() {
    if (!_phone.loggedIn.value) return;
    _pollTimer?.cancel();
    _completeLogin();
  }

  /// QR 與手機登入共用的成功收尾（唯一取得使用者資訊的地方）
  Future<void> _completeLogin() async {
    if (_loginHandled) return;
    _loginHandled = true;
    await BilibiliApi.fetchAndSaveUserInfo();
    if (!mounted) return;
    setState(() => _status = 'success');
    widget.onLoginSuccess?.call();
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

      if (!mounted || _loginHandled) {
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
          // 獲取使用者資訊並通知成功
          await _completeLogin();
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

  Widget _buildButton(
    String label,
    VoidCallback onPressed, {
    bool autofocus = false,
  }) {
    return Focus(
      autofocus: autofocus,
      // autofocus 的按鈕同時是預設按鈕
      focusNode: autofocus ? _defaultButtonFocus : null,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          onPressed();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            !node.focusInDirection(TraversalDirection.left)) {
          widget.sidebarFocusNode?.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
              decoration: BoxDecoration(
                color: isFocused
                    ? const Color(0xFFfb7299)
                    : const Color(0xFFfb7299).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: isFocused
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPhoneSection() {
    return SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '用手機登入',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '手機需與電視連接同一個 Wi-Fi（同一個區網），用行動網路無法連線',
            style: TextStyle(
              color: Color(0xFFFFB74D),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<String?>(
            valueListenable: _phone.url,
            builder: (context, url, _) {
              if (!_phoneReady || url == null) {
                return Container(
                  width: 200,
                  height: 200,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      '請把電視連上 Wi-Fi 或有線網路',
                      style: TextStyle(color: Colors.orange, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: url,
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    url,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          const Text(
            '用手機相機掃描，可用密碼、簡訊或 Cookie 登入',
            style: TextStyle(color: Colors.white70, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<String>(
            valueListenable: _phone.status,
            builder: (context, text, _) {
              final shown = _phoneReady ? text : '請把電視連上 Wi-Fi 或有線網路';
              final ok = shown == '登入成功';
              return Text(
                shown,
                style: TextStyle(
                  color: ok
                      ? const Color(0xFF4CAF50)
                      : (_phoneReady ? Colors.white54 : Colors.orange),
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTvSection() {
    return SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'TV 掃碼登入',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '用 B 站 App 掃描，不需同一個網路',
            style: TextStyle(color: Color(0xFF81C784), fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          _buildQrContent(),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          _buildStatusText(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qrFailed = _status == 'expired' || _status == 'error';
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTvSection(),
                const SizedBox(width: 40),
                _buildPhoneSection(),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (qrFailed) ...[
                  _buildButton(
                    '重新產生 QR Code',
                    _manualRegenerate,
                    autofocus: true,
                  ),
                  const SizedBox(width: 16),
                ],
                _buildButton('重新整理手機登入', _startPhoneLogin),
                const SizedBox(width: 16),
                _buildButton(
                  '回報問題',
                  () => showErrorReportDialog(context),
                  autofocus: !qrFailed,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
