import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'base_api.dart';
import 'sign_utils.dart';
import '../auth_service.dart';
import '../codec_service.dart';
import '../settings_service.dart';

/// 播放相關 API (影片詳情、播放地址、彈幕、進度上報)
class PlaybackApi {
  /// 獲取影片詳情（包含分P資訊和播放歷史）
  static Future<Map<String, dynamic>?> getVideoInfo(String bvid) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url =
          'https://api.bilibili.com/x/web-interface/view?bvid=$bvid&_=$timestamp';
      final headers = BaseApi.getHeaders(withCookie: true);
      debugPrint(
        '🎬 [API] getVideoInfo headers: ${headers['Cookie'] != null ? 'Cookie present' : 'NO COOKIE'}',
      );

      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0) {
          return json['data'];
        }
      }
    } catch (e) {
      // print('getVideoInfo error: $e');
    }
    return null;
  }

  /// 獲取影片的 cid (用於播放和彈幕)
  static Future<int?> getVideoCid(String bvid) async {
    try {
      final url = 'https://api.bilibili.com/x/web-interface/view?bvid=$bvid';

      final response = await http.get(
        Uri.parse(url),
        headers: BaseApi.getHeaders(),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          return json['data']['cid'];
        }
      }
    } catch (e) {
      // print('getVideoCid error: $e');
    }
    return null;
  }

  /// 獲取影片播放地址
  /// 返回 {'url': String, 'audioUrl': String?, 'qualities': List<Map>, 'currentQuality': int, 'isDash': bool}
  /// [forceCodec] 強制指定編碼器 (用於失敗重試)
  static Future<Map<String, dynamic>?> getVideoPlayUrl({
    required String bvid,
    required int cid,
    int qn = 80,
    VideoCodec? forceCodec,
    int? epId, // 非 null 時走番劇 (PGC) playurl
    bool riskRetried = false, // 已因風控 (-351/-352) 重試過一次
  }) async {
    try {
      final isPgc = epId != null;
      if (!isPgc) await BaseApi.ensureWbiKeys();

      final params = {
        'bvid': bvid,
        'cid': cid.toString(),
        'qn': qn.toString(),
        'fnval': '4048', // 請求 DASH + HEVC + AV1 + HDR 等全格式
        'fnver': '0',
        'fourk': '1',
        // 以下參數同網頁版（參考 PiliPlus），缺少時容易被風控回 -351/-352
        'voice_balance': '0',
        'gaia_source': 'pre-load',
        'isGaiaAvoided': 'true',
        'web_location': '1315873',
        if (!AuthService.isLoggedIn) 'try_look': '1', // 未登入也可看 1080P
        'dm_img_list': '[]',
        'dm_img_str': BaseApi.randomBase64(16, 64),
        'dm_cover_img_str': BaseApi.randomBase64(32, 128),
        'dm_img_inter': '{"ds":[],"wh":[0,0,0],"of":[0,0,0]}',
      };

      String url;
      if (isPgc) {
        // 番劇 playurl 不需要 WBI 簽名，回傳的 result.video_info 結構同 UGC 的 data
        final pgcParams = {
          'ep_id': epId.toString(),
          'cid': cid.toString(),
          'qn': qn.toString(),
          'fnval': '4048',
          'fnver': '0',
          'fourk': '1',
        };
        final queryString = pgcParams.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&');
        url = 'https://api.bilibili.com/pgc/player/web/v2/playurl?$queryString';
      } else {
        final signedParams = SignUtils.signWithWbi(
          params,
          BaseApi.imgKey!,
          BaseApi.subKey!,
        );
        final queryString = signedParams.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&');
        url = 'https://api.bilibili.com/x/player/wbi/playurl?$queryString';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final dynamic rawData = isPgc
            ? (json['result'] is Map ? json['result']['video_info'] : null)
            : json['data'];
        if (isPgc && (json['code'] != 0 || rawData == null)) {
          // 番劇錯誤 (如 -10403 地區限制)：直接回傳 B站訊息，標記為 API 錯誤，不再換編碼器重試
          return {
            'error': json['code'] != 0
                ? '${json['message'] ?? '未知錯誤'}（${json['code']}）'
                : '此集需要大會員或無法播放（${json['code']}）',
            'apiError': true,
          };
        }
        if (json['code'] == 0 && rawData != null) {
          final data = rawData;

          final qualities = <Map<String, dynamic>>[];
          final acceptQuality = data['accept_quality'] as List? ?? [];
          final acceptDesc = data['accept_description'] as List? ?? [];
          for (int i = 0; i < acceptQuality.length; i++) {
            qualities.add({
              'qn': acceptQuality[i],
              'desc': i < acceptDesc.length
                  ? acceptDesc[i]
                  : '${acceptQuality[i]}P',
            });
          }

          String? videoUrl;
          String? audioUrl;
          bool isDash = false;

          if (data['dash'] != null) {
            isDash = true;
            final dash = data['dash'];
            final videos = dash['video'] as List? ?? [];
            final audios = dash['audio'] as List? ?? [];

            if (videos.isNotEmpty) {
              final videosByQuality = <int, List<dynamic>>{};
              for (final v in videos) {
                final id = v['id'] as int? ?? 0;
                videosByQuality.putIfAbsent(id, () => []).add(v);
              }

              final targetQn = qn;
              var candidateVideos = videosByQuality[targetQn];
              if (candidateVideos == null || candidateVideos.isEmpty) {
                final sortedQualities = videosByQuality.keys.toList()
                  ..sort(
                    (a, b) =>
                        (b - targetQn).abs().compareTo((a - targetQn).abs()),
                  );
                if (sortedQualities.isNotEmpty) {
                  candidateVideos = videosByQuality[sortedQualities.first];
                }
              }
              candidateVideos ??= videos;

              dynamic selectedVideo;

              final fallbackToAvc = SettingsService.codecFallbackAvc;

              // 解析度／幀率是否有硬體解碼器可用
              Future<bool> hwOk(dynamic v) async {
                final family = CodecService.codecFamily(
                  v['codecs'] as String? ?? '',
                );
                if (family == null) return false;
                final w = (v['width'] as num?)?.toInt() ?? 0;
                final h = (v['height'] as num?)?.toInt() ?? 0;
                final fps = CodecService.parseFps(
                  v['frameRate'] ?? v['frame_rate'],
                );
                return CodecService.canHwDecode(family, w, h, fps);
              }

              // 允許的編碼家族內，可硬解的最大畫質 id
              Future<int?> maxQn() async {
                final VideoCodec? limit =
                    (forceCodec != null && forceCodec != VideoCodec.auto)
                    ? forceCodec
                    : (forceCodec == null &&
                          SettingsService.preferredCodec != VideoCodec.auto)
                    ? SettingsService.preferredCodec
                    : null;
                final allowed = limit != null
                    ? {limit.name}
                    : fallbackToAvc
                    ? {'avc'}
                    : {'avc', 'hevc', 'av1'};
                final hdr = await CodecService.isHdrDisplay();
                int? best;
                for (final v in videos) {
                  final id = v['id'] as int? ?? 0;
                  if (!hdr && (id == 125 || id == 126)) continue;
                  if (best != null && id <= best) continue;
                  final family = CodecService.codecFamily(
                    v['codecs'] as String? ?? '',
                  );
                  if (family == null || !allowed.contains(family)) continue;
                  if (await hwOk(v)) best = id;
                }
                return best;
              }

              // 1. 如果指定了 forceCodec（失敗回退時），優先使用
              if (forceCodec != null && forceCodec != VideoCodec.auto) {
                selectedVideo = candidateVideos.firstWhere((v) {
                  final codecs = (v['codecs'] as String? ?? '').toLowerCase();
                  return codecs.startsWith(forceCodec.prefix);
                }, orElse: () => null);

                // 若當前畫質沒有該編碼（如 4K 只有 HEVC/AV1，但強制要求 AVC）：
                // 向下在其他畫質尋找符合 forceCodec 的串流
                selectedVideo ??= videos.firstWhere((v) {
                  final codecs = (v['codecs'] as String? ?? '').toLowerCase();
                  return codecs.startsWith(forceCodec.prefix);
                }, orElse: () => null);
              }

              // 2. 首次嘗試（forceCodec==null），使用使用者設定
              if (selectedVideo == null && forceCodec == null) {
                final userCodec = SettingsService.preferredCodec;

                if (userCodec != VideoCodec.auto) {
                  // 使用者指定了具體編碼器
                  selectedVideo = candidateVideos.firstWhere((v) {
                    final codecs = (v['codecs'] as String? ?? '').toLowerCase();
                    return codecs.startsWith(userCodec.prefix);
                  }, orElse: () => null);

                  // 若當前畫質沒有該編碼，在所有畫質尋找
                  selectedVideo ??= videos.firstWhere((v) {
                    final codecs = (v['codecs'] as String? ?? '').toLowerCase();
                    return codecs.startsWith(userCodec.prefix);
                  }, orElse: () => null);
                } else {
                  // 使用者設定是"自動"，智慧選硬解最優: AV1 > HEVC > AVC
                  final order = fallbackToAvc
                      ? const ['avc']
                      : const ['av1', 'hevc', 'avc'];
                  for (final family in order) {
                    for (final v in candidateVideos) {
                      if (CodecService.codecFamily(
                                v['codecs'] as String? ?? '',
                              ) ==
                              family &&
                          await hwOk(v)) {
                        selectedVideo = v;
                        break;
                      }
                    }
                    if (selectedVideo != null) break;
                  }

                  // 都不能硬解：先選該畫質的 AVC
                  selectedVideo ??= candidateVideos.firstWhere((v) {
                    final codecs = (v['codecs'] as String? ?? '').toLowerCase();
                    return codecs.startsWith('avc');
                  }, orElse: () => null);
                }
              }

              // 3. 兜底：確保有影片（可能會用軟解）
              selectedVideo ??= candidateVideos.first;

              videoUrl = selectedVideo['baseUrl'] ?? selectedVideo['base_url'];
              final selectedCodec = (selectedVideo['codecs'] as String? ?? '')
                  .toLowerCase();
              final parsedCodec = selectedCodec.startsWith('avc')
                  ? 'avc'
                  : (selectedCodec.startsWith('hev') ||
                        selectedCodec.startsWith('hvc'))
                  ? 'hev'
                  : (selectedCodec.startsWith('av01') ||
                        selectedCodec.startsWith('av1'))
                  ? 'av01'
                  : selectedCodec;

              if (audios.isNotEmpty) {
                var sortedAudios = List.from(audios);
                sortedAudios.sort(
                  (a, b) =>
                      (b['bandwidth'] ?? 0).compareTo(a['bandwidth'] ?? 0),
                );
                audioUrl =
                    sortedAudios.first['baseUrl'] ??
                    sortedAudios.first['base_url'];
              }

              // 試看：code 為 0 但只提供試看片段 (「试看」為伺服器簡體字串，保留原文)
              final isPreview =
                  data['is_preview'] == 1 ||
                  acceptDesc.any((d) => d.toString().contains('试看'));

              if (videoUrl != null) {
                // 選取抽幀預覽串流：codecs 以 avc 開頭、id 最小但 >= 32 (若無則最小 id 的 avc，再無則 videoUrl)
                String? previewUrl;
                final avcVideos = videos.where((v) {
                  final codecs = (v['codecs'] as String? ?? '').toLowerCase();
                  return codecs.startsWith('avc');
                }).toList();

                if (avcVideos.isNotEmpty) {
                  final avcAtLeast32 = avcVideos.where((v) {
                    final id = v['id'] as int? ?? 0;
                    return id >= 32;
                  }).toList();

                  dynamic candidate;
                  if (avcAtLeast32.isNotEmpty) {
                    avcAtLeast32.sort(
                      (a, b) => (a['id'] as int? ?? 0).compareTo(
                        b['id'] as int? ?? 0,
                      ),
                    );
                    candidate = avcAtLeast32.first;
                  } else {
                    avcVideos.sort(
                      (a, b) => (a['id'] as int? ?? 0).compareTo(
                        b['id'] as int? ?? 0,
                      ),
                    );
                    candidate = avcVideos.first;
                  }
                  previewUrl = candidate['baseUrl'] ?? candidate['base_url'];
                }
                previewUrl ??= videoUrl;

                return {
                  'isPreview': isPgc && isPreview,
                  'url': videoUrl,
                  'audioUrl': audioUrl,
                  'qualities': qualities,
                  'currentQuality': data['quality'] ?? qn,
                  'isDash': isDash,
                  'codec': parsedCodec,
                  // MPD 只放選定的影片串流，避免 ExoPlayer 自行選到無法硬解的軌
                  'dashData': {
                    ...(data['dash'] as Map<String, dynamic>),
                    'video': [selectedVideo],
                  },
                  'previewUrl': previewUrl,
                  'hwDecodable': await hwOk(selectedVideo),
                  'maxDecodableQn': await maxQn(),
                };
              }
            }
          } else if (data['durl'] != null) {
            final durls = data['durl'] as List? ?? [];
            if (durls.isNotEmpty) {
              final firstDurl = durls[0] as Map;
              videoUrl = firstDurl['url'] as String?;
              final backupUrls = (firstDurl['backup_url'] as List? ?? [])
                  .map((e) => e.toString())
                  .where((e) => e.isNotEmpty)
                  .toList();
              final isPreview =
                  isPgc ||
                  data['is_preview'] == 1 ||
                  acceptDesc.any((d) => d.toString().contains('试看'));

              if (videoUrl != null && videoUrl.isNotEmpty) {
                return {
                  'isPreview': isPreview,
                  'url': videoUrl,
                  'backupUrls': backupUrls,
                  'audioUrl': null,
                  'qualities': qualities,
                  'currentQuality': data['quality'] ?? qn,
                  'isDash': false,
                  'codec': 'avc',
                  'dashData': null,
                  'previewUrl': videoUrl,
                  'hwDecodable': true,
                  'maxDecodableQn': null,
                };
              }
            }
          }

          if (isPgc) {
            return {'error': '此集需要大會員或無法播放（${json['code']}）', 'apiError': true};
          }
        } else if (!isPgc &&
            !riskRetried &&
            (json['code'] == -351 || json['code'] == -352)) {
          // 風控：強制更新 WBI 金鑰並換新的隨機參數，重試一次
          debugPrint('playurl 風控 ${json['code']}，重試一次');
          BaseApi.wbiKeysTime = null;
          return await getVideoPlayUrl(
            bvid: bvid,
            cid: cid,
            qn: qn,
            forceCodec: forceCodec,
            epId: epId,
            riskRetried: true,
          );
        } else {
          // API 返回錯誤碼
          throw Exception(
            'API錯誤: ${json['code']} - ${json['message'] ?? '未知錯誤'}',
          );
        }
      } else {
        // HTTP 錯誤
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      // 返回錯誤資訊而不是 null
      return {'error': e.toString()};
    }
    return null;
  }

  /// 獲取彈幕資料 (XML 格式，支援 deflate/gzip/raw)
  static Future<List<Map<String, dynamic>>> getDanmaku(int cid) async {
    try {
      final url = 'https://comment.bilibili.com/$cid.xml';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
          'Accept-Encoding': 'gzip, deflate',
        },
      );

      if (response.statusCode == 200) {
        String xmlString;
        final bytes = response.bodyBytes;

        if (bytes.isEmpty) return [];

        try {
          if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
            final decompressed = gzip.decode(bytes);
            xmlString = utf8.decode(decompressed);
          } else if (bytes.length >= 2 && bytes[0] == 0x78) {
            final decompressed = zlib.decode(bytes);
            xmlString = utf8.decode(decompressed);
          } else if (bytes.isNotEmpty && bytes[0] == 0x3c) {
            xmlString = utf8.decode(bytes);
          } else {
            final decompressed = ZLibDecoder(raw: true).convert(bytes);
            xmlString = utf8.decode(decompressed);
          }
        } catch (e) {
          xmlString = utf8.decode(bytes, allowMalformed: true);
        }

        final danmakuList = <Map<String, dynamic>>[];

        final regex = RegExp(r'<d p="([^"]+)">([^<]*)</d>');
        for (final match in regex.allMatches(xmlString)) {
          final pAttr = match.group(1)!;
          final content = match.group(2)!;

          final parts = pAttr.split(',');
          if (parts.length >= 4) {
            danmakuList.add({
              'time': double.tryParse(parts[0]) ?? 0.0,
              'type': int.tryParse(parts[1]) ?? 1,
              'fontSize': double.tryParse(parts[2]) ?? 25.0,
              'color': int.tryParse(parts[3]) ?? 0xFFFFFF,
              'content': content,
            });
          }
        }

        return danmakuList;
      }
    } catch (e) {
      // 忽略錯誤
    }
    return [];
  }

  /// 上報播放進度 (Heartbeat)
  static Future<bool> reportProgress({
    required String bvid,
    required int cid,
    required int progress,
    int? epId,
    int? seasonId,
  }) async {
    if (!AuthService.isLoggedIn) return false;

    try {
      final startTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final queryParams = {
        'bvid': bvid,
        'cid': cid.toString(),
        'played_time': progress.toString(),
        'real_played_time': progress.toString(),
        'start_ts': startTs.toString(),
        'csrf': AuthService.biliJct ?? '',
        // 番劇 heartbeat 需要 epid、sid、type=4、sub_type=1
        if (epId != null && seasonId != null) ...{
          'epid': epId.toString(),
          'sid': seasonId.toString(),
          'type': '4',
          'sub_type': '1',
        },
      };

      final queryString = queryParams.entries
          .map(
            (e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
          )
          .join('&');

      final url =
          'https://api.bilibili.com/x/click-interface/web/heartbeat?$queryString';

      final response = await http.post(
        Uri.parse(url),
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (epId != null) {
          debugPrint(
            '🎬 [Heartbeat] PGC ep=$epId code=${json['code']} message=${json['message']}',
          );
        }
        if (json['code'] == 0) {
          return true;
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return false;
  }

  /// 獲取影片線上觀看人數
  /// 返回 { 'total': 總人數字串, 'count': 本影片線上人數字串 }
  static Future<Map<String, String>?> getOnlineCount({
    required int aid,
    required int cid,
  }) async {
    try {
      final url =
          'https://api.bilibili.com/x/player/online/total?aid=$aid&cid=$cid';
      final response = await http.get(
        Uri.parse(url),
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'];
          return {'total': data['total'] ?? '', 'count': data['count'] ?? ''};
        }
      }
    } catch (e) {
      // 忽略錯誤
    }
    return null;
  }
}
