import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/text_extent.dart';
import 'speed_control.dart' show speedRateMax, speedRateMin;
import 'speed_step.dart' show formatRate;

/// 倍速文字固定槽位。
///
/// 倍率位数变化（`1x` ↔ `1.05x`）使按钮/胶囊变宽、锚定气泡位置跳动；
/// 本文件把「可能的最宽显示文本」实测为固定槽位宽度，顶栏倍速工具与
/// 观看态胶囊的倍速文字放入居中槽位——按钮/胶囊宽与几何中心恒定。
/// 固定槽位不影响实际倍速取值；气泡水平钳制逻辑保留兜底。

/// 槽位前后内边距（前后内边距含入槽位宽度）。
const double kRateSlotHorizontalPadding = 2.0;

/// 槽位宽度测算的候选倍率集：范围内全部两位小数取值（[speedRateMin]–
/// [speedRateMax]）。可达倍率（快捷档、0.05 滑条网格、步进档位）均为
/// 两位小数，本集是其超集，保证槽位容纳任意可达显示文本。
List<double> rateLabelCandidates() {
  final lo = (speedRateMin * 100).ceil();
  final hi = (speedRateMax * 100).floor();
  return [for (var k = lo; k <= hi; k++) k / 100];
}

/// 候选倍率显示文本中的最宽文本宽度（逻辑像素，不含附加内边距）。
///
/// [textScaler] 传调用处的缩放（——倍速读数
/// 承载语义，属语义档（随系统字号）：量测与渲染必须吃同一个 `textScaler`，
/// 否则字号放大档读数被固定槽裁掉）。
double widestRateLabelWidth(
  Iterable<double> rates,
  TextStyle style, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  var widest = 0.0;
  for (final rate in rates) {
    widest = math.max(
      widest,
      measureTextExtent('${formatRate(rate)}x', style, scaler: textScaler).width,
    );
  }
  return widest;
}

/// 槽位宽度缓存（键为样式相等性 + 下限 1 后的缩放系数；调用处样式均为
/// const、缩放档有限，条目数有限），避免每次 build 重复做全候选集
/// 文本实测。缩放入键：不同字号档互不命中缓存。
final Map<(TextStyle, double), double> _slotWidthCache = {};

/// 倍速文字固定槽位宽度（逻辑像素）= 可能的最宽显示文本宽度 + 前后内边距。
///
/// 缩放系数下限取 1（既有裁决）：槽内文字最小按 1.0 渲染，定宽若随
/// `textScaler < 1` 收缩，紧约束的 SizedBox 会比内容窄而溢出；`> 1` 时
/// 随缩放放大，槽内读数不被裁。
double rateLabelSlotWidth(
  TextStyle style, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final factor = math.max(1.0, textScaler.scale(1));
  return _slotWidthCache.putIfAbsent(
    (style, factor),
    () =>
        widestRateLabelWidth(
          rateLabelCandidates(),
          style,
          textScaler: TextScaler.linear(factor),
        ) +
        2 * kRateSlotHorizontalPadding,
  );
}

/// 倍速文字固定宽度槽位：宽度 = [rateLabelSlotWidth]（含前后内边距），
/// 文字居中、单行——倍率位数变化不改变宿主（按钮/胶囊）宽度与几何中心。
class RateTextSlot extends StatelessWidget {
  const RateTextSlot({super.key, required this.rate, required this.style});

  /// 当前显示倍率（仅影响文本内容，不影响槽位宽度）。
  final double rate;

  /// 文本样式；槽位宽度按此样式实测（调用处沿用各自既有样式）。
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // 槽宽量测吃当前 MediaQuery 缩放：与槽内 Text 的渲染缩放
    // 同源——字号放大档槽随宽、读数不被裁；< 1 由 [rateLabelSlotWidth]
    // 兜底不收缩。
    final textScaler = MediaQuery.textScalerOf(context);
    return SizedBox(
      width: rateLabelSlotWidth(style, textScaler: textScaler),
      child: Center(
        child: Text('${formatRate(rate)}x', style: style, maxLines: 1),
      ),
    );
  }
}
