import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../utils/zh_convert.dart';

/// 設定分類。放在這裡讓索引與 settings_view 共用，避免循環 import。
enum SettingsCategory {
  playback('播放設定'),
  btr('線程撕裂者'),
  interface_('介面設定'),
  plugins('外掛中心'),
  storage('其他設定'),
  about('關於軟體');

  const SettingsCategory(this.label);
  final String label;
}

/// 搜尋結果選中後，要聚焦的設定項目（以 row 的 label 辨識）。
///
/// 對應的 row 監聽 [notifier]，label 符合時請求焦點。
abstract final class SettingsFocusTarget {
  static final ValueNotifier<String?> notifier = ValueNotifier<String?>(null);
}

/// 設定索引的一筆資料。
class SettingsEntry {
  const SettingsEntry(
    this.label,
    this.subtitle,
    this.category, {
    this.englishOnly = false,
  });

  final String label;
  final String subtitle;
  final SettingsCategory category;

  /// 只在英文模式才有的項目（例如「更新語言包」），其他語言不列入搜尋結果。
  final bool englishOnly;
}

/// 設定索引：與 tabs/*.dart 的 row label／subtitle 對應。
abstract final class SettingsIndex {
  static const entries = <SettingsEntry>[
    // 播放設定
    SettingsEntry(
      '播放完畢後',
      '播完暫停、直接播下一部、倒數後播下一部、循環播放此影片、列表循環',
      SettingsCategory.playback,
    ),
    SettingsEntry('連播倒數', '「倒數後播下一部」模式播完後倒數幾秒', SettingsCategory.playback),
    SettingsEntry('迷你進度條', '播放時在螢幕底部顯示簡約進度條', SettingsCategory.playback),
    SettingsEntry('預設隱藏控制欄', '開啟影片時不顯示控制欄和進度條', SettingsCategory.playback),
    SettingsEntry('快進預覽模式', '快進快退時顯示預覽縮圖，按確定跳轉', SettingsCategory.playback),
    SettingsEntry('播放畫面模式', '影片顏色或順暢度異常時可切換試試', SettingsCategory.playback),
    SettingsEntry('影片解碼器', '自動=按硬體支援選最優，失敗時降級到其他格式', SettingsCategory.playback),
    SettingsEntry(
      '隧道播放（實驗）',
      '4K 60 幀不順時可試試，只在「原生」畫面模式有效；黑畫面或沒聲音請關閉',
      SettingsCategory.playback,
    ),
    // 線程撕裂者
    SettingsEntry('播放加速', '播放時從多個 CDN 節點並行下載，減少卡頓', SettingsCategory.btr),
    SettingsEntry('CDN 模式', '節點輪換使用，連續兩次 0 KiB 的節點會被停用', SettingsCategory.btr),
    SettingsEntry('自訂 CDN 節點', '編輯', SettingsCategory.btr),
    SettingsEntry('自動執行緒數（推薦）', '播放使用 8 個執行緒', SettingsCategory.btr),
    SettingsEntry('執行緒數', '每個播放請求使用的執行緒數', SettingsCategory.btr),
    // 介面設定
    SettingsEntry('啟動動畫', '啟動應用時顯示動畫，關閉則直接進入主頁', SettingsCategory.interface_),
    SettingsEntry('總是顯示時間', '播放介面右上角總是顯示當前時間', SettingsCategory.interface_),
    SettingsEntry(
      '影片卡片預覽',
      '游標停在影片卡片上 1 秒，靜音預覽 10 秒',
      SettingsCategory.interface_,
    ),
    SettingsEntry(
      '語言',
      '切換語言（繁體／簡體／English），重新啟動後生效',
      SettingsCategory.interface_,
    ),
    SettingsEntry(
      '更新語言包',
      '下載最新的英文語言包',
      SettingsCategory.interface_,
      englishOnly: true,
    ),
    SettingsEntry(
      '翻譯 B 站內容',
      '使用 Google ML Kit 在本機翻譯影片標題、UP 主名稱與字幕（需下載約 30MB 模型）',
      SettingsCategory.interface_,
      englishOnly: true,
    ),
    SettingsEntry(
      '首頁分區',
      '分區開關、分區排序 推薦 熱門 番劇 影視 遊戲 知識 科技 音樂 舞蹈 生活 美食 動畫',
      SettingsCategory.interface_,
    ),
    SettingsEntry('直播分區', '直播分區開關、直播分區排序', SettingsCategory.interface_),
    // 外掛中心
    SettingsEntry('去廣告增強', '過濾廣告、拉黑UP主、遮蔽關鍵詞', SettingsCategory.plugins),
    SettingsEntry('彈幕遮蔽', '遮蔽包含指定關鍵詞的彈幕', SettingsCategory.plugins),
    SettingsEntry(
      '空降助手',
      '基於 SponsorBlock 資料庫自動跳過影片中的廣告、贊助、片頭片尾等片段',
      SettingsCategory.plugins,
    ),
    // 其他設定
    SettingsEntry('清除圖片快取', '清除', SettingsCategory.storage),
    // 關於軟體
    SettingsEntry('檢查更新', '檢查 查看 有新版本 已是最新', SettingsCategory.about),
    SettingsEntry('自動檢查更新', '', SettingsCategory.about),
    SettingsEntry('檢查間隔', '', SettingsCategory.about),
    SettingsEntry('回報問題/建議', '送出錯誤報告或功能建議給開發者', SettingsCategory.about),
    SettingsEntry('回報紀錄', '查看 尚無紀錄 最近一次', SettingsCategory.about),
  ];

  /// 正規化：繁簡轉成同一種寫法後轉小寫。query 與索引文字用同一個函式。
  static String normalize(String text, {String Function(String)? convert}) {
    return (convert ?? ZhConvert.convert)(text.trim()).toLowerCase();
  }

  /// 以 [query] 搜尋 [source]（預設為內建索引）。
  /// query 為空白時回傳空清單。可傳入 [convert] 方便測試。
  static List<SettingsEntry> search(
    String query, {
    List<SettingsEntry> source = entries,
    String Function(String)? convert,
  }) {
    final q = normalize(query, convert: convert);
    if (q.isEmpty) return const [];
    final conv = convert ?? ZhConvert.convert;
    bool matches(SettingsEntry e) {
      if (e.englishOnly && ZhConvert.script != ZhScript.english) return false;
      if (normalize('${e.label} ${e.subtitle}', convert: convert).contains(q)) {
        return true;
      }
      // 英文模式：也比對翻譯後的 label 與 subtitle
      final translated = '${conv(e.label)} ${conv(e.subtitle)}';
      return normalize(translated, convert: convert).contains(q);
    }

    return [
      for (final e in source)
        if (matches(e)) e,
    ];
  }
}
