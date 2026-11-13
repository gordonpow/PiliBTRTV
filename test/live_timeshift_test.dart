import 'dart:io';
import 'dart:typed_data';

import 'package:bili_tv_app/services/live/live_timeshift.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假遠端：提供可變動的 fmp4 HLS 清單與片段。
class FakeRemote {
  late HttpServer server;
  int seqStart = 100;
  int count = 8;
  String map = 'init_a.m4s';
  int status = 200;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final name = req.uri.pathSegments.last;
      final res = req.response;
      if (name == 'index.m3u8') {
        if (status != 200) {
          res.statusCode = status;
        } else {
          final b = StringBuffer('#EXTM3U\n#EXT-X-VERSION:7\n'
              '#EXT-X-MEDIA-SEQUENCE:$seqStart\n#EXT-X-TARGETDURATION:1\n'
              '#EXT-X-MAP:URI="$map"\n');
          for (var i = 0; i < count; i++) {
            b.write('#EXTINF:1.00,x\n${seqStart + i}.m4s\n');
          }
          res.write(b);
        }
      } else {
        res.add(List.filled(100, name.codeUnitAt(0)));
      }
      await res.close();
    });
  }

  String get url =>
      'http://127.0.0.1:${server.port}/live-bvc/1/n/index.m3u8?expires=1';
}

Future<String> getBody(String url) async {
  final c = HttpClient();
  final r = await (await c.getUrl(Uri.parse(url))).close();
  final body = await r.transform(const SystemEncoding().decoder).join();
  c.close(force: true);
  return '${r.statusCode}\n$body';
}

Future<int> statusOf(String url) async {
  final c = HttpClient();
  final r = await (await c.getUrl(Uri.parse(url))).close();
  await r.drain<void>();
  c.close(force: true);
  return r.statusCode;
}

