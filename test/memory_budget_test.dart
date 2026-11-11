import 'package:bili_tv_app/services/device_profile.dart';
import 'package:bili_tv_app/services/memory_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemoryBudget 預算表', () {
    test('imageCacheCount 各等級', () {
      expect(MemoryBudget.imageCacheCount(MemoryTier.high), 500);
      expect(MemoryBudget.imageCacheCount(MemoryTier.mid), 300);
      expect(MemoryBudget.imageCacheCount(MemoryTier.low), 150);
      expect(MemoryBudget.imageCacheCount(MemoryTier.critical), 80);
    });

    test('imageCacheBytes 各等級（MB 換算）', () {
      expect(MemoryBudget.imageCacheBytes(MemoryTier.high), 200 << 20);
      expect(MemoryBudget.imageCacheBytes(MemoryTier.mid), 120 << 20);
      expect(MemoryBudget.imageCacheBytes(MemoryTier.low), 64 << 20);
      expect(MemoryBudget.imageCacheBytes(MemoryTier.critical), 32 << 20);
    });

    test('bgMax 各等級（critical = 0）', () {
      expect(MemoryBudget.bgMax(MemoryTier.high), 4);
      expect(MemoryBudget.bgMax(MemoryTier.mid), 3);
      expect(MemoryBudget.bgMax(MemoryTier.low), 2);
      expect(MemoryBudget.bgMax(MemoryTier.critical), 0);
    });

    test('cacheMax 各等級', () {
      expect(MemoryBudget.cacheMax(MemoryTier.high), 30);
      expect(MemoryBudget.cacheMax(MemoryTier.mid), 20);
      expect(MemoryBudget.cacheMax(MemoryTier.low), 10);
      expect(MemoryBudget.cacheMax(MemoryTier.critical), 5);
    });

    test('disableWarm 只有 critical 為 true', () {
      expect(MemoryBudget.disableWarm(MemoryTier.critical), true);
      expect(MemoryBudget.disableWarm(MemoryTier.low), false);
      expect(MemoryBudget.disableWarm(MemoryTier.mid), false);
      expect(MemoryBudget.disableWarm(MemoryTier.high), false);
    });

    test('disablePreResolve 只有 critical 為 true', () {
      expect(MemoryBudget.disablePreResolve(MemoryTier.critical), true);
      expect(MemoryBudget.disablePreResolve(MemoryTier.low), false);
      expect(MemoryBudget.disablePreResolve(MemoryTier.mid), false);
      expect(MemoryBudget.disablePreResolve(MemoryTier.high), false);
    });
  });
}
