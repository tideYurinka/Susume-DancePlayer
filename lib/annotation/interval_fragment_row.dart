/// 区间片段行共用纯件（prefactor）：区间片段行的三条共用纪律
/// 收成一处零依赖声明——
///
/// ① **时间↔像素的区间映射与裁切**（[intervalBlockRect]）：时间窗 → 块矩
///    形，含窗口外裁切、零宽与倒置区间降级为空；
/// ② **命中解析**（[resolveIntervalHit]）：区间对称扩展至不小于最小命中
///    宽（只向上、宽段不收缩）、多候选取距中心最近、同距取靠前、无候选
///    返回空；
/// ③ **命中区域划分**（[intervalHitRegion] 与 [IntervalHitRegion]）：块体
///    / 两端端点带 / 窄块阈值抑制端点带；
/// ④ **新建截断与保序插入**（[truncatedNewSpan] 与 [spanInsertionIndex]）：
///    新片段向区间末与右邻起点截断防重叠，并按起点升序插回。
///
/// 零 Flutter 依赖（不 import widget 层、不引 dart:ui），可在不启动
/// widget 环境的情况下直测；与像素/时间单位无关——命中解析按调用方换算
/// 好的整数坐标工作，与既有命中纪律（像素→时间换算由 widget 层承担）一
/// 致。抽出的件是两处既有消费侧（学习段体分支、局部镜像片段）迁移的靶，
/// 也是备注轨的消费对象。
library;

/// 半开区间 `[start, end)`。字段名 `Ms` 沿主要消费侧（毫秒）命名；算术
/// 本身与时间单位无关——任何一致的整数时间坐标（如学习段轨的微秒）皆可
/// 直接传入，见 [resolveIntervalHit]。
class IntervalSpan {
  const IntervalSpan({required this.startMs, required this.endMs});

  final int startMs;

  final int endMs;

  @override
  bool operator ==(Object other) =>
      other is IntervalSpan && other.startMs == startMs && other.endMs == endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);

  @override
  String toString() => 'IntervalSpan($startMs, $endMs)';
}

/// 区间映射出的块矩形（行内横向局部像素坐标；纵向由行矩形承担）。
class IntervalBlockRect {
  const IntervalBlockRect({required this.left, required this.width});

  final double left;

  final double width;

  @override
  bool operator ==(Object other) =>
      other is IntervalBlockRect && other.left == left && other.width == width;

  @override
  int get hashCode => Object.hash(left, width);

  @override
  String toString() => 'IntervalBlockRect($left, $width)';
}

/// 区间片段行的命中区域（交互划分；块体 = 整体拖，端点带 =
/// 端点拖）。
enum IntervalHitRegion { body, startEdge, endEdge }

/// 把 [span] 经时间窗 [window] 映射为行内块矩形：先与窗口求交（窗口外裁
/// 切），再按「窗 → [trackWidth] 像素」线性映射，整体偏移到内容区左缘
/// [contentLeft]。
///
/// [trackWidth] 是**内容区宽**、[contentLeft] 是内容区左缘
/// （轨道带内容区左缘让出轨道片头带——时间轴零点不在带左缘）。两者都**必填**
/// ——块摆位依赖完整的内容区口径，漏传即编译期报错；内容区从行左缘起的
/// 调用方显式传 0。
///
/// 返回 `null` = 不渲染的降级：区间零宽或倒置、与窗口无交（完全在窗外或
/// 裁后零宽）、窗口倒置或零宽、带宽非正。与既有渲染纪律同口径：右端贴
/// 窗、像素钳在窗内，零宽块不画。
IntervalBlockRect? intervalBlockRect({
  required IntervalSpan span,
  required IntervalSpan window,
  required double trackWidth,
  required double contentLeft,
}) {
  if (trackWidth <= 0) return null;
  if (window.startMs >= window.endMs) return null;
  if (span.startMs >= span.endMs) return null;
  final clippedStart = span.startMs < window.startMs
      ? window.startMs
      : span.startMs;
  final clippedEnd = span.endMs > window.endMs ? window.endMs : span.endMs;
  if (clippedStart >= clippedEnd) return null;
  final windowSpanMs = (window.endMs - window.startMs).toDouble();
  final left =
      contentLeft + (clippedStart - window.startMs) / windowSpanMs * trackWidth;
  final right =
      contentLeft + (clippedEnd - window.startMs) / windowSpanMs * trackWidth;
  final width = right - left;
  if (width <= 0) return null;
  return IntervalBlockRect(left: left, width: width);
}

/// 区间端点（端点拖共用的选边；块体 / 两端端点带的区域划分见
/// [IntervalHitRegion]）。
enum IntervalEdge { start, end }

