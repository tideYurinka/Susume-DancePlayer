/// 预览线吸附：轨道区拖动 seek 的目标经「吸附解析」纯函数——
/// 距最近目标线 ≤ 吸附半径时吸附到该线（目标集 = 分段线 + 首线 + 尾线，
/// 由 [previewSnapTargetSet] 组装、调用方传入）；吸附目标进入/切换时的
/// 震动反馈由轨道带（`track_band.dart`）在同一拖动会话内判定触发。
///
/// 吸附半径初值 ≈12dp（真机可调），dp → 时间换算由调用方按
/// 当前可视窗口宽度折算后传入。
///
/// [previewSnapEnabledProvider] 是本域的会话级开关状态（默认开，打开恢复
/// 复位/写回）；域自持跨帧状态走既有 Riverpod 状态模型，读取面与纯函数
/// 同库。
///
/// 依赖方向（单向）：只依赖 flutter_riverpod + 领域纯件（节拍网格读面、
/// 标注时间线、强拍解析）；零 import 中枢与任何 player 侧库，反向不可。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/annotation_timeline.dart';
import '../annotation/downbeat_snap.dart' show resolveDownbeatSnap;
import '../core/beat_grid.dart';

/// 预览线吸附开关模型（编辑会话级内存态，默认开）。
class PreviewSnapModel extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;

  /// 打开恢复写回。
  void replace(bool value) => state = value;
}

/// 预览线吸附开关注入点：轨道带右上 dock 组最左的开关（吸附网格设置
/// 左侧）；关闭后轨道区拖动 seek 不做磁性吸附、无震动。
final previewSnapEnabledProvider = NotifierProvider<PreviewSnapModel, bool>(
  PreviewSnapModel.new,
);

/// 吸附半径初值（dp）：拖动目标距分段线 ≤ 此像素距离换算的时间即吸附。
const double kPreviewSnapRadiusDp = 12.0;

/// dp 半径 → 时间半径：按当前可视窗口（窗口跨度 [windowSpan] 铺满带宽
/// [width] px）折算；宽度非正时退化为零半径（不吸附）。
Duration previewSnapRadiusTime({
  required Duration windowSpan,
  required double width,
}) {
  if (width <= 0) return Duration.zero;
  return Duration(
    microseconds:
        (windowSpan.inMicroseconds * kPreviewSnapRadiusDp / width).round(),
  );
}

/// 预览磁吸目标集：分段线 + 可选首线 + 可选尾线；与分段线重合
/// 的首/尾去重（同一位置只留一个目标）。首/尾传 null 表示不纳入目标集
/// （如首/尾控制柄拖动只吸附分段线）。顺序不参与解析语义（解析取最近）。
List<Duration> previewSnapTargetSet({
  required List<Duration> segmentLines,
  Duration? rangeStart,
  Duration? rangeEnd,
}) {
  final targets = List.of(segmentLines);
  for (final boundary in [rangeStart, rangeEnd]) {
    if (boundary != null && !targets.contains(boundary)) {
      targets.add(boundary);
    }
  }
  return targets;
}

/// 解析拖动目标的吸附落点。
///
/// 返回吸附到的目标线时间；不在任何线的 [snapRadius] 内、开关关闭或无
/// 目标线时返回 null（落点 = 原目标）。半径内取**最近**目标线；恰在半径
/// 边界（距离 == 半径）也算吸附。
Duration? resolvePreviewSnap({
  required Duration target,
  required List<Duration> segmentLines,
  required Duration snapRadius,
  bool enabled = true,
}) {
  if (!enabled || segmentLines.isEmpty) return null;
  Duration? nearest;
  var nearestDelta = snapRadius;
  for (final line in segmentLines) {
    final delta = (target - line).abs();
    if (delta <= nearestDelta) {
      nearest = line;
      nearestDelta = delta;
    }
  }
  return nearest;
}

/// 预览线拖动 seek 的吸附落点（纯函数；两支互斥）：返回**吸附到的目标线**
/// 时间；未吸附（开关关、无目标线、不在半径内）或待命态无强拍可吸时返回
/// null（调用侧落点 = 原目标）。「是否吸附」是独立于落点值的一位——原目标
/// 恰在目标线上时两者相等，故不折叠成原目标。
///
///   - [standby]（八拍矫正待命态）→ **恒定吸附最近强拍**——落点是模块侧硬
///     约束（锚点只能落在强拍上），不受「预览吸附」开关影响；
///   - 否则 [enabled] 时 → 吸附目标集（分段线 + 首线 + 尾线）内最近者
///     （[resolvePreviewSnap]；半径按 [windowSpan] 铺满 [contentWidth] 折算）。
///
/// [contentWidth] 是内容区宽（吸附半径按内容区口径折算，轨道片头不吃
/// 像素↔时间换算）。
Duration? snapScrubTarget(
  Duration target, {
  required bool standby,
  required BeatGrid grid,
  required bool enabled,
  required AnnotationTimeline timeline,
  required Duration windowSpan,
  required double contentWidth,
}) {
  if (standby) return resolveDownbeatSnap(target, grid: grid);
  if (!enabled) return null;
  return resolvePreviewSnap(
    target: target,
    segmentLines: previewSnapTargetSet(
      segmentLines: [for (final line in timeline.segmentLines) line.position],
      rangeStart: timeline.rangeStart,
      rangeEnd: timeline.rangeEnd,
    ),
    snapRadius: previewSnapRadiusTime(
      windowSpan: windowSpan,
      width: contentWidth,
    ),
  );
}
