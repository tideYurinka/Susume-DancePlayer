/// 学习段选中状态与循环范围推导（内存态，落本地文档）。
library;

import 'annotation_timeline.dart';
import 'learning_segments.dart';

/// 选中学习段连续合并后的播放区间。
class LearningSegmentRange {
  const LearningSegmentRange({required this.start, required this.end});

  /// 合并区间起点（第一个选中段段首）。
  final Duration start;

  /// 合并区间终点（最后一个选中段段尾）。
  final Duration end;

  /// 进度拖出取消判定的边界：段首/段尾端点仍属选中范围。
  bool contains(Duration position) {
    return position >= start && position <= end;
  }
}

/// 点击学习段后的选中集合变更（两条规则）：
/// 点中的段已在集合内 → 空集；否则 → 只含该段的单元素集合。
Set<int> toggleLearningSegmentSelection(
  Set<int> selected,
  AnnotationTimeline timeline,
  int order,
) {
  final segments = deriveLearningSegments(timeline);
  if (order < 0 || order >= segments.length) {
    throw RangeError.range(order, 0, segments.length - 1, 'order');
  }
  if (selected.contains(order)) return const {};
  return {order};
}

/// 长按拖动圈选的区间代数：给定起点段序与手指段序（含两端、
/// 自动排序）→ 连续段序集合；越出首/末段钳住；结果恒连续。长按拖动的
/// 实时预览与松手提交共用本函数。
Set<int> contiguousSelectionBetween(int start, int end, int segmentCount) {
  if (segmentCount <= 0) return const {};
  final last = segmentCount - 1;
  int clamp(int order) => order < 0 ? 0 : (order > last ? last : order);
  var lo = clamp(start);
  var hi = clamp(end);
  if (lo > hi) {
    final swap = lo;
    lo = hi;
    hi = swap;
  }
  return {for (var order = lo; order <= hi; order++) order};
}

/// 从最小段序起取最长连续块（一段连续块都构不成时视为无选中）——坏数据
/// 不造出跨空档的循环。
Set<int> contiguousBlockFromMin(Set<int> orders) {
  if (orders.isEmpty) return const {};
  final sorted = orders.toList()..sort();
  var end = 0;
  while (end + 1 < sorted.length && sorted[end + 1] == sorted[end] + 1) {
    end++;
  }
  return Set.unmodifiable(sorted.sublist(0, end + 1));
}

/// 由选中段序推导连续合并循环范围；无有效选中段时返回 null。
LearningSegmentRange? selectedLearningSegmentRange(
  AnnotationTimeline timeline,
  Set<int> selected,
) {
  final segments = deriveLearningSegments(timeline);
  final orders = [
    ...selected.where((order) => order >= 0 && order < segments.length),
  ]..sort();
  if (orders.isEmpty) return null;
  final first = segments[orders.first];
  final last = segments[orders.last];
  return LearningSegmentRange(start: first.start, end: last.end);
}
