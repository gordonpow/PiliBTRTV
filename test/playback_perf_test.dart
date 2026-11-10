import 'dart:ffi' show Abi;

import 'package:bili_tv_app/services/playback_perf.dart';
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

  group('autoQnCap', () {
    test('已知不順且是 4K 60 幀：上限 116', () {
      expect(
        autoQnCap(qn: 120, fps: 60, known4k60Bad: true, manual: false),
        116,
      );
    });
    test('4K 30 幀不受影響', () {
      expect(
        autoQnCap(qn: 120, fps: 30, known4k60Bad: true, manual: false),
        120,
      );
    });
    test('手動選 4K 不限制', () {
      expect(
        autoQnCap(qn: 120, fps: 60, known4k60Bad: true, manual: true),
        120,
      );
    });
    test('沒有記錄不限制；1080P60 不限制', () {
      expect(
        autoQnCap(qn: 120, fps: 60, known4k60Bad: false, manual: false),
        120,
      );
      expect(
        autoQnCap(qn: 116, fps: 60, known4k60Bad: true, manual: false),
        116,
      );
    });
  });
}
