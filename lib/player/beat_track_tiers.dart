/// 节拍轨三级刻度分级：从节拍网格 seam 派生按乐句结构分级的
/// 刻度序列——八拍大线 > 四拍中线 > 一拍小线。
///
/// 派生规则：八拍大线从 downbeat 序列按八拍相位
/// 分组——每个八拍区间（8 拍 = 两个 4/4 小节）的第 1 条 downbeat = 八拍
/// 大线、第 2 条 = 四拍中线；其余每拍 = 一拍小线。首个 downbeat 之前的
/// 弱起拍只按拍点呈现（不派生大线/中线）。
///
/// 八拍相位（大线/中线分类，含窗口切断的相位种子与无界网格周期算术）
/// 统一读 core 相位源（`core/eight_beat_phase.dart`，序数法、相位原点 =
/// 网格首个强拍）——与分段线吸附/节拍动画在结构上同源。纯函数、不侵入
/// [BeatGrid]。
library;

import '../annotation/learning_segments.dart';
import '../core/beat_grid.dart';
import '../core/eight_beat_phase.dart'
    show BeatPhase, eightBeatIntervalWeight, eightBeatIntervals;

/// 刻度层级：视觉强度 八拍大线 > 四拍中线 > 一拍小线。
enum BeatTickTier { eightBar, fourBar, beat }

/// 一根节拍轨刻度：拍时刻 + 层级。
class BeatTick {
  const BeatTick({required this.time, required this.tier});

  final Duration time;
  final BeatTickTier tier;
}

/// 派生 `[start, end]` 闭窗内的分级刻度序列（升序）。
///
/// [phase] = 八拍相位（网格 + 八拍锚点）派生源，**必填**：有锚点时大线/
/// 中线按锚点重定相（锚点自身即八拍点、其后每隔一个强拍一个八拍点、管到
/// 下一个锚点之前）；按无锚点求值时调用点须显式构造无锚点相位
/// （`BeatPhase(grid: grid)`）。漏传相位 = 编译错误。
List<BeatTick> beatTrackTicks(
  BeatGrid grid,
  Duration start,
  Duration end, {
  required BeatPhase phase,
}) {
  final firstDownbeat = grid.firstDownbeatIndex;
  final eightBarTimes = Set<Duration>.of(phase.pointsInWindow(start, end));
  return [
    for (final time in grid.beatsInWindow(start, end))
      BeatTick(
        time: time,
        tier: _tierOf(grid, time, firstDownbeat, eightBarTimes),
      ),
  ];
}

BeatTickTier _tierOf(
  BeatGrid grid,
  Duration time,
  int firstDownbeat,
  Set<Duration> eightBarTimes,
) {
  final index = grid.beatIndexAt(time);
  if (index < firstDownbeat || !grid.isDownbeat(index)) {
    return BeatTickTier.beat;
  }
  // 八拍区间内第奇数条 downbeat（全局序 1、3、5…）= 大线，偶数 = 中线。
  return eightBarTimes.contains(time)
      ? BeatTickTier.eightBar
      : BeatTickTier.fourBar;
}

/// 刻度宽按层级取值：八拍大线 1.5px、四拍中线与一拍小线 1px。
double beatTickWidthOf(BeatTickTier tier) => switch (tier) {
  BeatTickTier.eightBar => 1.5,
  BeatTickTier.fourBar || BeatTickTier.beat => 1.0,
};

/// 相邻可标八拍大线的最小屏上间距（32px：更密拍距也显示；不足不标，
/// 判定整窗严格两档）。
const double kEightCountLabelMinSpacingPx = 32;

/// 一个八拍数标注：八拍大线时刻 + 序号（所在学习段段内相对，段首八拍 = 1）。
class BeatEightCountLabel {
  const BeatEightCountLabel({required this.time, required this.count});

  final Duration time;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is BeatEightCountLabel &&
      other.time == time &&
      other.count == count;

  @override
  int get hashCode => Object.hash(time, count);

  @override
  String toString() => 'BeatEightCountLabel($time, #$count)';
}

