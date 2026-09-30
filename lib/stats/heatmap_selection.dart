/// 热力图气泡与滑动选择模式的纯几何/文案件。
///
/// 气泡定位沿用播放器倍速气泡的「纯偏移 + 钳制」先例
/// （`speed_bubble.dart` 的 [speedBubbleClampShift 同款 seam]）：偏移由
/// 「网格几何 + 当前横向滚动偏移」纯算术算出，左右靠近卡片边缘时钳在
/// 卡片内。全部为无 IO 纯函数，不使用 `Overlay`。
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Offset, Rect;

import '../core/bubble_position.dart';
import 'practice_stats_daily.dart';
import 'practice_stats_format.dart';

/// 格边长与格间距：53 列宽于卡片，横向滚动查看（与热力图卡同一几何）。
const double heatmapCellSize = 12;
const double heatmapCellGap = 2;

/// 一格的横向/纵向步距（格边长 + 格间距；格间留白由各格 margin 对半出）。
const double heatmapCellPitch = heatmapCellSize + heatmapCellGap;

/// 手势本地坐标 → 格子索引（TDD seam）：按网格步距换算后做首列/末列
/// 与首行/末行钳制——滑动出网格边缘时钉在边上那格，不落空也不越界。
({int column, int row}) heatmapCellIndexAt(
  Offset local, {
  required int columnCount,
  required int rowCount,
}) {
  int clamp(double value, int count) =>
      (value ~/ heatmapCellPitch).clamp(0, count - 1);
  return (
    column: clamp(local.dx, columnCount),
    row: clamp(local.dy, rowCount),
  );
}

/// 柱状图手势坐标 → 柱索引（TDD seam）：等宽柱列按比例换算后钳在
/// 首末柱——拖出图区边缘时钉在边上那根柱，与 [heatmapCellIndexAt] 同款
/// 「换算 + 钳制」seam。
int barChartIndexAt(double dx, double width, int count) {
  if (count <= 1 || width <= 0) return 0;
  return ((dx / width) * count).floor().clamp(0, count - 1);
}

/// 气泡左缘在卡片内的水平偏移（TDD seam）：格中心先经「网格内容
/// 坐标 − 滚动偏移 + 网格前置宽（卡片内边距 + 星期标签列）」换算成卡片内
/// 坐标，按气泡宽度居中排出后钳制在 `[margin, cardWidth − margin −
/// bubbleWidth]`；气泡放不下（比可用宽还宽）时贴左缘留边。
double heatmapBubbleLeftInCard({
  required double cellCenterX,
  required double scrollOffset,
  required double leadingInset,
  required double bubbleWidth,
  required double cardWidth,
  double margin = 8,
}) {
  final center = cellCenterX - scrollOffset + leadingInset;
  return (center - bubbleWidth / 2).clamp(
    margin,
    math.max(margin, cardWidth - margin - bubbleWidth),
  );
}

/// 柱状图气泡二维定位（TDD seam）：把目标柱的柱体矩形交给全 App 唯一
/// 的气泡避让纯件 [avoidingBubblePosition]——纵向中心对齐手指 y 并钳在绘图区
/// 内，横向朝远离目标柱的方向避让（气泡矩形与目标柱矩形不相交，允许遮挡非
/// 目标柱）。气泡宽到左右都不够时钳到绘图区内为止，此时不相交让位于不越界。
({double left, double top}) barChartBubblePosition({
  required double fingerY,
  required double bubbleWidth,
  required double bubbleHeight,
  required double plotWidth,
  required double plotHeight,
  required int targetIndex,
  required int barCount,
}) {
  final columnWidth = barCount <= 0 ? plotWidth : plotWidth / barCount;
  final columnLeft =
      targetIndex.clamp(0, math.max(0, barCount - 1)) * columnWidth;
  return avoidingBubblePosition(
    fingerY: fingerY,
    bubbleWidth: bubbleWidth,
    bubbleHeight: bubbleHeight,
    plotWidth: plotWidth,
    plotHeight: plotHeight,
    target: Rect.fromLTRB(columnLeft, 0, columnLeft + columnWidth, plotHeight),
  );
}

/// 气泡单行文案：`7月10日 · 练习 42:30`（按次数为
/// 「练习 N 次」），无练习日为「7月10日 · 这天没有练习」。日期不带相对
/// 标签，与界面文案一致。
String heatmapBubbleText(
  StatsMetric metric,
  DateTime day, {
  required Duration total,
  required int sessions,
}) =>
    '${day.month}月${day.day}日 · '
    '${heatmapCellValueLabel(metric, total: total, sessions: sessions)}';

/// 日格语义日期：`2026年7月10日`——跨年窗口里月份重复，语义报日期
/// 要带年份才分得清。
String heatmapCellDateLabel(DateTime day) =>
    '${day.year}年${day.month}月${day.day}日';

/// 日格语义练习量：与气泡同一个取值口径（按单位给时长或次数，
/// 无练习日为「这天没有练习」）。
String heatmapCellValueLabel(
  StatsMetric metric, {
  required Duration total,
  required int sessions,
}) {
  final value = statsMetricValue(total, sessions, metric);
  if (value <= 0) return '这天没有练习';
  return switch (metric) {
    StatsMetric.time => '练习 ${statsDurationText(total)}',
    StatsMetric.count => '练习 $sessions 次',
  };
}
