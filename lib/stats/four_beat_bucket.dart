/// 四拍桶几何与分摊：零 Flutter 纯件，记录器只做接线。
///
/// **桶几何**：一个桶 = 相邻两根四拍线之间的四拍区间；键 = 左侧那根
/// 四拍线的**绝对序号**（0 = 整曲首个强拍所在的那个单元）。四拍线自网格
/// 首个强拍（`firstDownbeatIndex`）起每 [kFourBeatBucketBeats] 拍一根，
/// 不消费八拍点。早于首个强拍的位置（弱起/前导）归桶 0（网格内没有它
/// 左侧的四拍线，按最近单元收纳；误差上限一个桶）。
library;

import '../core/document_beat_grid.dart';
import '../core/beat_grid.dart';
import '../core/local_day.dart';
import '../persistence/four_beat_bucket_key.dart';
import '../persistence/marker_document.dart' as marker_doc;

/// 四拍线的拍长（固定 4/4 先验）：桶宽 = 4 拍。
const int kFourBeatBucketBeats = 4;

/// 某一倍频档的四拍线时刻序列（毫秒，升序）：桶格的纯值承载。
///
/// 四拍线自该档派生网格首个强拍起每 4 个派生拍一根（[fourBeatBucketIndex]
/// 同一几何）；由「网格拍点 + 平移量 + 倍频」经 [deriveBeatPoints] 派生——
/// 统计投影按记录时档位重建当时桶格与按当前档位建当前桶格走同一入口。
class FourBeatBucketLines {
  FourBeatBucketLines.of({
    required List<marker_doc.BeatPoint> beats,
    required int shiftMs,
    required double density,
  }) : _lines = _fourBeatLineMs(
         deriveBeatPoints(beats: beats, shiftMs: shiftMs, density: density),
       );

  final List<int> _lines;

  static List<int> _fourBeatLineMs(List<(int, bool)> points) {
    final firstDown = points.indexWhere((p) => p.$2);
    final start = firstDown < 0 ? 0 : firstDown;
    return [
      for (var i = start; i < points.length; i += kFourBeatBucketBeats)
        points[i].$1,
    ];
  }

  int get count => _lines.length;

  /// 桶 [bucket] 的绝对时间区间（毫秒，左闭右开）；末桶右边界按末段
  /// 线距外推（与派生网格越末拍外推同口径）。
  (int, int) intervalOfMs(int bucket) {
    final clamped = bucket.clamp(0, _lines.length - 1);
    final start = _lines[clamped];
    final end = clamped + 1 < _lines.length
        ? _lines[clamped + 1]
        : _lines.last +
              (_lines.length >= 2
                  ? _lines.last - _lines[_lines.length - 2]
                  : 0);
    return (start, end);
  }

  /// 绝对时刻 [ms] 所在的桶序号（早于首根四拍线归 0，与
  /// [fourBeatBucketIndex] 的弱起收纳同口径）。
  int bucketAtMs(int ms) {
    if (_lines.isEmpty || ms < _lines.first) return 0;
    var lo = 0;
    var hi = _lines.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_lines[mid] <= ms) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

/// 一条落盘桶记录的可投影读面（倍频身份键 + 聚合值）。
class RecordedBucket {
  const RecordedBucket({
    required this.key,
    required this.wallSeconds,
    this.sweeps = 0,
  });

  /// 落盘桶键（带记录时的倍频身份）。
  final FourBeatBucketKey key;

  /// 墙钟秒。
  final double wallSeconds;

  final int sweeps;
}

/// 投影后的当前桶格聚合值：墙钟求和；扫过**合并取最小**（细分复制、合并
/// 不虚增）；扫过为 0 的纯墙钟记录不参与最小（不把次数清零）。
class ProjectedBucketValue {
  const ProjectedBucketValue({this.wallSeconds = 0, this.sweeps = 0});

  final double wallSeconds;
  final int sweeps;

  @override
  bool operator ==(Object other) =>
      other is ProjectedBucketValue &&
      other.wallSeconds == wallSeconds &&
      other.sweeps == sweeps;

