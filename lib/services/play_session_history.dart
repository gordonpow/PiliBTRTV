import '../models/video.dart';

/// 這次開 App 期間，在播放器依序看過的影片（只存在記憶體，關掉 App 就清空）。
/// 「上一部」沒有分P或合集可退時，會從這裡取前一部影片。
class PlaySessionHistory {
  PlaySessionHistory._();

  static const int maxSize = 50;

  static final List<Video> _stack = <Video>[];

  /// 目前堆疊（唯讀，測試用）
  static List<Video> get items => List.unmodifiable(_stack);

  static bool get canPop => _stack.isNotEmpty;

  /// 看最近一筆但不取出
  static Video? get peek => _stack.isEmpty ? null : _stack.last;

  /// 記錄一部影片；超過上限時丟掉最舊的。
  static void push(Video video) {
    _stack.add(video);
    if (_stack.length > maxSize) {
      _stack.removeRange(0, _stack.length - maxSize);
    }
  }

  /// 取出最近一筆；沒有時回傳 null。
  static Video? pop() => _stack.isEmpty ? null : _stack.removeLast();

  /// 清空（測試用）
  static void clear() => _stack.clear();
}
