import 'dart:convert' show utf8;
import 'dart:math';

import 'package:crypto/crypto.dart' show Digest, md5;

/// android_hd app 簽名與裝置識別碼產生（移植自 PiliPlus）
abstract final class AppSign {
  static const String appKey = 'dfca71928277209b';
  static const String appSec = 'b5475a8825547a4fc26c7d518eaaa02e';

  /// 為 [params] 加上 appkey、ts、sign（就地修改並回傳）。
  /// [ts] 為秒級時間戳，測試時可注入固定值。
  static Map<String, dynamic> appSign(
    Map<String, dynamic> params, {
    String appkey = appKey,
    String appsec = appSec,
    int? ts,
  }) {
    params['appkey'] = appkey;
    params['ts'] = (ts ?? DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();
    final sorted = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final query = sorted
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value.toString())}',
        )
        .join('&');
    params['sign'] = md5.convert(utf8.encode(query + appsec)).toString();
    return params;
  }

  static String generateBuvid([Random? random]) {
    final rnd = random ?? Random.secure();
    final md5Str = Digest(
      List.generate(16, (_) => rnd.nextInt(256)),
    ).toString().toUpperCase();
    return 'XY${md5Str[2]}${md5Str[12]}${md5Str[22]}$md5Str';
  }

  static String genDeviceId([Random? random, DateTime? now]) {
    final rnd = random ?? Random.secure();
    final time = now ?? DateTime.now();
    final bytes = <int>[
      ...Iterable.generate(16, (_) => rnd.nextInt(256)),
      _dec2bcd(time.year ~/ 100),
      _dec2bcd(time.year % 100),
      _dec2bcd(time.month),
      _dec2bcd(time.day),
      _dec2bcd(time.hour),
      _dec2bcd(time.minute),
      _dec2bcd(time.second),
      ...Iterable.generate(8, (_) => rnd.nextInt(256)),
    ];
    final check = (bytes.fold<int>(0, (a, b) => a + b) & 0xFF)
        .toRadixString(16)
        .padLeft(2, '0');
    return Digest(bytes).toString() + check;
  }

  static int _dec2bcd(int dec) => ((dec ~/ 10) << 4) | (dec % 10);

  /// 產生 [length] 長度的 0-9a-z 隨機字串
  static String randomString(int length, [Random? random]) {
    const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
    final rnd = random ?? Random.secure();
    return String.fromCharCodes(
      Iterable.generate(length, (_) => chars.codeUnitAt(rnd.nextInt(36))),
    );
  }
}
