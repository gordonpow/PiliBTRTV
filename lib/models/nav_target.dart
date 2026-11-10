import 'video.dart';

/// 播放器「上一部／下一部」的目標
sealed class NavTarget {
  const NavTarget();
}

/// 換分P或番劇的集：[index] 是 `episodes` 的索引
class EpisodeTarget extends NavTarget {
  final int index;
  const EpisodeTarget(this.index);
}

/// 換到另一部影片（合集的上下部、相關影片、播放紀錄的前一部）
class VideoTarget extends NavTarget {
  final Video video;

  /// 來自播放紀錄（上一部 pop 回去）；換片時不再記錄
  final bool fromHistory;
  const VideoTarget(this.video, {this.fromHistory = false});
}

/// 番劇播完最後一集：沒有下一部，要打開相關影片
class RelatedFallback extends NavTarget {
  const RelatedFallback();
}
