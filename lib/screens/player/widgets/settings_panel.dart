import 'package:bili_tv_app/widgets/zh_material.dart';

import '../../../models/play_repeat.dart';
import '../../../models/subtitle.dart';
import '../../../services/btr/btr_config.dart';
import '../../../services/audio_track.dart';
import '../../../services/settings_service.dart';
import 'cdn_status_view.dart';

enum SettingsMenuType {
  main,
  quality,
  danmaku,
  speed,
  cdn,
  playEnd,
  subtitle,
  audio,
}

class SettingsPanel extends StatefulWidget {
  final SettingsMenuType menuType;
  final int focusedIndex;
  final String qualityDesc;
  final double playbackSpeed;
  final List<double> availableSpeeds;
  final String playEndLabel; // 「播放完畢後」目前的模式名稱
  final List<SubtitleTrack> subtitleTracks;
  final int subtitleIndex; // -1 為關閉
  final List<AudioOption> audioOptions; // 本影片可選的音軌
  final AudioKind audioKind; // 目前使用的音軌

  // Danmaku Settings
  final bool danmakuEnabled;
  final double danmakuOpacity;
  final double danmakuFontSize;
  final double danmakuArea;
  final double danmakuSpeed;
  final bool hideTopDanmaku;
  final bool hideBottomDanmaku;

  // Callbacks
  final Function(SettingsMenuType, int) onNavigate;
  final VoidCallback onQualityPicker;

