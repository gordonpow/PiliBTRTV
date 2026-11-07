import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../auth_service.dart';

/// Bilibili API 基础类 - 提供共享工具方法
class BaseApi {
  static const String apiBase = 'https://api.bilibili.com';
  static const String passportBase = 'https://passport.bilibili.com';

  // WBI keys 缓存
  static String? imgKey;
  static String? subKey;
  static DateTime? wbiKeysTime;
  static bool _wbiLoaded = false;

  // buvid3 / buvid4 device cookies (required by x/web-interface/view etc.)
  static String? buvid3;
  static String? buvid4;

  /// Full Cookie string: buvid3 / buvid4 always, SESSDATA / bili_jct when
  /// logged in. Returns null when nothing is available.
  static String? get cookieHeader {
    final parts = <String>[];
    if (buvid3 != null && buvid3!.isNotEmpty) parts.add('buvid3=$buvid3');
    if (buvid4 != null && buvid4!.isNotEmpty) parts.add('buvid4=$buvid4');
    final sessdata = AuthService.sessdata;
    final biliJct = AuthService.biliJct;
    if (sessdata != null && sessdata.isNotEmpty) {
      parts.add('SESSDATA=$sessdata');
      if (biliJct != null && biliJct.isNotEmpty) {
        parts.add('bili_jct=$biliJct');
      }
    }
    return parts.isEmpty ? null : parts.join('; ');
  }

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36';

  /// Random buvid in the format XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX + 5 digits + infoc
  static String _generateBuvid() {
    final rnd = Random.secure();
    String hex(int n) => List.generate(
      n,
      (_) => rnd.nextInt(16).toRadixString(16).toUpperCase(),
    ).join();
    final digits = List.generate(5, (_) => rnd.nextInt(10)).join();
    return '${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}${digits}infoc';
  }

  /// Make sure buvid3 / buvid4 exist: prefs, then finger/spi, then random.
  static Future<void> ensureBuvid() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      buvid3 = prefs.getString('buvid3');
      buvid4 = prefs.getString('buvid4');
    } catch (_) {}
    if (buvid3 != null && buvid3!.isNotEmpty) return;

    try {
      final response = await http
          .get(
            Uri.parse('$apiBase/x/frontend/finger/spi'),
            headers: {
              'User-Agent': _userAgent,
              'Referer': 'https://www.bilibili.com',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final b3 = json['data']['b_3'] as String?;
          final b4 = json['data']['b_4'] as String?;
          if (b3 != null && b3.isNotEmpty) buvid3 = b3;
          if (b4 != null && b4.isNotEmpty) buvid4 = b4;
        }
      }
    } catch (_) {}

    buvid3 ??= _generateBuvid();
    try {
      await prefs?.setString('buvid3', buvid3!);
      if (buvid4 != null) await prefs?.setString('buvid4', buvid4!);
    } catch (_) {}
  }

  /// 获取通用请求头
  /// Cookie always carries buvid3; [withCookie] only controls login cookies.
  static Map<String, String> getHeaders({bool withCookie = false}) {
    final headers = {
      'User-Agent': _userAgent,
      'Referer': 'https://www.bilibili.com',
    };

    final parts = <String>[];
    if (buvid3 != null && buvid3!.isNotEmpty) parts.add('buvid3=$buvid3');
    if (buvid4 != null && buvid4!.isNotEmpty) parts.add('buvid4=$buvid4');
    if (withCookie) {
      final sessdata = AuthService.sessdata;
      final biliJct = AuthService.biliJct;
      if (sessdata != null && sessdata.isNotEmpty) {
        parts.add('SESSDATA=$sessdata');
        if (biliJct != null && biliJct.isNotEmpty) {
          parts.add('bili_jct=$biliJct');
        }
      }
    }
    if (parts.isNotEmpty) headers['Cookie'] = parts.join('; ');

    return headers;
  }

  /// 从本地存储加载 WBI keys
  static Future<void> _loadWbiFromStorage() async {
    if (_wbiLoaded) return;
    _wbiLoaded = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      imgKey = prefs.getString('wbi_img_key');
      subKey = prefs.getString('wbi_sub_key');
      final timeMs = prefs.getInt('wbi_keys_time');
      if (timeMs != null) {
        wbiKeysTime = DateTime.fromMillisecondsSinceEpoch(timeMs);
      }
    } catch (e) {
      // 忽略加载错误
    }
  }

  /// 保存 WBI keys 到本地存储
  static Future<void> _saveWbiToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (imgKey != null) prefs.setString('wbi_img_key', imgKey!);
      if (subKey != null) prefs.setString('wbi_sub_key', subKey!);
      if (wbiKeysTime != null) {
        prefs.setInt('wbi_keys_time', wbiKeysTime!.millisecondsSinceEpoch);
      }
    } catch (e) {
      // 忽略保存错误
    }
  }

  /// 获取 WBI keys (从 nav 接口)
  /// 缓存2小时，失败时继续使用旧值
  static Future<void> ensureWbiKeys() async {
    // 首次启动时从本地加载
    await _loadWbiFromStorage();

    // 缓存2小时
    if (imgKey != null && subKey != null && wbiKeysTime != null) {
      if (DateTime.now().difference(wbiKeysTime!).inMinutes < 120) {
        return;
      }
    }

    try {
      final response = await http.get(
        Uri.parse('$apiBase/x/web-interface/nav'),
        headers: getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final wbiImg = json['data']['wbi_img'];
          if (wbiImg != null) {
            final imgUrl = wbiImg['img_url'] as String? ?? '';
            final subUrl = wbiImg['sub_url'] as String? ?? '';

            imgKey = imgUrl.split('/').last.split('.').first;
            subKey = subUrl.split('/').last.split('.').first;
            wbiKeysTime = DateTime.now();

            // 保存到本地存储
            _saveWbiToStorage();
          }
        }
      }
    } catch (e) {
      // 刷新失败时继续使用旧值（如果有的话）
    }
  }

  /// 修复图片 URL
  static String fixPicUrl(String url) {
    if (url.startsWith('//')) return 'https:$url';
    return url;
  }

  /// 转换为整数 (支持 "1.2万" 格式)
  static int toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) {
      final direct = int.tryParse(value);
      if (direct != null) return direct;

      if (value.endsWith('万')) {
        final num = double.tryParse(value.replaceAll('万', ''));
        if (num != null) return (num * 10000).round();
      }
      if (value.endsWith('亿')) {
        final num = double.tryParse(value.replaceAll('亿', ''));
        if (num != null) return (num * 100000000).round();
      }
    }
    return 0;
  }

  /// 解析时长 (支持 "1:23" 和 "1:23:45" 格式)
  static int parseDuration(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      final parts = value.split(':');
      if (parts.length == 2) {
        return (int.tryParse(parts[0]) ?? 0) * 60 +
            (int.tryParse(parts[1]) ?? 0);
      }
      if (parts.length == 3) {
        return (int.tryParse(parts[0]) ?? 0) * 3600 +
            (int.tryParse(parts[1]) ?? 0) * 60 +
            (int.tryParse(parts[2]) ?? 0);
      }
    }
    return 0;
  }
}
