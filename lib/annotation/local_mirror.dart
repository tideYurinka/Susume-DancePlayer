/// 局部镜像片段（局部镜像轨数据基座）。
///
/// 纯语义两层：
///   - [LocalMirrorFragment]：可持久化区间片段值对象（[startMs],[endMs)
///     半开），随公开标记文件 typed 顶层字段落盘；
///   - [isSortedAndNonOverlapping]：片段表按 `startMs` 升序且两两不重叠的
///     不变量谓词（编辑侧靠互斥钳制/自动截断保证，本谓词钉其纯语义）。
library;

import '../core/local_mirror_fragment.dart';
import 'interval_fragment_row.dart';

// 值对象与字段声明住 `../core/local_mirror_fragment.dart`；本层原样转出，
// 既有调用点与文档模型的 import 路径不变。
export '../core/local_mirror_fragment.dart';

/// 片段表不变量谓词：每个片段半开区间成形（startMs <= endMs）、整体按
/// [LocalMirrorFragment.startMs] 升序且两两不重叠。
///
/// 升序按相邻段 `startMs` 单调不减 + 前段 `endMs` 不越过后段 `startMs`
/// 表达（半开共享端点 `endMs == 下一 startMs` 视为不重叠，合法）。空表与
/// 单元素恒成立。区间倒置（startMs > endMs）/重叠/乱序返回 false。
bool isSortedAndNonOverlapping(List<LocalMirrorFragment> fragments) {
  for (final fragment in fragments) {
    if (fragment.startMs > fragment.endMs) {
      return false;
    }
  }
  for (var i = 1; i < fragments.length; i++) {
    final prev = fragments[i - 1];
    final current = fragments[i];
    if (current.startMs < prev.startMs || current.startMs < prev.endMs) {
      return false;
    }
  }
  return true;
}

/// 片段表 → 区间表（共用件换算的统一入口）。
List<IntervalSpan> _spansOf(List<LocalMirrorFragment> fragments) => [
  for (final f in fragments) IntervalSpan(startMs: f.startMs, endMs: f.endMs),
];

/// 片段点按命中解析（纯函数 seam；行级点按调用）。
///
/// 与像素无关：入参 = 片段表 + 点按时刻（[timeMs]，毫秒）+ 最小命中宽
/// （[minHitWidthMs]，时间量——像素→时间换算由 widget 层承担，与既有
/// 命中纪律一致）。规则与 `resolveLearningTrackHit` 的学习段体分支同构：
///
///   - 每个片段的命中域 = 其区间**对称扩展至不小于最小命中宽**（只向上
///     扩展、宽段不收缩）；
///   - 多候选重叠（相邻小片段/间隙小）取**距点按最近的片段中心**（距离
///     相等时取靠前的片段，与 `resolveLearningTrackHit` 段体分支同构）；
///   - 皆否返回 `null`（轨道空白）。
///
/// 返回值为被点中片段在 [fragments] 中的下标。[minHitWidthMs] 非正时不扩
/// 展（命中域 = 几何区间）；扩展量对差值下取整，奇数毫秒差时扩展域总宽
/// 为 minHitWidthMs − 1（整数毫秒域内可忽略）。
///
/// 解析纪律收口于共用件 [resolveIntervalHit]（–02 prefactor）：本函数
/// 只做片段表 → 共用件的区间换算，不再自带同款实现。
int? resolveLocalMirrorTapHit({
  required List<LocalMirrorFragment> fragments,
  required int timeMs,
  required int minHitWidthMs,
}) {
  return resolveIntervalHit(
    spans: _spansOf(fragments),
    positionMs: timeMs,
    minHitWidthMs: minHitWidthMs,
  );
}

