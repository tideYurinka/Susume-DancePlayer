/// 八拍相位纯派生：
/// 分段线吸附、轨道刻度分级、节拍动画八拍首三方共用的**单一相位事实源**。
///
/// 序数法为唯一语义——自**相位原点**起 downbeat 全局序数（1 起）为奇数者
/// = 八拍点（偶数 = 四拍中线）。相位原点 = 相位派生的起点 downbeat 拍序
/// 号（入参必须是 downbeat 序号），默认 = 网格首个强拍
///（[BeatGrid.firstDownbeatIndex]，现状自动种子）。「手动设八拍锚点」经
/// [BeatPhase] 的锚点集合入参给出：锚点即其所属段的相位原点，锚点之前保持
/// 自动相位（由 [BeatPhase] 的分段求值逐段取最近锚点为该段原点承担）。
///
/// 无界（占位/异常均匀）网格按 `beatsPerBar × 2` 拍的周期算术求值，周期
/// 假设：downbeat 以 `beatsPerBar` 拍为周期自原点规律重现（与
/// `beat_track_tiers.dart` 的刻度周期假设一致）；长片不求值全量拍点。
///
/// 派生面（[BeatPhase] 的五个读法）：单点/索引判定（[BeatPhase.isEightBeatPoint]、
/// [BeatPhase.isStrongBeat]——八拍首与强拍格）、窗口八拍点序列
///（[BeatPhase.pointsInWindow] 时刻域 / [BeatPhase.eightBeatPointIndicesInRange]
/// 索引域，轨道分级与八拍数标注、含窗口切断）、最近八拍点解析
///（[BeatPhase.nearest]，分段线落点吸附与临时衔接段起点取整）、索引域回溯
///（[BeatPhase.eightBeatPointIndexAtOrBefore]，节拍动画八拍窗口首拍）。
/// 等距并列取时间靠后者（与 `snap.dart` 一致）。
///
/// **八拍锚点**：相位值对象 [BeatPhase] 把「网格 +
/// 锚点集合」的**分段奇偶重定相**收成单一派生事实源——锚点自身即八拍点、
/// 其后每隔一个强拍一个八拍点、管到下一个锚点之前；锚点之前保持自动相位
/// （原点 = 网格首个强拍），锚只向后延续。**无锚点时即「原点 = 网格首个
/// 强拍」的自动相位**（回归基线由 `test/core/beat_phase_anchors_test.dart`
/// 与 `test/core/eight_beat_phase_test.dart` 钉死）。
///
/// **消费方（显式清单见 `beat_track_state.dart` 的 `beatPhaseProvider`
/// 文档）**：轨道三级刻度分级与轨上八拍数小数字（[beatTrackTicks] /
/// `beatEightCountLabels` 的 `phase` 入参）、分段线落点吸附与段内八拍数
///（模块/纯函数相位入参）、数拍八拍号（`deriveBeatCount` 的 `phase` 入参）
/// 与节拍动画的八拍首 / 游标格（`deriveBeatPhase` 与
/// `MetronomeBeatAnimation` 的 `phase` 入参）、自动分段切割线
///（`deriveAutoSegmentCuts` 的 `phase` 入参）与段内八拍数的 0.5 分度加权
///（同上前者纯函数）。
library;

import 'beat_grid.dart';

/// 八拍相位周期：每 `beatsPerBar × 2` 拍一个八拍点（序数奇偶交替），与
/// 八拍长度常量（唯一出处 `beat_grid.dart`，4/4 固定先验下同值）同源
/// ——拍号体系口径改 [kBeatsPerBar] 一处即可。消费方
/// （相位派生、八拍区间权重、自动分段配额）一律读本原语或该常量，不得
/// 各自重算 `beatsPerBar × 2`。
int eightBeatStride(BeatGrid grid) => grid.beatsPerBar * 2;

