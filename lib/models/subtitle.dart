// CC 字幕資料模型與純邏輯（#17）。

/// 一條字幕軌。[machine] 為 true 表示由中文軌機器翻譯出的 English 軌（不對應 B 站的軌）。
class SubtitleTrack {
  final int id;
  final String lan;
  final String lanDoc;
  final String url;
  final bool isAi;
  final bool machine;

  const SubtitleTrack({
    required this.id,
    required this.lan,
    required this.lanDoc,
    required this.url,
    this.isAi = false,
    this.machine = false,
  });

  /// 解析 v2 API 的 subtitles[] 單項；subtitle_url 為空回 null（需登入才有）。
  static SubtitleTrack? fromJson(Map<String, dynamic> json) {
    final url = (json['subtitle_url'] ?? '').toString();
    if (url.isEmpty) return null;
    final lan = (json['lan'] ?? '').toString();
    return SubtitleTrack(
      id: (json['id'] as num?)?.toInt() ?? 0,
      lan: lan,
      lanDoc: (json['lan_doc'] ?? lan).toString(),
      url: url,
      isAi: json['type'] == 1,
    );
  }

  /// 英文軌：en、en-US、ai-en 等。
  bool get isEnglish => lan.startsWith('en') || lan == 'ai-en';

  /// 中文軌：zh-CN、ai-zh 等。
  bool get isChinese => lan.contains('zh');

  /// 機器翻譯軌的固定標籤。
  static const SubtitleTrack machineEnglish = SubtitleTrack(
    id: -1,
    lan: 'en-machine',
    lanDoc: 'English（機器翻譯）',
    url: '',
    machine: true,
  );

  /// 選單顯示名稱：AI 軌補「（自動生成）」（B 站名稱已含時不重複）。
  String get label {
    if (isAi &&
        !lanDoc.contains('自动') && // 與伺服器回傳的簡體文字比對
        !lanDoc.contains('自動') &&
        !lanDoc.toUpperCase().contains('AI')) {
      return '$lanDoc（自動生成）';
    }
    return lanDoc;
  }
}

/// 一行字幕，時間單位為秒。
class SubtitleLine {
  final double from;
  final double to;
  final String content;

  const SubtitleLine({
    required this.from,
    required this.to,
    required this.content,
  });

  SubtitleLine withContent(String c) =>
      SubtitleLine(from: from, to: to, content: c);
}

/// 解析字幕 body[]（略過格式不符或內容為空的項目），依 from 排序。
List<SubtitleLine> parseSubtitleBody(List<dynamic>? body) {
  if (body == null) return const [];
  final lines = <SubtitleLine>[];
  for (final e in body) {
    if (e is! Map) continue;
    final from = (e['from'] as num?)?.toDouble();
    final to = (e['to'] as num?)?.toDouble();
    final content = (e['content'] ?? '').toString();
    if (from == null || to == null || content.trim().isEmpty) continue;
    lines.add(SubtitleLine(from: from, to: to, content: content));
  }
  lines.sort((a, b) => a.from.compareTo(b.from));
  return lines;
}

/// 找涵蓋 [pos]（`from <= pos < to`）的行；沒有回 null。[lines] 須依 from 排序。
/// 二分找到最後一個 from <= pos 的行，再往回找第一個仍涵蓋 pos 的行（處理長字幕與重疊）。
/// 往回掃描最多 [maxBack] 行，一般字幕只需 1～2 步。
SubtitleLine? findSubtitleLine(
  List<SubtitleLine> lines,
  double pos, {
  int maxBack = 64,
}) {
  int lo = 0, hi = lines.length - 1, cand = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].from <= pos) {
      cand = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  for (int i = cand; i >= 0 && i > cand - maxBack; i--) {
    if (pos < lines[i].to) return lines[i];
  }
  return null;
}

/// 預設選軌（AC-3）。回傳 [tracks] 的索引，沒有可選回 -1。
/// 英文介面：英文 > 中文；其餘：中文。同語言非 AI 優先。找不到偏好語言時回 -1。
int pickDefaultSubtitle(List<SubtitleTrack> tracks, {required bool english}) {
  int best(bool Function(SubtitleTrack) test) {
    int idx = -1;
    for (int i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      if (t.machine || !test(t)) continue;
      if (idx < 0 || (tracks[idx].isAi && !t.isAi)) idx = i;
    }
    return idx;
  }

  if (english) {
    final en = best((t) => t.isEnglish);
    if (en >= 0) return en;
  }
  return best((t) => t.isChinese);
}

/// 是否提供「English（機器翻譯）」軌（R-12）。
bool machineTrackAvailable(
  List<SubtitleTrack> tracks, {
  required bool englishUi,
  required bool translatorEnabled,
}) {
  if (!englishUi || !translatorEnabled) return false;
  if (tracks.any((t) => t.isEnglish)) return false;
  return tracks.any((t) => t.isChinese);
}
