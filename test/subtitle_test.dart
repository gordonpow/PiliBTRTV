import 'package:bili_tv_app/models/subtitle.dart';
import 'package:bili_tv_app/services/api/subtitle_api.dart';
import 'package:flutter_test/flutter_test.dart';

SubtitleTrack t(String lan, {bool ai = false}) =>
    SubtitleTrack(id: 1, lan: lan, lanDoc: lan, url: '//x/$lan', isAi: ai);

void main() {
  group('v2 回應解析', () {
    test('過濾 subtitle_url 為空，並判斷 AI', () {
      final tracks = SubtitleApi.parseTracks({
        'code': 0,
        'data': {
          'subtitle': {
            'subtitles': [
              {
                'id': 1,
                'lan': 'ai-zh',
                'lan_doc': '中文（自动生成）',
                'subtitle_url': '//a/b.json',
                'type': 1,
              },
              {'id': 2, 'lan': 'en', 'lan_doc': 'English', 'subtitle_url': ''},
              {'id': 3, 'lan': 'zh-CN', 'lan_doc': '中文', 'subtitle_url': 'u'},
            ],
          },
        },
      });
      expect(tracks.map((e) => e.id), [1, 3]);
      expect(tracks[0].isAi, isTrue);
      expect(tracks[1].isAi, isFalse);
      expect(tracks[0].label, '中文（自动生成）'); // 已含自動生成，不重複加
    });

    test('AI 軌名稱補（自動生成）', () {
      expect(
        SubtitleTrack(
          id: 1,
          lan: 'ai-zh',
          lanDoc: '中文',
          url: 'u',
          isAi: true,
        ).label,
        '中文（自動生成）',
      );
    });

    test('code 非 0、缺欄位回空', () {
      expect(SubtitleApi.parseTracks({'code': -101}), isEmpty);
      expect(SubtitleApi.parseTracks({'code': 0, 'data': {}}), isEmpty);
      expect(SubtitleApi.parseTracks(null), isEmpty);
    });
  });

  group('body 解析', () {
    test('解析、略過空內容、依 from 排序', () {
      final lines = parseSubtitleBody([
        {'from': 5, 'to': 6.5, 'content': 'b'},
        {'from': 1.0, 'to': 2, 'content': 'a'},
        {'from': 3, 'to': 4, 'content': '  '},
        {'from': 7, 'content': 'x'},
        'bad',
      ]);
      expect(lines.map((e) => e.content), ['a', 'b']);
      expect(lines[1].to, 6.5);
      expect(parseSubtitleBody(null), isEmpty);
    });
  });

  group('二分搜尋', () {
    final lines = [
      const SubtitleLine(from: 1, to: 2, content: 'a'),
      const SubtitleLine(from: 2, to: 4, content: 'b'),
      const SubtitleLine(from: 5, to: 6, content: 'c'),
    ];
    test('邊界 from 含、to 不含', () {
      expect(findSubtitleLine(lines, 1)?.content, 'a');
      expect(findSubtitleLine(lines, 1.99)?.content, 'a');
      expect(findSubtitleLine(lines, 2)?.content, 'b');
      expect(findSubtitleLine(lines, 4), isNull);
      expect(findSubtitleLine(lines, 5)?.content, 'c');
      expect(findSubtitleLine(lines, 6), isNull);
    });
    test('第一行之前、空清單', () {
      expect(findSubtitleLine(lines, 0.5), isNull);
      expect(findSubtitleLine(const [], 1), isNull);
    });
    test('長字幕後接多行短字幕，仍找到長行', () {
      final l = [
        const SubtitleLine(from: 0, to: 100, content: 'long'),
        for (int i = 1; i <= 5; i++)
          SubtitleLine(from: i * 2.0, to: i * 2.0 + 1, content: 's$i'),
      ];
      expect(findSubtitleLine(l, 50)?.content, 'long');
      expect(findSubtitleLine(l, 4.5)?.content, 's2');
      expect(findSubtitleLine(l, 100), isNull);
    });
    test('重疊行取仍涵蓋的行', () {
      final l = [
        const SubtitleLine(from: 0, to: 10, content: 'long'),
        const SubtitleLine(from: 2, to: 3, content: 'short'),
      ];
      expect(findSubtitleLine(l, 2.5)?.content, 'short');
      expect(findSubtitleLine(l, 5)?.content, 'long');
    });
  });

  group('預設選軌', () {
    test('英文介面：英文 > 中文，非 AI 優先', () {
      final tr = [t('ai-zh', ai: true), t('zh-CN'), t('ai-en', ai: true)];
      expect(pickDefaultSubtitle(tr, english: true), 2);
      final tr2 = [t('ai-en', ai: true), t('en')];
      expect(pickDefaultSubtitle(tr2, english: true), 1);
    });
    test('英文介面沒英文軌：選中文', () {
      final tr = [t('ai-zh', ai: true), t('zh-CN')];
      expect(pickDefaultSubtitle(tr, english: true), 1);
    });
    test('中文介面：只選中文，不選英文', () {
      expect(
        pickDefaultSubtitle([t('en'), t('ai-zh', ai: true)], english: false),
        1,
      );
      expect(pickDefaultSubtitle([t('en')], english: false), -1);
      expect(pickDefaultSubtitle(const [], english: true), -1);
    });
  });

  group('機器翻譯軌出現條件', () {
    final zhOnly = [t('zh-CN')];
    test('英文介面＋啟用＋無英文軌＋有中文軌', () {
      expect(
        machineTrackAvailable(zhOnly, englishUi: true, translatorEnabled: true),
        isTrue,
      );
    });
    test('任一條件不滿足即無', () {
      expect(
        machineTrackAvailable(
          zhOnly,
          englishUi: false,
          translatorEnabled: true,
        ),
        isFalse,
      );
      expect(
        machineTrackAvailable(
          zhOnly,
          englishUi: true,
          translatorEnabled: false,
        ),
        isFalse,
      );
      expect(
        machineTrackAvailable(
          [t('zh-CN'), t('en')],
          englishUi: true,
          translatorEnabled: true,
        ),
        isFalse,
      );
      expect(
        machineTrackAvailable(
          [t('en')],
          englishUi: true,
          translatorEnabled: true,
        ),
        isFalse,
      );
    });
  });
}
