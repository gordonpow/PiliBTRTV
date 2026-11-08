import 'package:flutter_test/flutter_test.dart';
import 'package:bili_tv_app/models/videoshot.dart';

void main() {
  group('VideoshotData 幀索引與時間演算法測試', () {
    late VideoshotData sampleData;
    // B站 pvdata 前兩個值通常為 0
    final sampleTimestamps = [0, 0, 10, 20, 30, 45, 60];

    setUp(() {
      sampleData = VideoshotData(
        images: [
          'https://i0.hdslb.com/bfs/videoshot/1.jpg',
          'https://i0.hdslb.com/bfs/videoshot/2.jpg',
        ],
        imgXLen: 10,
        imgYLen: 10,
        imgXSize: 160,
        imgYSize: 90,
      );
      sampleData.setTimestamps(sampleTimestamps);
    });

    test('frameCount: 有時間戳與無時間戳的幀數計算', () {
      // 有時間戳時為 ts.length - 1
      expect(sampleData.frameCount, sampleTimestamps.length - 1);

      // 無時間戳時為 images.length * framesPerImage
      final dataWithoutTs = VideoshotData(
        images: ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
        imgXLen: 10,
        imgYLen: 10,
        imgXSize: 160,
        imgYSize: 90,
      );
      expect(dataWithoutTs.frameCount, 200);

      // 空圖片清單時為 0
      final emptyData = VideoshotData(
        images: [],
        imgXLen: 10,
        imgYLen: 10,
        imgXSize: 160,
        imgYSize: 90,
      );
      expect(emptyData.frameCount, 0);
    });

    test('indexAt: 依時間戳搜尋索引（含「減 1」邏輯與邊界）', () {
      // 0 秒對應索引 0
      expect(sampleData.indexAt(Duration.zero), 0);

      // 5 秒落於 [0, 10)，對應索引 0
      expect(sampleData.indexAt(const Duration(seconds: 5)), 0);

      // 10 秒落於 [10, 20)，對應索引 1
      expect(sampleData.indexAt(const Duration(seconds: 10)), 1);
      expect(sampleData.indexAt(const Duration(seconds: 19)), 1);

      // 20 秒落於 [20, 30)，對應索引 2
      expect(sampleData.indexAt(const Duration(seconds: 20)), 2);

      // 超出時間戳範圍：回傳 ts.length - 2
      expect(sampleData.indexAt(const Duration(seconds: 100)), 5);

      // 無時間戳時回傳 0
      final noTsData = VideoshotData(
        images: ['https://example.com/1.jpg'],
        imgXLen: 10,
        imgYLen: 10,
        imgXSize: 160,
        imgYSize: 90,
      );
      expect(noTsData.indexAt(const Duration(seconds: 10)), 0);
    });

    test('timeOfIndex: 依索引換算時間（含合法夾取與邊界處理）', () {
      const total = Duration(seconds: 60);

      // k = 0 對應 ts[1] = 0 秒
      expect(sampleData.timeOfIndex(0, total), Duration.zero);

      // k = 1 對應 ts[2] = 10 秒
      expect(sampleData.timeOfIndex(1, total), const Duration(seconds: 10));

      // k = 2 對應 ts[3] = 20 秒
      expect(sampleData.timeOfIndex(2, total), const Duration(seconds: 20));

      // k = 5 對應 ts[6] = 60 秒
      expect(sampleData.timeOfIndex(5, total), const Duration(seconds: 60));

      // 邊界：k < 0 時夾在 0
      expect(sampleData.timeOfIndex(-1, total), Duration.zero);
      expect(sampleData.timeOfIndex(-10, total), Duration.zero);

      // 邊界：k >= frameCount 時夾在 frameCount - 1 (索引 5)
      expect(sampleData.timeOfIndex(6, total), const Duration(seconds: 60));
      expect(sampleData.timeOfIndex(100, total), const Duration(seconds: 60));

      // 邊界：total 為 0 或負值時回傳 Duration.zero (審查紀錄 1)
      expect(sampleData.timeOfIndex(2, Duration.zero), Duration.zero);
      expect(
        sampleData.timeOfIndex(2, const Duration(seconds: -5)),
        Duration.zero,
      );

      // 邊界：無時間戳時依均勻分佈換算
      final noTsData = VideoshotData(
        images: ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
        imgXLen: 10,
        imgYLen: 10,
        imgXSize: 160,
        imgYSize: 90,
      );
      // frameCount = 200, total = 1000s
      const noTsTotal = Duration(seconds: 1000);
      expect(noTsData.timeOfIndex(0, noTsTotal), Duration.zero);
      expect(
        noTsData.timeOfIndex(100, noTsTotal),
        const Duration(seconds: 500),
      );
      expect(noTsData.timeOfIndex(-5, noTsTotal), Duration.zero);
    });

    test('frameAtIndex: 座標與圖片切換計算（含邊界 null 回傳）', () {
      // k = 0: 第一張大圖，(0, 0)
      final f0 = sampleData.frameAtIndex(0);
      expect(f0, isNotNull);
      expect(f0!.imageUrl, 'https://i0.hdslb.com/bfs/videoshot/1.jpg');
      expect(f0.x, 0);
      expect(f0.y, 0);
      expect(f0.width, 160);
      expect(f0.height, 90);

      // k = 1: (160, 0)
      final f1 = sampleData.frameAtIndex(1);
      expect(f1, isNotNull);
      expect(f1!.x, 160);
      expect(f1.y, 0);

      // 邊界：k < 0 回傳 null (審查紀錄 1)
      expect(sampleData.frameAtIndex(-1), isNull);
      expect(sampleData.frameAtIndex(-99), isNull);

      // 邊界：k >= frameCount 回傳 null (審查紀錄 1)
      expect(sampleData.frameAtIndex(sampleData.frameCount), isNull);
      expect(sampleData.frameAtIndex(sampleData.frameCount + 10), isNull);

      // 跨大圖切換測試 (使用較多幀的大圖模型)
      final largeData = VideoshotData(
        images: [
          'https://i0.hdslb.com/bfs/videoshot/1.jpg',
          'https://i0.hdslb.com/bfs/videoshot/2.jpg',
        ],
        imgXLen: 10,
        imgYLen: 10,
        imgXSize: 160,
        imgYSize: 90,
      );
      // framesPerImage = 100
      final f105 = largeData.frameAtIndex(105);
      expect(f105, isNotNull);
      expect(f105!.imageUrl, 'https://i0.hdslb.com/bfs/videoshot/2.jpg');
      expect(f105.x, 5 * 160);
      expect(f105.y, 0);
    });

    test('getFrameAt: 委派給 frameAtIndex(indexAt(pos))', () {
      final fromGetFrameAt = sampleData.getFrameAt(const Duration(seconds: 15));
      final k = sampleData.indexAt(const Duration(seconds: 15));
      final fromFrameAtIndex = sampleData.frameAtIndex(k);

      expect(fromGetFrameAt, isNotNull);
      expect(fromFrameAtIndex, isNotNull);
      expect(fromGetFrameAt!.imageUrl, fromFrameAtIndex!.imageUrl);
      expect(fromGetFrameAt.x, fromFrameAtIndex.x);
      expect(fromGetFrameAt.y, fromFrameAtIndex.y);
    });
    test('無時間戳時 indexAt 依影片長度換算，可逐幀前進', () {
      final data = VideoshotData(
        images: ['https://example.com/1.jpg'],
        imgXLen: 10,
        imgYLen: 10,
        imgXSize: 160,
        imgYSize: 90,
      );
      const total = Duration(seconds: 1000);
      expect(data.indexAt(Duration.zero, total), 0);
      for (var k = 0; k < 5; k++) {
        final t = data.timeOfIndex(k + 1, total);
        expect(data.indexAt(t, total), k + 1);
      }
      expect(data.indexAt(total, total), data.frameCount - 1);
      expect(data.indexAt(const Duration(seconds: 10)), 0); // 未提供長度
    });
  });
}
