import 'package:bili_tv_app/utils/fav_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bvidToAid', () {
    test('已知對照', () {
      expect(bvidToAid('BV17x411w7KC'), 170001);
      expect(bvidToAid('BV1xx411c7mD'), 2);
    });
    test('格式錯誤回傳 0', () {
      expect(bvidToAid(''), 0);
      expect(bvidToAid('BV1'), 0);
      expect(bvidToAid('AV17x411w7KC'), 0);
      expect(bvidToAid('BV1!x411w7KC'), 0);
    });
  });

  group('buildHistoryKid', () {
    test('archive 用 oid', () {
      expect(
        buildHistoryKid(business: 'archive', oid: 123, kid: 123),
        'archive_123',
      );
    });
    test('pgc 用 season_id', () {
      expect(buildHistoryKid(business: 'pgc', oid: 999, kid: 42), 'pgc_42');
    });
    test('live 用 oid', () {
      expect(buildHistoryKid(business: 'live', oid: 77, kid: 0), 'live_77');
    });
    test('缺值回傳空字串', () {
      expect(buildHistoryKid(business: '', oid: 1, kid: 1), '');
      expect(buildHistoryKid(business: 'archive', oid: 0, kid: 5), '');
      expect(buildHistoryKid(business: 'pgc', oid: 5, kid: 0), '');
    });
  });

  group('diffFavFolders', () {
    test('新增與移除', () {
      final d = diffFavFolders({1, 2, 3}, {2, 3, 5, 4});
      expect(d.add, [4, 5]);
      expect(d.del, [1]);
    });
    test('無變更', () {
      final d = diffFavFolders({1, 2}, {1, 2});
      expect(d.add, isEmpty);
      expect(d.del, isEmpty);
    });
    test('全部取消', () {
      final d = diffFavFolders({7, 8}, {});
      expect(d.add, isEmpty);
      expect(joinIds(d.del), '7,8');
    });
  });
}