/// 整体移（共用钳制数学，第三处消费收口于此）：把 [index] 处区间
/// 平移为新起点 [newStartMs]（保持原宽），并与相邻区间 + 首尾区间互斥
/// 钳制。钳空（无可放置区间，`hi <= lo`）= 返回 null；否则返回钳后的
/// 新区间。半开共享端点（新终点 == 右邻起点 / 新起点 == 左邻终点）视为
/// 不重叠、合法。
IntervalSpan? moveSpanClamped({
  required List<IntervalSpan> spans,
  required int index,
  required int rangeStartMs,
  required int rangeEndMs,
  required int newStartMs,
}) {
  if (index < 0 || index >= spans.length) return null;
  final span = spans[index];
  final width = span.endMs - span.startMs;
  final prevEnd = index > 0 ? spans[index - 1].endMs : rangeStartMs;
  final nextStart = index + 1 < spans.length
      ? spans[index + 1].startMs
      : rangeEndMs;
  final lo = prevEnd < rangeStartMs ? rangeStartMs : prevEnd;
  final hi = (nextStart - width) < rangeEndMs ? nextStart - width : rangeEndMs;
  if (hi <= lo) return null; // 钳空
  final start = newStartMs < lo ? lo : (newStartMs > hi ? hi : newStartMs);
  return IntervalSpan(startMs: start, endMs: start + width);
}

/// 端点拖（共用钳制数学，第三处消费收口于此）：把 [index] 处区间
/// 的 [edge] 端拖到 [edgeMs]（另一端不动），并与相邻区间 + 首尾区间互斥
/// 钳制；端点不得倒置（钳到对端即无宽 = 返回 null）。
IntervalSpan? dragSpanEdgeClamped({
  required List<IntervalSpan> spans,
  required int index,
  required IntervalEdge edge,
  required int rangeStartMs,
  required int rangeEndMs,
  required int edgeMs,
}) {
  if (index < 0 || index >= spans.length) return null;
  final span = spans[index];
  if (edge == IntervalEdge.start) {
    final lo = index > 0 ? spans[index - 1].endMs : rangeStartMs;
    final hi = span.endMs;
    if (hi <= lo) return null;
    final start = edgeMs < lo ? lo : (edgeMs > hi ? hi : edgeMs);
    if (start >= span.endMs) return null;
    return IntervalSpan(startMs: start, endMs: span.endMs);
  }
  final lo = span.startMs;
  final hi = index + 1 < spans.length ? spans[index + 1].startMs : rangeEndMs;
  if (hi <= lo) return null;
  final end = edgeMs < lo ? lo : (edgeMs > hi ? hi : edgeMs);
  if (end <= span.startMs) return null;
  return IntervalSpan(startMs: span.startMs, endMs: end);
}

/// 新建区间的右端截断（共用件）：起点 [startMs] + 宽 [widthMs]，
/// 向区间末 [rangeEndMs] 与**右邻区间起点**截断（半开共享端点视为不重叠，
/// 故只被严格位于 `(startMs, endMs)` 内的起点截短）；截后零宽或倒置返回
/// `null`。起点侧（吸附/推离）的口径与两轨不对称——留调用侧。
IntervalSpan? truncatedNewSpan({
  required List<IntervalSpan> spans,
  required int startMs,
  required int widthMs,
  required int rangeEndMs,
}) {
  var endMs = startMs + widthMs;
  if (endMs > rangeEndMs) endMs = rangeEndMs;
  for (final span in spans) {
    if (span.startMs > startMs && span.startMs < endMs) endMs = span.startMs;
  }
  if (endMs <= startMs) return null;
  return IntervalSpan(startMs: startMs, endMs: endMs);
}

/// 保序插入位：第一条起点不小于 [startMs] 的区间所在位置；没有这样的区间
/// （都排在它之前）则为列表长度（= 追加到末尾）。
int spanInsertionIndex(List<IntervalSpan> spans, int startMs) {
  final index = spans.indexWhere((span) => span.startMs >= startMs);
  return index < 0 ? spans.length : index;
}

