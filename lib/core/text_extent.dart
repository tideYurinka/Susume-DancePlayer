/// 文本排版尺寸量测：`TextPainter` 的构造 / layout / dispose 收在此处，
/// 调用方只给文本与样式，拿回排版尺寸。
///
/// 量测与渲染同源是调用方的责任：`scaler` 与 `direction` 必须与渲染侧取
/// 同一值（`Text` 侧同样吃 `MediaQuery.textScalerOf` 与 `Directionality`）。
library;

import 'package:flutter/painting.dart';

/// [text] 按 [style] 排版的尺寸。
///
/// [scaler] 默认不缩放；[maxWidth] 缺省即不限宽（单行 / 显式换行按原样），
/// [maxLines] 缺省即不限行数。
Size measureTextExtent(
  String text,
  TextStyle style, {
  TextScaler scaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
  double? maxWidth,
  int? maxLines,
}) => measureTextSpanExtent(
  TextSpan(text: text, style: style),
  scaler: scaler,
  direction: direction,
  maxWidth: maxWidth,
  maxLines: maxLines,
);

/// [span] 按原样排版的尺寸。
///
/// 分段样式由 span 树自带：调用方要量的是带分段样式的文本时（渲染侧同样
/// 传这棵树），不能塌成 [measureTextExtent] 的纯字符串——分段边界会改变
/// 排版中的字形成段。其余参数同 [measureTextExtent]。
Size measureTextSpanExtent(
  TextSpan span, {
  TextScaler scaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
  double? maxWidth,
  int? maxLines,
}) {
  final painter = TextPainter(
    text: span,
    textScaler: scaler,
    textDirection: direction,
    maxLines: maxLines,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  final size = painter.size;
  painter.dispose();
  return size;
}
