import 'dart:async';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../services/api/auth_api.dart';
import '../../../services/bilibili_api.dart';
import '../../../services/auth_service.dart';
import '../../../services/local_server.dart';
import '../../../services/phone_login_service.dart';
import '../../../widgets/error_report_dialog.dart';

/// 左側 QR 登入模式：TV 掃碼或網頁版掃碼
enum _LoginQrMode { tv, web }

class LoginView extends StatefulWidget {
  final FocusNode? sidebarFocusNode;
  final VoidCallback? onLoginSuccess;

  const LoginView({super.key, this.sidebarFocusNode, this.onLoginSuccess});

  @override
  State<LoginView> createState() => LoginViewState();
}

class LoginViewState extends State<LoginView> {
  /// 底部按鈕列各按鈕的焦點
  final FocusNode _regenFocus = FocusNode(debugLabel: 'loginRegen');
  final FocusNode _switchFocus = FocusNode(debugLabel: 'loginSwitch');
  final FocusNode _refreshFocus = FocusNode(debugLabel: 'loginRefresh');
  final FocusNode _reportFocus = FocusNode(debugLabel: 'loginReport');

  /// 預設按鈕：QR 失敗（非 48007）→ 重新產生；48007 與其餘 → 切換（最左邊）
  FocusNode _defaultFocusNode(bool qrFailed) {
    if (_is48007) return _switchFocus;
    if (qrFailed) return _regenFocus;
    // 一般狀態：從側邊欄按右鍵進來時落在按鈕列最左邊的按鈕
    return _switchFocus;
  }

  /// 從側邊欄導航進來時，把焦點移到預設按鈕
  void focusDefault() {
    final qrFailed = _status == 'expired' || _status == 'error';
    _defaultFocusNode(qrFailed).requestFocus();
  }

  _LoginQrMode _mode = _LoginQrMode.tv;

  /// 網頁版掃碼的 qrcode_key（TV 模式用 _authCode）
  String? _webQrKey;

  /// TV 掃碼輪詢回 48007（帳號不支援 TV 掃碼）
  bool _is48007 = false;

  /// QR 產生世代：切換模式、重產、登入成功時遞增，丟棄過期的非同步回應
  int _qrGen = 0;

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

  /// 輪詢請求是否進行中（避免重疊請求）
  bool _polling = false;

  /// 輪詢序號與起始時間：舊輪詢晚到的結果仍會處理（成功回應只能用一次，不能丟），
  /// 但只有序號相符的輪詢才能清除進行中旗標
  int _pollSeq = 0;
  DateTime _pollStartedAt = DateTime.now();
  static const Duration _pollWatchdog = Duration(seconds: 20);

