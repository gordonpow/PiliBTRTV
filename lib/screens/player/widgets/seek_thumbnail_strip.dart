import 'dart:async';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import '../../../models/videoshot.dart';
import '../../../services/api/videoshot_api.dart';
import '../../../services/frame_service.dart';

/// Netflix 式縮圖列與進度預覽 Overlay
class SeekThumbnailStrip extends StatefulWidget {
  final VideoshotData? videoshotData;
  final Duration previewPosition;
  final Duration duration;
  final String? previewFrameUrl;

  const SeekThumbnailStrip({
    super.key,
    required this.videoshotData,
    required this.previewPosition,
    required this.duration,
    this.previewFrameUrl,
  });

  @override
  State<SeekThumbnailStrip> createState() => _SeekThumbnailStripState();
}

class _SeekThumbnailStripState extends State<SeekThumbnailStrip> {
  Timer? _debounceTimer;
  Uint8List? _realFrameBytes;
  int? _currentFrameIndex;

  @override
  void initState() {
    super.initState();
    _checkFrameUpdate(force: true);
  }

  @override
  void didUpdateWidget(covariant SeekThumbnailStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.previewPosition != oldWidget.previewPosition ||
        widget.videoshotData != oldWidget.videoshotData ||
        widget.previewFrameUrl != oldWidget.previewFrameUrl) {
      _checkFrameUpdate();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _checkFrameUpdate({bool force = false}) {
    final vs = widget.videoshotData;
    if (vs == null) {
      _debounceTimer?.cancel();
      _realFrameBytes = null;
      _currentFrameIndex = null;
      return;
    }

    final k = vs.indexAt(widget.previewPosition, widget.duration);
    if (force || k != _currentFrameIndex) {
      _debounceTimer?.cancel();
      // 位置改變時先回到雪碧圖（只在 initState／didUpdateWidget 呼叫，之後必定重建）
      _realFrameBytes = null;
      _currentFrameIndex = k;

      // 停止變動 400ms 後擷取真實畫面幀
      _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
        if (!mounted) return;
        final url = widget.previewFrameUrl;
        if (url == null || url.isEmpty) return;

        final targetK = k;
        final targetTime = vs.timeOfIndex(targetK, widget.duration);
        final bytes = await FrameService.getFrame(url, targetTime);

        if (mounted && bytes != null && _currentFrameIndex == targetK) {
          setState(() {
            _realFrameBytes = bytes;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenW = size.width;
    final screenH = size.height;

    // 畫面下方約 45% 高度起，覆蓋縮圖列與進度條區域
    final overlayH = screenH * 0.55;

    final totalMs = widget.duration.inMilliseconds;
    final posMs = widget.previewPosition.inMilliseconds;
    final progress = totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: overlayH,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.95),
              Colors.black.withValues(alpha: 0.65),
              Colors.transparent,
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
        ),
        child: ClipRect(
          child: Stack(
            children: [
              // 縮圖列 (有縮圖資料時顯示)
              if (widget.videoshotData != null &&
                  widget.videoshotData!.frameCount > 0)
                _buildThumbnailStrip(screenW, screenH),

              // 下方進度條 (留白 80，左邊預覽時間，右邊總長)
              Positioned(
                left: 80,
                right: 80,
                bottom: 36,
                child: Row(
                  children: [
                    Text(
                      _formatDuration(widget.previewPosition),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFFB7299),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Text(
                      _formatDuration(widget.duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailStrip(double screenW, double screenH) {
    final vs = widget.videoshotData!;
    final k = vs.indexAt(widget.previewPosition, widget.duration);

    // 尺寸規範：中間卡片寬 = 螢幕寬 × 0.24、兩側卡片寬 = 螢幕寬 × 0.2
    final centerCardW = screenW * 0.24;
    final centerCardH = centerCardW * 9 / 16;
    final sideCardW = screenW * 0.20;
    final sideCardH = sideCardW * 9 / 16;
    const spacing = 16.0;

    // 縮圖垂直置中於畫面 60% 處 (相對於整個螢幕)
    // Overlay 起始點為 0.45 * screenH，因此在 Overlay 內的垂直中心點為 0.15 * screenH
    final cardCenterY = screenH * 0.15;
    final centerLeft = (screenW - centerCardW) / 2;

    final cards = <Widget>[];

    // 繪製兩側卡片：左邊 3 張、右邊 3 張 (超出畫面部分自然被裁切)
    for (int offset = -3; offset <= 3; offset++) {
      if (offset == 0) continue; // 中間卡片稍後置頂繪製

      final cardIndex = k + offset;
      final frameInfo = vs.frameAtIndex(cardIndex);
      // 邊界檢查：超出範圍不繪製 (審查紀錄 1)
      if (frameInfo == null) continue;

      double left;
      if (offset < 0) {
        // 左側卡片 (offset = -1, -2, -3)
        left = centerLeft - spacing - sideCardW + (offset + 1) * (sideCardW + spacing);
      } else {
        // 右側卡片 (offset = 1, 2, 3)
        left = centerLeft + centerCardW + spacing + (offset - 1) * (sideCardW + spacing);
      }

      final top = cardCenterY - sideCardH / 2;

      cards.add(
        Positioned(
          left: left,
          top: top,
          width: sideCardW,
          height: sideCardH,
          child: Opacity(
            opacity: 0.85,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildSpriteCard(
                frameInfo: frameInfo,
                cardWidth: sideCardW,
                cardHeight: sideCardH,
                data: vs,
              ),
            ),
          ),
        ),
      );
    }

    // 繪製中間卡片 (較大、白色 3px 外框、圓角 8)
    final centerFrameInfo = vs.frameAtIndex(k);
    if (centerFrameInfo != null) {
      final centerTop = cardCenterY - centerCardH / 2;

      cards.add(
        Positioned(
          left: centerLeft,
          top: centerTop,
          width: centerCardW,
          height: centerCardH,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 雪碧圖底層
                  _buildSpriteCard(
                    frameInfo: centerFrameInfo,
                    cardWidth: centerCardW,
                    cardHeight: centerCardH,
                    data: vs,
                  ),
                  // 真實抽幀畫面層 (取得後覆蓋)
                  if (_realFrameBytes != null)
                    Image.memory(
                      _realFrameBytes!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: cards,
    );
  }

  Widget _buildSpriteCard({
    required FrameInfo frameInfo,
    required double cardWidth,
    required double cardHeight,
    required VideoshotData data,
  }) {
    final scaleX = cardWidth / frameInfo.width;
    final scaleY = cardHeight / frameInfo.height;
    final spriteWidth = (data.imgXLen * data.imgXSize) * scaleX;
    final spriteHeight = (data.imgYLen * data.imgYSize) * scaleY;
    final offsetX = frameInfo.x * scaleX;
    final offsetY = frameInfo.y * scaleY;

    return ClipRect(
      child: SizedBox(
        width: cardWidth,
        height: cardHeight,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: -offsetX,
              top: -offsetY,
              child: CachedNetworkImage(
                imageUrl: frameInfo.imageUrl,
                cacheManager: VideoshotApi.cacheManager,
                width: spriteWidth,
                height: spriteHeight,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                httpHeaders: const {
                  'Referer': 'https://www.bilibili.com/',
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                },
                placeholder: (context, url) => Container(
                  width: cardWidth,
                  height: cardHeight,
                  color: const Color(0xFF1E1E1E),
                ),
                errorWidget: (context, url, error) => Container(
                  width: cardWidth,
                  height: cardHeight,
                  color: const Color(0xFF1E1E1E),
                  child: const Icon(
                    Icons.image_not_supported,
                    color: Colors.white38,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
