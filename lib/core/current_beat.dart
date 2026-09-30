/// 当前拍纯求值 + 数拍派生：core 纯层的
/// `(节拍上下文, 媒介位置) → 当前拍`/`数拍数字`——屏幕数拍与拍声选段同读的
/// **一次求值**。数拍锚按该位置逐拍现算（锚点链解析 + 就绪网格锚归位），前导
/// = 位置在锚点之前（八拍号 0），半拍线只在该位置属正式区时进值，与整拍
/// 同毫秒的线不进值（一拍一声）。零 Flutter 依赖。
library;

import 'dart:math' show max;

import 'beat_grid.dart';
import 'eight_beat_phase.dart';

/// 当前拍：自足的发布值——八拍号（0 = 前导区）、拍号、是否八拍点（大线）、
/// 是否强拍（中线）、该拍起点、下一拍（网格末拍为空）、拍内进度（0..1）、
/// 本拍内的半拍线时刻（空 = 无：前导区、开关关、与整拍同毫秒者不排）。
/// 消费方只读本值，不再读网格 / 相位 / 半拍线。
class CurrentBeat {
  const CurrentBeat({
    required this.eightCount,
    required this.beatCount,
    required this.isEightBeatPoint,
    required this.isStrongBeat,
    required this.beatStart,
    required this.nextBeat,
    required this.progress,
    required this.halfBeatLines,
  });

  /// 八拍号：练习区 1 起顺数；前导区恒 0（第 0 个八拍）。
  final int eightCount;

  /// 拍号：练习区 1–8；前导区按时间顺数（0|x）。
  final int beatCount;

  /// 本拍是否八拍点（大线）。
  final bool isEightBeatPoint;

  /// 本拍是否强拍（八拍点或四拍中线）。
  final bool isStrongBeat;

  /// 本拍起点（媒介时刻）。
  final Duration beatStart;

  /// 下一拍起点；有界网格末拍为空。
  final Duration? nextBeat;

  /// 拍内进度：`(位置 − 拍起点) / 拍长`，0..1。
  final double progress;

  /// 本拍内的半拍线时刻（升序）。
  final List<Duration> halfBeatLines;

  @override
  bool operator ==(Object other) =>
      other is CurrentBeat &&
      other.eightCount == eightCount &&
      other.beatCount == beatCount &&
      other.isEightBeatPoint == isEightBeatPoint &&
      other.isStrongBeat == isStrongBeat &&
      other.beatStart == beatStart &&
      other.nextBeat == nextBeat &&
      other.progress == progress &&
      _listEquals(other.halfBeatLines, halfBeatLines);

  @override
  int get hashCode => Object.hash(
    eightCount,
    beatCount,
    isEightBeatPoint,
    isStrongBeat,
    beatStart,
    nextBeat,
    progress,
    Object.hashAll(halfBeatLines),
  );

  @override
  String toString() =>
      'CurrentBeat($eightCount｜$beatCount, start: $beatStart, '
      'next: $nextBeat, progress: $progress, halves: $halfBeatLines)';
}

