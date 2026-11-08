import 'package:bili_tv_app/models/space_data.dart';
import 'package:bili_tv_app/models/video.dart';
import 'package:bili_tv_app/services/api/video_api.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _archiveItem({
  String type = 'DYNAMIC_TYPE_AV',
  String bvid = 'BV1xx',
}) => {
  'visible': true,
  'type': type,
  'modules': {
    'module_author': {
      'name': 'UP',
      'face': '//i0.hdslb.com/face.jpg',
      'mid': 123,
      'pub_ts': 1700000000,
    },
    'module_dynamic': {
      'major': {
        'type': 'MAJOR_TYPE_ARCHIVE',
        'archive': {
          'bvid': bvid,
          'title': '標題',
          'cover': '//i0.hdslb.com/cover.jpg',
          'duration_text': '01:30',
          'stat': {'play': 12000, 'danmaku': '34'},
          'badge': {'text': '充電專屬'},
        },
      },
    },
  },
};

void main() {
  group('Video.fromSpaceApp', () {
    test('解析欄位', () {
      final v = Video.fromSpaceApp({
        'bvid': 'BV1abc',
        'title': 't',
        'cover': '//x/y.jpg',
        'author': 'a',
        'play': 1000,
        'danmaku': 5,
        'duration': 90,
        'ctime': 1700000000,
      }, ownerMid: 9);
      expect(v.bvid, 'BV1abc');
      expect(v.pic, 'https://x/y.jpg');
      expect(v.ownerName, 'a');
      expect(v.ownerMid, 9);
      expect(v.view, 1000);
      expect(v.danmaku, 5);
      expect(v.duration, 90);
      expect(v.pubdate, 1700000000);
    });
  });

  group('SpaceData.fromJson', () {
    final json = <String, dynamic>{
      'card': {
        'name': 'N',
        'face': 'F',
        'sign': 'S',
        'fans': 100,
        'attention': 5,
        'likes': {'like_num': 42},
      },
      'tab2': [
        {'param': 'home', 'title': '主頁'},
        {'param': 'dynamic'},
        {'param': 'contribute'},
        {'param': 'bangumi'},
      ],
      'default_tab': 'video',
      'archive': {
        'count': 2,
        'item': [
          {'bvid': 'BV1', 'title': 'a', 'cover': 'c', 'duration': 10},
          {'bvid': '', 'title': 'skip'},
        ],
      },
      'series': {
        'item': [
          {'series_id': 7, 'name': '系列'},
        ],
      },
      'ugc_season': {
        'item': [
          {'season_id': 3, 'title': '合集', 'cover': '//c/1.jpg', 'count': 8},
        ],
      },
      'season': {
        'item': [
          {'title': '番', 'cover': 'c', 'param': '555', 'newest_ep_index': '12'},
          {'title': '壞', 'param': 'abc'},
        ],
      },
      'coin_archive': {
        'item': [
          {'bvid': 'BV2', 'title': 'coin'},
        ],
      },
    };

    test('完整資料', () {
      final d = SpaceData.fromJson(json);
      expect(d.name, 'N');
      expect(d.fans, 100);
      expect(d.following, 5);
      expect(d.likes, 42);
      expect(d.tabs, ['home', 'dynamic', 'contribute']);
      expect(d.defaultTab, 'contribute');
      expect(d.archive.length, 1);
      expect(d.archiveCount, 2);
      expect(d.seasons.single.id, 3);
      expect(d.seasons.single.cover, 'https://c/1.jpg');
      expect(d.seasons.single.isSeries, isFalse);
      expect(d.series.single.id, 7);
      expect(d.series.single.isSeries, isTrue);
      expect(d.coins.single.bvid, 'BV2');
      expect(d.likesArchive, isEmpty);
      expect(d.bangumi.length, 1);
      expect(d.bangumi.single.seasonId, 555);
      expect(d.bangumi.single.isPgc, isTrue);
      expect(d.bangumi.single.epIndexText, '12');
    });

    test('最小資料不拋例外', () {
      final d = SpaceData.fromJson({});
      expect(d.tabs, isEmpty);
      expect(d.defaultTab, 'contribute');
      expect(d.hasHomeContent, isFalse);
    });

    test('default_tab 不在 tab2 時取第一個', () {
      final d = SpaceData.fromJson({
        'tab2': [
          {'param': 'dynamic'},
          {'param': 'contribute'},
        ],
        'default_tab': 'home',
      });
      expect(d.defaultTab, 'dynamic');
    });
  });

  group('VideoApi.archiveFromDynamicItem', () {
    test('一般影片動態', () {
      final v = VideoApi.archiveFromDynamicItem(_archiveItem());
      expect(v, isNotNull);
      expect(v!.bvid, 'BV1xx');
      expect(v.pic, 'https://i0.hdslb.com/cover.jpg');
      expect(v.ownerMid, 123);
      expect(v.view, 12000);
      expect(v.duration, 90);
      expect(v.badge, '充電專屬');
    });

    test('轉發取 orig 內的影片', () {
      final forward = {
        'visible': true,
        'type': 'DYNAMIC_TYPE_FORWARD',
        'modules': {
          'module_author': {'name': 'forwarder'},
          'module_dynamic': {
            'major': {'type': 'MAJOR_TYPE_NONE'},
          },
        },
        'orig': _archiveItem(bvid: 'BVorig'),
      };
      final v = VideoApi.archiveFromDynamicItem(forward);
      expect(v?.bvid, 'BVorig');
      expect(v?.ownerName, 'UP');
      expect(
        VideoApi.archiveFromDynamicItem(forward, includeForward: false),
        isNull,
      );
    });

    test('非影片或不可見回傳 null', () {
      final text = _archiveItem();
      (((text['modules'] as Map)['module_dynamic'] as Map)['major']
              as Map)['type'] =
          'MAJOR_TYPE_OPUS';
      expect(VideoApi.archiveFromDynamicItem(text), isNull);

      final hidden = _archiveItem()..['visible'] = false;
      expect(VideoApi.archiveFromDynamicItem(hidden), isNull);
    });
  });
}
