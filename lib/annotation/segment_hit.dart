/// 学习段轨触控命中解析（最近段命中扩展；
/// seam」）。
///
/// 与像素无关的纯函数：入参 = 派生几何（分段线/首尾 + 学习段）+ 点按时间
/// 坐标 + 各命中目标的时间域扩展宽度（像素→时间换算由 widget 层承担），
/// 返回命中的段/线/首尾或空。命中优先级：
///
///   分段线/首尾线 > 段体 > 空。
///
/// 段体命中实现「等效最小命中宽 ≥ [minSegmentHitWidth]」：窄段对称扩展至
/// 最小命中宽，多候选重叠取距点按最近的段中心。分段线/
/// 首尾线的抓取与拖动同样经本 seam 判定（接线：命中/抓取区加宽至约
/// 40dp、按下即水平拖动、密集线取最近——线 > 段体 > 空）。
///
/// **两条解析分开**：线与首尾线的命中窗只约束单击——
/// [resolveLearningTrackHit] 是单击那一份（线 > 段体 > 空）；
/// [resolveLearningSegmentHit] 是长按圈选那一份，只按段体解析（最小命中宽
/// 扩展 + 最近段中心），不被命中窗遮蔽。
library;

import 'interval_fragment_row.dart';
import 'learning_segments.dart';
import 'segment_line.dart';

/// 学习段轨命中目标（值对象；空命中以返回 `null` 表达）。
sealed class LearningTrackHitTarget {
  const LearningTrackHitTarget();
}

/// 命中分段线（[lineIndex] 为时间线分段线列表下标）。
class SegmentLineHitTarget extends LearningTrackHitTarget {
  const SegmentLineHitTarget(this.lineIndex);

  final int lineIndex;

  @override
  bool operator ==(Object other) =>
      other is SegmentLineHitTarget && other.lineIndex == lineIndex;

  @override
  int get hashCode => lineIndex;

  @override
  String toString() => 'SegmentLineHitTarget($lineIndex)';
}

/// 命中视频首线/尾线（[isStart] = 首线）。
class RangeEdgeHitTarget extends LearningTrackHitTarget {
  const RangeEdgeHitTarget({required this.isStart});

  final bool isStart;

  @override
  bool operator ==(Object other) =>
      other is RangeEdgeHitTarget && other.isStart == isStart;

  @override
  int get hashCode => isStart ? 1 : 0;

  @override
  String toString() => 'RangeEdgeHitTarget(isStart: $isStart)';
}

/// 命中学习段（[segmentOrder] 为段序，属性按此序索引）。
class SegmentHitTarget extends LearningTrackHitTarget {
  const SegmentHitTarget(this.segmentOrder);

  final int segmentOrder;

  @override
  bool operator ==(Object other) =>
      other is SegmentHitTarget && other.segmentOrder == segmentOrder;

  @override
  int get hashCode => segmentOrder;

  @override
  String toString() => 'SegmentHitTarget($segmentOrder)';
}

/// 解析点按 [time] 命中的学习段轨目标。
///
///   - 分段线：点按距某线 ≤ [lineHalfWidth]（密集线取最近）；
///   - 首/尾线：点按距边界 ≤ [edgeHalfWidth]；
///   - 段体：点按落在段区间按 [minSegmentHitWidth] 对称扩展后的区间内
///     （窄段不足最小命中宽时扩展、宽段不收缩），多候选取距点按最近的
///     段中心；
///   - 以上皆否 → `null`（调用侧通常按「轨道空白」处理，如单击收起）。
LearningTrackHitTarget? resolveLearningTrackHit({
  required List<SegmentLine> segmentLines,
  required Duration rangeStart,
  required Duration rangeEnd,
  required List<LearningSegment> segments,
  required Duration time,
  required Duration lineHalfWidth,
  required Duration edgeHalfWidth,
  required Duration minSegmentHitWidth,
}) {
  final tUs = time.inMicroseconds;
  // 1) 分段线（优先级最高；密集线取最近）。
  int? lineIndex;
  int? bestLineDist;
  for (var i = 0; i < segmentLines.length; i++) {
    final dist = (tUs - segmentLines[i].position.inMicroseconds).abs();
    if (dist <= lineHalfWidth.inMicroseconds &&
        (bestLineDist == null || dist < bestLineDist)) {
      lineIndex = i;
      bestLineDist = dist;
    }
  }
  if (lineIndex != null) return SegmentLineHitTarget(lineIndex);
  // 2) 视频首/尾线。
  if ((tUs - rangeStart.inMicroseconds).abs() <= edgeHalfWidth.inMicroseconds) {
    return const RangeEdgeHitTarget(isStart: true);
  }
  if ((tUs - rangeEnd.inMicroseconds).abs() <= edgeHalfWidth.inMicroseconds) {
    return const RangeEdgeHitTarget(isStart: false);
  }
  // 3) 段体：最小命中宽扩展 + 最近段中心（解析纪律收口于共用件
  //    resolveIntervalHit，–02 prefactor；此处只做微秒域换算与
  //    下标 → 段序映射）。
  return resolveLearningSegmentHit(
    segments: segments,
    time: time,
    minSegmentHitWidth: minSegmentHitWidth,
  );
}

/// 按**段体**解析 [time] 命中的学习段：点按落在段区间按
/// [minSegmentHitWidth] 对称扩展后的区间内（窄段不足最小命中宽时扩展、
/// 宽段不收缩），多候选取距点按最近的段中心（同距取靠前）；无候选返回
/// `null`。
///
/// 本解析不认分段线与首尾线的命中窗——长按圈选的起手与逐帧走这条，
/// 拖动跨过分段线因此连续解析到相邻段、不停顿。
SegmentHitTarget? resolveLearningSegmentHit({
  required List<LearningSegment> segments,
  required Duration time,
  required Duration minSegmentHitWidth,
}) {
  final hitIndex = resolveIntervalHit(
    spans: [
      for (final segment in segments)
        IntervalSpan(
          startMs: segment.start.inMicroseconds,
          endMs: segment.end.inMicroseconds,
        ),
    ],
    positionMs: time.inMicroseconds,
    minHitWidthMs: minSegmentHitWidth.inMicroseconds,
  );
  if (hitIndex == null) return null;
  return SegmentHitTarget(segments[hitIndex].order);
}
