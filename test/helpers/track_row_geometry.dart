import 'package:dance_learning_app/player/track_geometry.dart';
import 'package:dance_learning_app/player/track_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试侧助力：按行键从渲染树取行矩形
/// 与行中心。只做「按行键取矩形」这一层包装，服务既有 widget 测试边界。

Rect trackRowRect(WidgetTester tester, String rowKey) =>
    tester.getRect(find.byKey(Key(rowKey)));

Offset trackRowCenter(WidgetTester tester, String rowKey) =>
    tester.getCenter(find.byKey(Key(rowKey)));

double trackRowCenterY(WidgetTester tester, String rowKey) =>
    trackRowCenter(tester, rowKey).dy;

/// 本带几何（[width] = 实测带宽；片头让位恒按 [kTrackPrefixWidth]）——带内
/// 横向换算的唯一测试入口：下面的换算函数都**转调本几何**，不重写公式。
TrackBandGeometry bandGeometryOf({
  Duration? total,
  TimelineWindow? window,
  required double width,
}) => TrackBandGeometry.eval(
  total: total,
  window: window,
  width: width,
  prefixWidth: kTrackPrefixWidth,
);

/// 内容区宽（内容区左缘让出轨道片头带）。
double bandContentWidth(double bandWidth) =>
    bandGeometryOf(width: bandWidth).contentWidth;

/// 时间 → 带内屏上 x：[bandLeft] 为带（行）矩形左缘，[window] 为可视窗口
/// （null = 全片）。
double bandXOf(
  Duration time, {
  required Duration total,
  required double width,
  double bandLeft = 0,
  TimelineWindow? window,
}) =>
    bandLeft +
    bandGeometryOf(
      total: total,
      window: window,
      width: width,
    ).timeToPixel(time);

/// 带内屏上 x → 时间（[bandXOf] 的逆）。
Duration bandTimeAt(
  double x, {
  required Duration total,
  required double width,
  double bandLeft = 0,
  TimelineWindow? window,
}) => bandGeometryOf(
  total: total,
  window: window,
  width: width,
).pixelToTime(x - bandLeft);

/// 时间（秒）→ 带内屏上 x 的便捷入口（多用例按秒写期望）：[total] 默认
/// 30s、[width] 默认 800（默认测试面宽）。
double bandX(num seconds, {num total = 30, double width = 800}) => bandXOf(
  Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round()),
  total: Duration(
    microseconds: (total * Duration.microsecondsPerSecond).round(),
  ),
  width: width,
);
