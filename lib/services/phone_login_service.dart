import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:math';

import 'package:crypto/crypto.dart' show md5;
import 'package:encrypt/encrypt.dart' show Encrypter, RSA, RSAKeyParser;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api/app_sign.dart';
import 'api/base_api.dart';
import 'auth_service.dart';
import 'local_server.dart';

/// 解析 `name=value; name2=value2` 格式的 Cookie 字串。
/// 以第一個 `=` 切分，只保留 SESSDATA、bili_jct、DedeUserID。
Map<String, String> parseLoginCookie(String raw) {
  const wanted = {'SESSDATA', 'bili_jct', 'DedeUserID'};
  final result = <String, String>{};
  for (final part in raw.split(';')) {
    final item = part.trim();
    final idx = item.indexOf('=');
    if (idx <= 0) continue;
    final name = item.substring(0, idx).trim();
    final value = item.substring(idx + 1).trim();
    if (wanted.contains(name) && value.isNotEmpty) {
      result[name] = value;
    }
  }
  return result;
}

/// 常數時間字串比對（避免從回應時間推測代碼）
bool constantTimeEquals(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  var diff = x.length ^ y.length;
  final n = max(x.length, y.length);
  for (var i = 0; i < n; i++) {
    diff |= (i < x.length ? x[i] : 0) ^ (i < y.length ? y[i] : 0);
  }
  return diff == 0;
}

/// 手機輔助登入：一次性代碼、狀態機與所有 B 站登入呼叫
///
/// 所有 B 站請求都在電視端進行；手機網頁只收集輸入與極驗結果。
/// 密碼、簡訊驗證碼等只放在記憶體，流程結束時清除，絕不寫入 log。
class PhoneLoginService {
  static final PhoneLoginService instance = PhoneLoginService._(
    addressProvider: () => LocalServer.instance.address,
  );

  PhoneLoginService._({
    required String? Function() addressProvider,
    DateTime Function()? clock,
  }) : _addressProvider = addressProvider,
       _now = clock ?? DateTime.now;

  @visibleForTesting
  PhoneLoginService.forTest({
    String? Function()? addressProvider,
    DateTime Function()? clock,
  }) : _addressProvider = addressProvider ?? (() => 'http://127.0.0.1:3322'),
       _now = clock ?? DateTime.now;

  static const Duration tokenLifetime = Duration(minutes: 15);
  static const Duration doneGrace = Duration(seconds: 60);
  static const int maxBadTokens = 10;
  static const String _fallbackError = '操作失敗，請稍後再試';
  static const String _networkError = '無法連線到嗶哩嗶哩，請稍後再試';

  final String? Function() _addressProvider;
  final DateTime Function() _now;

  /// 電視端顯示用的狀態文字
  final ValueNotifier<String> status = ValueNotifier<String>('等待手機連線');

  /// 目前的登入網址（null 表示沒有可用的網址）
  final ValueNotifier<String?> url = ValueNotifier<String?>(null);

  /// 登入成功時變為 true
  final ValueNotifier<bool> loggedIn = ValueNotifier<bool>(false);

  String? _token;
  DateTime? _tokenExpiry;
  DateTime? _doneUntil;
  Timer? _expiryTimer;
  bool _active = false;
  int _badCount = 0;
  int _flowId = 0;

  // 對外狀態
  String _step = 'input';
  String _message = '';
  String? _gt;
  String? _challenge;
  String? _hideTel;
  String? _riskUrl;
  bool _riskSent = false;
  bool _phoneConnected = false;

  // 流程暫存（只放記憶體）
  String _pending = '';
  String? _username;
  String? _password;
  String? _tel;
  int _cid = 86;
  String? _smsCaptchaKey;
  DateTime? _smsSentAt;
  String? _recaptchaToken;
  String? _origChallenge;
  String? _tmpToken;
  String? _requestId;
  String? _source;
  String? _riskCaptchaKey;

  // 裝置識別（與 BaseApi 的 buvid3 分開）
  String? _buvid;
  String? _deviceId;

