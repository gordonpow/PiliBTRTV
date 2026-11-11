import 'package:flutter_test/flutter_test.dart';
import 'package:bili_tv_app/utils/seek_speed.dart';

void main() {
  const short = Duration(minutes: 10);
  const long = Duration(hours: 3); // 10800 秒 / 20 = 540

  test('前 1 秒為 30', () {
    expect(holdSeekSpeed(Duration.zero, short), 30);
    expect(holdSeekSpeed(const Duration(milliseconds: 999), short), 30);
  });

  test('1～3 秒為 90', () {
    expect(holdSeekSpeed(const Duration(seconds: 1), short), 90);
    expect(holdSeekSpeed(const Duration(milliseconds: 2999), short), 90);
  });

  test('3 秒後短片為 180', () {
    expect(holdSeekSpeed(const Duration(seconds: 3), short), 180);
    expect(holdSeekSpeed(const Duration(seconds: 10), Duration.zero), 180);
  });

  test('3 秒後長片為片長 / 20', () {
    expect(holdSeekSpeed(const Duration(seconds: 5), long), 540);
  });
}