bool _listEquals(List<Duration> a, List<Duration> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 求值 [position] 的当前拍；无锚可数（位置早于首线或超出网格末拍）返回
/// null，屏幕不显示。
///
/// - 数拍锚按 [position] 逐拍现算：[_resolveBeatAnchor] 解析锚点链（录制锚
///   → 延迟锚 → 激活锚 → 最近分段线 → 首线），跨分段线的相邻两拍各用各自
///   位置的锚；就绪网格上锚恒归八拍点（[_alignBeatCountAnchorToGrid]，含
///   弱起），占位与异常网格锚原样；
/// - 前导 = 位置在锚点之前：由 [deriveBeatCount] 的前导分支给出（八拍号
///   0、拍号顺数），前导区内半拍线不进值；
/// - 占位网格照常求值；异常网格照常给出数值（静默由发声闸门承担，不在本
///   求值内）。
/// 解析 [position] 求值用的数拍锚（锚点链 [_resolveBeatAnchor] + 就绪网格
/// 归八拍点 [_alignBeatCountAnchorToGrid]）；求值与观测层同读这一条解析，
/// 锚链规则只落一处。无可数位置返回 null。
Duration? evaluateBeatCountAnchor({
  required BeatGrid grid,
  required BeatPhase phase,
  required Duration? recordingAnchor,
  required Duration? delayAnchor,
  required Duration? activeAnchor,
  required List<Duration> segmentLines,
  required Duration firstLine,
  required Duration position,
}) {
  var anchor = _resolveBeatAnchor(
    activeAnchor: activeAnchor,
    recordingAnchor: recordingAnchor,
    delayAnchor: delayAnchor,
    segmentLines: segmentLines,
    firstLine: firstLine,
    position: position,
    gridLastBeatTime: grid.lastBeatIndex == null
        ? null
        : grid.beatTime(grid.lastBeatIndex!),
  );
  if (anchor == null) return null;
  if (grid.nature == BeatGridNature.ready) {
    anchor = _alignBeatCountAnchorToGrid(phase: phase, anchor: anchor);
  }
  return anchor;
}

CurrentBeat? evaluateCurrentBeat({
  required BeatGrid grid,
  required BeatPhase phase,
  required Duration? recordingAnchor,
  required Duration? delayAnchor,
  required Duration? activeAnchor,
  required List<Duration> segmentLines,
  required Duration firstLine,
  required Duration position,
  List<Duration> halfBeatLines = const [],
  bool halfBeatEnabled = true,
}) {
  final anchor = evaluateBeatCountAnchor(
    grid: grid,
    phase: phase,
    recordingAnchor: recordingAnchor,
    delayAnchor: delayAnchor,
    activeAnchor: activeAnchor,
    segmentLines: segmentLines,
    firstLine: firstLine,
    position: position,
  );
  if (anchor == null) return null;
  final count = deriveBeatCount(
    grid: grid,
    anchor: anchor,
    position: position,
    phase: phase,
  );
  final isLeading = count is LeadingBeatCount;
  final (eightCount, beatCount) = switch (count) {
    PracticeBeatCount(:final eightCount, :final beatCount) => (
      eightCount,
      beatCount,
    ),
    LeadingBeatCount(:final beatCount) => (0, beatCount),
  };

  // 拍边界走网格 seam 的唯一求值（与动画层同一份
  // 守卫）：真实网格早于首拍定位 -1 钳到首拍（前导区游标停在拍首，拍内
  // 进度 0），有界网格末拍无下一拍。（首线早于
  // 首拍的首线段此前无人求值，接线发布值后成为常态路径。）
  final boundary = grid.beatBoundaryAt(position);
  final index = boundary.index;
  final beatStart = boundary.beatStart;
  final nextBeat = boundary.nextBeat;
  final beatLength = grid.beatsDuration(1, from: index);
  final progress = boundary.beforeFirst
      ? 0.0
      : (position.inMicroseconds - beatStart.inMicroseconds) /
            beatLength.inMicroseconds;

  // 半拍线：仅正式区、开关开；取严格落在本拍起点与下一拍起点之间的线——
  // 与整拍同毫秒（含下一拍起点）的线不进值，同一瞬间只保留整拍一声。
  var halves = const <Duration>[];
  if (!isLeading && halfBeatEnabled) {
    halves = [
      for (final line in halfBeatLines)
        if (line > beatStart && (nextBeat == null || line < nextBeat)) line,
    ]..sort();
  }

  return CurrentBeat(
    eightCount: eightCount,
    beatCount: beatCount,
    isEightBeatPoint: index >= 0 && phase.isEightBeatPoint(index),
    isStrongBeat: index >= 0 && phase.isStrongBeat(index),
    beatStart: beatStart,
    nextBeat: nextBeat,
    progress: progress,
    halfBeatLines: halves,
  );
}

/// 数拍数字派生结果：练习区两数或前导区两数（八拍号 0 + 拍号）。
sealed class BeatCountDisplay {
  const BeatCountDisplay();
}

/// 练习区：八拍号（青·大）+ 拍号（白·小），锚点 = 激活学习段段首。
class PracticeBeatCount extends BeatCountDisplay {
  const PracticeBeatCount({required this.eightCount, required this.beatCount});

  /// 第几个八拍（1 起，锚点所在八拍为 1）。
  final int eightCount;

  /// 八拍内第几拍（1–8）。
  final int beatCount;
}

/// 数拍八拍号四八拍循环显示（纯函数 seam）。
class EightCountCycleDisplay {
  const EightCountCycleDisplay({required this.number, this.group});

  /// 循环后的八拍号：(相对八拍 − 1) % 4 + 1（段内 1–4）。
  final int number;

  /// 组序 ⌈相对八拍 / 4⌉；第 1 组（相对八拍 ≤ 4）不显示 → null。
  final int? group;
}

/// 八拍号循环节（数四个八拍重新数，唯一出处）：显示号 = `(rel−1) % 本值 + 1`。
const int kEightCountCycle = 4;

/// 八拍号按「数四个八拍重新数」循环取号并派生组上标：
/// 显示 = `(rel−1)%kEightCountCycle+1`，rel > 4 时组 = ⌈rel/4⌉（第 2 组起显示）。
EightCountCycleDisplay eightCountCycleDisplay(int relativeEightCount) {
  return EightCountCycleDisplay(
    number: (relativeEightCount - 1) % kEightCountCycle + 1,
    group: relativeEightCount > 4 ? (relativeEightCount + 3) ~/ 4 : null,
  );
}

/// 前导区：第 0 个八拍顺数两数（八拍号固定 0，拍号顺数）。
class LeadingBeatCount extends BeatCountDisplay {
  const LeadingBeatCount({required this.beatCount});

  /// 八拍号恒为 0（第 0 个八拍）。
  int get eightCount => 0;

  /// 八拍内第几拍（1–8，按时间顺数；锚点前 1 拍 = 8）。
  final int beatCount;
}

/// 前导区第 [beatsBeforeAnchor] 拍（距锚点还有几拍，≥1）的「第 0 个八拍顺数」
/// 拍号：`8 + 1 − beatsBeforeAnchor`（八拍号固定 0、拍号顺数到 8），钳 1
/// ——锚点前超过 8 拍不外推 0 或负拍号。
///
/// **前导区拍号的唯一换算**：锚点之前的数拍位置
/// （[deriveBeatCount] 的前导区分支）走这里。
int _leadingBeatCount({required int beatsBeforeAnchor}) {
  final number = kBeatsPerEightCount + 1 - beatsBeforeAnchor;
  return number < 1 ? 1 : number;
}

/// 数拍数字锚点派生（纯函数 seam；相位必填）。
///
/// 拍序号经 [BeatGrid.beatIndexAt] 定位（锚点与位置同一换算源）。位置在
/// 锚点及之后（练习区）走**八拍点顺数**口径：
///
/// - 八拍号 = 段内八拍点个数 + 1——**段首锚定 1｜1**，其后每到一个八拍点
///   +1（[phase] = 网格 + 八拍锚点的单一相位源，**必填**：漏传是编译错误，
///   无锚点调用点显式构造无锚点相位值对象）；
/// - 拍号 = 自本号区间起点按拍序号顺数（号 1 的区间起点 = 段首，其后 =
///   该号对应的八拍点），恒在 1–8（`% 8` 回卷，段首不落八拍点或八拍点间距
///   > 8 拍时不外推）；
/// - 半八拍表现为「**下一个八拍号提前到来**」，而不是整段数拍持续漂移；
///   八拍号/拍号仍为整数，不引入 0.5 分度。
///
/// 位置在锚点之前（含真实网格早于首拍的 -1 定位）→ 第 0 个八拍顺数两数
/// （八拍号固定 0、拍号 = 9 + 拍差；锚点前 1 拍 = 8，顺数到段首变 1｜1；
/// 早于 8 拍钳到 1，不外推 0 或负拍号）——与锚点、相位无关，行为不变。
///
/// **口径**：段首落八拍点（分段线在就绪网格吸附后的常态、首线即八拍点）
/// 时，本口径与「段首起每 8 拍一号」逐位一致；段首**不落**八拍点（占位期
/// 插入/手工拖离的分段线、首线落在弱起区）时按八拍点顺数，以便喊到的八拍
/// 与音乐真实八拍一致——「段首起每 8 拍一号」在段首不落八拍点时相对音乐的
/// 固定 8 拍分组会持续漂移，正是本口径要避开的错位（无锚点基线 = 显式构造
/// 无锚点相位）。
BeatCountDisplay deriveBeatCount({
  required BeatGrid grid,
  required Duration anchor,
  required Duration position,
  required BeatPhase phase,
}) {
  final rawAnchor = grid.beatIndexAt(anchor);
  final positionIndex = grid.beatIndexAt(position);
  // 弱起双 −1：锚点与位置同落网格首拍之前（定位均为 -1）视为
  // 同在锚点——激活即显 1｜1，不误入前导区闪 0｜8。
  if (rawAnchor < 0 && positionIndex < 0) {
    return const PracticeBeatCount(eightCount: 1, beatCount: 1);
  }
  final anchorBeat = max(rawAnchor, 0);
  final delta = positionIndex - anchorBeat;
  if (delta < 0) {
    return LeadingBeatCount(
      beatCount: _leadingBeatCount(beatsBeforeAnchor: -delta),
    );
  }
  final source = phase;
  // 段内八拍点（拍序号严格晚于段首者，索引域区间查询）：自段首顺数，半八拍
  // 时下一个号提前到来；区间起点取末位八拍点（号 1 无八拍点时退回段首 =
  // 段首 1｜1）。拍号在超长区间（八拍点间距 > 8 拍的稀疏网格）按 % 8 回卷。
  final pointIndices = source.eightBeatPointIndicesInRange(
    anchorBeat + 1,
    positionIndex,
  );
  final intervalStart = pointIndices.isEmpty ? anchorBeat : pointIndices.last;
  return PracticeBeatCount(
    eightCount: pointIndices.length + 1,
    beatCount: (positionIndex - intervalStart) % kBeatsPerEightCount + 1,
  );
}

/// 数拍计数锚点对齐网格八拍大线（纯函数 seam）。
///
/// 数拍数字自锚点起按拍差计数（[deriveBeatCount]），而矩形动画当前格与轨道
/// 八拍大线按网格**八拍点相位**推进；锚点不落在八拍大线上时（**弱起**首线 =
/// 网格首拍早于首个强拍、历史错位分段线等）两套相位不同源，数字会与大线差
/// 一拍。本函数把锚点归到八拍大线上，四条口径：
///
/// - 锚点本身即大线 → 原样返回（恒等，既有大线锚行为不变）；
/// - **弱起**首线早于首个强拍（锚点落在相位原点之前）→ 首个强拍所在的大线
///   （相位原点自身即八拍点）；
/// - 其余非大线锚点 → 其后最近的大线；
/// - 网格尾部无后随大线 → 回退前一条大线。
///
/// 大线取自**相位源**（[BeatPhase] 的八拍点，单一相位门）：八拍点
/// 按强拍序数判定、不按拍序号算术，故与数拍八拍号（[deriveBeatCount] 的
/// 八拍点顺数）、矩形动画当前格、轨道大线同源同号——非均匀强拍网格与「八拍
/// 锚点」重定相下亦然。
///
/// 锚早于网格首拍（定位 -1）在就绪网格上**不原样放行**：自首拍起找后随
/// 八拍点，弱起首线归到首个强拍（相位原点，其自身即八拍点）；网格无任何
/// 八拍点可对齐时才原样返回，不新造相位。占位/异常的**无界**均匀网格（无
/// 真实八拍点）锚原样返回；**前导**区计数归 [deriveBeatCount]，不经本函数
/// （延迟播放与录制准备的兜底取值同此，均不受影响）。
Duration _alignBeatCountAnchorToGrid({
  required BeatPhase phase,
  required Duration anchor,
}) {
  final grid = phase.grid;
  final rawIndex = grid.beatIndexAt(anchor);
  final lastIndex = grid.lastBeatIndex;
  if (lastIndex == null) return anchor;
  if (rawIndex >= 0 && phase.isEightBeatPoint(rawIndex)) return anchor;
  // 锚早于网格首拍：搜索窗自首拍起，后随最近八拍点即首个强拍所在点。
  final searchFrom = rawIndex < 0 ? 0 : rawIndex;
  final following = phase.eightBeatPointIndicesInRange(searchFrom, lastIndex);
  if (following.isNotEmpty) return grid.beatTime(following.first);
  if (rawIndex < 0) return anchor;
  final previous = phase.eightBeatPointIndexAtOrBefore(rawIndex);
  return previous == null ? anchor : grid.beatTime(previous);
}

/// 锚点链解析（seam）：
///
/// 0. [recordingAnchor]（录制会话的起录点）非空 → 恒用其——
///    **无激活段录制时锚 = 起录点**（不退化成「最近分段线 ≤ position →
///    首线」）；有激活段时起录点即段首，与第 1 条同值；
/// 1. [delayAnchor]（延迟锚 = 延迟起点）非空 →
///    恒用其——预备区（位置在起点之前）走前导区 `0|x` 口径、越点后起点即
///    第 1 个八拍，`1|1` 起顺数，全部由既有编号派生；会话值，打断即撤；
/// 2. 激活锚（临时衔接段段首，否则激活学习段合并起点段首）非空 → 恒用
///    其段首；
/// 3. 否则 → 位置之前最近的分段线（≤ 语义：位置恰在线上 = 该线为新段
///    段首，从 1｜1 重数）；
/// 4. 无分段线 → 首线。
///
/// 位置早于首线或超出网格末拍（无拍可数）→ 返回 null（不显示），即使
/// 有激活锚/录制锚。临时段激活期间的锚定与时钟对齐语义归上层，本 seam 只按
/// [activeAnchor] 原样取段首。
///
/// 对齐网格八拍大线（纯函数 [_alignBeatCountAnchorToGrid]）由
/// 调用侧落定——本 seam 只解析**锚以哪一处为准**。
Duration? _resolveBeatAnchor({
  required Duration? activeAnchor,
  Duration? recordingAnchor,
  Duration? delayAnchor,
  required Iterable<Duration> segmentLines,
  required Duration firstLine,
  required Duration position,
  required Duration? gridLastBeatTime,
}) {
  if (position < firstLine) return null;
  if (gridLastBeatTime != null && position > gridLastBeatTime) return null;
  if (recordingAnchor != null) return recordingAnchor;
  if (delayAnchor != null) return delayAnchor;
  if (activeAnchor != null) return activeAnchor;
  Duration? nearest;
  for (final line in segmentLines) {
    if (line <= position && (nearest == null || line > nearest)) {
      nearest = line;
    }
  }
  return nearest ?? firstLine;
}
