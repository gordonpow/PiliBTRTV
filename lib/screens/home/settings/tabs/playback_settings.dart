import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../../../models/play_repeat.dart';
import '../../../../services/settings_service.dart';
import '../../../../services/codec_service.dart';
import 'package:bili_tv_app/utils/zh_toast.dart';
import '../widgets/setting_toggle_row.dart';
import '../widgets/setting_action_row.dart';
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
        SettingDropdownRow<PlayRepeat>(
          label: '播放完畢後',
          subtitle: '播完暫停、直接播下一部、倒數後播下一部、循環播放此影片、列表循環',
          value: SettingsService.playRepeat,
          items: PlayRepeat.values,
          itemLabel: (v) => v.label,
          isFirst: true, // 第一項，向上返回分類標籤
          onMoveUp: widget.onMoveUp,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (v) async {
            if (v != null) {
              await SettingsService.setPlayRepeat(v);
              setState(() {});
            }
          },
        ),
        const SizedBox(height: 16),
        SettingDropdownRow<int>(
          label: '連播倒數',
          subtitle: '「倒數後播下一部」模式播完後倒數幾秒',
          value: SettingsService.upNextCountdown,
          items: SettingsService.upNextCountdownOptions,
          itemLabel: (v) => '$v 秒',
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (v) async {
            if (v != null) {
              await SettingsService.setUpNextCountdown(v);
              setState(() {});
            }
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
        SettingDropdownRow<bool>(
          label: '播放畫面模式',
          subtitle: '影片顏色或順暢度異常時可切換試試',
          value: SettingsService.playerTextureView,
          items: const [false, true],
          itemLabel: (v) => v ? '相容' : '原生（預設）',
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (v) async {
            if (v != null) {
              await SettingsService.setPlayerTextureView(v);
              setState(() {});
            }
          },
        ),
        const SizedBox(height: 16),
        SettingToggleRow(
          label: '卡頓時自動降畫質',
          subtitle: '連續掉幀過多時，自動降為下一級畫質',
          value: SettingsService.autoDowngradeOnDrops,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setAutoDowngradeOnDrops(value);
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
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (codec) async {
            if (codec != null) {
              await SettingsService.setPreferredCodec(codec);
              setState(() {});
            }
          },
        ),
        const SizedBox(height: 16),
        SettingToggleRow(
          label: '隧道播放（實驗）',
          subtitle: '4K 60 幀不順時可試試，只在「原生」畫面模式有效；黑畫面或沒聲音請關閉',
          value: SettingsService.playerTunneling,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setPlayerTunneling(value);
            setState(() {});
          },
        ),
        const SizedBox(height: 16),
        SettingActionRow(
          label: '重設 4K 60 幀偵測',
          value: SettingsService.known4k60Bad
              ? '已記錄此裝置播放 4K 60 幀不順'
              : '目前沒有 4K 60 幀不順的記錄',
          buttonLabel: '重設',
          isLast: true, // 最後一項，阻止向下導航
          sidebarFocusNode: widget.sidebarFocusNode,
          onTap: () async {
            await SettingsService.clearKnown4k60Bad();
            showZhToast(msg: '已重設 4K 60 幀偵測');
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }
}
