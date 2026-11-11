import 'package:flutter_test/flutter_test.dart';
import 'package:bili_tv_app/services/api/playback_api.dart';
import 'package:bili_tv_app/services/resume_resolver.dart';

void main() {
  group('parsePlayerProgress', () {
    test('毫秒轉秒', () {
      final r = PlaybackApi.parsePlayerProgress({
        'code': 0,
        'data': {'last_play_time': 123456, 'last_play_cid': 99},
      });
      expect(r, (cid: 99, seconds: 123));
    });

    test('0 毫秒回 0 秒', () {
      final r = PlaybackApi.parsePlayerProgress({
        'code': 0,
        'data': {'last_play_time': 0, 'last_play_cid': 5},
      });
      expect(r, (cid: 5, seconds: 0));
    });

    test('code 非 0 回 null', () {
      expect(
        PlaybackApi.parsePlayerProgress({
          'code': -400,
          'data': {'last_play_time': 1000, 'last_play_cid': 1},
        }),
        isNull,
      );
    });

    test('缺欄位回 null', () {
      expect(
        PlaybackApi.parsePlayerProgress({
          'code': 0,
          'data': {'last_play_cid': 1},
        }),
        isNull,
      );
      expect(PlaybackApi.parsePlayerProgress({'code': 0}), isNull);
    });
  });

  group('ResumeResolver', () {
    test('伺服器 cid 相符即採用，含 0 秒', () {
      final r = ResumeResolver.resolve(
        resolvedCid: 1,
        serverCid: 1,
        serverSeconds: 0,
        cacheCid: 1,
        cacheProgress: 100,
        cacheSavedAt: 500,
      );
      expect(r, (seconds: 0, source: 'server'));
    });

    test('伺服器 cid 不符退回快取', () {
      final r = ResumeResolver.resolve(
        resolvedCid: 1,
        serverCid: 2,
        serverSeconds: 50,
        cacheCid: 1,
        cacheProgress: 100,
        cacheSavedAt: 500,
      );
      expect(r, (seconds: 100, source: 'cache'));
    });

    test('快取與列表取較新', () {
      final listNewer = ResumeResolver.resolve(
        resolvedCid: 1,
        cacheCid: 1,
        cacheProgress: 100,
        cacheSavedAt: 500,
        listProgress: 30,
        listViewAt: 900,
      );
      expect(listNewer, (seconds: 30, source: 'list'));
      final cacheNewer = ResumeResolver.resolve(
        resolvedCid: 1,
        cacheCid: 1,
        cacheProgress: 100,
        cacheSavedAt: 1000,
        listProgress: 30,
        listViewAt: 900,
      );
      expect(cacheNewer, (seconds: 100, source: 'cache'));
    });

    test('只有一邊有時間就用那一邊', () {
      final r = ResumeResolver.resolve(
        resolvedCid: 1,
        cacheCid: 1,
        cacheProgress: 100,
        cacheSavedAt: 0,
        listProgress: 30,
        listViewAt: 900,
      );
      expect(r.source, 'list');
      final r2 = ResumeResolver.resolve(
        resolvedCid: 1,
        cacheCid: 1,
        cacheProgress: 100,
        cacheSavedAt: 500,
        listProgress: 30,
        listViewAt: 0,
      );
      expect(r2.source, 'cache');
    });

    test('只有列表 -1 時為 none；快取 cid 不符忽略', () {
      final r = ResumeResolver.resolve(
        resolvedCid: 1,
        cacheCid: 2,
        cacheProgress: 100,
        cacheSavedAt: 500,
        listProgress: -1,
        listViewAt: 900,
      );
      expect(r, (seconds: 0, source: 'none'));
    });

    test('列表 -1（他處看完）比快取新：從 0 開始', () {
      final r = ResumeResolver.resolve(
        resolvedCid: 1,
        cacheCid: 1,
        cacheProgress: 100,
        cacheSavedAt: 500,
        listProgress: -1,
        listViewAt: 900,
      );
      expect(r, (seconds: 0, source: 'list'));
      final older = ResumeResolver.resolve(
        resolvedCid: 1,
        cacheCid: 1,
        cacheProgress: 100,
        cacheSavedAt: 1000,
        listProgress: -1,
        listViewAt: 900,
      );
      expect(older, (seconds: 100, source: 'cache'));
    });

    test('只有列表時用列表', () {
      final r = ResumeResolver.resolve(
        resolvedCid: 1,
        listProgress: 42,
        listViewAt: 10,
      );
      expect(r, (seconds: 42, source: 'list'));
    });
  });
}