  @override
  int get hashCode => Object.hash(wallSeconds, sweeps);
}

class _Accumulator {
  double seconds = 0;
  int? minSweeps;
}

/// 读取时投影（见词条「四拍桶」）：把各倍频档的落盘桶记录归入
/// **当前桶格**再聚合。
///
/// 对每条记录：按它自己的倍频重建**当时桶格**（[recordGridOf]）→ 桶序号
/// 换算成绝对时间区间 → 归入当前桶格（[currentGrid]）。秒守恒——细分时
/// 按重叠比例均分、合并时自然求和；扫过细分复制、合并取最小。返回
/// 本地日 → 当前桶序号 → 聚合值；同一份历史在五档之间任意切换后仍落在
/// 同一段音乐上，磁盘一个字节不动。
Map<String, Map<int, ProjectedBucketValue>> projectFourBeatBuckets({
  required Map<String, List<RecordedBucket>> days,
  required FourBeatBucketLines Function(double density) recordGridOf,
  required FourBeatBucketLines currentGrid,
}) {
  final out = <String, Map<int, _Accumulator>>{};
  for (final day in days.entries) {
    final acc = out.putIfAbsent(day.key, () => <int, _Accumulator>{});
    for (final record in day.value) {
      final grid = recordGridOf(record.key.density);
      final (a, b) = grid.intervalOfMs(record.key.index);
      final first = currentGrid.bucketAtMs(a);
      final last = currentGrid.bucketAtMs(b > a ? b - 1 : a);
      if (first == last) {
        _merge(acc, first, record.wallSeconds, record.sweeps);
        continue;
      }
      final span = (b - a).toDouble();
      for (var bucket = first; bucket <= last; bucket++) {
        final (cs, ce) = currentGrid.intervalOfMs(bucket);
        final overlap = (b < ce ? b : ce) - (a > cs ? a : cs);
        if (overlap <= 0) continue;
        _merge(acc, bucket, record.wallSeconds * overlap / span, record.sweeps);
      }
    }
  }
  return {
    for (final day in out.entries)
      day.key: {
        for (final bucket in day.value.entries)
          bucket.key: ProjectedBucketValue(
            wallSeconds: bucket.value.seconds,
            sweeps: bucket.value.minSweeps ?? 0,
          ),
      },
  };
}

void _merge(
  Map<int, _Accumulator> acc,
  int bucket,
  double seconds,
  int sweeps,
) {
  final cell = acc.putIfAbsent(bucket, _Accumulator.new);
  cell.seconds += seconds;
  if (sweeps > 0) {
    cell.minSweeps = cell.minSweeps == null
        ? sweeps
        : (cell.minSweeps! < sweeps ? cell.minSweeps! : sweeps);
  }
}

/// 位置 [mediaPosition] 所在的四拍桶序号（早于首个强拍归 0）。
///
/// 消费方只在网格就绪（[BeatGridReads.hasRealBeats]）时调用；未就绪的
/// 网格不产桶。
int fourBeatBucketIndex(BeatGrid grid, Duration mediaPosition) {
  final beat = grid.beatIndexAt(mediaPosition);
  final delta = beat - grid.firstDownbeatIndex;
  if (delta <= 0) return 0;
  return delta ~/ kFourBeatBucketBeats;
}

/// 一个采样区间产出的一笔桶账：某本地日、某桶的墙钟秒与扫过次数。
///
/// 一笔账只承载一种增量（要么墙钟秒、要么扫过 1 次），便于存储侧合并。
class FourBeatBucketCredit {
  const FourBeatBucketCredit({
    required this.day,
    required this.bucket,
    this.wallSeconds = 0,
    this.sweeps = 0,
    this.density = 1,
  });

  /// 该笔账归属的本地日（零点时刻）。
  final DateTime day;

  /// 桶序号（绝对四拍线序号）。
  final int bucket;

  /// 该桶在本区间的墙钟秒（倍速不折算）。
  final double wallSeconds;

  /// 该桶在本区间被扫过的次数（越过右边界记 1）。
  final int sweeps;

  /// 记账时的节拍倍频：桶键带记录时的倍频身份；缺省 1 = 原样
  /// （裸整数键，全部历史零迁移）。
  final double density;

  @override
  bool operator ==(Object other) =>
      other is FourBeatBucketCredit &&
      other.day == day &&
      other.bucket == bucket &&
      other.wallSeconds == wallSeconds &&
      other.sweeps == sweeps &&
      other.density == density;

  @override
  int get hashCode => Object.hash(day, bucket, wallSeconds, sweeps, density);

