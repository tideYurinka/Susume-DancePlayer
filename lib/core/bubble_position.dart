/// 读数气泡的二维定位与避让算术：全 App 一条规则、两处调用——
/// 统计页柱状图传目标柱的柱体矩形，舞详情练习分布图传选中段的像素区间矩形。
///
/// 纵向一律中心对齐手指 y 并钳在绘图区内（气泡比绘图区还高时 top 取 0，
/// 确定取值、无负值）；横向一律朝远离目标的一侧避让——目标中心落在绘图区
/// 左半时气泡贴目标右缘、落在右半时贴左缘，两者之间**不留缝**（零间距）。
/// 左右两侧都放不下时把气泡钳回绘图区内为止，此时不相交让位于不越界。
///
/// 领域模块（`lib/stats` 的柱状图卡与 `lib/home` 的练习分布卡）各自按本域
/// 几何算出目标矩形后调用，不各写一份气泡几何。
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Rect;

/// 避让式气泡定位：返回气泡左上角在绘图区局部坐标下的 `(left, top)`。
///
/// [target] 是被避让的读数矩形（目标柱柱体 / 选中段像素区间），只有横向
/// 区间参与避让——纵向只跟手指 y 与绘图区走。
({double left, double top}) avoidingBubblePosition({
  required double fingerY,
  required double bubbleWidth,
  required double bubbleHeight,
  required double plotWidth,
  required double plotHeight,
  required Rect target,
}) {
  final top = bubbleHeight >= plotHeight
      ? 0.0
      : (fingerY - bubbleHeight / 2).clamp(0.0, plotHeight - bubbleHeight);
  final maxLeft = math.max(0.0, plotWidth - bubbleWidth);
  final targetInLeftHalf = target.center.dx < plotWidth / 2;
  // 左半目标 → 气泡整体靠右（贴目标右缘）；右半 → 靠左。
  final left = targetInLeftHalf
      ? math.min(target.right, maxLeft)
      : math.max(target.left - bubbleWidth, 0.0);
  return (left: left, top: top);
}
