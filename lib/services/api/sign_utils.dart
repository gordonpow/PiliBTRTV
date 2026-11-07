import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Bilibili API 簽名工具
class SignUtils {
  // TV 端 appkey 和 appsec (雲視聽小電視)
  static const String tvAppKey = '4409e2ce8ffd12b8';
  static const String _tvAppSec = '59b43e04ad6965f34319062b478f83dd';

  // WBI 簽名的混淆表
  static const List<int> _mixinKeyEncTab = [
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
    37,
    48,
    7,
    16,
    24,
    55,
    40,
    61,
    26,
    17,
    0,
    1,
    60,
    51,
    30,
    4,
    22,
    25,
    54,
    21,
    56,
    59,
    6,
    63,
    57,
    62,
    11,
    36,
    20,
    34,
    44,
    52,
  ];

  /// 計算 MD5
  static String _md5(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  /// TV 登入 APP 簽名
  /// 簽名規則: params 按 key 排序 → query string → 末尾加 appsec → MD5
  static Map<String, String> signForTvLogin(Map<String, String> params) {
    // 新增公共引數
    final signParams = Map<String, String>.from(params);
    signParams['appkey'] = tvAppKey;
    signParams['ts'] = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();

    // 按 key 排序
    final sortedKeys = signParams.keys.toList()..sort();

    // 構建 query string
    final queryString = sortedKeys.map((k) => '$k=${signParams[k]}').join('&');

    // 計算簽名
    final sign = _md5(queryString + _tvAppSec);

    // 返回包含 sign 的引數
    signParams['sign'] = sign;
    return signParams;
  }

  /// 生成 WBI 混淆 key
  static String _getMixinKey(String imgKey, String subKey) {
    final raw = imgKey + subKey;
    final buffer = StringBuffer();
    for (int i = 0; i < 32; i++) {
      buffer.write(raw[_mixinKeyEncTab[i]]);
    }
    return buffer.toString();
  }

  /// WBI 簽名 (用於推薦、搜尋等介面)
  static Map<String, String> signWithWbi(
    Map<String, String> params,
    String imgKey,
    String subKey,
  ) {
    final mixinKey = _getMixinKey(imgKey, subKey);
    final wts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    // 新增時間戳
    final signParams = Map<String, String>.from(params);
    signParams['wts'] = wts;

    // 過濾特殊字元並排序
    final filteredParams = <String, String>{};
    for (var entry in signParams.entries) {
      // 過濾值中的特殊字元
      final value = entry.value.replaceAll(RegExp(r"[!'()*]"), '');
      filteredParams[entry.key] = value;
    }

    final sortedKeys = filteredParams.keys.toList()..sort();
    final queryString = sortedKeys
        .map((k) => '$k=${Uri.encodeComponent(filteredParams[k]!)}')
        .join('&');

    // 計算 w_rid
    final wRid = _md5(queryString + mixinKey);

    filteredParams['w_rid'] = wRid;
    return filteredParams;
  }
}
