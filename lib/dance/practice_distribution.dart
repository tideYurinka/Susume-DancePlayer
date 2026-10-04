/// 练习分布曲线派生：零 Flutter 纯件，页面只渲染。
///
/// 曲线的采样点是**四拍桶**：横轴是绝对歌曲时间，每个桶的
/// 值 = (时长 / 次数) × (累计 / 近 7 天 / 今日)。桶的绝对时间区间左闭右开，
/// 由网格的四拍线几何给出；末桶右界按末段线距外推（与记录侧桶格同口径）。
/// 横坐标取该桶时间区间的中点。
///
/// 范围按桶的**本地日**筛选（累计 = 全部；近 7 天 = 今天起的 7 个本地日，
/// 含今天；今日 = 仅今天），未练过的桶如实为 0。时钟由调用方注入。
library;

import 'dart:math' as math;

import '../annotation/learning_segment_attributes.dart';
import '../annotation/learning_segments.dart';
import '../core/beat_grid.dart';
import '../core/document_beat_grid.dart';
import '../core/local_day.dart';
import 'segment_practice_aggregation.dart';

/// 曲线纵轴：练习时长 / 练习次数。
enum PracticeDistributionMetric { duration, count }

/// 曲线范围（默认累计，可接近 7 天与今日）。
enum PracticeDistributionRange { cumulative, last7Days, today }

/// 一个采样点：一个四拍桶的绝对时间区间（左闭右开）与该桶的两个量。
class PracticeDistributionBucket {
  const PracticeDistributionBucket({
    required this.start,
    required this.end,
    required this.duration,
    required this.count,
  });

  /// 桶的绝对时间区间：左闭右开，从视频开头起算。
  final Duration start;
  final Duration end;

  /// 该桶在当前范围下的练习时长。
  final Duration duration;

  /// 该桶在当前范围下的练习次数。
  final int count;

  /// 横坐标取值口径：该桶时间区间的中点。
  Duration get midpoint => start + (end - start) ~/ 2;

  /// 纵轴取值（时长取微秒——与次数同量纲只用于曲线归一）。
  double valueFor(PracticeDistributionMetric metric) =>
      metric == PracticeDistributionMetric.duration
      ? duration.inMicroseconds.toDouble()
      : count.toDouble();

  @override
  bool operator ==(Object other) =>
      other is PracticeDistributionBucket &&
      other.start == start &&
      other.end == end &&
      other.duration == duration &&
      other.count == count;

  @override
  int get hashCode => Object.hash(start, end, duration, count);

  @override
  String toString() =>
      'PracticeDistributionBucket(${start.inMilliseconds}–'
      '${end.inMilliseconds}ms, $duration/$count)';
}

/// 曲线数据（范围筛选一次派生）。
class PracticeDistribution {
  const PracticeDistribution({
    required this.buckets,
    required this.beatGridNotReady,
  });

  /// 四拍桶采样点（自左向右按时间升序）。
  final List<PracticeDistributionBucket> buckets;

  /// 该时段无节拍数据（网格未就绪）：数值为 0 只是缺数据，不是没练。
  final bool beatGridNotReady;
}

/// 曲线与范围重算的输入（舞库快照携带；页面切换范围时不再读 IO）。
///
/// 相等性按内容判定：分段线几何逐段比较、桶读面逐值比较、网格按本派生实际
/// 消费的三项（小节拍数 / 首个强拍 / 末拍）比较。
class PracticeDistributionInput {
  const PracticeDistributionInput({
    this.segments = const [],
    this.grid,
    this.buckets = const {},
  });

  /// 当前分段线派生的学习段几何。
  final List<LearningSegment> segments;

  /// 当前就绪网格（null = 未就绪）。
  final BeatGrid? grid;

  /// 桶读面：本地日 → 桶序号 → 值。
  final Map<String, Map<int, SegmentBucketValue>> buckets;

  @override
  bool operator ==(Object other) =>
      other is PracticeDistributionInput &&
      _segmentsEqual(other.segments, segments) &&
      _gridKey(other.grid) == _gridKey(grid) &&
      _bucketsEqual(other.buckets, buckets);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(segments),
    _gridKey(grid),
    Object.hashAllUnordered([
      for (final day in buckets.entries)
        Object.hash(
          day.key,
          Object.hashAllUnordered([
            for (final bucket in day.value.entries)
              Object.hash(bucket.key, bucket.value),
          ]),
        ),
    ]),
  );
}

