/// 临时衔接段。
///
/// 点击分段线激活的**会话态**临时学习段：范围为线前 1 八拍 + 后 1 八拍
/// （合计 2 八拍），仅按视频首/尾截断、可跨相邻学习段、起点按八拍点
/// 取整。不落盘、不进熟练度/重点、不参与步进「激活段」候选；与真实
/// 学习段激活互斥（单一循环范围事实，见 player/annotation_editor.dart 的
/// [transitionSegmentProvider] 与 [activeLoopRangeProvider]）。
library;

import 'dart:math' as math;

import '../core/beat_grid.dart';
import '../core/eight_beat_phase.dart';
import 'annotation_timeline.dart';
import 'learning_segments.dart';
import 'segment_line.dart';

/// 激活中的临时衔接段（不可变值对象）。
class TransitionSegment {
  const TransitionSegment({
    required this.lineIndex,
    required this.start,
    required this.end,
  });

  /// 触发线（升序分段线列表中的索引；仅作「再点同线取消」的同一性判据，
  /// 几何变化重建时间线时整体清除而非重映射）。
  final int lineIndex;

  /// 临时段起点（网格取整 + 首截断后的绝对时间）。
  final Duration start;

  /// 临时段终点（尾截断后的绝对时间；不取整）。
  final Duration end;

  @override
  bool operator ==(Object other) {
    return other is TransitionSegment &&
        other.lineIndex == lineIndex &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(lineIndex, start, end);

  @override
  String toString() =>
      'TransitionSegment(lineIndex: $lineIndex, start: $start, end: $end)';
}

/// 解析点击分段线 [lineIndex] 激活的临时衔接段范围：
///
/// - 起点理论值 = 线位置 − 1 八拍、终点理论值 = 线位置 + 1 八拍；
/// - 起点先按**八拍点**取整（[BeatPhase.nearest] 最近八拍点；强制
///   对齐，无「关闭吸附不取整」分支），再钳到不早于视频首（**截断优先于
///   网格**：取整点落到首界外时贴首，不回吸到区间内的格线）；终点仅按
///   视频尾截断、不取整；
/// - 取整/截断后起点不早于终点（区间过窄）或线索引无效 → 无有效临时段，
///   返回 null（调用侧不激活）。
///
/// [phase] = 八拍相位值对象（网格 + 八拍锚点）：起点取整经相位源求值，
/// 设过锚点后起点落在重定相后的八拍点上；
/// 相位由持有容器的调用方在调用点交出（与同目录自动分段切割线同款，无
/// 占位网格默认参）。
///
/// 范围只按时间计算——可跨相邻学习段（真实段边界不参与）。
TransitionSegment? resolveTransitionSegment({
  required AnnotationTimeline timeline,
  required int lineIndex,
  required BeatPhase phase,
}) {
  if (lineIndex < 0 || lineIndex >= timeline.segmentLines.length) return null;
  final SegmentLine(:position) = timeline.segmentLines[lineIndex];
  // 窗宽 = 八拍标称。
  final eightBeats = phase.grid.eightBeatNominal;
  final raw = position - eightBeats;
  var start = phase.nearest(raw) ?? raw;
  if (start < timeline.rangeStart) start = timeline.rangeStart;
  final end = position + eightBeats > timeline.rangeEnd
      ? timeline.rangeEnd
      : position + eightBeats;
  if (start >= end) return null;
  return TransitionSegment(lineIndex: lineIndex, start: start, end: end);
}

/// 每侧窗宽占该侧邻学习段显示宽的百分比（分侧公式的 10%）。
const int kTransitionTriggerSidePercent = 10;

/// 学习轨行内临时段触发窗的**分侧**横向半宽。
///
///   左侧半宽 = min([maxSideWidthPx], 左邻学习段显示宽 × 10%)
///   右侧半宽 = min([maxSideWidthPx], 右邻学习段显示宽 × 10%)
///
/// 左右可不对称。显示宽度 = 时间 ↔ x 换算后的像素宽
/// （[microsecondsPerPixel] 为当前可视窗口密度）。分段线 [lineIndex] 左右
/// 相邻学习段 = [segments] 中同下标与下标 +1 项（n 条线派生 n+1 个首尾
/// 相接段，见 `learning_segments.dart`）。任意学习段被两端相邻线窗合计
/// 占用 ≤ 显示宽 20%：显示宽 < 200px 时每侧恰为 10%；显示宽 ≥ 200px
/// 时每侧取 20dp 上限（「顶帽」），仍 ≤ 该侧 10% → 恒保留
/// ≥80% 触发面积；短学习段旁窗自动收窄、放大轨道（µs/px 变小）后窗
/// 随之恢复。与像素无关的纯函数：返回时间域半宽（调用侧与线中心 x
/// 距离换算比较）。线索引越界时钳制到最近的有效线（几何不变式恒成立）；
/// 无有效线（段数 < 2，防御性）时两侧均回落为上限。
({Duration left, Duration right}) transitionTriggerSideHalfWidths({
  required List<LearningSegment> segments,
  required int lineIndex,
  required double microsecondsPerPixel,
  required double maxSideWidthPx,
}) {
  final capUs = (maxSideWidthPx * microsecondsPerPixel).round();
  Duration side(LearningSegment segment) => Duration(
    microseconds: math.min(
      capUs,
      segment.duration.inMicroseconds * kTransitionTriggerSidePercent ~/ 100,
    ),
  );
  if (segments.length < 2) {
    final cap = Duration(microseconds: capUs);
    return (left: cap, right: cap);
  }
  // 越界钳制到最近的有效线（有效线区间 [0, segments.length - 2]），
  // 保证不变式在防御性路径下同样成立。
  final index = lineIndex.clamp(0, segments.length - 2);
  return (
    left: side(segments[index]),
    right: side(segments[index + 1]),
  );
}
