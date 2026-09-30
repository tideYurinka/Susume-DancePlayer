/// 三指滑动跳转（产品需求）。
///
/// 跳转到滑动方向时间轴上最近的一条分段线；该方向无分段线时左滑跳视频首
/// （首边界）、右滑跳视频尾（尾边界）。三指滑动只产生跳转，不新建、移动或
/// 删除任何标记。
///
/// 分段线位置来自标注时间线（[segmentLinePositions]）；回退目标由调用方
/// 传入视频首/尾边界（设视频首/尾后为 rangeStart/rangeEnd）。
library;

import '../annotation/annotation_timeline.dart';

/// 三指滑动方向（沿时间轴：左滑后退、右滑前进）。
enum ThreeFingerSwipeDirection { left, right }

/// 分段线位置接缝：取标注时间线内的全部分段线位置（升序）。
///
/// 时间线不变式保证分段线严格位于首/尾开区间内（见 `annotation_timeline.dart`
/// 文件头），故回退目标（首/尾边界）不会与任何分段线重合。
List<Duration> segmentLinePositions(AnnotationTimeline timeline) => [
  for (final line in timeline.segmentLines) line.position,
];

/// 分段线位置接缝：只取时间线内**标记过**（flag 置位）的分段线位置（升序）。
///
/// 三指跳转的目标集用这个投影；数拍锚点链继续用 [segmentLinePositions]。
List<Duration> flaggedSegmentLinePositions(AnnotationTimeline timeline) => [
  for (final line in timeline.segmentLines)
    if (line.flagged) line.position,
];

/// 三指滑动跳转目标（纯函数）：
///
/// - 左滑：当前进度左侧最近的一条分段线；该方向无分段线 → [videoStart]；
/// - 右滑：当前进度右侧最近的一条分段线；该方向无分段线 → [videoEnd]。
///
/// 只返回跳转目标，不产生任何标记变更（三指滑动只跳转）。
Duration threeFingerJumpTarget({
  required ThreeFingerSwipeDirection direction,
  required Duration currentPosition,
  required List<Duration> segmentLines,
  required Duration videoStart,
  required Duration videoEnd,
}) {
  final lines = [...segmentLines]..sort();
  switch (direction) {
    case ThreeFingerSwipeDirection.left:
      for (final line in lines.reversed) {
        if (line < currentPosition) return line;
      }
      return videoStart;
    case ThreeFingerSwipeDirection.right:
      for (final line in lines) {
        if (line > currentPosition) return line;
      }
      return videoEnd;
  }
}
