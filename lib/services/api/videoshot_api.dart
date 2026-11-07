import 'dart:convert';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'base_api.dart';
import '../../models/videoshot.dart';

/// 影片快照 API
class VideoshotApi {
  /// 獲取影片快照(雪碧圖)資料
  ///
  /// [bvid] 影片 BV 號
  /// [cid] 影片分P的 cid (可選，不傳則獲取預設分P)
  static Future<VideoshotData?> getVideoshot({
    required String bvid,
    int? cid,
  }) async {
    try {
      final params = <String, String>{'bvid': bvid};
      if (cid != null) {
        params['cid'] = cid.toString();
      }

      final uri = Uri.parse(
        '${BaseApi.apiBase}/x/player/videoshot',
      ).replace(queryParameters: params);

      final response = await http.get(uri, headers: BaseApi.getHeaders());

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final data = json['data'] as Map<String, dynamic>;
          final images = data['image'] as List<dynamic>?;

          // 檢查是否有有效的雪碧圖
          if (images != null && images.isNotEmpty) {
            final videoshotData = VideoshotData.fromJson(data);

            // 非同步載入 pvdata（精確時間戳）和圖片資源
            if (videoshotData.pvdataUrl != null) {
              _loadPvdata(videoshotData);
            }
            _preloadImages(videoshotData);

            return videoshotData;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to get videoshot: $e');
    }
    return null;
  }

  /// 非同步載入 pvdata.bin 並解析幀時間戳
  static Future<void> _loadPvdata(VideoshotData data) async {
    if (data.pvdataUrl == null) return;

    try {
      final response = await http.get(
        Uri.parse(data.pvdataUrl!),
        headers: BaseApi.getHeaders(),
      );

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final timestamps = VideoshotData.parsePvdata(Uint8List.fromList(bytes));
        data.setTimestamps(timestamps);
        debugPrint('Loaded ${timestamps.length} frame timestamps from pvdata');
      }
    } catch (e) {
      debugPrint('Failed to load pvdata: $e');
      // 載入失敗時繼續使用均勻分佈估算
    }
  }

  /// 自定義快取管理器，用於管理雪碧圖
  /// 增加最大快取數量(1000)和保留時間(7天)，避免頻繁清理導致重新下載
  static final cacheManager = CacheManager(
    Config(
      'videoshot_cache',
      stalePeriod: const Duration(hours: 5),
      maxNrOfCacheObjects: 100,
      repo: JsonCacheInfoRepository(databaseName: 'videoshot_cache'),
      fileService: HttpFileService(),
    ),
  );

  /// 預載入雪碧圖圖片到快取
  static Future<void> _preloadImages(VideoshotData data) async {
    try {
      for (final url in data.images) {
        // 使用自定義快取管理器預下載
        cacheManager.downloadFile(url);
      }
      debugPrint('Started preloading ${data.images.length} videoshot images');
    } catch (e) {
      debugPrint('Failed to preload images: $e');
    }
  }

  /// 預載入單張雪碧圖到 Flutter 記憶體快取 (GPU)
  ///
  /// [context] Flutter BuildContext
  /// [url] 雪碧圖 URL
  static Future<void> precacheSprite(BuildContext context, String url) async {
    try {
      final provider = CachedNetworkImageProvider(
        url,
        cacheManager: cacheManager,
        headers: const {
          'Referer': 'https://www.bilibili.com',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
        },
      );
      await precacheImage(provider, context);
      debugPrint('Precached sprite to GPU: ${url.split('/').last}');
    } catch (e) {
      debugPrint('Failed to precache sprite: $e');
    }
  }

  /// 從 Flutter 記憶體快取中移除雪碧圖
  ///
  /// [url] 雪碧圖 URL
  static void evictSprite(String url) {
    try {
      final provider = CachedNetworkImageProvider(
        url,
        cacheManager: cacheManager,
        headers: const {
          'Referer': 'https://www.bilibili.com',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
        },
      );
      provider.evict();
      debugPrint('Evicted sprite from GPU: ${url.split('/').last}');
    } catch (e) {
      debugPrint('Failed to evict sprite: $e');
    }
  }
}