/// 区间片段行命中解析（共享 helper）：点按 [positionMs] 命中 [spans] 中
/// 的哪个区间，返回其下标；无候选返回 `null`（轨道空白）。
///
///   - 每个区间的命中域 = 其区间**对称扩展至不小于 [minHitWidthMs]**（只
///     向上扩展、宽段不收缩）；
///   - 多候选重叠（相邻小片段/间隙小）取**距点按最近的区间中心**，距离
///     相等时取**靠前**的区间；
///   - 皆否返回 `null`。
///
/// 扩展量对差值下取整：奇数毫秒差时扩展域总宽为 [minHitWidthMs] − 1
/// （既有同款解析的固有口径，整数毫秒域内可忽略）。[minHitWidthMs] 非正
/// 时不扩展（命中域 = 几何区间）。
int? resolveIntervalHit({
  required List<IntervalSpan> spans,
  required int positionMs,
  required int minHitWidthMs,
}) {
  int? index;
  var bestDist = -1;
  for (var i = 0; i < spans.length; i++) {
    final span = spans[i];
    final widthMs = span.endMs - span.startMs;
    final expansionMs = widthMs >= minHitWidthMs
        ? 0
        : (minHitWidthMs - widthMs) ~/ 2;
    if (positionMs < span.startMs - expansionMs ||
        positionMs >= span.endMs + expansionMs) {
      continue;
    }
    final dist = (positionMs - (span.startMs + span.endMs) ~/ 2).abs();
    if (index == null || dist < bestDist) {
      index = i;
      bestDist = dist;
    }
  }
  return index;
}

/// 划分块内偏移 [offsetInBlock] 的命中区域：块体 / 左右端点带。
///
///   - 偏移在块外（`< 0` 或 `≥ [blockWidth]`）→ `null`；
///   - **窄块阈值抑制**：块宽不足 [narrowWidth] 时端点带整段抑制，全块
///     归块体（块宽低于 `2×` 端点带宽时两带覆盖整块、吞掉块体点按的死区
///     必然出现，故窄块优先块体）；
///   - 否则偏移落在左带 `[0, [edgeBandWidth])` → [IntervalHitRegion.startEdge]，
///     右带 `[blockWidth − [edgeBandWidth], [blockWidth])` →
///     [IntervalHitRegion.endEdge]，其余 → [IntervalHitRegion.body]。
IntervalHitRegion? intervalHitRegion({
  required double blockWidth,
  required double offsetInBlock,
  required double edgeBandWidth,
  required double narrowWidth,
}) {
  if (offsetInBlock < 0 || offsetInBlock >= blockWidth) return null;
  if (blockWidth < narrowWidth) return IntervalHitRegion.body;
  if (offsetInBlock < edgeBandWidth) return IntervalHitRegion.startEdge;
  if (offsetInBlock >= blockWidth - edgeBandWidth) {
    return IntervalHitRegion.endEdge;
  }
  return IntervalHitRegion.body;
}

/// 端点命中域分配结果：块两端各自的端点带宽度（像素）。
class IntervalEdgeHitAllocation {
  const IntervalEdgeHitAllocation({
    required this.startWidth,
    required this.endWidth,
  });

  /// start 端点带宽度；`0` = 该侧让出（不渲染、不起手端点拖）。
  final double startWidth;

  /// end 端点带宽度；`0` = 该侧让出。
  final double endWidth;

  /// 两端都放不下 = 最坏退化：整块归块体（整体移），端点拖不可达。
  bool get wholeBlockIsMove => startWidth <= 0 && endWidth <= 0;

  @override
  bool operator ==(Object other) =>
      other is IntervalEdgeHitAllocation &&
      other.startWidth == startWidth &&
      other.endWidth == endWidth;

  @override
  int get hashCode => Object.hash(startWidth, endWidth);

  @override
  String toString() => 'IntervalEdgeHitAllocation($startWidth, $endWidth)';
}

/// 端点命中域分配：块两端各按该侧可用空间自适应
/// 分配端点带——能放多少给多少，与相邻片段或带缘冲突的那部分不给，最坏
/// 退化成整块归移动；选中后目标带宽取 [selectedBandWidth]（端点柄，命中
/// 域更长）。两条路径的输出都不越出各侧可用空间（带内可用横向范围由
/// 可用空间入参界定）。
///
/// 可用空间是**块缘向外**到最近占用的空闲像素：朝相邻片段一侧应让半
/// （对方的端点带同样要伸进这条空隙，各取一半即互不侵占），朝带缘一侧
/// 全给——由调用点折算，本函数只认数值。
IntervalEdgeHitAllocation allocateIntervalEdgeHitDomains({
  required double startAvailable,
  required double endAvailable,
  required double bandWidth,
  required double selectedBandWidth,
  required bool selected,
}) {
  assert(bandWidth >= 0, '端点带宽度非负');
  assert(selectedBandWidth >= 0, '选中端点柄宽度非负');
  final desired = selected ? selectedBandWidth : bandWidth;
  double width(double available) {
    final w = available < desired ? available : desired;
    return w > 0 && w.isFinite ? w : 0.0;
  }

  return IntervalEdgeHitAllocation(
    startWidth: width(startAvailable),
    endWidth: width(endAvailable),
  );
}
