/// 四拍桶 → 学习段的展示分组聚合（见词条「四拍桶」）：零 Flutter 纯件。
///
/// 分组按**当前**分段线求值，是纯展示口径——移动分段线只换分组、历史桶
/// 不回改。一个桶整体归其**左边界**（左侧四拍线的时刻）所在的段：段界切在
/// 桶内时该桶整段归前一段（桶里只有聚合值、没有桶内时间分布，误差上限 =
/// 一个桶）。
///
/// - 段练习时长 = 段内桶墙钟秒之和；
/// - 段练习次数 = 段内桶扫过次数最小值（一段被完整经过的遍数）；
/// - 节拍网格未就绪（[BeatGridReads.hasRealBeats] 为假）不产桶、数值为 0，
///   各段标注「该时段无节拍数据」。
///
/// 输入是**扁平的可聚合读面**（本地日 → 桶序号 → 值），与桶分片存储模型
/// 同形但零依赖：纯值层不 import 存储实现；桶宽 = 一小节拍数
/// ([BeatGrid.beatsPerBar]，4/4 固定先验 = 四拍)，与记录侧同宽。
library;

import '../annotation/learning_segments.dart';
import '../core/beat_grid.dart';

/// 一个桶的可聚合值（墙钟秒与扫过次数；与桶分片存储值同形的读面类型）。
class SegmentBucketValue {
  const SegmentBucketValue({required this.wallSeconds, required this.sweeps});

  /// 墙钟秒（倍速不折算）。
  final double wallSeconds;

  /// 扫过次数（越过右边界记 1）。
  final int sweeps;

  SegmentBucketValue plus(SegmentBucketValue other) => SegmentBucketValue(
    wallSeconds: wallSeconds + other.wallSeconds,
    sweeps: sweeps + other.sweeps,
  );

  @override
  bool operator ==(Object other) =>
      other is SegmentBucketValue &&
      other.wallSeconds == wallSeconds &&
      other.sweeps == sweeps;

  @override
  int get hashCode => Object.hash(wallSeconds, sweeps);
}

/// 一段的练习聚合值（详情行与后续曲线共用同一口径）。
class SegmentPractice {
  const SegmentPractice({
    required this.practiceDuration,
    required this.practiceCount,
    required this.beatGridNotReady,
  });

  /// 段练习时长：段内桶墙钟秒之和。
  final Duration practiceDuration;

  /// 段练习次数：段内**全部**桶的扫过次数最小值；未完整经过（存在扫过为 0
  /// 的桶）为 0；段内无桶位为 0。
  final int practiceCount;

  /// 该时段无节拍数据（网格未就绪）：数值为 0 只是缺数据，不是没练。
  final bool beatGridNotReady;

  @override
  bool operator ==(Object other) =>
      other is SegmentPractice &&
      other.practiceDuration == practiceDuration &&
      other.practiceCount == practiceCount &&
      other.beatGridNotReady == beatGridNotReady;

  @override
  int get hashCode =>
      Object.hash(practiceDuration, practiceCount, beatGridNotReady);

  @override
  String toString() =>
      'SegmentPractice(${practiceDuration.inMilliseconds}ms, '
      '次数 $practiceCount, beatGridNotReady: $beatGridNotReady)';
}

/// 桶读面按桶序号跨本地日求和（累计口径）：段档与八拍档共用的唯一求和处。
Map<int, SegmentBucketValue> sumSegmentBuckets(
  Map<String, Map<int, SegmentBucketValue>> buckets,
) {
  final totals = <int, SegmentBucketValue>{};
  for (final day in buckets.values) {
    for (final entry in day.entries) {
      final previous = totals[entry.key];
      totals[entry.key] = previous == null
          ? entry.value
          : previous.plus(entry.value);
    }
  }
  return totals;
}

/// 把桶读面 [buckets]（本地日 → 桶序号 → 值）按 [segments]（升序、首尾
/// 相接）聚合成逐段练习值，返回列表与 [segments] 按下标对齐。
///
/// [grid] 为当前网格（null 或未就绪 = 不产桶、逐段标注缺数据）。累计口径：
/// 跨本地日的同桶值先求和。
List<SegmentPractice> aggregateSegmentPractice({
  required List<LearningSegment> segments,
  required BeatGrid? grid,
  required Map<String, Map<int, SegmentBucketValue>> buckets,
}) {
  if (segments.isEmpty) return const [];
  final ready = grid != null && grid.hasRealBeats;
  final totals = ready
      ? sumSegmentBuckets(buckets)
      : const <int, SegmentBucketValue>{};

  final micros = List<int>.filled(segments.length, 0);
  final counts = List<int>.filled(segments.length, 0);
  final seen = List<bool>.filled(segments.length, false);
  if (ready) {
    // 遍历有效区间内的每个桶位（含无记录者：读面上缺席 = 扫过 0），逐桶
    // 归段：次数取段内**全部**桶位的最小值，故未完整经过的段为 0；时长只
    // 累加有记录的桶。
    final end = segments.last.end;
    for (var bucket = 0; ; bucket++) {
      final boundary = _bucketLeftBoundary(grid, bucket);
      if (boundary == null || boundary >= end) break;
      final index = _segmentIndexFor(segments, boundary);
      if (index == null) continue;
      final value = totals[bucket];
      if (value != null) {
        micros[index] +=
            (value.wallSeconds * Duration.microsecondsPerSecond).round();
      }
      final sweeps = value?.sweeps ?? 0;
      counts[index] = seen[index]
          ? (sweeps < counts[index] ? sweeps : counts[index])
          : sweeps;
      seen[index] = true;
    }
  }

  return [
    for (var i = 0; i < segments.length; i++)
      SegmentPractice(
        practiceDuration: Duration(microseconds: micros[i]),
        practiceCount: seen[i] ? counts[i] : 0,
        beatGridNotReady: !ready,
      ),
  ];
}

/// 桶键 → 左侧四拍线的时刻。网格外（越末拍）返回 null；桶 0 的左边界是
/// 首个强拍所在单元，早于它的弱起也归桶 0（与记录侧桶键几何同款）。
Duration? _bucketLeftBoundary(BeatGrid grid, int bucket) {
  final lineBeat = grid.firstDownbeatIndex + bucket * grid.beatsPerBar;
  final last = grid.lastBeatIndex;
  if (last != null && lineBeat > last) return null;
  return grid.beatTime(lineBeat);
}

/// 左边界所在的段下标：落在某个段 `[start, end)` 内才归该段；早于首段或
/// 在区间尾之后都无段可归，返回 null（丢弃）。
int? _segmentIndexFor(List<LearningSegment> segments, Duration boundary) {
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    if (boundary >= segment.start && boundary < segment.end) return i;
  }
  return null;
}