/// 把目标起点 [startMs] 钳进 [rangeStartMs..rangeEndMs] 内，并向右推离任何
/// 包含它的既有片段（保证落点处于空闲区间，含与片段终点紧邻）。
int clampIntoFreeGap(
  List<LocalMirrorFragment> fragments,
  int startMs, {
  required int rangeStartMs,
  required int rangeEndMs,
}) {
  var point = startMs < rangeStartMs ? rangeStartMs : startMs;
  if (point > rangeEndMs) point = rangeEndMs;
  var moved = true;
  while (moved) {
    moved = false;
    for (final f in fragments) {
      if (f.startMs <= point && point < f.endMs) {
        point = f.endMs;
        moved = true;
      }
    }
  }
  if (point > rangeEndMs) point = rangeEndMs;
  return point;
}

/// 以吸附后的起点创建片段：起点钳进有效区间并向右推离既有 [fragments]，
/// 右端 = 起点 + [widthMs]（一个八拍），向有效区间末与右邻段起点截断
/// 防重叠（截断数学收口于共用件 [truncatedNewSpan]）。正宽才成立；钳空/
/// 无可放置返回 null = no-op drop。
LocalMirrorFragment? placeFragmentCreation({
  required List<LocalMirrorFragment> fragments,
  required int rangeStartMs,
  required int rangeEndMs,
  required int startMs,
  required int widthMs,
}) {
  if (rangeEndMs <= rangeStartMs) return null;
  final start = clampIntoFreeGap(
    fragments,
    startMs,
    rangeStartMs: rangeStartMs,
    rangeEndMs: rangeEndMs,
  );
  final span = truncatedNewSpan(
    spans: _spansOf(fragments),
    startMs: start,
    widthMs: widthMs,
    rangeEndMs: rangeEndMs,
  );
  if (span == null) return null;
  return LocalMirrorFragment(startMs: span.startMs, endMs: span.endMs);
}

/// 把 [fragment] 按其 startMs 插入 [fragments]（保持升序且两两不重叠——
/// 调用方保证 fragment 与既有互斥）；既有表已违序则原样返回。
List<LocalMirrorFragment> insertFragmentKeepingInvariant(
  List<LocalMirrorFragment> fragments,
  LocalMirrorFragment fragment,
) {
  if (!isSortedAndNonOverlapping(fragments)) return fragments;
  final i = spanInsertionIndex(_spansOf(fragments), fragment.startMs);
  return [...fragments.sublist(0, i), fragment, ...fragments.sublist(i)];
}

/// 整体移：把 [index] 处片段平移为新起点 [newStartMs]（保持原宽），并在
/// 与相邻片段 + 首尾区间之间互斥钳制。钳空（无可放置区间）= 返回 null =
/// no-op drop（本次不成立、调用方不写）。钳制数学收口于共用件
/// [moveSpanClamped]（第三处消费收口，本函数只做片段 ↔ 区间换算）。
LocalMirrorFragment? moveFragmentClamped({
  required List<LocalMirrorFragment> fragments,
  required int index,
  required int rangeStartMs,
  required int rangeEndMs,
  required int newStartMs,
}) {
  final moved = moveSpanClamped(
    spans: _spansOf(fragments),
    index: index,
    rangeStartMs: rangeStartMs,
    rangeEndMs: rangeEndMs,
    newStartMs: newStartMs,
  );
  if (moved == null) return null;
  return LocalMirrorFragment(startMs: moved.startMs, endMs: moved.endMs);
}

/// 端点拖：把 [index] 处片段的 [edge] 端拖到 [edgeMs]（另一端不动），并与
/// 相邻片段 + 首尾区间互斥钳制；端点不得越界（钳空/越位）= 返回 null =
/// no-op drop。钳制数学收口于共用件 [dragSpanEdgeClamped]。
LocalMirrorFragment? dragFragmentEdgeClamped({
  required List<LocalMirrorFragment> fragments,
  required int index,
  required IntervalEdge edge,
  required int rangeStartMs,
  required int rangeEndMs,
  required int edgeMs,
}) {
  final dragged = dragSpanEdgeClamped(
    spans: _spansOf(fragments),
    index: index,
    edge: edge,
    rangeStartMs: rangeStartMs,
    rangeEndMs: rangeEndMs,
    edgeMs: edgeMs,
  );
  if (dragged == null) return null;
  return LocalMirrorFragment(startMs: dragged.startMs, endMs: dragged.endMs);
}
