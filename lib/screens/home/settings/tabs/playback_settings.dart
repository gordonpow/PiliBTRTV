import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../../../services/settings_service.dart';
import '../../../../services/codec_service.dart';
import '../widgets/setting_toggle_row.dart';
import '../widgets/setting_dropdown_row.dart';

class PlaybackSettings extends StatefulWidget {
  final VoidCallback onMoveUp;
  final FocusNode? sidebarFocusNode;

  const PlaybackSettings({
    super.key,
    required this.onMoveUp,
    this.sidebarFocusNode,
  });

  @override
  State<PlaybackSettings> createState() => _PlaybackSettingsState();
}

class _PlaybackSettingsState extends State<PlaybackSettings> {
  List<String> _hardwareDecoders = [];

  @override
  void initState() {
    super.initState();
    _loadHardwareDecoders();
  }

  void _loadHardwareDecoders() async {
    final decoders = await CodecService.getHardwareDecoders();
    if (mounted) {
      setState(() {
        _hardwareDecoders = decoders;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingToggleRow(
          label: '自動連播',
          subtitle: '影片播完自動播放下一集或推薦影片',
          value: SettingsService.autoPlay,
          autofocus: true,
          isFirst: true, // 第一項，向上返回分類標籤
          onMoveUp: widget.onMoveUp,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setAutoPlay(value);
            setState(() {});
          },
        ),
        const SizedBox(height: 16),
        SettingToggleRow(
          label: '迷你進度條',
          subtitle: '播放時在螢幕底部顯示簡約進度條',
          value: SettingsService.showMiniProgress,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setShowMiniProgress(value);
            setState(() {});
          },
        ),
        const SizedBox(height: 16),
        SettingToggleRow(
          label: '預設隱藏控制欄',
          subtitle: '開啟影片時不顯示控制欄和進度條',
          value: SettingsService.hideControlsOnStart,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setHideControlsOnStart(value);
            setState(() {});
          },
        ),
        const SizedBox(height: 16),
        SettingToggleRow(
          label: '快進預覽模式',
          subtitle: '快進快退時顯示預覽縮圖，按確定跳轉',
          value: SettingsService.seekPreviewMode,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setSeekPreviewMode(value);
            setState(() {});
          },
        ),
        const SizedBox(height: 16),
        SettingDropdownRow<VideoCodec>(
          label: '影片解碼器',
          subtitle: '自動=按硬體支援選最優，失敗時降級到其他格式',
          value: SettingsService.preferredCodec,
          items: VideoCodec.values.where((codec) {
            // 自動選項始終顯示
            if (codec == VideoCodec.auto) return true;
            // 只顯示硬體支援的編碼器
            return _hardwareDecoders.contains(codec.name.toLowerCase());
          }).toList(),
          itemLabel: (codec) => codec.label,
          isLast: true, // 最後一項，阻止向下導航
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (codec) async {
            if (codec != null) {
              await SettingsService.setPreferredCodec(codec);
              setState(() {});
            }
          },
        ),
      ],
    );
  }
}