/// 网格的派生读面键（拍点时刻/强拍结构变化由分段线几何另行体现，不逐拍
/// 比较）。逐段档并入失效键：段内档不改变派生拍数，「末拍序号」一维覆盖
/// 不到它，故键含逐段档
/// 集合的规范形（按段序升序的 `段序:档值` 串）——改完段内档不会读到旧网格。
({
  int beatsPerBar,
  int firstDownbeatIndex,
  int? lastBeatIndex,
  String segmentDensities,
})?
_gridKey(BeatGrid? grid) {
  if (grid == null) return null;
  final densities = grid is DocumentBeatGrid
      ? grid.segmentDensities
      : const <int, double>{};
  final canonical = [
    for (final order in densities.keys.toList()..sort())
      '$order:${densities[order]}',
  ].join(',');
  return (
    beatsPerBar: grid.beatsPerBar,
    firstDownbeatIndex: grid.firstDownbeatIndex,
    lastBeatIndex: grid.lastBeatIndex,
    segmentDensities: canonical,
  );
}

bool _segmentsEqual(List<LearningSegment> a, List<LearningSegment> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _bucketsEqual(
  Map<String, Map<int, SegmentBucketValue>> a,
  Map<String, Map<int, SegmentBucketValue>> b,
) {
  if (a.length != b.length) return false;
  for (final day in a.entries) {
    final otherDay = b[day.key];
    if (otherDay == null || otherDay.length != day.value.length) return false;
    for (final bucket in day.value.entries) {
      if (otherDay[bucket.key] != bucket.value) return false;
    }
  }
  return true;
}

/// 按 [range] 筛选桶读面：累计原样；近 7 天取今天起向前 7 个本地日（含今天）；
/// 今日只取当天。
Map<String, Map<int, SegmentBucketValue>> filterPracticeBuckets(
  Map<String, Map<int, SegmentBucketValue>> buckets, {
  required PracticeDistributionRange range,
  required DateTime now,
}) {
  if (range == PracticeDistributionRange.cumulative) return buckets;
  final today = localDay(now);
  final days = <String>{
    if (range == PracticeDistributionRange.today)
      localDayKey(today)
    else
      for (var offset = 0; offset < 7; offset++)
        localDayKey(DateTime(today.year, today.month, today.day - offset)),
  };
  return {
    for (final entry in buckets.entries)
      if (days.contains(entry.key)) entry.key: entry.value,
  };
}

/// 组装曲线数据：范围筛选一次。
///
/// 网格未就绪（null 或 [BeatGridReads.hasRealBeats] 为假）时不产桶、
/// [beatGridNotReady] 为真。
PracticeDistribution buildPracticeDistribution({
  required PracticeDistributionInput source,
  required PracticeDistributionRange range,
  required DateTime now,
}) => _distributionOf(
  source,
  filterPracticeBuckets(source.buckets, range: range, now: now),
);

/// 分布图的一次装配：时钟取一次，范围筛选一次，曲线与逐段练习值同批返回
/// ——「两处永远说同一个数」由这一次筛选保证，不靠调用方自觉。
({PracticeDistribution distribution, List<SegmentPractice> segmentPractices})
buildPracticeDistributionView({
  required PracticeDistributionInput source,
  required PracticeDistributionRange range,
  required DateTime now,
}) {
  final filtered = filterPracticeBuckets(
    source.buckets,
    range: range,
    now: now,
  );
  return (
    distribution: _distributionOf(source, filtered),
    segmentPractices: aggregateSegmentPractice(
      segments: source.segments,
      grid: source.grid,
      buckets: filtered,
    ),
  );
}

PracticeDistribution _distributionOf(
  PracticeDistributionInput source,
  Map<String, Map<int, SegmentBucketValue>> filtered,
) {
  final ready = source.grid != null && source.grid!.hasRealBeats;
  final buckets = ready
      ? _bucketPoints(source.grid!, filtered)
      : const <PracticeDistributionBucket>[];
  return PracticeDistribution(
    buckets: List.unmodifiable(buckets),
    beatGridNotReady: !ready,
  );
}

/// 四拍桶采样点：桶格 = 网格自首个强拍起每 [BeatGrid.beatsPerBar] 拍一根
/// 四拍线的区间序列（左闭右开）；末桶右界按末段线距外推。缺席桶位如实
/// 为 0（次数直取桶值，不做组内最小）。
List<PracticeDistributionBucket> _bucketPoints(
  BeatGrid grid,
  Map<String, Map<int, SegmentBucketValue>> buckets,
) {
  final totals = sumSegmentBuckets(buckets);
  final boundaries = <Duration>[];
  final last = grid.lastBeatIndex;
  if (last == null) return const [];
  for (var bucket = 0; bucket <= last; bucket++) {
    final lineBeat = grid.firstDownbeatIndex + bucket * grid.beatsPerBar;
    if (lineBeat > last) break;
    boundaries.add(grid.beatTime(lineBeat));
  }
  if (boundaries.isEmpty) return const [];

  // 末桶右界：按末段线距外推；只有一根线时退为一个桶宽。
  final step = boundaries.length >= 2
      ? boundaries.last - boundaries[boundaries.length - 2]
      : grid.beatsDuration(grid.beatsPerBar, from: grid.firstDownbeatIndex);

  return [
    for (var i = 0; i < boundaries.length; i++)
      PracticeDistributionBucket(
        start: boundaries[i],
        end: i + 1 < boundaries.length
            ? boundaries[i + 1]
            : boundaries.last + step,
        duration: Duration(
          microseconds: totals[i] == null
              ? 0
              : (totals[i]!.wallSeconds * Duration.microsecondsPerSecond)
                    .round(),
        ),
        count: totals[i]?.sweeps ?? 0,
      ),
  ];
}

/// 横轴按真实时间几何摆位：把时刻序列线性映射到绘图区 x（[pad] 内缩）。
/// 单点居中；区间为零（只有一个不同时刻）时同样居中。
List<double> timeLerpX(
  List<Duration> times, {
  required double width,
  required double pad,
}) {
  if (times.isEmpty) return const [];
  final first = times.first;
  final last = times.last;
  final span = last - first;
  final usable = width - pad * 2;
  return [
    for (final time in times)
      span <= Duration.zero
          ? pad + usable / 2
          : pad + (time - first).inMicroseconds / span.inMicroseconds * usable,
  ];
}

/// 时间刻度取样：最多 4 档，取首 / 约 1/3 / 约 2/3 /
/// 末的下标，去重升序。
List<int> timeTickIndices(int count) {
  if (count <= 0) return const [];
  final last = count - 1;
  final ticks = <int>[0];
  for (final index in [(last / 3).round(), (last * 2 / 3).round(), last]) {
    if (index > ticks.last) ticks.add(index);
  }
  return ticks;
}

/// 熟练度色带铺位：一段在绘图区的像素区间与其两缘的过渡带宽。
///
/// 颜色不在此取——本模块零 Flutter，绘制侧按 [mastery] 经
/// `learningMasteryColor` 取色。
class MasteryBand {
  const MasteryBand({
    required this.left,
    required this.right,
    required this.mastery,
    this.leadTransition = 0,
    this.trailTransition = 0,
  });

  /// 段的像素左右界（已钳到绘图区；极窄段不出现负宽）。
  final double left;
  final double right;

  /// 该段熟练度档位（五档取色入口的唯一事实）。
  final LearningMastery mastery;

  /// 与左 / 右邻段共界时的过渡带全宽（过渡带以段界为中心、两半各归各段）；
  /// 0 = 该缘无邻段（首段左缘、末段右缘、段间空隙）。
  final double leadTransition;
  final double trailTransition;

  double get width => right - left;

  @override
  bool operator ==(Object other) =>
      other is MasteryBand &&
      other.left == left &&
      other.right == right &&
      other.mastery == mastery &&
      other.leadTransition == leadTransition &&
      other.trailTransition == trailTransition;

  @override
  int get hashCode =>
      Object.hash(left, right, mastery, leadTransition, trailTransition);

  @override
  String toString() =>
      'MasteryBand($left–$right, ${mastery.name}, '
      'tw: $leadTransition/$trailTransition)';
}

/// 段界过渡带宽度：`min(12dp, 邻段较窄段宽 × 0.3)`——取两侧较窄者，
/// 窄段之间的过渡互不吃掉。
double bandTransitionWidth(double leftWidth, double rightWidth) =>
    math.min(12, math.min(leftWidth, rightWidth) * 0.3);

/// 时间 → 所属学习段：给定时刻落在哪一段。段区间左闭右开——
/// 恰在段边界上的时刻归后一段；首段之前、末段之后、段与段之间的空隙都
/// 无段可归，返回 null（点按即清除选中）。
int? segmentIndexAtTime(List<LearningSegment> segments, Duration time) {
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    if (time >= segment.start && time < segment.end) return i;
  }
  return null;
}

