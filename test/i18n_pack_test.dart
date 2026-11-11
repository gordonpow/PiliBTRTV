import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:bili_tv_app/utils/i18n_pack.dart';
import 'package:bili_tv_app/utils/zh_convert.dart';
import 'package:flutter_test/flutter_test.dart';

const _pack = {
  'version': '202611100000',
  'strings': {'語言': 'Language', '設定': 'Settings'},
  'templates': {'{0}分鐘前': '{0} min ago', '共 {0} 個{1}': '{0} {1} in total'},
};

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('i18n_test');
    I18nPack.directoryProvider = () async => dir;
    I18nPack.clear();
    ZhConvert.resetForTest();
    ZhConvert.localeProvider = () => const Locale('en', 'US');
  });

  tearDown(() async {
    // 並行下載的另一個寫入（meta 檔）可能在測試結束後才完成，
    // Windows 刪除時會遇到「目錄不是空的」：稍等後重試，最後失敗就略過
    for (var i = 0; i < 5; i++) {
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  group('convert 英文分支', () {
    test('字典命中回英文，且不需要繁簡表', () {
      I18nPack.loadJson(_pack);
      ZhConvert.script = ZhScript.english;
      expect(ZhConvert.convert('語言'), 'Language');
    });

    test('template 套用，片段可再查字典', () {
      I18nPack.loadJson(_pack);
      ZhConvert.script = ZhScript.english;
      expect(ZhConvert.convert('5分鐘前'), '5 min ago');
      expect(ZhConvert.convert('共 3 個設定'), '3 Settings in total');
    });

    test('查無字串回繁體原字串', () {
      I18nPack.loadJson(_pack);
      ZhConvert.script = ZhScript.english;
      expect(ZhConvert.convert('沒有的字串'), '沒有的字串');
    });

    test('空字串與沒有語言包', () {
      ZhConvert.script = ZhScript.english;
      expect(ZhConvert.convert(''), '');
      expect(ZhConvert.convert('語言'), '語言');
    });
  });

  group('resolve／systemScript', () {
    test('明確設定', () {
      expect(ZhConvert.resolve(1), ZhScript.traditional);
      expect(ZhConvert.resolve(2), ZhScript.simplified);
      expect(ZhConvert.resolve(3), ZhScript.english);
    });

    test('中文系統語言', () {
      void check(Locale l, ZhScript expected) {
        ZhConvert.localeProvider = () => l;
        expect(ZhConvert.resolve(0), expected, reason: '$l');
      }

      check(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        ZhScript.traditional,
      );
      check(const Locale('zh', 'TW'), ZhScript.traditional);
      check(const Locale('zh', 'HK'), ZhScript.traditional);
      check(const Locale('zh', 'MO'), ZhScript.traditional);
      check(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        ZhScript.simplified,
      );
      check(const Locale('zh', 'CN'), ZhScript.simplified);
      check(const Locale('zh', 'SG'), ZhScript.simplified);
    });

    test('非中文：有語言包回英文，沒有回繁體', () {
      expect(ZhConvert.resolve(0), ZhScript.traditional);
      I18nPack.loadJson(_pack);
      expect(ZhConvert.resolve(0), ZhScript.english);
    });

    test('needsEnglishPack 與語言包無關', () {
      expect(ZhConvert.needsEnglishPack(0), isTrue);
      expect(ZhConvert.needsEnglishPack(3), isTrue);
      expect(ZhConvert.needsEnglishPack(1), isFalse);
      expect(ZhConvert.needsEnglishPack(2), isFalse);
      ZhConvert.localeProvider = () => const Locale('zh', 'TW');
      expect(ZhConvert.needsEnglishPack(0), isFalse);
    });
  });

  group('下載與背景檢查', () {
    test('download 存檔後 load 可讀回', () async {
      I18nPack.fetcher = (url, onProgress) async {
        expect(url, I18nPack.url);
        onProgress?.call(10, 10);
        return '{"version":"v1","strings":{"語言":"Language"}}';
      };
      expect(await I18nPack.download(), 'v1');
      I18nPack.clear();
      await I18nPack.load();
      expect(I18nPack.isLoaded, isTrue);
      expect(I18nPack.version, 'v1');
    });

    test('無效語言包丟例外且不存檔', () async {
      I18nPack.fetcher = (_, _) async => '{"strings":{}}';
      await expectLater(I18nPack.download(), throwsFormatException);
      await I18nPack.load();
      expect(I18nPack.isLoaded, isFalse);
    });

    test('檔案損毀視為未載入', () async {
      File('${dir.path}/en.json').writeAsStringSync('not json');
      await I18nPack.load();
      expect(I18nPack.isLoaded, isFalse);
    });

    test('失敗後 24 小時內不重試，之後可重試', () async {
      var calls = 0;
      var now = DateTime(2026, 11, 10, 12);
      I18nPack.clock = () => now;
      I18nPack.fetcher = (_, _) async {
        calls++;
        throw const SocketException('offline');
      };
      await I18nPack.maybeUpdateInBackground();
      expect(calls, 1);
      now = now.add(const Duration(hours: 23));
      await I18nPack.maybeUpdateInBackground();
      expect(calls, 1);
      now = now.add(const Duration(hours: 2));
      await I18nPack.maybeUpdateInBackground();
      expect(calls, 2);
      addTearDown(() => I18nPack.clock = DateTime.now);
    });

    test('並行 download 只發一次請求且都成功', () async {
      var calls = 0;
      I18nPack.fetcher = (_, onProgress) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return '{"version":"v1","strings":{"語言":"Language"}}';
      };
      final results = await Future.wait([
        I18nPack.download(),
        I18nPack.download(),
      ]);
      expect(calls, 1);
      expect(results, ['v1', 'v1']);
      // 結束後可再下載一次
      await I18nPack.download();
      expect(calls, 2);
    });

    test('檔案損毀且 meta ok:true 時，背景檢查會立即重新下載', () async {
      var calls = 0;
      final now = DateTime(2026, 11, 10, 12);
      I18nPack.clock = () => now;
      addTearDown(() => I18nPack.clock = DateTime.now);
      File('${dir.path}/en.json').writeAsStringSync('not json');
      File('${dir.path}/meta.json').writeAsStringSync(
        '{"lastCheck":${now.millisecondsSinceEpoch},"ok":true}',
      );
      I18nPack.fetcher = (_, _) async {
        calls++;
        return '{"version":"v2","strings":{"語言":"Language"}}';
      };
      await I18nPack.load();
      expect(I18nPack.isLoaded, isFalse);
      await I18nPack.maybeUpdateInBackground();
      expect(calls, 1);
      await I18nPack.load();
      expect(I18nPack.version, 'v2');
    });

    test('已載入且成功後 7 天內不檢查', () async {
      var calls = 0;
      var now = DateTime(2026, 11, 10, 12);
      I18nPack.clock = () => now;
      I18nPack.fetcher = (_, _) async {
        calls++;
        return '{"version":"v1","strings":{"語言":"Language"}}';
      };
      await I18nPack.maybeUpdateInBackground();
      await I18nPack.load();
      expect(calls, 1);
      now = now.add(const Duration(days: 6));
      await I18nPack.maybeUpdateInBackground();
      expect(calls, 1);
      now = now.add(const Duration(days: 2));
      await I18nPack.maybeUpdateInBackground();
      expect(calls, 2);
      addTearDown(() => I18nPack.clock = DateTime.now);
    });

    group('App 版本變更', () {
      late int calls;
      late DateTime now;

      setUp(() {
        calls = 0;
        now = DateTime(2026, 11, 10, 12);
        I18nPack.clock = () => now;
        I18nPack.fetcher = (_, _) async {
          calls++;
          return '{"version":"v1","strings":{"語言":"Language"}}';
        };
        addTearDown(() => I18nPack.clock = DateTime.now);
      });

      Map<String, dynamic> readMeta() =>
          jsonDecode(File('${dir.path}/meta.json').readAsStringSync())
              as Map<String, dynamic>;

      test('版本相同且未超過間隔時不下載', () async {
        await I18nPack.maybeUpdateInBackground(appVersion: 'a1');
        await I18nPack.load();
        expect(calls, 1);
        now = now.add(const Duration(days: 1));
        await I18nPack.maybeUpdateInBackground(appVersion: 'a1');
        expect(calls, 1);
      });

      test('版本不同時立即下載', () async {
        await I18nPack.maybeUpdateInBackground(appVersion: 'a1');
        await I18nPack.load();
        expect(calls, 1);
        await I18nPack.maybeUpdateInBackground(appVersion: 'a2');
        expect(calls, 2);
      });

      test('下載成功後 meta 記錄新的版本', () async {
        await I18nPack.maybeUpdateInBackground(appVersion: 'a1');
        expect(readMeta()['app'], 'a1');
        await I18nPack.download();
        // 手動下載不能把 app 清掉
        expect(readMeta()['app'], 'a1');
        await I18nPack.maybeUpdateInBackground(appVersion: 'a2');
        expect(readMeta()['app'], 'a2');
      });

      test('舊的 meta 沒有 app 欄位時，帶版本會觸發一次檢查', () async {
        await I18nPack.download();
        await I18nPack.load();
        expect(calls, 1);
        File('${dir.path}/meta.json').writeAsStringSync(
          '{"lastCheck":${now.millisecondsSinceEpoch},"ok":true}',
        );
        await I18nPack.maybeUpdateInBackground(appVersion: 'a1');
        expect(calls, 2);
        await I18nPack.maybeUpdateInBackground(appVersion: 'a1');
        expect(calls, 2);
      });
    });
  });
}
