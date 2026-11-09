import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_api.dart';
import 'base_api.dart';

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

String _fixUrl(String? u) {
  if (u == null) return '';
  return u.startsWith('//') ? 'https:$u' : u;
}

/// 個人資料（/x/web-interface/nav）
class MyInfo {
  final int mid;
  final String uname;
  final String face;
  final int level;
  final int currentExp;

  /// 下一級所需經驗；滿級時伺服器回傳字串 "--"，此時為 null。
  final int? nextExp;
  final double coins;
  final double bcoin;
  final bool isVip;

  /// 大會員到期時間（毫秒），沒有則為 0。
  final int vipDueMs;
  final String vipLabel;

  const MyInfo({
    required this.mid,
    required this.uname,
    required this.face,
    required this.level,
    required this.currentExp,
    required this.nextExp,
    required this.coins,
    required this.bcoin,
    required this.isVip,
    required this.vipDueMs,
    required this.vipLabel,
  });

  factory MyInfo.fromNav(Map<String, dynamic> d) {
    final lv = d['level_info'] is Map ? d['level_info'] as Map : const {};
    final wallet = d['wallet'] is Map ? d['wallet'] as Map : const {};
    final label = d['vip_label'] is Map ? d['vip_label'] as Map : const {};
    final next = lv['next_exp'];
    return MyInfo(
      mid: _toInt(d['mid']),
      uname: d['uname'] as String? ?? '',
      face: _fixUrl(d['face'] as String?),
      level: _toInt(lv['current_level']),
      currentExp: _toInt(lv['current_exp']),
      nextExp: (next is num || (next is String && int.tryParse(next) != null))
          ? _toInt(next)
          : null,
      coins: _toDouble(d['money']),
      bcoin: _toDouble(wallet['bcoin_balance']),
      isVip: _toInt(d['vipStatus']) == 1,
      vipDueMs: _toInt(d['vipDueDate']),
      vipLabel: label['text'] as String? ?? '',
    );
  }
}

/// 關注數、粉絲數、動態數（/x/web-interface/nav/stat）
class MyStat {
  final int following;
  final int follower;
  final int dynamicCount;

  const MyStat({
    required this.following,
    required this.follower,
    required this.dynamicCount,
  });

  factory MyStat.fromJson(Map<String, dynamic> d) => MyStat(
    following: _toInt(d['following']),
    follower: _toInt(d['follower']),
    dynamicCount: _toInt(d['dynamic_count']),
  );
}

class FollowingUser {
  final int mid;
  final String name;
  final String face;
  final String sign;

  const FollowingUser({
    required this.mid,
    required this.name,
    required this.face,
    required this.sign,
  });
}

class FollowingPage {
  final List<FollowingUser> list;
  final int total;

  const FollowingPage({required this.list, required this.total});

  factory FollowingPage.fromJson(Map<String, dynamic> d) {
    final raw = d['list'];
    final users = <FollowingUser>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final mid = _toInt(e['mid']);
        if (mid == 0) continue;
        users.add(
          FollowingUser(
            mid: mid,
            name: e['uname'] as String? ?? '',
            face: _fixUrl(e['face'] as String?),
            sign: e['sign'] as String? ?? '',
          ),
        );
      }
    }
    return FollowingPage(list: users, total: _toInt(d['total']));
  }
}

/// 個人頁面用 API（皆需登入 cookie）
class UserApi {
  static const int followingsPageSize = 20;

  /// 回傳 null 表示失敗（含未登入）。
  static Future<MyInfo?> getMyInfo() async {
    final data = await AuthApi.fetchNavData();
    if (data == null) return null;
    return MyInfo.fromNav(data);
  }

  static Future<MyStat?> getMyStat() async {
    final data = await _get('/x/web-interface/nav/stat');
    if (data == null) return null;
    return MyStat.fromJson(data);
  }

  static Future<FollowingPage?> getFollowings(int mid, int pn) async {
    final data = await _get(
      '/x/relation/followings?vmid=$mid&pn=$pn&ps=$followingsPageSize&order=desc',
    );
    if (data == null) return null;
    return FollowingPage.fromJson(data);
  }

  static Future<Map<String, dynamic>?> _get(String path) async {
    try {
      final response = await http.get(
        Uri.parse('${BaseApi.apiBase}$path'),
        headers: BaseApi.getHeaders(withCookie: true),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] is Map) {
          return Map<String, dynamic>.from(json['data'] as Map);
        }
        debugPrint('UserApi: $path code=${json['code']}');
      } else {
        debugPrint('UserApi: $path HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('UserApi: $path 例外 ${e.runtimeType}');
    }
    return null;
  }
}
