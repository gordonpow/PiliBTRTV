import 'package:bili_tv_app/models/video.dart';
import 'package:bili_tv_app/services/play_session_history.dart';
import 'package:bili_tv_app/utils/ugc_season_utils.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _ep(String bvid, int cid, {Map<String, dynamic>? arc}) => {
  'bvid': bvid,
  'aid': cid + 1000,
  'cid': cid,
  'title': 't-$bvid',
  'arc':
      arc ?? {'pic': '//i0.hdslb.com/$bvid.jpg', 'duration': 60, 'pubdate': 9},
};

Map<String, dynamic> _info() => {
  'owner': {'mid': 7, 'name': '主', 'face': 'f'},
  'ugc_season': {
    'sections': [
      {
        'episodes': [_ep('BV1', 1), _ep('BV2', 2)],
      },
      {
        'episodes': [
          _ep(
            'BV3',
            3,
            arc: {
              'pic': 'p3',
              'author': {'mid': 8, 'name': '別人', 'face': 'x'},
              'stat': {'view': 5, 'danmaku': 6},
            },
          ),
        ],
      },
    ],
  },
};

void main() {
  group('flattenUgcSeason', () {
    test('依段落與段落內順序攤平，並找出目前位置', () {
      final r = flattenUgcSeason(_info(), 'BV2');
      expect(r.videos.map((v) => v.bvid), ['BV1', 'BV2', 'BV3']);
      expect(r.index, 1);
      expect(r.videos[2].cid, 3);
      expect(r.videos[0].aid, 1001);
    });

    test('欄位：pic 補 https、duration、owner 後備、arc.author', () {
      final r = flattenUgcSeason(_info(), 'BV1');
      expect(r.videos[0].pic, 'https://i0.hdslb.com/BV1.jpg');
      expect(r.videos[0].duration, 60);
      expect(r.videos[0].ownerName, '主'); // 取目前影片的 owner
      expect(r.videos[0].ownerMid, 7);
      expect(r.videos[2].ownerName, '別人'); // arc.author
      expect(r.videos[2].view, 5);
      expect(r.videos[2].danmaku, 6);
    });

    test('沒有 ugc_season、沒有 sections 時為空', () {
      expect(flattenUgcSeason({'title': 'x'}, 'BV1').videos, isEmpty);
      expect(flattenUgcSeason(null, 'BV1').index, -1);
      expect(
        flattenUgcSeason({
          'ugc_season': {'sections': []},
        }, 'BV1').videos,
        isEmpty,
      );
      expect(flattenUgcSeason({'ugc_season': {}}, 'BV1').videos, isEmpty);
    });

    test('找不到目前 bvid 時為空', () {
      final r = flattenUgcSeason(_info(), 'BVX');
      expect(r.videos, isEmpty);
      expect(r.index, -1);
    });

    test('略過沒有 bvid 的項目', () {
      final info = {
        'ugc_season': {
          'sections': [
            {
              'episodes': [
                {'cid': 1},
                _ep('BV1', 1),
              ],
            },
          ],
        },
      };
      final r = flattenUgcSeason(info, 'BV1');
      expect(r.videos.length, 1);
      expect(r.index, 0);
    });
  });

  group('PlaySessionHistory', () {
    setUp(PlaySessionHistory.clear);

    Video v(int i) => Video(bvid: 'BV$i', title: 't$i', pic: '');

    test('push／pop 後進先出', () {
      PlaySessionHistory.push(v(1));
      PlaySessionHistory.push(v(2));
      expect(PlaySessionHistory.canPop, isTrue);
      expect(PlaySessionHistory.peek?.bvid, 'BV2');
      expect(PlaySessionHistory.pop()?.bvid, 'BV2');
      expect(PlaySessionHistory.pop()?.bvid, 'BV1');
      expect(PlaySessionHistory.pop(), isNull);
      expect(PlaySessionHistory.canPop, isFalse);
    });

    test('上限 50 筆，丟掉最舊的', () {
      for (var i = 0; i < 60; i++) {
        PlaySessionHistory.push(v(i));
      }
      expect(PlaySessionHistory.items.length, 50);
      expect(PlaySessionHistory.items.first.bvid, 'BV10');
      expect(PlaySessionHistory.peek?.bvid, 'BV59');
    });
  });
}