/// 派生八拍数标注序列（段内相对编号）：
///
/// [phase] = 八拍相位派生源（轨上八拍数小数字与大线同相位），
/// **必填**；按无锚点求值时调用点须显式构造无锚点相位。
///
///   - 仅真实拍点可用（[BeatGridReads.hasRealBeats]；占位/异常不标）且存在
///     学习段（[segments] 为空 = 未创建分段线 = 无段内编号基准，不标）；
///   - 标注值 = 该大线在其**所在学习段**内的八拍序号（段首所在八拍 = 1，
///     段首非八拍整点时为段内第一个大线）；跨段重数；序号对段全量大线
///     计数、不随可视窗口漂移（窗口外的大线照常占序号）；
///   - 与分段线/首线/尾线**同位**的大线不标（同位已由线表达）、但仍占
///     所在段序号（段边界大线归为后段段首、占其后段序号 1）；大线归段
///     按左闭右开 `[seg.start, seg.end)`（末段含 [seg.end]）；
///   - **整窗一次判定**：对可视窗口一次性计算相邻候选大线的最小屏距 minGap
///     （相邻 Δ / [microsecondsPerPixel]，μsPerPx 口径不变）；
///     minGap ≥ [minSpacingPx]
///     → 窗口内全部候选放标；否则 → 全部不放（严格两档、无中间抽稀）。
///     结果只取决于窗口内候选子集本身，无「窗口首候选恒放」式的原点对齐
///     偏好；故在间距均匀的区间内平移，取舍只随窗口边缘候选的进出改变，
///     不会因窗口起点落在哪个候选上而翻转。
///
/// [hiddenAtTimes]：**让位不显示但仍占序号**的时刻集（待命态
/// 八拍锚点所在大线让位给锚点视觉）——与「同位大线不显示但占序号」同一
/// 口径：该处不产出标注、其序号照常计数（相邻大线序号连续）。
List<BeatEightCountLabel> beatEightCountLabels({
  required BeatGrid grid,
  required List<LearningSegment> segments,
  required Duration windowStart,
  required Duration windowEnd,
  required double microsecondsPerPixel,
  double minSpacingPx = kEightCountLabelMinSpacingPx,
  required BeatPhase phase,
  Set<Duration> hiddenAtTimes = const {},
}) {
  if (!grid.hasRealBeats || microsecondsPerPixel <= 0 || segments.isEmpty) {
    return const [];
  }
  // 同位占用集 = 各段段首边界（首线/各分段线）+ 末段段尾（尾线）；
  // 中间段界由「归后段段首」口径经段首边界入集。
  final occupied = <Duration>{for (final s in segments) s.start};
  occupied.add(segments.last.end);
  final candidates = <({Duration time, int ordinal})>[];
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    // 段界大线归后段（左闭右开）；末段含段尾（尾线同位占末段序号）。
    final isLast = i + 1 == segments.length;
    final rightBound = isLast ? segment.end : segments[i + 1].start;
    var ordinal = 0;
    for (final tick in beatTrackTicks(
      grid,
      segment.start,
      segment.end,
      phase: phase,
    )) {
      if (tick.tier != BeatTickTier.eightBar) continue;
      if (tick.time > rightBound || (!isLast && tick.time == rightBound)) {
        continue;
      }
      ordinal += 1;
      if (tick.time < windowStart || tick.time > windowEnd) continue;
      if (occupied.contains(tick.time)) continue;
      // 让位隐藏：序号已计、不产出标注。
      if (hiddenAtTimes.contains(tick.time)) continue;
      candidates.add((time: tick.time, ordinal: ordinal));
    }
  }
  candidates.sort((a, b) => a.time.compareTo(b.time));
  if (candidates.isEmpty) return const [];
  // 整窗一次判定（语义见上方 doc 末条）；单候选无相邻约束（minGap 恒
  // 足够）→ 可放。
  var minGapPx = double.infinity;
  for (var i = 1; i < candidates.length; i++) {
    final gapPx =
        (candidates[i].time - candidates[i - 1].time).inMicroseconds /
        microsecondsPerPixel;
    if (gapPx < minGapPx) minGapPx = gapPx;
  }
  if (minGapPx < minSpacingPx) return const [];
  return [
    for (final c in candidates)
      BeatEightCountLabel(time: c.time, count: c.ordinal),
  ];
}

/// [phase] = 八拍相位派生源，**必填**（段内八拍数与轨上大线同相位，有锚点
/// 时按锚点重定相计数；按八拍点**区间加权**求 0.5 分度值）；按无锚点求值
/// 时调用点须显式构造无锚点相位。
///
/// 段内八拍数：
///
/// 段首与段尾**均为八拍点整点**时返回段内八拍总数，按八拍点区间**加权**
/// 求和（区间序列与权重都读 core 共用原语，本函数不自实现 stride/相位算术）
/// ——整八拍区间 1、半八拍区间 0.5，故**允许 0.5 分度**（如「4.5 个八拍」）；
/// 段首/段尾非八拍整点（含用户手动拖出的段）、网格非就绪（占位/异常）或
/// 网格非有界实现（占位回落防御：真实拍点可用谓词
/// [BeatGridReads.hasRealBeats] 不认占位/异常网格，不得按占位网格派生假 N）
/// 一律返回 null（不显示）。派生网格单一来源= [grid] 本身；
/// 手动段与自动段同一口径（不要求凑够 4 个整八拍）。
double? segmentEightBeatCount({
  required BeatGrid grid,
  required Duration start,
  required Duration end,
  required BeatPhase phase,
}) {
  if (!grid.hasRealBeats || end <= start) return null;
  final intervals = eightBeatIntervals(phase, start, end);
  if (intervals.isEmpty) return null;
  if (intervals.first.start != start || intervals.last.end != end) return null;
  var total = 0.0;
  for (final interval in intervals) {
    total += eightBeatIntervalWeight(interval.beatGap, grid: grid);
  }
  return total;
}

/// 段内八拍数文案：整数值不带小数位
///（「4 个八拍」的 `4`）、半八拍保留一位（`4.5`）。入参按
/// [eightBeatIntervalWeight] 口径，恒为 0.5 的整数倍，故不出现 0.333… 式
/// 伪小数。
String formatEightBeatCount(double count) {
  final rounded = count.roundToDouble();
  return count == rounded
      ? rounded.toInt().toString()
      : count.toStringAsFixed(1);
}