  // ---------------------------------------------------------------- 代碼

  /// 登入頁開啟時呼叫。回傳登入網址；沒有區網位址時回傳 null。
  String? start() {
    _active = true;
    _regenerate();
    return url.value;
  }

  /// 登入頁離開時呼叫。成功後的 60 秒寬限期內保留唯讀的 done 狀態。
  void stop() {
    _active = false;
    if (_step == 'done' && _doneUntil != null && _now().isBefore(_doneUntil!)) {
      _flowId++;
      return;
    }
    _clearAll();
  }

  void _regenerate() {
    _clearAll();
    final address = _addressProvider();
    if (address == null) {
      status.value = '請把電視連上 Wi-Fi 或有線網路';
      return;
    }
    _token = _randomToken();
    _tokenExpiry = _now().add(tokenLifetime);
    _expiryTimer = Timer(tokenLifetime, _onExpired);
    url.value = '$address/login?t=$_token';
    status.value = '等待手機連線';
  }

  void _clearAll() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _token = null;
    _tokenExpiry = null;
    _doneUntil = null;
    _badCount = 0;
    _phoneConnected = false;
    _resetFlow();
    loggedIn.value = false;
    url.value = null;
    status.value = '等待手機連線';
  }

  void _resetFlow() {
    _flowId++;
    _step = 'input';
    _message = '';
    _gt = null;
    _challenge = null;
    _hideTel = null;
    _riskUrl = null;
    _riskSent = false;
    _clearSecrets();
  }

  void _clearSecrets() {
    _pending = '';
    _username = null;
    _password = null;
    _tel = null;
    _smsCaptchaKey = null;
    _smsSentAt = null;
    _recaptchaToken = null;
    _origChallenge = null;
    _tmpToken = null;
    _requestId = null;
    _source = null;
    _riskCaptchaKey = null;
  }

  void _onExpired() {
    if (_step == 'done') {
      _clearAll();
      return;
    }
    if (_active) {
      _regenerate();
    } else {
      _clearAll();
    }
  }

  void _expireIfNeeded() {
    if (_token == null) return;
    final now = _now();
    if (_step == 'done') {
      if (_doneUntil != null && !now.isBefore(_doneUntil!)) _clearAll();
    } else if (_tokenExpiry != null && !now.isBefore(_tokenExpiry!)) {
      _onExpired();
    }
  }

  static String _randomToken() {
    const chars =
        'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 去掉 0 O 1 l I 等易混淆字元
    final rnd = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(16, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  /// 檢查請求帶的代碼。錯誤、過期都回 false。
  /// [write] 為 true 時（POST），成功後的寬限期內一律拒絕。
  bool checkToken(String? candidate, {bool write = false}) {
    _expireIfNeeded();
    final token = _token;
    if (token == null) return false;
    if (!constantTimeEquals(candidate ?? '', token)) {
      _badCount++;
      if (_badCount >= maxBadTokens) {
        // 連續錯誤太多：作廢目前代碼並重新產生
        if (_active) {
          _regenerate();
        } else {
          _clearAll();
        }
      }
      return false;
    }
    if (_step == 'done' && write) return false;
    return true;
  }

  // ---------------------------------------------------------------- 狀態

  void _setStatus(String text) => status.value = text;

  /// 回傳給手機網頁的狀態
  Map<String, dynamic> stateJson() {
    if (_step == 'input' && !_phoneConnected && _token != null) {
      _phoneConnected = true;
      _setStatus('手機已連線');
    }
    return {
      'step': _step,
      'message': _message,
      'gt': ?(_step == 'captcha' ? _gt : null),
      'challenge': ?(_step == 'captcha' ? _challenge : null),
      'hideTel': ?(_step == 'riskSms' ? _hideTel : null),
      'url': ?(_step == 'riskSms' ? _riskUrl : null),
      'sent': ?(_step == 'riskSms' ? _riskSent : null),
    };
  }

  int _beginFlow() {
    _resetFlow();
    return _flowId;
  }

  bool _valid(int id) => id == _flowId && _token != null;

  void _setStep(String step, String message, {String? tvText}) {
    _step = step;
    _message = message;
    if (tvText != null) _setStatus(tvText);
  }

  void _fail(String message, {String step = 'error'}) {
    _setStep(step, message, tvText: message);
    if (step == 'error') _clearSecrets();
  }

  Future<Map<String, dynamic>> _guard(
    int id,
    Future<void> Function() body, {
    String failStep = 'error',
  }) async {
    try {
      await body();
    } catch (e) {
      if (_valid(id)) {
        final net =
            e is TimeoutException ||
            e is SocketException ||
            e is http.ClientException;
        _fail(net ? _networkError : _fallbackError, step: failStep);
      }
    }
    return stateJson();
  }

  static String _msg(Map res, String fallback) {
    final m = res['message'];
    return (m is String && m.isNotEmpty && m != '0') ? m : fallback;
  }

  // ---------------------------------------------------------------- 對外動作

  /// 密碼登入
  Future<Map<String, dynamic>> submitPassword(
    String username,
    String password,
  ) async {
    if (username.isEmpty || password.isEmpty) {
      return {...stateJson(), 'message': '請輸入帳號與密碼'};
    }
    final id = _beginFlow();
    _username = username;
    _password = password;
    _pending = 'password';
    _setStep('working', '', tvText: '驗證中…');
    return _guard(id, () => _doPassword(id, null));
  }

  /// 送出簡訊驗證碼
  Future<Map<String, dynamic>> sendSms(int cid, String tel) async {
    if (!RegExp(r'^\d{4,15}$').hasMatch(tel) || cid <= 0) {
      return {...stateJson(), 'message': '請輸入正確的手機號碼'};
    }
    final id = _beginFlow();
    _cid = cid;
    // 非 86 區碼時，去掉開頭的 0
    _tel = (cid != 86 && tel.startsWith('0'))
        ? tel.replaceFirst(RegExp(r'^0+'), '')
        : tel;
    _pending = 'smsSend';
    _setStep('working', '', tvText: '驗證中…');
    return _guard(id, () => _doSmsSend(id, null));
  }

  /// 簡訊驗證碼登入
  Future<Map<String, dynamic>> smsLogin(String code) async {
    if (_step != 'smsSent' || _smsCaptchaKey == null || _tel == null) {
      return {...stateJson(), 'message': '請先取得簡訊驗證碼'};
    }
    if (code.isEmpty) return {...stateJson(), 'message': '請輸入簡訊驗證碼'};
    if (_smsSentAt != null &&
        _now().difference(_smsSentAt!) > const Duration(minutes: 5)) {
      _fail('驗證碼已過期，請重新取得');
      return stateJson();
    }
    final id = _flowId;
    _setStep('working', '', tvText: '驗證中…');
    return _guard(id, () async {
      final key = await _fetchWebKey();
      final res = await _loginBySms(code, key);
      if (!_valid(id)) return;
      await _handleLoginResponse(id, res, recoverStep: 'smsSent');
    }, failStep: 'smsSent');
  }

  /// 極驗完成後，依目前步驟重送請求
  Future<Map<String, dynamic>> submitCaptcha(
    String challenge,
    String validate,
    String seccode,
  ) async {
    if (_step != 'captcha' ||
        challenge.isEmpty ||
        validate.isEmpty ||
        seccode.isEmpty) {
      return stateJson();
    }
    final id = _flowId;
    final gee = (challenge: challenge, validate: validate, seccode: seccode);
    final pending = _pending;
    _setStep('working', '', tvText: '驗證中…');
    return _guard(id, () async {
      switch (pending) {
        case 'password':
          await _doPassword(id, gee);
        case 'smsSend':
          await _doSmsSend(id, gee);
        case 'riskSmsSend':
          await _doRiskSmsSend(id, gee);
        default:
          _fail(_fallbackError);
      }
    });
  }

  /// 風控簡訊：code 為空代表「傳送驗證碼」，否則送出驗證
  Future<Map<String, dynamic>> riskVerify(String code) async {
    if (_step != 'riskSms' || _tmpToken == null) return stateJson();
    final id = _flowId;
    if (code.isEmpty) {
      _setStep('working', '', tvText: '驗證中…');
      return _guard(id, () async {
        final pre = await _preCapture();
        if (!_valid(id)) return;
        if (!_applyCaptcha(pre, 'riskSmsSend')) {
          _fail('取得驗證碼失敗，請改用其他登入方式', step: 'riskSms');
        }
      }, failStep: 'riskSms');
    }
    if (_riskCaptchaKey == null) {
      return {...stateJson(), 'message': '請先傳送驗證碼'};
    }
    _setStep('working', '', tvText: '驗證中…');
    return _guard(id, () async {
      final verify = await _postJson(
        '${BaseApi.passportBase}/x/safecenter/login/tel/verify',
        AppSign.appSign({
          'type': 'loginTelCheck',
          'code': code,
          'tmp_code': _tmpToken!,
          'request_id': _requestId ?? '',
          'source': _source ?? '',
          'captcha_key': _riskCaptchaKey!,
        }),
        headers: {..._baseHeaders(), 'Referer': _riskUrl ?? ''},
      );
      if (!_valid(id)) return;
      final vData = verify['data'];
      if (verify['code'] != 0 || vData is! Map || vData['code'] is! String) {
        _fail(_msg(verify, '驗證失敗'), step: 'riskSms');
        return;
      }
      final tokenRes = await _postJson(
        '${BaseApi.passportBase}/x/passport-login/oauth2/access_token',
        AppSign.appSign({
          'build': '2001100',
          'buvid': await _getBuvid(),
          'code': vData['code'],
          'disable_rcmd': '0',
          'grant_type': 'authorization_code',
          'local_id': await _getBuvid(),
          'mobi_app': 'android_hd',
          'platform': 'android',
        }),
        headers: _appHeaders(),
      );
      if (!_valid(id)) return;
      final data = tokenRes['data'];
      if (tokenRes['code'] != 0 || data is! Map) {
        _fail(_msg(tokenRes, '登入失敗，請改用其他登入方式'), step: 'riskSms');
        return;
      }
      await _finishLogin(id, data);
    }, failStep: 'riskSms');
  }

  /// Cookie 登入
  Future<Map<String, dynamic>> submitCookie(String raw) async {
    final cookies = parseLoginCookie(raw);
    if (!cookies.containsKey('SESSDATA') ||
        !cookies.containsKey('bili_jct') ||
        !cookies.containsKey('DedeUserID')) {
      return {
        ...stateJson(),
        'message': 'Cookie 必須包含 SESSDATA、bili_jct、DedeUserID',
      };
    }
    // 避免標頭注入：值不可含空白、分號、引號或控制字元
    final safe = RegExp(r'^[^\s;"\\\x00-\x1f\x7f]+$');
    if (cookies.values.any((v) => !safe.hasMatch(v))) {
      return {...stateJson(), 'message': 'Cookie 格式不正確'};
    }
    final id = _beginFlow();
    _setStep('working', '', tvText: '驗證中…');
    return _guard(id, () async {
      final headers = BaseApi.getHeaders();
      final merged = [
        ?headers['Cookie'],
        'SESSDATA=${cookies['SESSDATA']}',
        'bili_jct=${cookies['bili_jct']}',
        'DedeUserID=${cookies['DedeUserID']}',
      ].join('; ');
      headers['Cookie'] = merged;
      final res = await _getJson(
        '${BaseApi.apiBase}/x/member/web/account',
        headers,
      );
      if (!_valid(id)) return;
      final data = res['data'];
      if (res['code'] != 0 ||
          data is! Map ||
          data['mid'].toString() != cookies['DedeUserID']) {
        _fail('Cookie 無效或已過期');
        return;
      }
      await AuthService.saveCookieLogin(cookies);
      if (!_valid(id)) return;
      _markDone();
    });
  }

  // ---------------------------------------------------------------- 流程實作

  Future<void> _doPassword(
    int id,
    ({String challenge, String validate, String seccode})? gee,
  ) async {
    final webKey = await _fetchWebKey();
    if (!_valid(id)) return;
    final username = _username, password = _password;
    if (username == null || password == null) {
      _fail(_fallbackError);
      return;
    }
    final buvid = await _getBuvid();
    final deviceId = await _getDeviceId();
    final publicKey = RSAKeyParser().parse(webKey.key);
    final encrypter = Encrypter(RSA(publicKey: publicKey as dynamic));
    final data = <String, dynamic>{
      'bili_local_id': deviceId,
      'build': '2001100',
      'buvid': buvid,
      'c_locale': 'zh_CN',
      'channel': 'master',
      'device': 'phone',
      'device_id': deviceId,
      'device_name': 'vivo',
      'device_platform': 'Android14vivo',
      'disable_rcmd': '0',
      'dt': Uri.encodeComponent(
        encrypter.encrypt(AppSign.randomString(16)).base64,
      ),
      'from_pv': 'main.homepage.avatar-nologin.all.click',
      'from_url': Uri.encodeComponent('bilibili://pegasus/promo'),
      'gee_challenge': ?gee?.challenge,
      'gee_seccode': ?gee?.seccode,
      'gee_validate': ?gee?.validate,
      'local_id': buvid,
      'mobi_app': 'android_hd',
      'password': encrypter.encrypt(webKey.hash + password).base64,
      'permission': 'ALL',
      'platform': 'android',
      'recaptcha_token': ?(gee != null ? _recaptchaToken : null),
      's_locale': 'zh_CN',
      'statistics': _statistics,
      'username': username,
    };
    AppSign.appSign(data);
    final res = await _postJson(
      '${BaseApi.passportBase}/x/passport-login/oauth2/login',
      data,
      headers: _appHeaders(),
    );
    if (!_valid(id)) return;
    await _handleLoginResponse(id, res);
  }

  Future<void> _doSmsSend(
    int id,
    ({String challenge, String validate, String seccode})? gee,
  ) async {
    final buvid = await _getBuvid();
    final timestamp = _now().millisecondsSinceEpoch;
    final data = <String, dynamic>{
      'build': '2001100',
      'buvid': buvid,
      'c_locale': 'zh_CN',
      'channel': 'master',
      'cid': _cid,
      'disable_rcmd': '0',
      'gee_challenge': ?gee?.challenge,
      'gee_seccode': ?gee?.seccode,
      'gee_validate': ?gee?.validate,
      'local_id': buvid,
      'login_session_id': md5
          .convert(ascii.encode(buvid + timestamp.toString()))
          .toString(),
      'mobi_app': 'android_hd',
      'platform': 'android',
      'recaptcha_token': ?(gee != null ? _recaptchaToken : null),
      's_locale': 'zh_CN',
      'statistics': _statistics,
      'tel': _tel,
      'ts': (timestamp ~/ 1000).toString(),
    };
    AppSign.appSign(data, ts: timestamp ~/ 1000);
    final res = await _postJson(
      '${BaseApi.passportBase}/x/passport-login/sms/send',
      data,
      headers: _appHeaders(),
    );
    if (!_valid(id)) return;
    final code = res['code'];
    final d = res['data'];
    final recaptchaUrl = d is Map ? (d['recaptcha_url'] ?? '') : '';
    if (code == 0 && recaptchaUrl == '' && d is Map) {
      final key = d['captcha_key'];
      if (key is String && key.isNotEmpty) {
        _smsCaptchaKey = key;
        _smsSentAt = _now();
        _setStep('smsSent', '簡訊驗證碼已送出', tvText: '簡訊已送出，請在手機輸入驗證碼');
        return;
      }
      _fail('傳送簡訊驗證碼失敗');
      return;
    }
    if (code == 0 || code == -105) {
      await _captchaFromUrl(
        id,
        recaptchaUrl is String ? recaptchaUrl : '',
        'smsSend',
      );
      return;
    }
    _fail(_msg(res, '傳送簡訊驗證碼失敗'));
  }

  Future<void> _doRiskSmsSend(
    int id,
    ({String challenge, String validate, String seccode}) gee,
  ) async {
    final res = await _postJson(
      '${BaseApi.passportBase}/x/safecenter/common/sms/send',
      AppSign.appSign({
        'disable_rcmd': '0',
        'sms_type': 'loginTelCheck',
        'tmp_code': _tmpToken ?? '',
        // 風控簡訊送碼帶 captcha/pre 回傳的原始 challenge
        'gee_challenge': _origChallenge ?? gee.challenge,
        'gee_seccode': gee.seccode,
        'gee_validate': gee.validate,
        'recaptcha_token': ?_recaptchaToken,
      }),
      headers: {..._baseHeaders(), 'Referer': _riskUrl ?? ''},
    );
    if (!_valid(id)) return;
    final d = res['data'];
    if (res['code'] == 0 && d is Map && d['captcha_key'] is String) {
      _riskCaptchaKey = d['captcha_key'] as String;
      _riskSent = true;
      _setStep('riskSms', '簡訊驗證碼已送出', tvText: '簡訊已送出，請在手機輸入驗證碼');
      return;
    }
    _fail(_msg(res, '傳送簡訊驗證碼失敗'), step: 'riskSms');
  }

  Future<Map<String, dynamic>> _loginBySms(
    String code,
    ({String key, String hash}) webKey,
  ) async {
    final buvid = await _getBuvid();
    final deviceId = await _getDeviceId();
    final publicKey = RSAKeyParser().parse(webKey.key);
    final encrypter = Encrypter(RSA(publicKey: publicKey as dynamic));
    final data = <String, dynamic>{
      'bili_local_id': deviceId,
      'build': '2001100',
      'buvid': buvid,
      'c_locale': 'zh_CN',
      'captcha_key': _smsCaptchaKey,
      'channel': 'master',
      'cid': _cid,
      'code': code,
      'device': 'phone',
      'device_id': deviceId,
      'device_name': 'vivo',
      'device_platform': 'Android14vivo',
      'disable_rcmd': '0',
      'dt': Uri.encodeComponent(
        encrypter.encrypt(AppSign.randomString(16)).base64,
      ),
      'from_pv': 'main.my-information.my-login.0.click',
      'from_url': Uri.encodeComponent('bilibili://user_center/mine'),
      'local_id': buvid,
      'mobi_app': 'android_hd',
      'platform': 'android',
      's_locale': 'zh_CN',
      'statistics': _statistics,
      'tel': _tel,
    };
    AppSign.appSign(data);
    return _postJson(
      '${BaseApi.passportBase}/x/passport-login/login/sms',
      data,
      headers: _appHeaders(),
    );
  }

  /// 處理密碼／簡訊登入的回應
  Future<void> _handleLoginResponse(
    int id,
    Map<String, dynamic> res, {
    String recoverStep = 'error',
  }) async {
    final code = res['code'];
    final data = res['data'];
    if (code == 0) {
      if (data is! Map) {
        _fail('登入異常，介面未返回資料', step: recoverStep);
        return;
      }
      if (data['status'] == 2) {
        await _startRisk(id, data);
        return;
      }
      await _finishLogin(id, data, recoverStep: recoverStep);
      return;
    }
    if (code == -105 && data is Map) {
      final u = data['url'];
      await _captchaFromUrl(id, u is String ? u : '', _pending);
      return;
    }
    _fail(_msg(res, '登入失敗'), step: recoverStep);
  }

  /// 從 recaptcha_url 取極驗參數；拿不到時改用 captcha/pre
  Future<void> _captchaFromUrl(
    int id,
    String captchaUrl,
    String pending,
  ) async {
    Map<String, dynamic>? params;
    if (captchaUrl.isNotEmpty) {
      final uri = Uri.tryParse(captchaUrl);
      if (uri != null) {
        params = {
          'gee_gt': uri.queryParameters['gee_gt'],
          'gee_challenge': uri.queryParameters['gee_challenge'],
          'recaptcha_token': uri.queryParameters['recaptcha_token'],
        };
      }
    }
    if (params == null || !_geeValid(params)) {
      final pre = await _preCapture();
      if (!_valid(id)) return;
      params = pre;
    }
    if (!_applyCaptcha(params, pending)) {
      _fail('取得驗證碼失敗，請改用其他登入方式');
    }
  }

  static bool _geeValid(Map<String, dynamic>? p) =>
      p != null &&
      p['gee_gt'] is String &&
      (p['gee_gt'] as String).isNotEmpty &&
      p['gee_challenge'] is String &&
      (p['gee_challenge'] as String).isNotEmpty;

  bool _applyCaptcha(Map<String, dynamic>? p, String pending) {
    if (!_geeValid(p)) return false;
    _gt = p!['gee_gt'] as String;
    _challenge = p['gee_challenge'] as String;
    _origChallenge = _challenge;
    final token = p['recaptcha_token'];
    _recaptchaToken = token is String && token.isNotEmpty ? token : null;
    _pending = pending;
    _setStep('captcha', '請完成滑塊驗證', tvText: '請在手機完成滑塊驗證');
    return true;
  }

  Future<Map<String, dynamic>?> _preCapture() async {
    final res = await _postJson(
      '${BaseApi.passportBase}/x/safecenter/captcha/pre',
      const {},
      headers: _baseHeaders(),
    );
    final d = res['data'];
    if (res['code'] == 0 && d is Map) return Map<String, dynamic>.from(d);
    return null;
  }

  /// 風控驗證（data.status == 2）
  Future<void> _startRisk(int id, Map data) async {
    final riskUrl = data['url'];
    final uri = riskUrl is String ? Uri.tryParse(riskUrl) : null;
    final tmp = uri?.queryParameters['tmp_token'];
    if (uri == null || tmp == null || tmp.isEmpty) {
      _fail('登入需要額外驗證，請改用其他登入方式');
      return;
    }
    _tmpToken = tmp;
    _requestId = uri.queryParameters['request_id'];
    _source = uri.queryParameters['source'];
    _riskUrl = riskUrl as String;
    final info = await _getJson(
      '${BaseApi.passportBase}/x/safecenter/user/info?tmp_code=${Uri.encodeQueryComponent(tmp)}',
      _baseHeaders(),
    );
    if (!_valid(id)) return;
    final d = info['data'];
    final account = d is Map ? d['account_info'] : null;
    if (info['code'] != 0 || account is! Map) {
      _fail('取得安全驗證資訊失敗，請改用其他登入方式');
      return;
    }
    if (account['tel_verify'] != true) {
      _fail('此帳號不支援手機號驗證，請改用其他登入方式');
      return;
    }
    final hide = account['hide_tel'];
    _hideTel = hide is String ? hide : '';
    _riskSent = false;
    final m = data['message'];
    _setStep(
      'riskSms',
      m is String && m.isNotEmpty ? m : '本次登入需要驗證您的手機號',
      tvText: '需要手機號驗證，請在手機操作',
    );
  }

  /// 登入成功：儲存憑證、進入 done
  Future<void> _finishLogin(
    int id,
    Map data, {
    String recoverStep = 'error',
  }) async {
    final tokenInfo = data['token_info'];
    final cookieInfo = data['cookie_info'];
    if (tokenInfo is! Map || cookieInfo is! Map) {
      _fail('登入異常，介面未返回身份資訊，可能是帳號風控，請改用其他登入方式', step: recoverStep);
      return;
    }
    var mid = BaseApi.toInt(tokenInfo['mid']);
    final cookies = cookieInfo['cookies'];
    var hasSess = false;
    if (cookies is List) {
      for (final c in cookies) {
        if (c is Map) {
          if (c['name'] == 'SESSDATA') hasSess = true;
          if (mid == 0 && c['name'] == 'DedeUserID') {
            mid = BaseApi.toInt(c['value']);
          }
        }
      }
    }
    if (!hasSess || mid == 0) {
      _fail('登入異常，介面未返回身份資訊，請改用其他登入方式', step: recoverStep);
      return;
    }
    await AuthService.saveLoginCredentials(
      accessToken: (tokenInfo['access_token'] ?? '').toString(),
      refreshToken: (tokenInfo['refresh_token'] ?? '').toString(),
      mid: mid,
      cookieInfo: Map<String, dynamic>.from(cookieInfo),
    );
    if (!_valid(id)) return;
    _markDone();
  }

  void _markDone() {
    _clearSecrets();
    _doneUntil = _now().add(doneGrace);
    _expiryTimer?.cancel();
    _expiryTimer = Timer(doneGrace, _onExpired);
    _setStep('done', '登入成功', tvText: '登入成功');
    loggedIn.value = true;
  }

  // ---------------------------------------------------------------- HTTP

  static const String _statistics =
      '{"appId":5,"platform":3,"version":"2.0.1","abtest":""}';
  static const String _appUa =
      'Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android model/android_hd mobi_app/android_hd build/2001100 channel/master innerVer/2001100 osVer/15 network/2';
  static const String _traceId =
      '11111111111111111111111111111111:1111111111111111:0:0';

  Future<String> _getBuvid() async {
    await _ensureDevice();
    return _buvid!;
  }

  Future<String> _getDeviceId() async {
    await _ensureDevice();
    return _deviceId!;
  }

  Future<void> _ensureDevice() async {
    if (_buvid != null && _deviceId != null) return;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    _buvid ??= prefs?.getString('phone_login_buvid');
    _deviceId ??= prefs?.getString('phone_login_device_id');
    if (_buvid == null || _buvid!.isEmpty) {
      _buvid = AppSign.generateBuvid();
      await prefs?.setString('phone_login_buvid', _buvid!);
    }
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = AppSign.genDeviceId();
      await prefs?.setString('phone_login_device_id', _deviceId!);
    }
  }

  Map<String, String> _baseHeaders() => BaseApi.getHeaders();

  Map<String, String> _appHeaders() => {
    'buvid': _buvid ?? '',
    'env': 'prod',
    'app-key': 'android_hd',
    'user-agent': _appUa,
    'x-bili-trace-id': _traceId,
    'x-bili-aurora-eid': '',
    'x-bili-aurora-zone': '',
    'bili-http-engine': 'cronet',
    'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
  };

  Future<({String key, String hash})> _fetchWebKey() async {
    final res = await _getJson(
      '${BaseApi.passportBase}/x/passport-login/web/key',
      _baseHeaders(),
    );
    final d = res['data'];
    if (res['code'] != 0 || d is! Map || d['key'] is! String) {
      throw StateError('web key');
    }
    return (key: d['key'] as String, hash: (d['hash'] ?? '').toString());
  }

  Future<Map<String, dynamic>> _getJson(
    String url,
    Map<String, String> headers,
  ) async {
    await _ensureDevice();
    final res = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 15));
    return _decode(res.body);
  }

  Future<Map<String, dynamic>> _postJson(
    String url,
    Map<String, dynamic> data, {
    required Map<String, String> headers,
  }) async {
    await _ensureDevice();
    // 標頭可能在 _ensureDevice 之前建立，補上 buvid
    if (headers.containsKey('buvid')) headers['buvid'] = _buvid ?? '';
    final res = await http
        .post(
          Uri.parse(url),
          headers: headers,
          body: data.map((k, v) => MapEntry(k, v.toString())),
        )
        .timeout(const Duration(seconds: 15));
    return _decode(res.body);
  }

  static Map<String, dynamic> _decode(String body) {
    final j = jsonDecode(body);
    if (j is Map<String, dynamic>) return j;
    throw const FormatException('bad response');
  }
}