/// 像素 → 时刻（手势层的逆映射）：与 [timeLerpX] 同一份仿射映射的
/// 反函数；x 越出绘图区时钳到域端（不返回界外时刻）。
Duration timeAtPixel(
  double x, {
  required Duration domainStart,
  required Duration domainEnd,
  required double width,
  required double pad,
}) {
  final span = domainEnd - domainStart;
  final usable = math.max(width - pad * 2, 0.0);
  if (span <= Duration.zero || usable <= 0) return domainStart;
  final fraction = ((x - pad) / usable).clamp(0.0, 1.0);
  return domainStart + span * fraction;
}

/// 段的横轴像素区间：选中边框、气泡锚点、色带三处共用一份几何。
/// 时间域 `[domainStart, domainEnd]` 线性映射到 `[pad, width - pad]`（与
/// [timeLerpX] 同式），段界越出时间域时钳到绘图区端点，极窄段不出现负宽。
({double left, double right}) segmentPixelRange(
  LearningSegment segment, {
  required Duration domainStart,
  required Duration domainEnd,
  required double width,
  required double pad,
}) {
  final plotLeft = pad;
  final plotRight = math.max(pad, width - pad);
  Duration clampToDomain(Duration time) {
    if (time < domainStart) return domainStart;
    if (time > domainEnd) return domainEnd;
    return time;
  }

  final start = clampToDomain(segment.start);
  final end = clampToDomain(segment.end);
  final mapped = timeLerpX(
    [domainStart, start, end, domainEnd],
    width: width,
    pad: pad,
  );
  return (
    left: mapped[1].clamp(plotLeft, plotRight),
    right: mapped[2].clamp(plotLeft, plotRight),
  );
}

