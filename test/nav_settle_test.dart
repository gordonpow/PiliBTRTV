import 'package:bili_tv_app/services/device_profile.dart';
import 'package:bili_tv_app/utils/nav_settle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final s = NavSettle.instance;
  final t0 = DateTime(2026, 1, 1);
  Duration ms(int n) => Duration(milliseconds: n);

  setUp(() {
    s.resetForTest();
    DeviceProfile.lowMemory = false;
  });
  tearDown(() => DeviceProfile.lowMemory = false);

  test('單次、快速、連續', () {
    expect(s.onFocusArrived(now: t0), ms(150));
    expect(s.onFocusArrived(now: t0.add(ms(200))), ms(250));
    expect(s.onFocusArrived(now: t0.add(ms(400))), ms(500));
  });

  test('超過 2 秒不算連續', () {
    expect(s.onFocusArrived(now: t0), ms(150));
    expect(s.onFocusArrived(now: t0.add(ms(1000))), ms(150));
    expect(s.onFocusArrived(now: t0.add(ms(2500))), ms(150));
  });

  test('低記憶體裝置', () {
    DeviceProfile.lowMemory = true;
    expect(s.onFocusArrived(now: t0), ms(300));
    expect(s.onFocusArrived(now: t0.add(ms(200))), ms(300));
    expect(s.onFocusArrived(now: t0.add(ms(400))), ms(600));
  });
}
