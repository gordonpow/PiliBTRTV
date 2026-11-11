import 'package:bili_tv_app/services/audio_track.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _dash({bool dolby = false, bool flac = false}) => {
  'audio': [
    {'id': 30216, 'bandwidth': 64000, 'baseUrl': 'a64'},
    {'id': 30280, 'bandwidth': 192000, 'baseUrl': 'a192'},
  ],
  if (dolby)
    'dolby': {
      'type': 1,
      'audio': [
        {'id': 30250, 'bandwidth': 448000, 'baseUrl': 'dolby'},
      ],
    },
  if (flac)
    'flac': {
      'display': true,
      'audio': {'id': 30251, 'bandwidth': 900000, 'baseUrl': 'flac'},
    },
};

String? _url(Map? m) => m?['baseUrl'] as String?;

void main() {
  test('只有標準音軌', () {
    final o = parseAudioOptions(_dash());
    expect(o.map((e) => e.kind), [AudioKind.standard]);
    expect(_url(o.first.stream), 'a192');
  });

  test('有杜比與 Hi-Res', () {
    final o = parseAudioOptions(_dash(dolby: true, flac: true), dolbyOk: false);
    expect(o.map((e) => e.kind), AudioKind.values);
    expect(o[1].supported, isFalse);
    expect(o[2].supported, isTrue);
  });

  test('flac 或 dolby 為 null 時略過', () {
    final d = _dash(dolby: true)..['flac'] = null;
    expect(parseAudioOptions(d).length, 2);
    final d2 = _dash()..['dolby'] = null;
    expect(parseAudioOptions(d2).length, 1);
  });

  test('selectAudio 選擇與退回', () {
    final d = _dash(dolby: true, flac: true);
    expect(
      _url(selectAudio(d, AudioKind.dolby, dolbyOk: true, hiresOk: true)),
      'dolby',
    );
    expect(
      _url(selectAudio(d, AudioKind.hires, dolbyOk: true, hiresOk: true)),
      'flac',
    );
    // 裝置不支援退回標準
    expect(
      _url(selectAudio(d, AudioKind.dolby, dolbyOk: false, hiresOk: true)),
      'a192',
    );
    // 影片沒有該音軌退回標準
    expect(
      _url(selectAudio(_dash(), AudioKind.hires, dolbyOk: true, hiresOk: true)),
      'a192',
    );
    expect(
      selectedAudioKind(d, AudioKind.dolby, dolbyOk: false, hiresOk: true),
      AudioKind.standard,
    );
    expect(
      selectAudio({}, AudioKind.standard, dolbyOk: true, hiresOk: true),
      isNull,
    );
  });
}
