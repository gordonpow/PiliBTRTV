import 'package:bili_tv_app/widgets/zh_material.dart';
import '../../../models/video.dart';
import '../../../widgets/tv_video_card.dart';
import '../widgets/space_grid.dart';

/// 分頁內容的共同介面：讓外層能把焦點送進內容。
abstract interface class SpaceTabController {
  /// 把焦點移到內容最上方的可聚焦元素；沒有可聚焦的內容回傳 false。
  bool focusFirst();
}

/// 影片卡片（格狀用），選取時回傳影片。
Widget buildSpaceVideoCard(
  BuildContext context,
  Video video,
  SpaceGridCell cell,
  void Function(Video video) onSelect,
) {
  return TvVideoCard(
    video: video,
    focusNode: cell.node,
    showDanmaku: true,
    onTap: () => onSelect(video),
    onMoveLeft: cell.onMoveLeft,
    onMoveRight: cell.onMoveRight,
    onMoveUp: cell.onMoveUp,
    onMoveDown: cell.onMoveDown,
    onFocus: cell.onFocus,
  );
}