Future<void> until(bool Function() cond, {int ms = 10000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('等待逾時');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  late Directory root;
  late FakeRemote remote;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lts_test_');
    LiveTimeshiftSession.tempRootProvider = () async => root;
    LiveTimeshiftSession.resetStaticForTest();
    remote = FakeRemote();
    await remote.start();
  });

  tearDown(() async {
    await remote.server.close(force: true);
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  LiveTimeshiftSession make({
    Future<String?> Function()? resolve,
    Duration max = const Duration(minutes: 5),
    Duration fatalAfter = const Duration(seconds: 60),
  }) =>
      LiveTimeshiftSession(
        resolveUrl: resolve ?? () async => remote.url,
        maxBuffer: max,
        retryBase: const Duration(milliseconds: 50),
        fatalAfter: fatalAfter,
        deleteDelay: const Duration(milliseconds: 100),
      );

  test('start 回傳本機網址；清單與片段可取得；路徑穿越 404；dispose 後 404',
      () async {
    final s = make();
    final url = await s.start();
    expect(url, matches(RegExp(r'^http://127\.0\.0\.1:\d+/live/[^/]+/index\.m3u8$')));
    final pl = await getBody(url);
    expect(pl, startsWith('200\n#EXTM3U'));
    expect(pl, contains('#EXT-X-MAP:URI="init0.m4s"'));
    expect(s.bufferedDuration, greaterThanOrEqualTo(const Duration(seconds: 3)));

    final base = url.substring(0, url.lastIndexOf('/'));
    expect(await statusOf('$base/init0.m4s'), 200);
    expect(await statusOf('$base/s0.m4s'), 200);
    expect(await statusOf('$base/..%2f..%2fx.m4s'), 404);
    expect(await statusOf('$base/a.txt'), 404);
    expect(await statusOf('$base/nofile.m4s'), 404);

    await s.dispose();
    await s.dispose(); // 可重複呼叫
    expect(await statusOf(url), 404);
    final base2 = Directory('${root.path}/live_timeshift');
    expect(base2.existsSync() ? base2.listSync() : [], isEmpty);
  });

  test('遠端 sequence 跳號與 init 變更產生 discontinuity', () async {
    final s = make();
    final url = await s.start();
    remote.seqStart = 200; // 跳號
    remote.map = 'init_b.m4s'; // init 改變
    await until(() => s.bufferedDuration > const Duration(seconds: 9));
    final pl = await getBody(url);
    expect(pl, contains('#EXT-X-DISCONTINUITY'));
    expect(pl, contains('#EXT-X-MAP:URI="init1.m4s"'));
    await s.dispose();
  });

  test('超過上限刪除舊片段：sequence 與 dropped 更新、檔案延遲刪除', () async {
    final s = make(max: const Duration(seconds: 5));
    final url = await s.start();
    final base = url.substring(0, url.lastIndexOf('/'));
    // 連續推進遠端，讓暫存超過上限
    for (var i = 0; i < 6; i++) {
      remote.seqStart += 8;
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    await until(() => s.droppedDuration > Duration.zero);
    final pl = await getBody(url);
    final seq = RegExp(r'MEDIA-SEQUENCE:(\d+)').firstMatch(pl)!.group(1)!;
    expect(int.parse(seq), greaterThan(0));
    expect(s.liveAbsolute, s.droppedDuration + s.bufferedDuration);
    expect(s.absoluteOf(const Duration(seconds: 2)),
        s.droppedDuration + const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(await statusOf('$base/s0.m4s'), 404);
    await s.dispose();
  });

  test('playerPosFor 夾在 [0, buffered - liveEdgeOffset]', () async {
    final s = make();
    await s.start();
    var max = s.bufferedDuration - s.liveEdgeOffset;
    if (max < Duration.zero) max = Duration.zero;
    expect(s.playerPosFor(const Duration(hours: -1)), Duration.zero);
    expect(s.playerPosFor(const Duration(hours: 5)), max);
    await s.dispose();
  });

  test('重新取流：403 觸發 resolveUrl，狀態 stalled 後 recovered', () async {
    var resolves = 0;
    final s = make(resolve: () async {
      resolves++;
      if (resolves > 1) remote.status = 200; // 重新取流後恢復
      return remote.url;
    });
    final states = <LiveTimeshiftState>[];
    await s.start();
    s.states.listen(states.add);
    final before = resolves;
    remote.status = 403;
    await until(() => resolves > before);
    await until(() => states.contains(LiveTimeshiftState.recovered));
    expect(states.first, LiveTimeshiftState.stalled);
    await s.dispose();
  });

  test('網路持續失敗超過門檻發出 fatal', () async {
    final s = make(fatalAfter: const Duration(milliseconds: 300));
    final states = <LiveTimeshiftState>[];
    await s.start();
    s.states.listen(states.add);
    remote.status = 500;
    await until(() => states.contains(LiveTimeshiftState.fatal));
    await s.dispose();
  });

  test('start 逾時丟例外；start 進行中 dispose 丟例外', () async {
    remote.status = 500;
    final s = LiveTimeshiftSession(
      resolveUrl: () async => remote.url,
      maxBuffer: const Duration(minutes: 5),
      startTimeout: const Duration(milliseconds: 500),
    );
    await expectLater(s.start(), throwsA(isA<Exception>()));

    final s2 = make();
    final f = s2.start();
    final expectation = expectLater(f, throwsA(anything));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await s2.dispose();
    await expectation;
  });

  test('previewSource 找到所在片段並回傳 init＋片段路徑', () async {
    final s = make();
    await s.start();
    await until(() => s.bufferedDuration >= const Duration(seconds: 6));
    final a = s.previewSource(Duration.zero)!;
    expect(a.n, 0);
    expect(a.paths.length, 2);
    expect(a.paths[0], endsWith('init0.m4s'));
    expect(a.paths[1], endsWith('s0.m4s'));
    expect(File(a.paths[0]).existsSync(), isTrue);
    expect(File(a.paths[1]).existsSync(), isTrue);
    // 0.5 秒仍在片段 0；1.5 秒在片段 1；超出範圍取最後一個
    expect(s.previewSource(const Duration(milliseconds: 500))!.n, 0);
    expect(s.previewSource(const Duration(milliseconds: 1500))!.n, 1);
    expect(s.previewSource(const Duration(hours: 1))!.n,
        greaterThanOrEqualTo(2));
    await s.dispose();
    expect(s.previewSource(Duration.zero), isNull);
  });

  test('錄製時背景預先擷取縮圖；無圖時回退串前一片段；trim 後移除', () async {
    final calls = <List<String>>[];
    final s = LiveTimeshiftSession(
      resolveUrl: () async => remote.url,
      maxBuffer: const Duration(minutes: 5),
      retryBase: const Duration(milliseconds: 50),
      deleteDelay: const Duration(milliseconds: 100),
      thumbnailer: (paths) async {
        calls.add(paths);
        // 只有三個檔案（init＋前一片段＋本片段）的回退請求才成功
        if (paths.length == 3) return Uint8List.fromList([9, 9]);
        return null;
      },
    );
    await s.start();
    // 預設關閉：不處理佇列
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(calls, isEmpty);
    s.thumbnailsEnabled = true;
    await until(() => s.thumbnailFor(1) != null);
    expect(s.thumbnailFor(1), [9, 9]);
    // 片段 0 沒有前一片段，回退不可用，也沒有更早的縮圖
    expect(s.thumbnailFor(0), isNull);
    expect(calls.any((p) => p.length == 3), isTrue);
    await s.dispose();
    expect(s.thumbnailFor(1), isNull);
  });

  test('cleanupStale 刪除殘留目錄', () async {
    final stale = Directory('${root.path}/live_timeshift/old')
      ..createSync(recursive: true);
    File('${stale.path}/s0.m4s').writeAsBytesSync([1]);
    await LiveTimeshiftSession.cleanupStale();
    expect(Directory('${root.path}/live_timeshift').existsSync(), isFalse);
  });
}
