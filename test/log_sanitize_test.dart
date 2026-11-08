import 'package:bili_tv_app/services/log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cookie 整行', () {
    expect(
      sanitizeLogLine('Cookie: SESSDATA=abc; bili_jct=def'),
      'Cookie: ***',
    );
  });

  test('cookie 片段與 token', () {
    final s = sanitizeLogLine(
      'got SESSDATA=abc123; buvid3=XYZ-infoc b_nut=170000 DedeUserID=99 '
      '{"access_token":"tok123","refresh_token":"rt456"}',
    );
    expect(s, isNot(contains('abc123')));
    expect(s, isNot(contains('XYZ')));
    expect(s, isNot(contains('170000')));
    expect(s, isNot(contains('=99')));
    expect(s, isNot(contains('tok123')));
    expect(s, isNot(contains('rt456')));
    expect(s, contains('SESSDATA=***'));
  });

  test('mid / uid', () {
    expect(sanitizeLogLine('mid=12345 uid: 678'), 'mid=*** uid: ***');
  });

  test('csrf / w_rid / access_key', () {
    expect(
      sanitizeLogLine('csrf=aaa w_rid=bbb access_key=ccc ok'),
      'csrf=*** w_rid=*** access_key=*** ok',
    );
  });

  test('URL 去掉 query', () {
    expect(
      sanitizeLogLine(
        'GET https://api.bilibili.com/x/web?keyword=secret&mid=1 failed',
      ),
      'GET https://api.bilibili.com/x/web failed',
    );
  });

  test('IPv4', () {
    expect(
      sanitizeLogLine('connect 192.168.1.20:8080'),
      'connect x.x.x.x:8080',
    );
  });

  test('searchVideos 只留狀態碼', () {
    expect(
      sanitizeLogLine('searchVideos: HTTP 412 keyword=foo'),
      'searchVideos: HTTP 412',
    );
    expect(
      sanitizeLogLine('searchVideos error: foo bar'),
      'searchVideos: (內容已省略)',
    );
  });

  test('一般行不變', () {
    const line = 'Player init ok codec=avc 1920x1080 version v1.2.2-btr.2';
    expect(sanitizeLogLine(line), line);
  });
}
