import 'package:bili_tv_app/services/device_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---- 既有測試（保持不變）----
  test('isLowMemory 邊界', () {
    expect(DeviceProfile.isLowMemory(), false);
    expect(DeviceProfile.isLowMemory(totalMemMb: null), false);
    expect(DeviceProfile.isLowMemory(totalMemMb: 0), false);
    expect(DeviceProfile.isLowMemory(totalMemMb: 1), true);
    expect(DeviceProfile.isLowMemory(totalMemMb: 2304), true);
    expect(DeviceProfile.isLowMemory(totalMemMb: 2305), false);
    expect(DeviceProfile.isLowMemory(isLowRam: true, totalMemMb: 4096), true);
    expect(DeviceProfile.isLowMemory(isLowRam: false, totalMemMb: 4096), false);
  });

  // ---- tierFor 純函式測試 ----
  group('tierFor', () {
    test('isLowRam 一律 low', () {
      expect(
        DeviceProfile.tierFor(totalMemMb: 8192, isLowRam: true),
        MemoryTier.low,
      );
    });

    test('totalMemMb <= 2304 → low', () {
      expect(
        DeviceProfile.tierFor(totalMemMb: 1, isLowRam: false),
        MemoryTier.low,
      );
      expect(
        DeviceProfile.tierFor(totalMemMb: 2304, isLowRam: false),
        MemoryTier.low,
      );
    });

    test('totalMemMb 2305~4096 → mid', () {
      expect(
        DeviceProfile.tierFor(totalMemMb: 2305, isLowRam: false),
        MemoryTier.mid,
      );
      expect(
        DeviceProfile.tierFor(totalMemMb: 4096, isLowRam: false),
        MemoryTier.mid,
      );
    });

    test('totalMemMb > 4096 → high', () {
      expect(
        DeviceProfile.tierFor(totalMemMb: 4097, isLowRam: false),
        MemoryTier.high,
      );
      expect(
        DeviceProfile.tierFor(totalMemMb: 8192, isLowRam: false),
        MemoryTier.high,
      );
    });

    test('totalMemMb == 0（查詢失敗）→ mid', () {
      expect(
        DeviceProfile.tierFor(totalMemMb: 0, isLowRam: false),
        MemoryTier.mid,
      );
    });
  });

  // ---- isCritical 純函式測試 ----
  group('isCritical', () {
    test('系統回報 lowMemory=true → critical', () {
      expect(
        DeviceProfile.isCritical(
          availMb: 500,
          thresholdMb: 100,
          lowMemory: true,
        ),
        true,
      );
    });

    test('availMb < threshold * 1.5 → critical', () {
      // threshold=200，1.5倍=300，avail=200 < 300 → critical
      expect(
        DeviceProfile.isCritical(
          availMb: 200,
          thresholdMb: 200,
          lowMemory: false,
        ),
        true,
      );
    });

    test('availMb < 300 即使 threshold * 1.5 < 300 → critical', () {
      // threshold=100，1.5倍=150 < 300，所以下限是 300；avail=250 < 300 → critical
      expect(
        DeviceProfile.isCritical(
          availMb: 250,
          thresholdMb: 100,
          lowMemory: false,
        ),
        true,
      );
    });

    test('availMb 恰好等於 max(threshold*1.5, 300) → 不 critical', () {
      // threshold=200，max(300, 300)=300，avail=300 → 不 critical（< 才是）
      expect(
        DeviceProfile.isCritical(
          availMb: 300,
          thresholdMb: 200,
          lowMemory: false,
        ),
        false,
      );
    });

    test('availMb 充足 → 不 critical', () {
      expect(
        DeviceProfile.isCritical(
          availMb: 1000,
          thresholdMb: 200,
          lowMemory: false,
        ),
        false,
      );
    });
  });

  // ---- 離開 critical 需連續兩次才恢復 ----
  group('monitor 離開 critical 計數', () {
    setUp(() {
      // 重置所有監控狀態（含 _exitCount、計時器、等級）
      DeviceProfile.resetForTest();
    });

    test('onMemoryPressure 立即進入 critical', () {
      DeviceProfile.onMemoryPressure();
      expect(DeviceProfile.currentTier, MemoryTier.critical);
    });

    test('注入查詢：一次恢復不夠，兩次才離開 critical', () async {
      // 先進入 critical
      DeviceProfile.onMemoryPressure();
      expect(DeviceProfile.currentTier, MemoryTier.critical);

      // 注入「健康」的查詢結果
      Future<Map<String, dynamic>> healthyQuery() async => <String, dynamic>{
        'availMemMb': 1000,
        'thresholdMb': 100,
        'lowMemory': false,
      };

      // 第一次恢復查詢：還在 critical（需要連續兩次）
      await DeviceProfile.queryAndUpdateForTest(healthyQuery);
      expect(DeviceProfile.currentTier, MemoryTier.critical);

      // 第二次恢復查詢：離開 critical，回到 staticTier（mid）
      await DeviceProfile.queryAndUpdateForTest(healthyQuery);
      expect(DeviceProfile.currentTier, MemoryTier.mid);
    });

    test('注入查詢：critical 中途再次觸發，重置離開計數', () async {
      DeviceProfile.onMemoryPressure();

      Future<Map<String, dynamic>> healthyQuery() async => <String, dynamic>{
        'availMemMb': 1000,
        'thresholdMb': 100,
        'lowMemory': false,
      };
      Future<Map<String, dynamic>> criticalQuery() async => <String, dynamic>{
        'availMemMb': 50,
        'thresholdMb': 100,
        'lowMemory': true,
      };

      // 第一次健康查詢
      await DeviceProfile.queryAndUpdateForTest(healthyQuery);
      expect(DeviceProfile.currentTier, MemoryTier.critical);

      // 中途再次 critical → 重置計數
      await DeviceProfile.queryAndUpdateForTest(criticalQuery);
      expect(DeviceProfile.currentTier, MemoryTier.critical);

      // 重新需要兩次健康查詢才能離開
      await DeviceProfile.queryAndUpdateForTest(healthyQuery);
      expect(DeviceProfile.currentTier, MemoryTier.critical);
      await DeviceProfile.queryAndUpdateForTest(healthyQuery);
      expect(DeviceProfile.currentTier, MemoryTier.mid);
    });
  });
}