/// 相邻八拍点区间（拍序号差 [beatGap]）的八拍权重（「段内八拍数」）：
/// 整八拍区间（相隔一个 stride = `beatsPerBar × 2` 拍）= 1、
/// 半八拍区间（相隔 `beatsPerBar` 拍、即八拍点之间只隔一个小节）= 0.5。
///
/// **量化到最近的 0.5**（`round(stride 倍数的两倍) ÷ 2`），故返回值**恒为
/// 0.5 的整数倍**（不出现 1.125 式伪小数，由构造保证、非仅靠注释）；
/// `beatsPerBar` 固定先验 4 时与
/// `beatGap ÷ stride` 逐位一致。
///
/// **自动分段**与**段内八拍数**共用本区间口径（[eightBeatIntervals] 提供
/// 区间序列）：前者取权重**向下取整**作配额（半八拍 = 0、不占那 4 个配额），
/// 后者按权重求和。
double eightBeatIntervalWeight(int beatGap, {required BeatGrid grid}) {
  final halves = (beatGap * 2 / eightBeatStride(grid)).round();
  return halves / 2;
}

/// `[start, end]` 闭窗内**相邻八拍点区间**序列（升序）：每个区间 = 左右八拍
/// 点时刻 + 二者拍序号差（[eightBeatIntervalWeight] 的入参）。**本文件唯一
/// 八拍点逐对求差实现**——自动分段（按配额下刀）与段内八拍数（按权重求和）
/// 两个消费方共用，避免各自走 "取点 + beatIndexAt 求差" 的形状。
List<({Duration start, Duration end, int beatGap})> eightBeatIntervals(
  BeatPhase phase,
  Duration start,
  Duration end,
) {
  final grid = phase.grid;
  final points = phase.pointsInWindow(start, end);
  return [
    for (var i = 1; i < points.length; i++)
      (
        start: points[i - 1],
        end: points[i],
        beatGap: grid.beatIndexAt(points[i]) - grid.beatIndexAt(points[i - 1]),
      ),
  ];
}

/// 键盘微调（方向键）的相邻八拍点：[current] 之后（[direction] > 0）或
/// 之前（< 0）的最近八拍点，无则 null。求值范围 = [current] 邻域
/// （[grid] 八拍标称 × 2），与 [BeatPhase.pointsInWindow] 同一相位源。
Duration? adjacentEightBeatPoint(
  BeatPhase phase,
  BeatGrid grid,
  Duration current,
  int direction,
) {
  if (direction == 0) return null;
  final reach = grid.eightBeatNominal * 2;
  final points = direction > 0
      ? phase.pointsInWindow(current, current + reach)
      : phase.pointsInWindow(current - reach, current);
  return points.fold<Duration?>(null, (adjacent, point) {
    if (direction > 0) {
      if (point <= current || (adjacent != null && point >= adjacent)) {
        return adjacent;
      }
      return point;
    }
    if (point >= current || (adjacent != null && point <= adjacent)) {
      return adjacent;
    }
    return point;
  });
}

/// 键盘微调（方向键）的相邻拍点：沿 [grid] 挪一拍（[direction] 正为后继、
/// 负为前驱）；越出可及拍序（首拍之前 / 末拍之后）返回 null。
Duration? adjacentBeatPoint(BeatGrid grid, Duration current, int direction) {
  final index = grid.beatIndexAt(current) + direction;
  final last = grid.lastBeatIndex;
  if (index < 0 || (last != null && index > last)) return null;
  return grid.beatTime(index);
}

/// 自 [origin] 起第 [beatIndex] 拍的 downbeat 全局序数（1 起）；拍点在
/// 原点之前或非 downbeat 返回 null。有界真实网格逐拍计数（拍点间距可非
/// 均匀）；无界网格按周期假设算术求值。
int? _downbeatOrdinal(BeatGrid grid, int beatIndex, int origin) {
  if (beatIndex < origin || !grid.isDownbeat(beatIndex)) return null;
  if (grid.lastBeatIndex == null) {
    return (beatIndex - origin) ~/ grid.beatsPerBar + 1;
  }
  var ordinal = 0;
  for (var i = origin; i <= beatIndex; i++) {
    if (grid.isDownbeat(i)) ordinal += 1;
  }
  return ordinal;
}

