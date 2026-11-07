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
  }) async {
    try {
      await BaseApi.ensureWbiKeys();

      final params = {
        'bvid': bvid,
        'cid': cid.toString(),
        'qn': qn.toString(),
        'fnval': '4048', // 請求 DASH + HEVC + AV1 + HDR 等全格式
        'fnver': '0',
        'fourk': '1',
      };

      final signedParams = SignUtils.signWithWbi(
        params,
        BaseApi.imgKey!,
        BaseApi.subKey!,
      );
      final queryString = signedParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final url = 'https://api.bilibili.com/x/player/playurl?$queryString';

      final response = await http.get(
        Uri.parse(url),
        headers: BaseApi.getHeaders(withCookie: true),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'];

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

              // 獲取硬體解碼器支援列表
              final hwDecoders = await CodecService.getHardwareDecoders();
              final hasAv1Hw = hwDecoders.contains('av1');
              final hasHevcHw = hwDecoders.contains('hevc');
              final hasAvcHw = hwDecoders.contains('avc');

              // 1. 如果指定了 forceCodec（失敗回退時），優先使用
              if (forceCodec != null && forceCodec != VideoCodec.auto) {
                selectedVideo = candidateVideos.firstWhere((v) {
                  final codecs = v['codecs'] as String? ?? '';
                  return codecs.startsWith(forceCodec.prefix);
                }, orElse: () => null);
              }

              // 2. 首次嘗試（forceCodec==null），使用使用者設定
              if (selectedVideo == null && forceCodec == null) {
                final userCodec = SettingsService.preferredCodec;

                if (userCodec != VideoCodec.auto) {
                  // 使用者指定了具體編碼器
                  selectedVideo = candidateVideos.firstWhere((v) {
                    final codecs = v['codecs'] as String? ?? '';
                    return codecs.startsWith(userCodec.prefix);
                  }, orElse: () => null);
                } else {
                  // 使用者設定是"自動"，智慧選硬解最優: AV1 > HEVC > AVC
                  if (hasAv1Hw) {
                    selectedVideo = candidateVideos.firstWhere((v) {
                      final codecs = v['codecs'] as String? ?? '';
                      return codecs.startsWith('av01');
                    }, orElse: () => null);
                  }

                  if (selectedVideo == null && hasHevcHw) {
                    selectedVideo = candidateVideos.firstWhere((v) {
                      final codecs = v['codecs'] as String? ?? '';
                      return codecs.startsWith('hev') ||
                          codecs.startsWith('hvc');
                    }, orElse: () => null);
                  }

                  if (selectedVideo == null && hasAvcHw) {
                    selectedVideo = candidateVideos.firstWhere((v) {
                      final codecs = v['codecs'] as String? ?? '';
                      return codecs.startsWith('avc');
                    }, orElse: () => null);
                  }
                }
              }

              // 3. 兜底：確保有影片（可能會用軟解）
              selectedVideo ??= candidateVideos.first;

              videoUrl = selectedVideo['baseUrl'] ?? selectedVideo['base_url'];
              final selectedCodec = selectedVideo['codecs'] as String? ?? '';

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

              if (videoUrl != null) {
                return {
                  'url': videoUrl,
                  'audioUrl': audioUrl,
                  'qualities': qualities,
                  'currentQuality': data['quality'] ?? qn,
                  'isDash': isDash,
                  'codec': selectedCodec,
                  'dashData': data['dash'],
                };
              }
            }
          } else if (data['durl'] != null) {
            final durls = data['durl'] as List;
            if (durls.isNotEmpty) {
              videoUrl = durls[0]['url'];
            }
          }
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
