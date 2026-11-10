import 'dart:ffi' show Abi;

import 'package:bili_tv_app/services/playback_perf.dart';
import 'package:bili_tv_app/services/settings_service.dart' show VideoCodec;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dropRate', () {
    expect(dropRate(30, 60, 10), closeTo(0.05, 1e-9));
    expect(dropRate(0, 60, 10), 0);
    expect(dropRate(10, 0, 10), 0);
  });

  test('nextLowerQn 取下一級較低畫質', () {
    expect(nextLowerQn([127, 120, 116, 112, 80, 74, 64], 120), 116);
    expect(nextLowerQn([120, 80, 64], 120), 80);
    expect(nextLowerQn([126, 125, 120, 116, 80], 126), 116);
    expect(nextLowerQn([127, 126, 120, 116], 127), 126);
    expect(nextLowerQn([116, 112, 80], 116), 112);
    expect(nextLowerQn([16, 32], 16), isNull);
  });

  test('32 位元 4K 略過 BTR', () {
    expect(isProcess32Bit(Abi.androidArm), isTrue);
    expect(isProcess32Bit(Abi.androidIA32), isTrue);
    expect(isProcess32Bit(Abi.androidArm64), isFalse);
    expect(shouldSkipBtr(is32Bit: true, qn: 120), isTrue);
    expect(shouldSkipBtr(is32Bit: true, height: 2160), isTrue);
    expect(shouldSkipBtr(is32Bit: true, qn: 80, height: 1080), isFalse);
    expect(shouldSkipBtr(is32Bit: false, qn: 120), isFalse);
  });

  test('cpuPercent', () {
    expect(
      cpuPercent(
        prevJiffies: 0,
        prevElapsedMs: 0,
        curJiffies: 400,
        curElapsedMs: 10000,
        hz: 100,
        cores: 4,
      ),
      closeTo(10, 1e-9),
    );
    expect(
      cpuPercent(
        prevJiffies: 0,
        prevElapsedMs: 0,
        curJiffies: 1,
        curElapsedMs: 0,
        hz: 100,
        cores: 4,
      ),
      isNull,
    );
  });

  test('formatPerfLine', () {
    final line = formatPerfLine(
      posSec: 123,
      droppedInterval: 12,
      droppedTotal: 340,
      rate: 0.02,
      offsetUs: -850,
      rendered: 600,
      bufSec: 8.2,
      bandwidthBps: 24e6,
      cpu: 45,
    );
    expect(
      line,
      't=123s drop=12/340 (2.0%) offset=-850us rendered=600 buf=8.2s bw=24Mbps cpu=45%',
    );
  });

  group('DowngradeTracker', () {
    test('連續兩個區間 > 15% 才降，一次只降一次', () {
      final t = DowngradeTracker();
      expect(t.record(0.2, enabled: true), isFalse);
      expect(t.record(0.2, enabled: true), isTrue);
      t.commitDowngrade();
      expect(t.record(0.2, enabled: true), isFalse);
    });

    test('中間有正常區間則重算；剛好 15% 不算', () {
      final t = DowngradeTracker();
      t.record(0.2, enabled: true);
      t.record(0.1, enabled: true);
      expect(t.record(0.2, enabled: true), isFalse);
      final u = DowngradeTracker();
      u.record(0.15, enabled: true);
      expect(u.record(0.15, enabled: true), isFalse);
    });

    test('每部最多 2 次、手動選畫質後不再降、關閉開關不降', () {
      final t = DowngradeTracker();
      for (var i = 0; i < 2; i++) {
        t.record(0.3, enabled: true);
        expect(t.record(0.3, enabled: true), isTrue);
        t.commitDowngrade();
      }
      t.record(0.3, enabled: true);
      expect(t.record(0.3, enabled: true), isFalse);

      final u = DowngradeTracker()..userPicked = true;
      u.record(0.3, enabled: true);
      expect(u.record(0.3, enabled: true), isFalse);

      final v = DowngradeTracker();
      v.record(0.3, enabled: false);
      expect(v.record(0.3, enabled: false), isFalse);
    });

    test('重建只重置區間，換片才重置次數', () {
      final t = DowngradeTracker();
      t.record(0.3, enabled: true);
      t.resetInterval();
      expect(t.record(0.3, enabled: true), isFalse);
      t.commitDowngrade();
      t.resetInterval();
      expect(t.autoCount, 1);
      t.resetForVideo();
      expect(t.autoCount, 0);
    });
  });

  group('autoCodecOrder', () {
    test('一般順序 AV1 > HEVC > AVC', () {
      expect(autoCodecOrder(fallbackToAvc: false, preferHevc: false), [
        'av1',
        'hevc',
        'avc',
      ]);
    });
    test('隧道 4K 高幀率 HEVC 優先', () {
      expect(autoCodecOrder(fallbackToAvc: false, preferHevc: true), [
        'hevc',
        'av1',
        'avc',
      ]);
    });
    test('fallbackToAvc 只回 avc', () {
      expect(autoCodecOrder(fallbackToAvc: true, preferHevc: true), ['avc']);
    });
    test('is4kHighFps', () {
      expect(is4kHighFps(height: 2160, fps: 60), isTrue);
      expect(is4kHighFps(height: 2160, fps: 0), isTrue);
      expect(is4kHighFps(height: 2160, fps: 30), isFalse);
      expect(is4kHighFps(height: 1080, fps: 60), isFalse);
    });
  });

  group('isDecoderStall', () {
    bool f({
      bool want = true,
      int? state = 2,
      int sec = 8,
      int? ahead = 10000,
    }) => isDecoderStall(
      playWhenReady: want,
      playbackState: state,
      bufferingFor: Duration(seconds: sec),
      bufferedAheadMs: ahead,
    );
    test('達門檻判定卡住', () => expect(f(), isTrue));
    test('使用者暫停不算', () => expect(f(want: false), isFalse));
    test('非緩衝狀態不算', () => expect(f(state: 3), isFalse));
    test('緩衝未滿 8 秒不算', () => expect(f(sec: 7), isFalse));
    test('已緩衝不足 10 秒不算（網路慢）', () => expect(f(ahead: 9999), isFalse));
    test('取不到已緩衝量不算', () => expect(f(ahead: null), isFalse));
  });

  group('nextStallCodec', () {
    test('av01 -> hevc', () {
      expect(nextStallCodec('av01.0.13M.08', {'av01'}), VideoCodec.hevc);
    });
    test('hev -> avc', () {
      expect(nextStallCodec('hev1.1.6.L153', {'hev'}), VideoCodec.avc);
    });
    test('avc -> null', () {
      expect(nextStallCodec('avc1.640034', {'avc'}), isNull);
    });
    test('已試過的家族跳過', () {
      expect(nextStallCodec('av01.0.13M.08', {'av01', 'hev'}), VideoCodec.avc);
      expect(nextStallCodec('av01.0.13M.08', {'av01', 'hev', 'avc'}), isNull);
    });
  });

  group('formatStallLog', () {
    test('有目標編碼', () {
      expect(
        formatStallLog(
          from: 'av01',
          to: 'hev',
          bufferingSec: 8,
          bufferedAheadSec: 12.34,
        ),
        '事件 解碼卡住 av01->hev 緩衝=8s 已緩衝=12.3s',
      );
    });
    test('已是 AVC', () {
      expect(
        formatStallLog(
          from: 'avc',
          to: null,
          bufferingSec: 9,
          bufferedAheadSec: 11,
        ),
        '事件 解碼卡住 已是 AVC，不再切換 緩衝=9s 已緩衝=11.0s',
      );
    });
  });

  group('isHdrStream', () {
    test('qn 125／126', () {
      expect(isHdrStream(qn: 125, codecs: 'avc1.640033'), isTrue);
      expect(isHdrStream(qn: 126, codecs: ''), isTrue);
    });
    test('HEVC Main10', () {
      expect(isHdrStream(qn: 120, codecs: 'hvc1.2.4.L153.90'), isTrue);
      expect(isHdrStream(qn: 80, codecs: 'hev1.2.4.L120.90'), isTrue);
      expect(isHdrStream(qn: 120, codecs: 'hev1.1.6.L153.90'), isFalse);
    });
    test('AV1 位元深度', () {
      expect(isHdrStream(qn: 80, codecs: 'av01.0.13M.10'), isTrue);
      expect(isHdrStream(qn: 80, codecs: 'av01.0.13M.12'), isTrue);
      expect(isHdrStream(qn: 80, codecs: 'av01.0.13M.08'), isFalse);
    });
    test('AVC 非 HDR', () {
      expect(isHdrStream(qn: 80, codecs: 'avc1.64001F'), isFalse);
    });
  });

  group('nonHdrFallbackQn', () {
    test('跳過 125／126 取最高較低畫質', () {
      expect(nonHdrFallbackQn([127, 126, 125, 120, 116, 80], 125), 120);
      expect(nonHdrFallbackQn([126, 125, 120, 80], 126), 120);
    });
    test('不選比目前高的', () {
      expect(nonHdrFallbackQn([120, 80, 64], 80), 64);
    });
    test('沒有更低畫質回 null', () {
      expect(nonHdrFallbackQn([126, 125], 125), isNull);
      expect(nonHdrFallbackQn(const [], 125), isNull);
    });
  });
}
