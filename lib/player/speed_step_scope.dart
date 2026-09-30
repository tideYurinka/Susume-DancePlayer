/// 倍速步进范围判定（**纯函数域**）。
///
/// 语义：
///
/// - 预览位置位于选中的学习段（多段选中 = 合并范围）内 → 直接启用并作用于
///   选中段；
/// - 位于选中范围外 → 弹三选一：「激活当前学习段并启用步进倍速」「对全片
///   启用步进倍速」「取消」；预览不在任何学习段内时，第一项候选为分段线
///   后面的那一段（不存在则置灰）；
/// - 「对全片」范围 = 首/尾划定的有效练习区间（`AnnotationTimeline.rangeStart/
///   rangeEnd`）。
///
/// 本文件只含纯函数与值对象（无 IO、无状态、无依赖），可单测直接验证；
/// 弹窗与启用编排见 `speed_step_entry.dart`（两处步进面板共用的入口）。
library;

import '../annotation/annotation_timeline.dart';
import '../annotation/learning_segments.dart';
import '../annotation/segment_selection.dart';

/// 范围判定结果。
class SpeedStepScopeDecision {
  const SpeedStepScopeDecision({
    required this.withinActiveScope,
    this.candidateOrder,
  });

  /// 预览位置是否位于选中学习段（合并范围）内：是 → 可直接启用。
  final bool withinActiveScope;

  /// 三选一弹窗第一项（「激活当前学习段」）的候选段序；null = 无可用候选
  /// （预览不在任何学习段内且其后无分段线，第一项置灰）。
  final int? candidateOrder;
}

/// 判定预览位置 [position] 的步进范围。
///
/// 候选段规则：位置落在某段内（左闭右开，末段含尾点）→ 该段；位置不在任何
/// 段内（恰在分段线上、有效区间之前、无分段线等）→ 分段线后面的那一段
/// （即第一个起点在位置之后的段）；位置在有效练习区间之后（其后无段）→ null。
SpeedStepScopeDecision resolveSpeedStepScope({
  required AnnotationTimeline timeline,
  required Set<int> selected,
  required Duration position,
}) {
  final segments = deriveLearningSegments(timeline);
  if (segments.isEmpty) {
    return const SpeedStepScopeDecision(withinActiveScope: false);
  }
  final range = selectedLearningSegmentRange(timeline, selected);
  final candidate = _candidateOrder(segments, position);
  if (range != null && range.contains(position)) {
    return SpeedStepScopeDecision(
      withinActiveScope: true,
      candidateOrder: candidate,
    );
  }
  return SpeedStepScopeDecision(
    withinActiveScope: false,
    candidateOrder: candidate,
  );
}

int? _candidateOrder(List<LearningSegment> segments, Duration position) {
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    final includesEnd = i == segments.length - 1;
    if (position >= segment.start &&
        (position < segment.end || (includesEnd && position == segment.end))) {
      return segment.order;
    }
  }
  // 不在任何段内（分段线上 / 有效区间之前）：取分段线后面的那一段——
  // 即第一个起点在位置之后的段；其后无段（位置在有效区间之后）→ null。
  for (final segment in segments) {
    if (segment.start > position) return segment.order;
  }
  return null;
}
