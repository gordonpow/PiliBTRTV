import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_tv_app/services/settings_service.dart';
import 'package:bili_tv_app/services/translate/content_translator.dart';
import 'package:bili_tv_app/models/video.dart';
import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:bili_tv_app/widgets/content_text.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeEngine implements TranslateEngine {
  final calls = <String>[];
  Completer<void>? gate;
  bool fail = false;
  bool downloaded = true;
  int downloadCalls = 0;

  @override
  Future<bool> isModelDownloaded() async => downloaded;

  @override
  Future<void> downloadModel() async {
    downloadCalls++;
    if (fail) throw Exception('no play services');
  }

  @override
  Future<String> translate(String text) async {
    calls.add(text);
    if (gate != null) await gate!.future;
    return 'EN:$text';
  }

  @override
  Future<void> close() async {}
}

void main() {
  late Directory dir;
  late _FakeEngine engine;
  late ContentTranslator tr;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('translate_test');
    engine = _FakeEngine();
    tr = ContentTranslator.withEngine(
      engine,
      directory: () async => dir,
      saveDelay: const Duration(milliseconds: 30),
    );
  });

  tearDown(() async {
    // 先等背景寫檔結束，再刪暫存資料夾（Windows 檔案鎖）
    await tr.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('佇列優先序：新請求排前面（LIFO），字幕（priority 1）永遠最前', () async {
    engine.gate = Completer<void>();
    final block = tr.request('擋');
    await Future<void>.delayed(Duration.zero);
    final a = tr.request('甲');
    final b = tr.request('乙');
    final sub = tr.request('字幕', priority: 1);
    final c = tr.request('丙');
    engine.gate!.complete();
    await Future.wait([block.future, a.future, b.future, sub.future, c.future]);
    expect(engine.calls, ['擋', '字幕', '丙', '乙', '甲']);
  });

  test('modelReady 變動時 changes 遞增', () async {
    final before = tr.changes.value;
    await tr.downloadModel();
    expect(tr.modelReady, isTrue);
    expect(tr.changes.value, greaterThan(before));
    final mid = tr.changes.value;
    await tr.close();
    expect(tr.changes.value, greaterThan(mid));
    tr.notifyChanged();
    expect(tr.changes.value, greaterThan(mid + 1));
  });

  test('翻譯後寫入快取，第二次命中不再呼叫 ML Kit', () async {
    expect(tr.cached('你好'), isNull);
    expect(await tr.translate('你好'), 'EN:你好');
    expect(tr.cached('你好'), 'EN:你好');
    expect(await tr.translate('你好'), 'EN:你好');
    expect(engine.calls, ['你好']);
  });

  test('不含中日韓字元原樣回傳，不呼叫 ML Kit', () async {
    expect(await tr.translate('Hello 123'), 'Hello 123');
    expect(engine.calls, isEmpty);
    expect(tr.cached('Hello 123'), isNull);
  });

  test('同字串進行中合併為一次呼叫', () async {
    engine.gate = Completer<void>();
    final a = tr.translate('標題');
    final b = tr.translate('標題');
    await Future<void>.delayed(Duration.zero);
    engine.gate!.complete();
    expect(await Future.wait([a, b]), ['EN:標題', 'EN:標題']);
    expect(engine.calls, ['標題']);
  });

  test('序列佇列：一次只跑一個，且可取消尚未開始的任務', () async {
    engine.gate = Completer<void>();
    final first = tr.request('甲');
    await Future<void>.delayed(Duration.zero);
    final second = tr.request('乙');
    expect(engine.calls, ['甲']); // 並行 1
    second.cancel();
    engine.gate!.complete();
    expect(await first.future, 'EN:甲');
    expect(await second.future, isNull);
    expect(engine.calls, ['甲']);
  });

  test('合併的請求只有一方取消時仍會翻譯', () async {
    engine.gate = Completer<void>();
    final block = tr.request('擋');
    final a = tr.request('丙');
    final b = tr.request('丙');
    await Future<void>.delayed(Duration.zero);
    a.cancel();
    engine.gate!.complete();
    await block.future;
    expect(await b.future, 'EN:丙');
  });

  test('translateBatch 逐句回呼，isCancelled 為 true 時停止', () async {
    final got = <int, String>{};
    var cancelled = false;
    await tr.translateBatch(
      ['一', '二', '三', '四'],
      isCancelled: () => cancelled,
      onLine: (i, t) {
        got[i] = t;
        if (i == 1) cancelled = true;
      },
    );
    expect(got, {0: 'EN:一', 1: 'EN:二'});
    expect(engine.calls, ['一', '二']);
  });

  test('下載失敗丟出含底層訊息的例外，modelReady 保持 false', () async {
    engine.fail = true;
    await expectLater(
      tr.downloadModel(),
      throwsA(predicate((e) => '$e'.contains('no play services'))),
    );
    expect(tr.modelReady, isFalse);
  });

  test('磁碟快取：debounce 後寫檔，新實例載入', () async {
    await tr.downloadModel();
    await tr.translate('快取');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final file = File('${dir.path}/translate_cache.json');
    expect(jsonDecode(file.readAsStringSync()), {'快取': 'EN:快取'});
    expect(File('${file.path}.tmp').existsSync(), isFalse);

    final tr2 = ContentTranslator.withEngine(
      _FakeEngine(),
      directory: () async => dir,
    );
    await tr2.downloadModel();
    expect(tr2.cached('快取'), 'EN:快取');
  });

  test('快取檔損毀時清空重建', () async {
    final file = File('${dir.path}/translate_cache.json')
      ..writeAsStringSync('{broken');
    await tr.downloadModel();
    expect(tr.cached('任何'), isNull);
    expect(file.existsSync(), isFalse);
  });

  test('Video.ownerIsContent：預設 true，追番人數與類型標籤為 false', () {
    expect(Video(bvid: 'x', title: 't', pic: '').ownerIsContent, isTrue);
    expect(
      Video.fromBangumiIndex({
        'title': 't',
        'order': '868.4万追番',
      }).ownerIsContent,
      isFalse,
    );
    expect(
      Video.fromSeasonRelated({
        'title': 't',
        'styles': [
          {'name': '戰鬥'},
        ],
      }).ownerIsContent,
      isFalse,
    );
  });

  group('ZhConvert.convertContent', () {
    setUp(() {
      ZhConvert.resetForTest();
      ZhConvert.localeProvider = () => const Locale('zh', 'TW');
    });

    test('繁體、簡體模式一般文字與 convert 相同', () {
      for (final script in [ZhScript.traditional, ZhScript.simplified]) {
        ZhConvert.script = script;
        for (final t in ['', 'Hello', '影片標題 abc', '视频标题']) {
          expect(ZhConvert.convertContent(t), ZhConvert.convert(t));
        }
      }
    });

    test('英文模式沒有繁簡表時原樣回傳（不查字典）', () {
      ZhConvert.script = ZhScript.english;
      expect(ZhConvert.convertContent('视频'), '视频');
    });
  });

  group('預設開啟與背景下載', () {
    setUp(() {
      ZhConvert.resetForTest();
      ZhConvert.localeProvider = () => const Locale('en');
      ZhConvert.script = ZhScript.english;
    });

    test('translateContent 沒存過預設 true，存過照存的值', () async {
      SharedPreferences.setMockInitialValues({});
      SettingsService.debugSetPrefs(await SharedPreferences.getInstance());
      expect(SettingsService.translateContent, isTrue);
      await SettingsService.setTranslateContent(false);
      expect(SettingsService.translateContent, isFalse);
    });

    test('英文介面、模型未下載：init 背景下載並啟用', () async {
      SharedPreferences.setMockInitialValues({});
      SettingsService.debugSetPrefs(await SharedPreferences.getInstance());
      engine.downloaded = false;
      await tr.init();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(engine.downloadCalls, 1);
      expect(tr.modelReady, isTrue);
    });

    test('背景下載失敗：記錄時間，24 小時內不重試', () async {
      SharedPreferences.setMockInitialValues({});
      SettingsService.debugSetPrefs(await SharedPreferences.getInstance());
      engine.downloaded = false;
      engine.fail = true;
      await tr.downloadInBackground();
      expect(engine.downloadCalls, 1);
      expect(tr.modelReady, isFalse);
      expect(SettingsService.translateDownloadFailedAt, greaterThan(0));
      await tr.downloadInBackground();
      expect(engine.downloadCalls, 1);
      // force（剛選 English）略過退避
      await tr.downloadInBackground(force: true);
      expect(engine.downloadCalls, 2);
      // 超過 24 小時後可重試
      await SettingsService.setTranslateDownloadFailedAt(
        DateTime.now().millisecondsSinceEpoch -
            ContentTranslator.retryBackoff.inMilliseconds -
            1000,
      );
      await tr.downloadInBackground();
      expect(engine.downloadCalls, 3);
    });

    test('使用者關閉翻譯後不再自動下載', () async {
      SharedPreferences.setMockInitialValues({'translate_content': false});
      SettingsService.debugSetPrefs(await SharedPreferences.getInstance());
      engine.downloaded = false;
      await tr.init();
      await tr.downloadInBackground(force: true);
      expect(engine.downloadCalls, 0);
    });

    test('非英文介面 init 不下載', () async {
      SharedPreferences.setMockInitialValues({});
      SettingsService.debugSetPrefs(await SharedPreferences.getInstance());
      ZhConvert.script = ZhScript.traditional;
      engine.downloaded = false;
      await tr.init();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(engine.downloadCalls, 0);
    });

    testWidgets('modelReady 由 false 變 true：先前顯示原文的 ContentText 重新翻譯', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      SettingsService.debugSetPrefs(await SharedPreferences.getInstance());
      final saved = ContentTranslator.instance;
      ContentTranslator.instance = tr;
      addTearDown(() => ContentTranslator.instance = saved);
      expect(tr.enabled, isFalse);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: ContentText('你好世界'),
        ),
      );
      expect(find.text('你好世界'), findsOneWidget);
      await tester.runAsync(() async {
        await tr.enable();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('EN:你好世界'), findsOneWidget);
    });

    test('下載失敗但模型之後在原生層完成：輪詢發現後自動啟用並通知', () async {
      SharedPreferences.setMockInitialValues({});
      SettingsService.debugSetPrefs(await SharedPreferences.getInstance());
      final t = ContentTranslator.withEngine(
        engine,
        directory: () async => dir,
        pollInterval: const Duration(milliseconds: 20),
      );
      addTearDown(t.close);
      engine.downloaded = false;
      engine.fail = true;
      await t.init();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(t.modelReady, isFalse);
      final before = t.changes.value;
      engine.downloaded = true;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(t.modelReady, isTrue);
      expect(t.changes.value, greaterThan(before));
    });
  });
}