/// 有界网格 `[lo, hi]` 拍序号闭区间内的八拍点拍序号（升序）：逐段求值——
/// 段内序数自段起点（相位原点）起计、序数奇数者即八拍点；段尾止于下一
/// 段起点之前。**本文件唯一序数扫描实现**。
List<int> _segmentPointIndices(
  BeatGrid grid,
  List<int> segmentStarts,
  int lo,
  int hi,
) {
  final last = grid.lastBeatIndex;
  final points = <int>[];
  for (var s = 0; s < segmentStarts.length; s++) {
    final segmentStart = segmentStarts[s];
    final nextStart = s + 1 < segmentStarts.length
        ? segmentStarts[s + 1]
        : null;
    if (last != null) {
      if (segmentStart > last) break;
      final segmentEnd = nextStart ?? (last + 1);
      final upper = segmentEnd - 1 > hi ? hi : segmentEnd - 1;
      if (upper < segmentStart) continue;
      var ordinal = 0;
      // 序数必须自段起点计数（窗口切断不重置相位）。
      for (var i = segmentStart; i <= upper; i++) {
        if (!grid.isDownbeat(i)) continue;
        ordinal += 1;
        if (ordinal.isOdd && i >= lo) points.add(i);
      }
      continue;
    }
    // 无界网格：段内八拍点 = 段起点起每 stride 拍一个。
    final stride = eightBeatStride(grid);
    if (nextStart != null && nextStart <= segmentStart) continue;
    var first = segmentStart;
    if (first < lo) {
      first =
          segmentStart + ((lo - segmentStart + stride - 1) ~/ stride) * stride;
    }
    for (var i = first; i <= hi; i += stride) {
      if (nextStart != null && i >= nextStart) break;
      points.add(i);
    }
  }
  return points;
}