  /// 「已掃描」超過 60 秒後顯示額外提示
  Timer? _scannedHintTimer;
  bool _showScannedHint = false;

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
    _scannedHintTimer?.cancel();
    _phone.loggedIn.removeListener(_onPhoneLoggedIn);
    _phone.stop();
    _regenFocus.dispose();
    _switchFocus.dispose();
    _refreshFocus.dispose();
    _reportFocus.dispose();
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
    try {
      // 取不到使用者資訊不應阻擋登入完成
      await BilibiliApi.fetchAndSaveUserInfo().timeout(
        const Duration(seconds: 8),
      );
    } catch (e) {
      debugPrint('Login: 取得使用者資訊失敗 ${e.runtimeType}');
    }
    if (!mounted) return;
    setState(() => _status = 'success');
    widget.onLoginSuccess?.call();
  }

  bool get _isWeb => _mode == _LoginQrMode.web;

  Future<void> _generateQrCode() async {
    final gen = ++_qrGen;
    final web = _isWeb;
    _pollTimer?.cancel();
    _polling = false;
    _pollSeq++;
    _resetScannedHint();
    setState(() {
      _status = 'loading';
      _is48007 = false;
    });
    final result = web
        ? await BilibiliApi.generateWebQrCode()
        : await BilibiliApi.generateTvQrCode();
    if (gen != _qrGen || !mounted || _loginHandled) return;

    final key = result == null
        ? null
        : (web ? result['qrcode_key'] : result['auth_code']);
    if (result != null && (key ?? '').isNotEmpty) {
      setState(() {
        _qrUrl = result['url'];
        if (web) {
          _webQrKey = key;
        } else {
          _authCode = key;
        }
        _status = 'waiting';
      });
      if (web) debugPrint('WebLogin: QR Code 產生成功');
      _startPolling(gen);
    } else {
      debugPrint(
        web ? 'WebLogin: QR Code 產生失敗' : 'TvLogin: QR Code 產生失敗（詳見 AuthApi 記錄）',
      );
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

  /// 切換 TV／網頁版掃碼
  void _switchMode() {
    _pollTimer?.cancel();
    _polling = false;
    _pollSeq++;
    _resetScannedHint();
    _expiredCount = 0;
    _qrGen++;
    setState(() {
      _mode = _isWeb ? _LoginQrMode.tv : _LoginQrMode.web;
      _is48007 = false;
      _qrUrl = null;
    });
    _generateQrCode();
  }

  void _resetScannedHint() {
    _scannedHintTimer?.cancel();
    _scannedHintTimer = null;
    _showScannedHint = false;
  }

  /// 狀態改變時才更新（TV／網頁版皆寫 log，不含任何憑證）
  void _setStatus(String next) {
    if (_status != next) {
      debugPrint('${_isWeb ? 'WebLogin' : 'TvLogin'}: 狀態 $_status→$next');
      if (next == 'scanned') {
        // 暫時性網路錯誤後回到 scanned 不重新計時
        if (_scannedHintTimer == null && !_showScannedHint) {
          _scannedHintTimer = Timer(const Duration(seconds: 60), () {
            if (mounted && (_status == 'scanned' || _status == 'network')) {
              setState(() => _showScannedHint = true);
            }
          });
        }
      } else if (next != 'network' || _status != 'scanned') {
        _resetScannedHint();
      }
    }
    setState(() => _status = next);
  }

  void _startPolling(int gen) {
    _pollTimer?.cancel();
    final web = _isWeb;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      // 上一次輪詢尚未回來就略過這一輪，避免重疊請求
      if (_polling &&
          DateTime.now().difference(_pollStartedAt) < _pollWatchdog) {
        return;
      }
      final key = web ? _webQrKey : _authCode;
      if (key == null) {
        timer.cancel();
        return;
      }
      final seq = ++_pollSeq;
      _polling = true;
      _pollStartedAt = DateTime.now();
      try {
        await _pollOnce(timer, gen, web, key);
      } catch (e) {
        debugPrint('${web ? 'WebLogin' : 'TvLogin'}: 輪詢例外 ${e.runtimeType}');
      } finally {
        if (seq == _pollSeq) _polling = false;
      }
    });
  }

  Future<void> _pollOnce(Timer timer, int gen, bool web, String key) async {
    if (gen != _qrGen || !mounted || _loginHandled) {
      timer.cancel();
      return;
    }
    // 不加 timeout：成功回應只能用一次，晚到也要處理（由 watchdog 允許新輪詢）
    final result = await (web
        ? BilibiliApi.pollWebQrLogin(key)
        : BilibiliApi.pollTvLogin(key));
    final status = result['status'] as String?;

    if (gen != _qrGen || !mounted || _loginHandled) {
      // 此計時器已過期（世代已換）或頁面已結束，直接停掉
      timer.cancel();
      return;
    }

    switch (status) {
      case 'success':
        // 先停輪詢並遞增世代，避免後續 await 期間重疊回應覆蓋成功狀態
        timer.cancel();
        _qrGen++;
        try {
          if (web) {
            await _finishWebLogin(
              Map<String, String>.from(result['cookies'] as Map),
            );
          } else {
            debugPrint(
              'TvLogin: 掃碼成功，儲存憑證 mid有效=${((result['mid'] as int?) ?? 0) != 0} '
              'hasCookie=${result['cookie_info'] != null}',
            );
            await AuthService.saveLoginCredentials(
              accessToken: result['access_token'] ?? '',
              refreshToken: result['refresh_token'] ?? '',
              mid: (result['mid'] as int?) ?? 0,
              cookieInfo: result['cookie_info'],
            );
            await _completeLogin();
          }
        } catch (e) {
          debugPrint(
            '${web ? 'WebLogin' : 'TvLogin'}: 登入收尾失敗 ${e.runtimeType}',
          );
          if (!mounted || _loginHandled) return;
          _resetScannedHint();
          setState(() {
            _errorText = '登入失敗，請重新掃描';
            _status = 'error';
          });
        }
        break;
      case 'scanned':
        _expiredCount = 0;
        _setStatus('scanned');
        break;
      case 'expired':
        timer.cancel();
        if (_expiredCount < _maxAutoRegenerate) {
          _expiredCount++;
          _generateQrCode();
        } else {
          _setStatus('expired');
        }
        break;
      case 'error':
        timer.cancel();
        final code = result['code'];
        final message = result['message'] ?? '';
        debugPrint(
          '${web ? 'WebLogin' : 'TvLogin'}: 輪詢錯誤 code=$code message=$message',
        );
        final is48007 = !web && code == 48007;
        _resetScannedHint();
        setState(() {
          _errorText = is48007 ? '此帳號不支援 TV 掃碼，請改用網頁版掃碼' : '錯誤：$message（$code）';
          _status = 'error';
          _is48007 = is48007;
        });
        if (is48007) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _switchFocus.requestFocus();
          });
        }
        break;
      case 'network':
        _setStatus('network');
        break;
      case 'waiting':
      default:
        if (_status == 'network') _setStatus('waiting');
        break;
    }
  }

  /// 網頁版掃碼成功：先驗證 Cookie，再儲存並收尾
  Future<void> _finishWebLogin(Map<String, String> cookies) async {
    final ok = await AuthApi.verifyWebCookies(cookies);
    if (!mounted || _loginHandled) return;
    if (!ok) {
      debugPrint('WebLogin: Cookie 驗證失敗');
      setState(() {
        _errorText = 'Cookie 驗證失敗，請重新掃描';
        _status = 'error';
      });
      return;
    }
    try {
      await AuthService.saveCookieLogin(cookies);
    } catch (e) {
      debugPrint('WebLogin: 儲存憑證失敗 ${e.runtimeType}');
      if (!mounted) return;
      setState(() {
        _errorText = 'Cookie 驗證失敗，請重新掃描';
        _status = 'error';
      });
      return;
    }
    debugPrint(
      'WebLogin: 登入成功 mid有效=${(cookies['DedeUserID'] ?? '').isNotEmpty}',
    );
    await _completeLogin();
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

    final statusText = Text(
      text,
      style: TextStyle(color: color, fontSize: 16),
      textAlign: TextAlign.center,
    );
    if (_status == 'scanned' && _showScannedHint) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          statusText,
          const SizedBox(height: 6),
          const Text(
            '手機確認後若沒有反應，請按重新產生，或改用網頁版掃碼',
            style: TextStyle(color: Colors.orange, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return statusText;
  }

  /// 底部按鈕列：依目前可見的按鈕建立有序清單，左右鍵依清單順序移動焦點
  Widget _buildButtonRow(bool qrFailed) {
    final items = <(String, VoidCallback, FocusNode)>[
      if (qrFailed) ('重新產生 QR Code', _manualRegenerate, _regenFocus),
      (_isWeb ? '改用 TV 掃碼' : '改用網頁版掃碼', _switchMode, _switchFocus),
      ('重新整理手機登入', _startPhoneLogin, _refreshFocus),
      ('回報問題/建議', () => showErrorReportDialog(context), _reportFocus),
    ];
    // 每個狀態只有一個 autofocus 按鈕，選擇與 focusDefault 相同
    final autofocusNode = _defaultFocusNode(qrFailed);
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 16));
      final (label, onPressed, node) = items[i];
      children.add(
        _buildButton(
          label,
          onPressed,
          focusNode: node,
          autofocus: identical(node, autofocusNode) && !_is48007,
          prev: i > 0 ? items[i - 1].$3 : null,
          next: i < items.length - 1 ? items[i + 1].$3 : null,
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _buildButton(
    String label,
    VoidCallback onPressed, {
    required FocusNode focusNode,
    bool autofocus = false,
    FocusNode? prev,
    FocusNode? next,
  }) {
    return Focus(
      autofocus: autofocus,
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select) {
          if (event is KeyDownEvent) onPressed();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          // 最左邊的按鈕再按左鍵，回到側邊欄
          if (prev != null) {
            prev.requestFocus();
          } else {
            widget.sidebarFocusNode?.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          // 最右邊的按鈕再按右鍵，停留原地
          next?.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown) {
          // 上下沒有可聚焦的元件，停留原地
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
          Text(
            _isWeb ? '網頁版掃碼登入' : 'TV 掃碼登入',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isWeb
                ? '用 B 站手機 App 掃描，在手機上按確認；適用 TV 掃碼出現 48007 的帳號。此方式不支援投幣'
                : '用 B 站 App 掃描，不需同一個網路',
            style: const TextStyle(color: Color(0xFF81C784), fontSize: 15),
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
            _buildButtonRow(qrFailed),
          ],
        ),
      ),
    );
  }
}
