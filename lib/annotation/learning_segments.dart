/// 学习段几何（**派生、不落盘**）：由视频首/尾 + 分段线实时计算。
///
/// 语义（「视频首/尾」）：
///
///   - 未创建分段线时**无学习段片段**（返回空）；
///   - 有 n 条分段线时产生 n+1 个学习段：相邻两段首尾相接、总长恒等于
///     有效练习区间时长（首/尾边界变化时几何随之更新）；
///   - 首段左端点为视频首、末段右端点为视频尾，两端不可拖动
///     （由派生几何自动体现，UI 侧据此约束拖动）。
///
/// 段属性（熟练度/激活/重点）按段序（order）另行存储，字段归属见
/// `persistence/` 的双文件文档模型（熟练度/激活在
/// `local_document.dart`，重点在 `marker_document.dart`）。
library;

import 'annotation_timeline.dart';
import 'segment_line.dart';

/// 一个学习段（几何值对象；属性按 [order] 在时间线外另行索引）。
class LearningSegment {
  const LearningSegment({
    required this.order,
    required this.start,
    required this.end,
  }) : assert(end >= start, '学习段结束不能早于开始');

  /// 段序（0 起，自左向右；属性存储按此序对齐）。
  final int order;

  /// 段起始（绝对时间点）。
  final Duration start;

  /// 段结束（绝对时间点）。
  final Duration end;

  Duration get duration => end - start;

  @override
  bool operator ==(Object other) {
    return other is LearningSegment &&
        other.order == order &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(order, start, end);

  @override
  String toString() => 'LearningSegment(order: $order, [$start, $end])';
}

/// 由首/尾区间与分段线推导学习段列表（升序、首尾相接）。
///
/// 无分段线 → 空；否则按 `[rangeStart, 各分段线, rangeEnd]` 切分，每段为相邻
/// 两边界间的左闭右开区间，段序即其在列表中的下标。结果总长 ==
/// `practiceRangeDuration`。
List<LearningSegment> deriveLearningSegments(AnnotationTimeline t) {
  if (t.segmentLines.isEmpty) return const [];
  final bounds = <Duration>[
    t.rangeStart,
    for (final line in t.segmentLines) line.position,
    t.rangeEnd,
  ];
  final segments = <LearningSegment>[];
  for (var i = 0; i < bounds.length - 1; i++) {
    segments.add(
      LearningSegment(order: i, start: bounds[i], end: bounds[i + 1]),
    );
  }
  return List.unmodifiable(segments);
}

/// 学习段几何：由落盘的有效区间与分段线推导（播放器与索引侧同一条派生，
/// 段集口径全仓唯一）。
///
/// 上界是视频总时长；索引侧不存视频时长（视频时长仍无持久住处），故以
/// 有效区间尾作归一路上界——播放器写出的文件里分段线落在有效区间内、
/// 区间落在 `[0, 视频时长]` 内，两者几何逐位一致；只有区间尾超出真实视频
/// 时长的脏文件无法察觉（区间尾即上界）。有效区间未落盘（首尾皆 0）时
/// 无几何可用，按未标注处理（与播放器「时长未知不恢复标注」同款）。
List<LearningSegment> learningSegmentsOf({
  required int rangeStartMs,
  required int rangeEndMs,
  required List<SegmentLine> segmentLines,
}) {
  if (rangeStartMs == 0 && rangeEndMs == 0) return const [];
  final end = Duration(milliseconds: rangeEndMs);
  return deriveLearningSegments(
    AnnotationTimeline.normalized(
      videoDuration: end,
      rangeStart: Duration(milliseconds: rangeStartMs),
      rangeEnd: end,
      segmentLines: segmentLines,
    ),
  );
}
