import 'device_profile.dart';

/// 各記憶體等級的快取與預載預算（集中定義，避免散落各處）。
///
/// 規格表格（T-2 記憶體分級 #27）：
/// | tier     | 圖片快取張數 | 圖片快取 MB | _bgMax | _cacheMax | 暖機 | 預解析 |
/// |----------|------------|------------|--------|-----------|------|--------|
/// | high     | 500        | 200        | 4      | 30        | 開   | 開     |
/// | mid      | 300        | 120        | 3      | 20        | 開   | 開     |
/// | low      | 150        | 64         | 2      | 10        | 開   | 開     |
/// | critical | 80         | 32         | 0      | 5         | 關   | 關     |
class MemoryBudget {
  MemoryBudget._();

  /// 圖片快取最大張數
  static int imageCacheCount(MemoryTier tier) {
    return switch (tier) {
      MemoryTier.high => 500,
      MemoryTier.mid => 300,
      MemoryTier.low => 150,
      MemoryTier.critical => 80,
    };
  }

  /// 圖片快取最大位元組數
  static int imageCacheBytes(MemoryTier tier) {
    return switch (tier) {
      MemoryTier.high => 200 << 20,
      MemoryTier.mid => 120 << 20,
      MemoryTier.low => 64 << 20,
      MemoryTier.critical => 32 << 20,
    };
  }

  /// 鄰近卡片預解析最大數量（0 = 停用）
  static int bgMax(MemoryTier tier) {
    return switch (tier) {
      MemoryTier.high => 4,
      MemoryTier.mid => 3,
      MemoryTier.low => 2,
      MemoryTier.critical => 0,
    };
  }

  /// prefetch 播放網址快取最大筆數
  static int cacheMax(MemoryTier tier) {
    return switch (tier) {
      MemoryTier.high => 30,
      MemoryTier.mid => 20,
      MemoryTier.low => 10,
      MemoryTier.critical => 5,
    };
  }

  /// critical 時是否停用暖機播放器
  static bool disableWarm(MemoryTier tier) => tier == MemoryTier.critical;

  /// critical 時是否停用鄰近預解析
  static bool disablePreResolve(MemoryTier tier) => tier == MemoryTier.critical;
}