  const SettingsPanel({
    super.key,
    required this.menuType,
    required this.focusedIndex,
    required this.qualityDesc,
    required this.playbackSpeed,
    required this.availableSpeeds,
    required this.playEndLabel,
    required this.subtitleTracks,
    required this.subtitleIndex,
    required this.audioOptions,
    required this.audioKind,
    required this.danmakuEnabled,
    required this.danmakuOpacity,
    required this.danmakuFontSize,
    required this.danmakuArea,
    required this.danmakuSpeed,
    required this.hideTopDanmaku,
    required this.hideBottomDanmaku,
    required this.onNavigate,
    required this.onQualityPicker,
  });

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(SettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.menuType == SettingsMenuType.danmaku ||
            widget.menuType == SettingsMenuType.subtitle) &&
        widget.focusedIndex != oldWidget.focusedIndex) {
      _scrollToFocused();
    }
  }

  void _scrollToFocused() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        const itemHeight = 80.0;
        final targetOffset = widget.focusedIndex * itemHeight;
        final currentOffset = _scrollController.offset;
        final viewport = _scrollController.position.viewportDimension;

        if (targetOffset < currentOffset) {
          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else if (targetOffset + itemHeight > currentOffset + viewport) {
          _scrollController.animateTo(
            targetOffset + itemHeight - viewport,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String title = '設定';
    if (widget.menuType == SettingsMenuType.danmaku) title = '彈幕設定';
    if (widget.menuType == SettingsMenuType.speed) title = '倍速播放';
    if (widget.menuType == SettingsMenuType.quality) title = '畫質選擇';
    if (widget.menuType == SettingsMenuType.cdn) title = 'CDN 狀態';
    if (widget.menuType == SettingsMenuType.playEnd) title = '播放完畢後';
    if (widget.menuType == SettingsMenuType.subtitle) title = '字幕';
    if (widget.menuType == SettingsMenuType.audio) title = '音質';

    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: 350,
      child: Container(
        color: const Color(0xFF1F1F1F).withValues(alpha: 0.95),
        child: Column(
          children: [
            // 標題欄
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                children: [
                  /*
                  if (widget.menuType != SettingsMenuType.main)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  */
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (widget.menuType == SettingsMenuType.main)
                    const Icon(Icons.settings, color: Colors.white54),
                ],
              ),
            ),
            // 列表內容
            Expanded(child: _buildSettingsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsList() {
    switch (widget.menuType) {
      case SettingsMenuType.danmaku:
        return _buildDanmakuSettingsList();
      case SettingsMenuType.speed:
        return _buildSpeedSettingsList();
      case SettingsMenuType.playEnd:
        return _buildPlayEndSettingsList();
      case SettingsMenuType.subtitle:
        return _buildSubtitleSettingsList();
      case SettingsMenuType.audio:
        return _buildAudioSettingsList();
      case SettingsMenuType.cdn:
        return const CdnStatusView();
      case SettingsMenuType.main:
      default:
        return _buildMainSettingsList();
    }
  }

  Widget _buildMainSettingsList() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildSettingItem(
          index: 0,
          icon: Icons.hd,
          title: '畫質',
          value: widget.qualityDesc,
          onTap: widget.onQualityPicker,
        ),
        _buildSettingItem(
          index: 1,
          icon: Icons.graphic_eq,
          title: '音質',
          value: audioKindLabel(widget.audioKind),
          onTap: () =>
              widget.onNavigate(SettingsMenuType.audio, _audioFocusIndex()),
        ),
        _buildSettingItem(
          index: 2,
          icon: Icons.subtitles,
          title: '彈幕設定',
          value: widget.danmakuEnabled ? '開' : '關',
          onTap: () => widget.onNavigate(SettingsMenuType.danmaku, 0),
        ),
        _buildSettingItem(
          index: 3,
          icon: Icons.speed,
          title: '播放速度',
          value: '${widget.playbackSpeed}x',
          onTap: () => widget.onNavigate(SettingsMenuType.speed, 0),
        ),
        _buildSettingItem(
          index: 4,
          icon: Icons.cloud,
          title: 'CDN 狀態',
          value: BtrConfig.playback ? 'BTR' : '直連',
          onTap: () => widget.onNavigate(SettingsMenuType.cdn, 0),
        ),
        _buildSettingItem(
          index: 5,
          icon: Icons.star_border,
          title: '收藏',
          value: '選擇收藏夾',
          onTap: () {},
        ),
        _buildSettingItem(
          index: 6,
          icon: Icons.repeat,
          title: '播放完畢後',
          value: widget.playEndLabel,
          onTap: () => widget.onNavigate(
            SettingsMenuType.playEnd,
            SettingsService.playRepeat.index,
          ),
        ),
        if (widget.subtitleTracks.isNotEmpty)
          _buildSettingItem(
            index: 7,
            icon: Icons.closed_caption,
            title: '字幕',
            value: widget.subtitleIndex >= 0
                ? widget.subtitleTracks[widget.subtitleIndex].label
                : '關閉',
            onTap: () => widget.onNavigate(
              SettingsMenuType.subtitle,
              widget.subtitleIndex + 1,
            ),
          ),
      ],
    );
  }

  Widget _buildDanmakuSettingsList() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildSettingItem(
          index: 0,
          icon: widget.danmakuEnabled ? Icons.subtitles : Icons.subtitles_off,
          title: '彈幕開關',
          value: widget.danmakuEnabled ? '開' : '關',
          onTap: () {},
        ),
        _buildSettingItem(
          index: 1,
          icon: Icons.opacity,
          title: '彈幕透明度',
          value: widget.danmakuOpacity.toStringAsFixed(1),
          onTap: () {},
        ),
        _buildSettingItem(
          index: 2,
          icon: Icons.format_size,
          title: '彈幕字型大小',
          value: widget.danmakuFontSize.toInt().toString(),
          onTap: () {},
        ),
        _buildSettingItem(
          index: 3,
          icon: Icons.aspect_ratio,
          title: '彈幕佔屏比',
          value: _getDanmakuAreaText(),
          onTap: () {},
        ),
        _buildSettingItem(
          index: 4,
          icon: Icons.shutter_speed,
          title: '彈幕速度',
          value: widget.danmakuSpeed.toInt().toString(),
          onTap: () {},
        ),
        _buildSettingItem(
          index: 5,
          icon: Icons.vertical_align_top,
          title: '允許頂部懸停彈幕',
          value: !widget.hideTopDanmaku ? '開' : '關',
          onTap: () {},
        ),
        _buildSettingItem(
          index: 6,
          icon: Icons.vertical_align_bottom,
          title: '允許底部懸停彈幕',
          value: !widget.hideBottomDanmaku ? '開' : '關',
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildSpeedSettingsList() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: widget.availableSpeeds.asMap().entries.map((entry) {
        final index = entry.key;
        final speed = entry.value;
        final isSelected = speed == widget.playbackSpeed;
        return _buildSettingItem(
          index: index,
          icon: Icons.speed,
          title: '${speed}x',
          value: isSelected ? '當前' : '',
          onTap: () {},
        );
      }).toList(),
    );
  }

  Widget _buildPlayEndSettingsList() {
    final current = SettingsService.playRepeat;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: PlayRepeat.values.map((mode) {
        return _buildSettingItem(
          index: mode.index,
          icon: Icons.repeat,
          title: mode.label,
          value: mode == current ? '當前' : '',
          onTap: () {},
        );
      }).toList(),
    );
  }

  /// 音質子選單進入時，焦點落在目前使用的音軌
  int _audioFocusIndex() {
    final i = widget.audioOptions.indexWhere((o) => o.kind == widget.audioKind);
    return i < 0 ? 0 : i;
  }

  Widget _buildAudioSettingsList() {
    final options = widget.audioOptions.isEmpty
        ? const [AudioOption(kind: AudioKind.standard, stream: {})]
        : widget.audioOptions;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (int i = 0; i < options.length; i++)
          _buildSettingItem(
            index: i,
            icon: Icons.graphic_eq,
            title: audioKindLabel(options[i].kind),
            value: !options[i].supported
                ? '此裝置不支援'
                : (options[i].kind == widget.audioKind ? '當前' : ''),
            dimmed: !options[i].supported,
            onTap: () {},
          ),
      ],
    );
  }

  Widget _buildSubtitleSettingsList() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildSettingItem(
          index: 0,
          icon: Icons.closed_caption_disabled,
          title: '關閉',
          value: widget.subtitleIndex < 0 ? '當前' : '',
          onTap: () {},
        ),
        for (int i = 0; i < widget.subtitleTracks.length; i++)
          _buildSettingItem(
            index: i + 1,
            icon: Icons.closed_caption,
            title: widget.subtitleTracks[i].label,
            value: i == widget.subtitleIndex ? '當前' : '',
            onTap: () {},
          ),
      ],
    );
  }

  String _getDanmakuAreaText() {
    if (widget.danmakuArea >= 1.0) return '滿屏';
    if (widget.danmakuArea >= 0.75) return '3/4屏';
    if (widget.danmakuArea >= 0.5) return '半屏';
    if (widget.danmakuArea >= 0.25) return '1/4屏';
    return '1/4屏';
  }

  Widget _buildSettingItem({
    required int index,
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
    bool dimmed = false, // 不可選的項目變暗
  }) {
    // Determine if focused based on parent index
    final isFocused = widget.focusedIndex == index;
    return Opacity(
      opacity: dimmed ? 0.4 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isFocused
                  ? const Color(0xFFfb7299).withValues(alpha: 0.3)
                  : Colors.transparent,
              border: isFocused
                  ? const Border(
                      left: BorderSide(color: Color(0xFFfb7299), width: 3),
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isFocused
                      ? const Color(0xFFfb7299)
                      : Colors.white.withValues(alpha: 0.7),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isFocused
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.9),
                          fontSize: 15,
                          fontWeight: isFocused
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      if (value.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          value,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.menuType == SettingsMenuType.main && index > 0)
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withValues(alpha: 0.5),
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
