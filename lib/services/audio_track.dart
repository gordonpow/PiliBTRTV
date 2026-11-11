/// 音軌種類：標準、杜比全景聲、Hi-Res 無損。
/// 注意：`index` 會存進 SettingsService，新增項目只能加在最後。
enum AudioKind { standard, dolby, hires }

/// 影片可用的一個音軌選項。
class AudioOption {
  final AudioKind kind;

  /// DASH 音訊串流（含 baseUrl、codecs、bandwidth 等）
  final Map stream;

  /// 此裝置是否支援播放
  final bool supported;

  const AudioOption({
    required this.kind,
    required this.stream,
    this.supported = true,
  });
}

Map? _firstMap(Object? v) {
  if (v is Map) return v;
  if (v is List && v.isNotEmpty && v.first is Map) return v.first as Map;
  return null;
}

/// 標準音軌：`audio` 中 bandwidth 最高的一條。
Map? _pickStandard(Map dash) {
  final audios = dash['audio'];
  if (audios is! List) return null;
  Map? best;
  num bestBw = -1;
  for (final a in audios) {
    if (a is! Map) continue;
    final bw = (a['bandwidth'] as num?) ?? 0;
    if (best == null || bw > bestBw) {
      best = a;
      bestBw = bw;
    }
  }
  return best;
}

Map? _pickDolby(Map dash) {
  final dolby = dash['dolby'];
  if (dolby is! Map) return null;
  return _firstMap(dolby['audio']);
}

Map? _pickHires(Map dash) {
  final flac = dash['flac'];
  if (flac is! Map) return null;
  return _firstMap(flac['audio']);
}

/// 解析本影片的音軌選項（標準一定在最前面，其後依序是杜比、Hi-Res）。
/// [dolbyOk]／[hiresOk] 為裝置支援狀態，用來標記 [AudioOption.supported]。
List<AudioOption> parseAudioOptions(
  Map dash, {
  bool dolbyOk = true,
  bool hiresOk = true,
}) {
  final out = <AudioOption>[];
  final std = _pickStandard(dash);
  if (std != null) out.add(AudioOption(kind: AudioKind.standard, stream: std));
  final dolby = _pickDolby(dash);
  if (dolby != null) {
    out.add(
      AudioOption(kind: AudioKind.dolby, stream: dolby, supported: dolbyOk),
    );
  }
  final hires = _pickHires(dash);
  if (hires != null) {
    out.add(
      AudioOption(kind: AudioKind.hires, stream: hires, supported: hiresOk),
    );
  }
  return out;
}

/// 依想要的音軌選出串流；影片沒有該音軌或裝置不支援時退回標準。
/// 完全沒有音訊時回傳 null。
Map? selectAudio(
  Map dash,
  AudioKind want, {
  required bool dolbyOk,
  required bool hiresOk,
}) {
  if (want == AudioKind.dolby && dolbyOk) {
    final d = _pickDolby(dash);
    if (d != null) return d;
  }
  if (want == AudioKind.hires && hiresOk) {
    final h = _pickHires(dash);
    if (h != null) return h;
  }
  return _pickStandard(dash);
}

/// 回傳 [selectAudio] 實際選到的音軌種類（與其退回規則一致）。
AudioKind selectedAudioKind(
  Map dash,
  AudioKind want, {
  required bool dolbyOk,
  required bool hiresOk,
}) {
  if (want == AudioKind.dolby && dolbyOk && _pickDolby(dash) != null) {
    return AudioKind.dolby;
  }
  if (want == AudioKind.hires && hiresOk && _pickHires(dash) != null) {
    return AudioKind.hires;
  }
  return AudioKind.standard;
}

/// 音軌顯示名稱
String audioKindLabel(AudioKind kind) => switch (kind) {
  AudioKind.standard => '標準',
  AudioKind.dolby => '杜比全景聲',
  AudioKind.hires => 'Hi-Res 無損',
};