/// 熟练度色带铺位纯件：按段的真实时间铺位算各段像素区间，相邻共界段之间
/// 定出过渡带宽。段的像素区间与时间横轴同一份几何（[domainStart]–[domainEnd]
/// 线性映射到 `[pad, width - pad]`，与 [timeLerpX] 同式），段界越出时间域时
/// 钳到绘图区端点。
List<MasteryBand> masteryBands({
  required List<LearningSegment> segments,
  required Map<int, LearningMastery> masteries,
  required Duration domainStart,
  required Duration domainEnd,
  required double width,
  required double pad,
}) {
  if (segments.isEmpty) return const [];
  final ranges = [
    for (final segment in segments)
      segmentPixelRange(
        segment,
        domainStart: domainStart,
        domainEnd: domainEnd,
        width: width,
        pad: pad,
      ),
  ];
  double leftOf(int i) => math.min(ranges[i].left, ranges[i].right);
  double rightOf(int i) => math.max(ranges[i].left, ranges[i].right);

  final widths = [
    for (var i = 0; i < segments.length; i++) rightOf(i) - leftOf(i),
  ];
  return [
    for (var i = 0; i < segments.length; i++)
      MasteryBand(
        left: leftOf(i),
        right: rightOf(i),
        mastery: masteries[segments[i].order] ?? LearningMastery.unlearned,
        leadTransition: i > 0 && leftOf(i) == rightOf(i - 1)
            ? bandTransitionWidth(widths[i - 1], widths[i])
            : 0,
        trailTransition: i + 1 < segments.length && rightOf(i) == leftOf(i + 1)
            ? bandTransitionWidth(widths[i], widths[i + 1])
            : 0,
      ),
  ];
}
