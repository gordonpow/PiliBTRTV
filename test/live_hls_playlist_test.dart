import 'package:flutter_test/flutter_test.dart';
import 'package:bili_tv_app/services/live/live_hls_playlist.dart';

const _sample = '''#EXTM3U
#EXT-X-VERSION:7
#EXT-X-START:TIME-OFFSET=0
#EXT-X-MEDIA-SEQUENCE:427277177
#EXT-X-TARGETDURATION:1
#EXT-X-MAP:URI="h1794479804.m4s"
#EXT-BILI-AUX:123a9d1|K|23b6b|c002a293
#EXTINF:1.00,23b6b|c002a293
427277177.m4s
#EXT-BILI-AUX:123ada9|N|2097c|131b359d
#EXTINF:1.00,2097c|131b359d
427277178.m4s
''';

void main() {
  final base = Uri.parse('https://h.example.com/live-bvc/12/abc/index.m3u8?expires=1&a=b');

  test('解析遠端清單：MAP、sequence、相對 URI', () {
    final pl = RemotePlaylist.parse(_sample, base)!;
    expect(pl.mediaSequence, 427277177);
    expect(pl.targetDuration, 1);
    expect(pl.mapUri.toString(),
        'https://h.example.com/live-bvc/12/abc/h1794479804.m4s');
    expect(pl.segments.length, 2);
    expect(pl.segments[1].sequence, 427277178);
    expect(pl.segments[1].duration, 1.0);
    expect(pl.segments[0].uri.toString(),
        'https://h.example.com/live-bvc/12/abc/427277177.m4s');
  });

  test('不是 m3u8 回傳 null', () {
    expect(RemotePlaylist.parse('<html>', base), isNull);
  });

  test('本機清單：MEDIA-SEQUENCE、MAP 位置、TARGETDURATION', () {
    final p = LiveLocalPlaylist();
    for (var i = 0; i < 3; i++) {
      p.add(
          duration: const Duration(seconds: 4),
          discontinuity: false,
          initIndex: 0);
    }
    final text = p.render();
    final lines = text.trim().split('\n');
    expect(lines[0], '#EXTM3U');
    expect(text, contains('#EXT-X-TARGETDURATION:4'));
    expect(text, contains('#EXT-X-MEDIA-SEQUENCE:0'));
    expect(text, contains('#EXT-X-DISCONTINUITY-SEQUENCE:0'));
    expect(text, isNot(contains('ENDLIST')));
    expect(text, isNot(contains('PLAYLIST-TYPE')));
    // MAP 在第一個 EXTINF 之前，且只出現一次
    expect(text.indexOf('#EXT-X-MAP'), lessThan(text.indexOf('#EXTINF')));
    expect('#EXT-X-MAP'.allMatches(text).length, 1);
    expect(text, contains('#EXTINF:4.000,\ns0.m4s'));
  });

  test('discontinuity 與 init 變更：標記與新 MAP', () {
    final p = LiveLocalPlaylist();
    p.add(duration: const Duration(seconds: 2), discontinuity: false, initIndex: 0);
    p.add(duration: const Duration(seconds: 2), discontinuity: true, initIndex: 1);
    p.add(duration: const Duration(seconds: 2), discontinuity: true, initIndex: 1);
    final text = p.render();
    expect('#EXT-X-DISCONTINUITY\n'.allMatches(text).length, 2);
    expect(text, contains('#EXT-X-MAP:URI="init1.m4s"'));
    expect('#EXT-X-MAP'.allMatches(text).length, 2);
    final d = text.indexOf('#EXT-X-DISCONTINUITY\n');
    final m = text.indexOf('#EXT-X-MAP:URI="init1.m4s"');
    expect(d, lessThan(m));
  });

  test('刪除舊片段後數值正確', () {
    final p = LiveLocalPlaylist();
    p.add(duration: const Duration(seconds: 4), discontinuity: false, initIndex: 0);
    p.add(duration: const Duration(seconds: 4), discontinuity: true, initIndex: 1);
    p.add(duration: const Duration(seconds: 4), discontinuity: false, initIndex: 1);
    p.add(duration: const Duration(seconds: 4), discontinuity: true, initIndex: 1);
    expect(p.bufferedDuration, const Duration(seconds: 16));

    final removed = p.trim(const Duration(seconds: 9));
    expect(removed.map((s) => s.n), [0, 1]);
    expect(p.droppedDuration, const Duration(seconds: 8));
    expect(p.droppedDiscontinuities, 1);
    expect(p.bufferedDuration, const Duration(seconds: 8));
    expect(p.mediaSequence, 2);
    expect(p.usedInits, {1});

    final text = p.render();
    expect(text, contains('#EXT-X-MEDIA-SEQUENCE:2'));
    expect(text, contains('#EXT-X-DISCONTINUITY-SEQUENCE:1'));
    // 第一個保留片段使用的 init 出現在開頭
    expect(text.indexOf('#EXT-X-MAP:URI="init1.m4s"'),
        lessThan(text.indexOf('#EXTINF')));
    expect(text, isNot(contains('s0.m4s')));
    expect(text, isNot(contains('s1.m4s')));
  });

  test('trim 至少保留 1 個片段', () {
    final p = LiveLocalPlaylist();
    p.add(duration: const Duration(seconds: 10), discontinuity: false, initIndex: 0);
    expect(p.trim(const Duration(seconds: 1)), isEmpty);
    expect(p.segments.length, 1);
  });
}