  @override
  String toString() =>
      'FourBeatBucketCredit(${localDayKey(day)}, 桶 $bucket, '
      '${wallSeconds}s, 扫过 $sweeps, 倍频 $density)';
}

/// 四拍桶分摊账本：把「判定为计」的连续播放区间的采样点摊到四拍桶上。
///
/// **记账规则**（见词条「练习记账」）：
/// - 一个采样区间的墙钟 dt 记在**当前采样点所在的桶**（按本地日拆开）；
/// - 连续推进**越过某桶右边界**（桶序号恰好 +1）时该桶扫过次数 +1；
/// - **断点**（引擎转停、位置跳变、位置回退）结束当前连续推进：断点处
///   不跨越中间桶、不给中间桶补账、不回补；回跳后再次经过的桶照常再累加。
///   跳变采样区间的 dt 仍按上一句记在当前采样点所在的桶（只是不记扫过）。
/// - **播放头没推进**（位置事件缺口）只进会话总时长、不产桶；
/// - **网格未就绪**（null 或 [BeatGridReads.hasRealBeats] 为假）不产桶，
///   就绪度中途变化即切开（下一采样起正常产桶）；
/// - dt 一律墙钟（倍速不折算），不做按桶边界的精确切分（采样步长上界
///   远小于桶长）。
///
/// 账本只认采样序列，不读 provider、不碰存储——调用方（记录器）负责在
/// 判定翻转到「不计」、换视频、退出时调用 [breakRun]。
class FourBeatBucketLedger {
  DateTime? _prevWall;
  Duration? _prevPosition;
  int? _prevBucket;

  /// 结束当前连续推进（引擎转停/判定翻转/换视频/退出）：下一采样重新
  /// 立基准，不跨断点补账。
  void breakRun() {
    _prevWall = null;
    _prevPosition = null;
    _prevBucket = null;
  }

  /// 消费一个采样点：墙钟 [wall]、媒介位置 [mediaPosition]、当前网格
  /// [grid]（null 或未就绪 = 不产桶）、记账时的倍频 [density]（进桶键
  /// 身份）。返回本次采样产出的桶账（通常 0-2 笔，跨零点可更多）。
  List<FourBeatBucketCredit> addSample({
    required DateTime wall,
    required Duration mediaPosition,
    required BeatGrid? grid,
    double density = 1,
  }) {
    if (grid == null || !grid.hasRealBeats) {
      breakRun();
      return const [];
    }
    final prevWall = _prevWall;
    final prevPosition = _prevPosition;
    final prevBucket = _prevBucket;
    final bucket = fourBeatBucketIndex(grid, mediaPosition);
    // 无论是否连续都更新推进基准：缺口/停住的时段不在下次回补。
    _prevWall = wall;
    _prevPosition = mediaPosition;
    _prevBucket = bucket;

    if (prevWall == null || prevPosition == null || prevBucket == null) {
      return const [];
    }
    if (!wall.isAfter(prevWall)) return const [];
    // 播放头没推进或回退：不产桶（回退的桶序号只会不增，下方 step<0 兜底）。
    if (mediaPosition <= prevPosition) return const [];
    final step = bucket - prevBucket;
    // 回退：断点，不跨越中间桶、不补账。
    if (step < 0) return const [];
    // dt 一律记在当前采样点所在的桶；跳变（step>1）同样只
    // 记 dt、不补中间桶。
    final credits = _creditInterval(prevWall, wall, bucket, density);
    if (step == 1) {
      // 越过 prevBucket 的右边界：该桶扫过 +1（记在越界发生的当天）。
      credits.add(
        FourBeatBucketCredit(
          day: localDay(wall),
          bucket: prevBucket,
          sweeps: 1,
          density: density,
        ),
      );
    }
    return credits;
  }

  /// 把 [start]–[end] 的墙钟秒按本地午夜拆开，逐日记到 [bucket]。
  List<FourBeatBucketCredit> _creditInterval(
    DateTime start,
    DateTime end,
    int bucket,
    double density,
  ) {
    final out = <FourBeatBucketCredit>[];
    var segmentStart = start;
    while (segmentStart.isBefore(end)) {
      final midnight = DateTime(
        segmentStart.year,
        segmentStart.month,
        segmentStart.day + 1,
      );
      final segmentEnd = midnight.isBefore(end) ? midnight : end;
      final seconds = segmentEnd.difference(segmentStart).inMicroseconds / 1e6;
      if (seconds > 0) {
        out.add(
          FourBeatBucketCredit(
            day: localDay(segmentStart),
            bucket: bucket,
            wallSeconds: seconds,
            density: density,
          ),
        );
      }
      if (!midnight.isBefore(end)) break;
      segmentStart = midnight;
    }
    return out;
  }
}
