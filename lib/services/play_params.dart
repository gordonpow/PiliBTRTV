import 'package:flutter/foundation.dart' show debugPrint;

import 'auth_service.dart';
import 'bilibili_api.dart';
import 'codec_service.dart';
import 'playback_perf.dart';
import 'settings_service.dart';

/// 播放網址的共用請求邏輯（播放器與焦點預載共用，確保兩邊參數一致）
class PlayParams {
  PlayParams._();

  /// 播放器第一次請求的預設畫質（對應 PlayerStateMixin.currentQuality 的初始值）
  static const int initialQn = 80;

  /// 初次 qn 請求 + VIP 智慧升級。回傳最終 playInfo（可能含 error 或為 null）。
  static Future<Map<String, dynamic>?> resolvePlayInfo({
    required String bvid,
    required int cid,
    required int qn,
    VideoCodec? codec,
    int? epId,
  }) async {
    // 1. 首次請求: 使用預設畫質(80)或當前設定畫質
    // 這樣可以獲取到影片實際支援的 accept_quality 列表，而不是盲猜
    var playInfo = await BilibiliApi.getVideoPlayUrl(
      bvid: bvid,
      cid: cid,
      qn: qn,
      forceCodec: codec,
      epId: epId,
    );

    // 2. 智慧升級 (僅針對 VIP)
    // 如果是 VIP 且首次請求成功，檢查是否有更高畫質可用
    if (AuthService.isVip &&
        playInfo != null &&
        playInfo['qualities'] != null) {
      final qualities = playInfo['qualities'] as List;
      if (qualities.isNotEmpty) {
        // 獲取該影片支援的最高畫質
        // qualities 是 List<Map<String, dynamic>>, 需提取 qn 並排序
        final supportedQns = qualities.map((e) => e['qn'] as int).toList();
        // 解碼上限（缺少時不限制）；自動升級一律排除 HDR(125)、杜比(126)、8K(127)
        final cap = playInfo['maxDecodableQn'] as int?;
        final allowedQns = supportedQns.where(
          (q) => (cap == null || q <= cap) && q != 125 && q != 126 && q != 127,
        );
        if (allowedQns.isNotEmpty) {
          final maxQn = allowedQns.reduce(
            (curr, next) => curr > next ? curr : next,
          );
          final currentQn = playInfo['currentQuality'] as int? ?? 0;

          // 如果最高畫質 > 當前畫質 (且當前畫質只是預設的80，或者我們想強制升級)
          // 注意: 有時候 maxQn 可能高達 127/126，而 currentQn 只有 80
          if (maxQn > currentQn) {
            debugPrint(
              '🎬 [SmartQuality] VIP detected. Upgrading from $currentQn to $maxQn (HDR/Dolby/8K skipped)',
            );

            final upgradePlayInfo = await BilibiliApi.getVideoPlayUrl(
              bvid: bvid,
              cid: cid,
              qn: maxQn, // 精確請求最高畫質
              forceCodec: codec,
              epId: epId,
            );

            // 如果升級請求成功，使用新資料（若指定 codec 則升級結果不可偏離所要求編碼）
            if (upgradePlayInfo != null &&
                upgradePlayInfo['hwDecodable'] == false) {
              debugPrint('🎬 [SmartQuality] 升級後的串流無法硬體解碼，沿用 $currentQn');
            } else if (upgradePlayInfo != null &&
                upgradePlayInfo['error'] == null &&
                (codec == null ||
                    (upgradePlayInfo['codec'] as String? ?? '')
                        .toLowerCase()
                        .startsWith(codec.prefix))) {
              playInfo = upgradePlayInfo;
              playInfo = await _capKnownBad4k60(
                playInfo,
                bvid: bvid,
                cid: cid,
                codec: codec,
                epId: epId,
                supportedQns: supportedQns,
              );
            }
          }
        }
      }
    }
    return playInfo;
  }

  /// 已知此裝置 4K 60 幀不順時，自動升級選到 4K 高幀率就改請求 1080P60（116）。
  /// 改成功時在回傳的 playInfo 加 `known4k60Capped: true`，由播放器顯示提示與寫效能紀錄。
  static Future<Map<String, dynamic>> _capKnownBad4k60(
    Map<String, dynamic> info, {
    required String bvid,
    required int cid,
    required VideoCodec? codec,
    required int? epId,
    required List<int> supportedQns,
  }) async {
    if (!SettingsService.known4k60Bad) return info;
    final v = (info['dashData'] as Map?)?['video'];
    if (v is! List || v.isEmpty || v.first is! Map) return info;
    final qn = (info['currentQuality'] as num?)?.toInt() ?? 0;
    // 用目前畫質那條串流的幀率；找不到才退回第一條
    final stream = v.whereType<Map>().firstWhere(
      (m) => (m['id'] as num?)?.toInt() == qn,
      orElse: () => v.first as Map,
    );
    final fps = CodecService.parseFps(
      stream['frameRate'] ?? stream['frame_rate'],
    );
    final cap = autoQnCap(qn: qn, fps: fps, known4k60Bad: true, manual: false);
    if (cap == qn || !supportedQns.contains(cap)) return info;
    final capped = await BilibiliApi.getVideoPlayUrl(
      bvid: bvid,
      cid: cid,
      qn: cap,
      forceCodec: codec,
      epId: epId,
    );
    if (capped == null ||
        capped['error'] != null ||
        capped['hwDecodable'] == false) {
      return info;
    }
    return {...capped, 'known4k60Capped': true};
  }
}