/// 候选集最近解析：等距并列取时间靠后者（本文件唯一比较形状；
/// `annotation/snap.dart` 的同名收口在标注层，core 不反向依赖它）。
Duration? _nearestOf(Iterable<Duration> candidates, Duration position) {
  Duration? best;
  var bestDistance = -1;
  for (final candidate in candidates) {
    final distance = (candidate.inMilliseconds - position.inMilliseconds).abs();
    if (best == null || distance <= bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best;
}

/// 八拍相位值对象：由「网格 + 锚点集合」求值
/// 的单一派生事实源，暴露三类派生面——单点判定、窗口序列、最近点解析。
///
/// **锚点语义 = 分段奇偶重定相**：对任一拍取「不晚于它的最后一个锚点」为
/// 该段相位原点（无则网格首个强拍），自原点起按强拍序数奇偶判定；锚点自身
/// 即八拍点（序数 1），其后每隔一个强拍一个八拍点，管到下一个锚点之前。
/// 锚点**只向后延续**，锚点之前的相位逐位不变。
///
/// **锚点集合**（构造入参）= 拍序号数组，语义上等价于一组"分段相位原点"：
/// 构造时按升序去重、丢弃非强拍与越界序号（文件里的陈旧锚点不报错，见
/// 「已知降级」），故 [anchors] 是规范化后的现值。
///
/// 有界真实网格逐拍计数（拍点间距可非均匀）、无界网格按周期算术（沿用两条
/// 路径的既有边界语义）；无锚点、无合法锚点时即「原点 = 网格首个强拍」的
/// 自动相位。
class BeatPhase {
  BeatPhase({required this.grid, List<int> anchors = const []})
    : anchors = _normalizeAnchors(grid, anchors);

  /// 相位求值网格（含节拍对齐平移量的派生网格）。
  final BeatGrid grid;

  /// 规范化后的锚点集合（升序、去重、全为强拍且落在网格内）。
  final List<int> anchors;

  /// 段起点序列（首段 = 网格首个强拍，其后每个锚点一段）。
  List<int> get _segmentStarts => [
    grid.firstDownbeatIndex,
    for (final anchor in anchors)
      if (anchor > grid.firstDownbeatIndex) anchor,
  ];

  /// 第 [beatIndex] 拍是否八拍点（取该拍所属段的相位原点判定）。
  bool isEightBeatPoint(int beatIndex) {
    final ordinal = _downbeatOrdinal(grid, beatIndex, _originOf(beatIndex));
    return ordinal != null && ordinal.isOdd;
  }

  /// 第 [beatIndex] 拍是否**强拍**（八拍点或四拍中线 = downbeat）——
  /// 轨道三级刻度的「大线/中线」与节拍动画的「强拍格/摆锤强拍」共用同一条
  /// 判定；索引算术（八拍首按序数 + 小节首按 `rel % beatsPerBar`）在非均匀
  /// downbeat 网格上会漏判，不采用。
  bool isStrongBeat(int beatIndex) =>
      isEightBeatPoint(beatIndex) || grid.isDownbeat(beatIndex);

  /// `[lo, hi]` 拍序号闭区间内的八拍点拍序号（升序；索引域窗口序列，
  /// 数拍八拍号顺数用）；实现见 [_segmentPointIndices]（与时刻域窗口
  /// [pointsInWindow] 同一序数扫描，窗口切断不重置相位）。
  List<int> eightBeatPointIndicesInRange(int lo, int hi) =>
      _pointIndicesInRange(lo, hi);

  /// **不晚于 [beatIndex] 的最近八拍点拍序号**（节拍动画的八拍
  /// 窗口首拍——游标格与强拍格由此共用同一相位源）；该拍所属段内首个八拍
  /// 点之前（弱起区、锚点段原点之前）或无强拍网格返回 null，调用侧按既有
  /// 口径回退。
  ///
  /// 与 [isEightBeatPoint] 同源：返回的序号恒满足 `isEightBeatPoint(序号)`
  /// （复用 [eightBeatPointIndicesInRange] 的段内序数扫描）。
  int? eightBeatPointIndexAtOrBefore(int beatIndex) {
    final origin = _originOf(beatIndex);
    if (beatIndex < origin) return null;
    // 段起点作下界：本段之内的点照常返回，更早段的点被下界滤掉（同段内
    // 序数自段起点起算，故下界不改变奇偶判定）。
    final points = _pointIndicesInRange(origin, beatIndex);
    return points.isEmpty ? null : points.last;
  }

  /// 该拍所属段的相位原点 = 不晚于它的最后一个锚点（无 = 网格首个强拍）。
  int _originOf(int beatIndex) {
    var origin = grid.firstDownbeatIndex;
    for (final anchor in anchors) {
      if (anchor > beatIndex) break;
      origin = anchor;
    }
    return origin;
  }

  /// `[start, end]` 闭窗内的八拍点时刻序列（升序，含窗口切断）。
  List<Duration> pointsInWindow(Duration start, Duration end) {
    final last = grid.lastBeatIndex;
    final indices = last != null
        // 有界：覆盖区全量点序号（逐段逐拍计数），再按窗口过滤。
        ? _pointIndicesInRange(0, last)
        // 无界：以定位拍邻域求点序号（长片不求值全量拍点）。
        : _pointIndicesInRange(
            grid.beatIndexAt(start) - eightBeatStride(grid),
            grid.beatIndexAt(end) + eightBeatStride(grid),
          );
    return [
      for (final index in indices)
        if (_inWindow(grid.beatTime(index), start, end)) grid.beatTime(index),
    ];
  }

  /// 解析 [position] 就近的八拍点；网格无八拍点返回 null。等距并列取时间
  /// 靠后者（与 `snap.dart` 同口径）。
  Duration? nearest(Duration position) {
    final last = grid.lastBeatIndex;
    final stride = eightBeatStride(grid);
    final indices = last != null
        ? _pointIndicesInRange(0, last)
        : _pointIndicesInRange(
            grid.beatIndexAt(position) - stride,
            grid.beatIndexAt(position) + stride,
          );
    return _nearestOf([
      for (final index in indices) grid.beatTime(index),
    ], position);
  }

  /// `[lo, hi]` 拍序号闭区间内的八拍点拍序号（升序；逐段求值，实现见
  /// [_segmentPointIndices]）。
  List<int> _pointIndicesInRange(int lo, int hi) =>
      _segmentPointIndices(grid, _segmentStarts, lo, hi);
}

bool _inWindow(Duration time, Duration start, Duration end) =>
    time >= start && time <= end;

/// 锚点规范化：丢弃非强拍与越界序号，升序去重（语义见 [BeatPhase.anchors]）。
List<int> _normalizeAnchors(BeatGrid grid, List<int> raw) {
  final last = grid.lastBeatIndex;
  final valid = <int>[
    for (final anchor in raw)
      if (anchor >= 0 && (last == null || anchor <= last))
        if (grid.isDownbeat(anchor)) anchor,
  ]..sort();
  final normalized = <int>[];
  for (final anchor in valid) {
    if (normalized.isEmpty || normalized.last != anchor) normalized.add(anchor);
  }
  return List.unmodifiable(normalized);
}
