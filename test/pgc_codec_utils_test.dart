import 'package:bili_tv_app/services/api/pgc_api.dart';
import 'package:bili_tv_app/services/codec_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseBangumiUrl', () {
    test('ss 網址解析出 seasonId', () {
      final r = PgcApi.parseBangumiUrl(
        'https://www.bilibili.com/bangumi/play/ss33577',
      );
      expect(r, isNotNull);
      expect(r!.seasonId, 33577);
      expect(r.epId, 0);
    });

    test('ep 網址解析出 epId', () {
      final r = PgcApi.parseBangumiUrl(
        'https://www.bilibili.com/bangumi/play/ep326317?foo=1',
      );
      expect(r, isNotNull);
      expect(r!.seasonId, 0);
      expect(r.epId, 326317);
    });

    test('無關網址回傳 null', () {
      expect(
        PgcApi.parseBangumiUrl('https://www.bilibili.com/video/BV1xx411c7mD'),
        isNull,
      );
    });

    test('空字串回傳 null', () {
      expect(PgcApi.parseBangumiUrl(''), isNull);
    });
  });

  group('codecFamily', () {
    test('各編碼家族', () {
      expect(CodecService.codecFamily('avc1.640032'), 'avc');
      expect(CodecService.codecFamily('hev1.1.6.L150.90'), 'hevc');
      expect(CodecService.codecFamily('hvc1.1.6.L150.90'), 'hevc');
      expect(CodecService.codecFamily('hvc1'), 'hevc');
      expect(CodecService.codecFamily('dvh1.05.06'), 'hevc');
      expect(CodecService.codecFamily('av01.0.13M.08'), 'av1');
    });

    test('非視訊編碼回傳 null', () {
      expect(CodecService.codecFamily('mp4a.40.2'), isNull);
    });
  });

  group('parseFps', () {
    test('小數字串', () {
      expect(CodecService.parseFps('29.970'), closeTo(29.97, 1e-9));
    });

    test('分數字串', () {
      expect(CodecService.parseFps('30000/1001'), closeTo(29.97, 0.001));
    });

    test('空字串、null、無法解析回 0', () {
      expect(CodecService.parseFps(''), 0);
      expect(CodecService.parseFps(null), 0);
      expect(CodecService.parseFps('abc'), 0);
    });

    test('數字', () {
      expect(CodecService.parseFps(25), 25);
    });
  });
}
