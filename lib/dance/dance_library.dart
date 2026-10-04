/// 舞库读面：把一支舞散在四处的事实合成一张读面。
///
/// 一支舞 = 一条视频索引条目（内容寻址身份）；卡片量与排序在
/// 「一次装入整库」的批量快照上算出，单支舞入口与批量结果同源同口径。
/// 合成、派生与排序都是无框架纯函数（本文件依赖闭包零 Flutter）；
/// 装配四个读端口与写后失效在 `dance_library_providers.dart`。
///
/// 派生口径（唯一）：
/// - 熟练度百分比 = 学习段档位值均值 × 25（无分段线不显示）；
/// - 完全掌握 = 段集非空且全部段为最高档（缺项按未练计入）；
/// - 练习总时长 / 最近练习来自练舞统计聚合（无记录按零时长、无最近练习）；
/// - 平均练习遍数 = 累计墙钟练习时长 ÷ 当前有效区间时长（无有效区间显示 —）；
/// - 逐段量 = 段号 / 八拍区间（经八拍点单一相位源求值；网格未就绪不显示）/
///   熟练度档位；段练习时长与段练习次数随桶读面走练习分布读面
///   （`practice_distribution.dart`），节拍未就绪的时段在那里标注缺数据；
/// - 封面引用 = 位置 + 缓存是否就绪：位置取公开标记文件 `meta.coverPositionMs`
///   （缺省/不存在 = 跟随首线 = 有效区间起点），就绪由封面缓存文件是否
///   存在回答；页面只渲染，不自己拼路径、不自己取帧。
library;

import '../annotation/learning_segment_attributes.dart';
import '../annotation/learning_segments.dart';
import '../core/beat_grid.dart';
import '../core/cover_frame.dart' show kCoverPlaceholderAspectRatio;
import '../core/document_beat_grid.dart';
import '../core/eight_beat_phase.dart' show BeatPhase;
import '../persistence/video_index.dart';
import '../persistence/local_document.dart';
import '../persistence/marker_document.dart' hide BeatGrid;
import '../persistence/plan_calendar.dart';
import '../persistence/song_signature.dart';
import 'practice_distribution.dart';
import 'segment_practice_aggregation.dart';

/// 逐段详情行（详情量）：段号、熟练度档位与八拍区间。
///
/// 几何与播放器侧同源（有效区间 + 分段线派生），档位按段序取本地文档
/// 的熟练度（缺项按未练）；逐段练习值不在此——它们随桶读面走练习分布读面。
class DanceSegmentDetail {
  const DanceSegmentDetail({
    required this.order,
    required this.start,
    required this.end,
    required this.mastery,
    required this.eightBeatRange,
  });

  /// 段号（0 起，与播放器段序同源；渲染时按「第 N 段」加一）。
  final int order;

  /// 段起始（绝对时间点）。
  final Duration start;

  /// 段结束（绝对时间点）。
  final Duration end;

  /// 该段熟练度档位（缺项按未练）。
  final LearningMastery mastery;

  /// 该段覆盖的八拍区间；网格未就绪时为 null（不显示）。
  final DanceEightBeatRange? eightBeatRange;

  @override
  bool operator ==(Object other) =>
      other is DanceSegmentDetail &&
      other.order == order &&
      other.start == start &&
      other.end == end &&
      other.mastery == mastery &&
      other.eightBeatRange == eightBeatRange;

  @override
  int get hashCode => Object.hash(order, start, end, mastery, eightBeatRange);

  @override
  String toString() =>
      'DanceSegmentDetail(order: $order, [$start, $end], '
      'mastery: $mastery, eightBeatRange: $eightBeatRange)';
}

/// 八拍区间（详情量）：该段覆盖的八拍点在全曲时间序上的闭区间（1 起）。
class DanceEightBeatRange {
  const DanceEightBeatRange({required this.first, required this.last});

  /// 区间首（不晚于段首的最后一个八拍点的全曲序数）。
  final int first;

  /// 区间尾（早于段尾的最后一个八拍点的全曲序数）。
  final int last;

  @override
  bool operator ==(Object other) =>
      other is DanceEightBeatRange &&
      other.first == first &&
      other.last == last;

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => 'DanceEightBeatRange($first–$last)';
}

/// 一支舞各学习段的熟练度取值（稀疏：**缺项即未练**，显式「未练」不入表）。
///
/// [orders] 是这批值的作用段序表，[mastery] 只含显式设置过的段。逐段改档的
/// 单段补丁、一键完全掌握的目标值与点击前快照都经这一个值传递——段序对齐与
/// 稀疏不变式只有一处；值本身不读写持久化（落盘在 `dance_library_writes`）。
class DanceMasteryValues {
  const DanceMasteryValues({required this.orders, this.mastery = const {}});

  /// 作用段序表（与学习段段序同源）。
  final List<int> orders;

  /// 显式设置过的段熟练度；缺项按未练。
  final Map<int, LearningMastery> mastery;

  /// 捕获这批段当前的熟练度（一键完全掌握的点击前快照）。
  factory DanceMasteryValues.of(List<DanceSegmentDetail> segments) =>
      DanceMasteryValues(
        orders: [for (final segment in segments) segment.order],
        mastery: {
          for (final segment in segments)
            if (segment.mastery != LearningMastery.unlearned)
              segment.order: segment.mastery,
        },
      );

  /// 同一段序表、全部段最高档（一键完全掌握的目标值）。
  DanceMasteryValues get allMastered => DanceMasteryValues(
    orders: orders,
    mastery: {for (final order in orders) order: LearningMastery.mastered},
  );

  @override
  bool operator ==(Object other) {
    if (other is! DanceMasteryValues) return false;
    if (!_listEquals(other.orders, orders)) return false;
    if (other.mastery.length != mastery.length) return false;
    for (final entry in mastery.entries) {
      if (other.mastery[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(orders),
    Object.hashAllUnordered(
      mastery.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );

  @override
  String toString() => 'DanceMasteryValues(orders: $orders, mastery: $mastery)';
}

/// 单支舞的练舞统计摘要（第四处输入的聚合值）。
///
/// [lastPracticedAt] 取该舞最近一次会话的末刻（与练舞统计 store 从磁盘
/// 重建最近活动时刻的口径同源）；null = 从未练过。
class DancePracticeTotals {
  const DancePracticeTotals({this.total = Duration.zero, this.lastPracticedAt});

  /// 累计墙钟练习时长。
  final Duration total;

  /// 最近练习时刻；null = 从未练过。
  final DateTime? lastPracticedAt;

  @override
  bool operator ==(Object other) =>
      other is DancePracticeTotals &&
      other.total == total &&
      other.lastPracticedAt == lastPracticedAt;

  @override
  int get hashCode => Object.hash(total, lastPracticedAt);

  @override
  String toString() =>
      'DancePracticeTotals(total: $total, lastPracticedAt: $lastPracticedAt)';
}

/// 紧急度：输入 = 到期日 + 是否逾期 + 是否已达成。
/// 由计划文档的 DDL 在合成舞库快照处经 [danceUrgencyOf] 算出；无目标
/// （未设或已清除）为 null。
class DanceUrgency {
  const DanceUrgency({
    required this.dueDay,
    this.overdue = false,
    this.achieved = false,
  });

  /// 目标日（本地日零点）。
  final DateTime dueDay;

  /// 是否逾期（已过到期日且未达成）。
  final bool overdue;

  /// 目标是否已达成（已按时落档或完全掌握）。
  final bool achieved;

  @override
  bool operator ==(Object other) =>
      other is DanceUrgency &&
      other.dueDay == dueDay &&
      other.overdue == overdue &&
      other.achieved == achieved;

  @override
  int get hashCode => Object.hash(dueDay, overdue, achieved);

  @override
  String toString() =>
      'DanceUrgency(dueDay: $dueDay, overdue: $overdue, achieved: $achieved)';
}

/// 卡片角标取值（单枚，优先级 逾期 > 临期 > 完全掌握勾）。
enum DanceCardBadge { overdue, nearDeadline, mastered }

/// 紧急度求值（纯件）：由目标日 + 落档结论与完全掌握派生。已清除 /
/// 未设（[dueDay] 为 null）与已达成（落档按时或完全掌握）不带紧急度；逾期
/// 落档的历史仍带逾期紧急度。输入取基本类型，舞库
/// 纯值层不依赖计划文档结构（零 Flutter 约束）；剩余天数口径取
/// `plan_calendar.dart`，不另写一份。
DanceUrgency? danceUrgencyOf({
  required DateTime? dueDay,
  required bool settledOnTime,
  required bool fullyMastered,
  required DateTime now,
}) {
  if (dueDay == null) return null;
  if (settledOnTime || fullyMastered) return null;
  return DanceUrgency(
    dueDay: dueDay,
    overdue: planRemainingDays(dueDay: dueDay, now: now) < 0,
  );
}

/// 单枚角标取值（纯件）：优先级 逾期 > 临期 ≤3 天 > 完全掌握勾；
/// 无目标且未完全掌握的舞不出角标。完全掌握即目标已达成，紧急度求值已
/// 为 null，完成勾自然落在角标槽。
DanceCardBadge? danceCardBadgeOf(DanceSnapshot dance, {required DateTime now}) {
  final urgency = dance.urgency;
  if (urgency != null && !urgency.achieved) {
    if (urgency.overdue) return DanceCardBadge.overdue;
    if (planIsNearDeadline(
      planRemainingDays(dueDay: urgency.dueDay, now: now),
    )) {
      return DanceCardBadge.nearDeadline;
    }
  }
  if (dance.fullyMastered) return DanceCardBadge.mastered;
  return null;
}

/// 一支舞的读面快照：卡片量与详情量同源，页面只渲染不算术。
class DanceSnapshot {
  const DanceSnapshot({
    required this.entry,
    required this.importOrder,
    required this.signature,
    required this.masteryPercent,
    required this.fullyMastered,
    required this.practiceTotal,
    required this.lastPracticedAt,
    required this.averagePracticeCount,
    required this.segments,
    required this.coverPosition,
    required this.coverReady,
    required this.coverAspectRatio,
    required this.urgency,
  });

  /// 索引条目（身份、路径、续播位置与显示名回退的载体）。
  final VideoIndexEntry entry;

  /// 导入次序（索引条目列表中的位置）：新条目追加、既有条目就地替换，
  /// 位置即导入次序。索引没有独立的导入时间字段（既有决定只否决过
  /// 「视频时长」字段），排序的未练尾排取此序而不用会被打开刷新的
  /// 最近打开时间。
  final int importOrder;

  /// 署名真值优先（公开标记文件 `meta.signature`，回退索引署名缓存）。
  final SongSignature? signature;

  /// 熟练度百分比（均值 × 25）；无分段线时为 null（不显示）。
  final double? masteryPercent;

  /// 完全掌握：段集非空且全部段最高档。
  final bool fullyMastered;

  /// 累计墙钟练习时长（无统计记录 = [Duration.zero]）。
  final Duration practiceTotal;

  /// 最近练习时刻；null = 从未练过。
  final DateTime? lastPracticedAt;

  /// 平均练习遍数 = 累计墙钟练习时长 ÷ 当前有效区间时长；无有效区间
  /// （未落盘或零长）为 null（显示 —）。
  final double? averagePracticeCount;

  /// 逐段详情行（按段序升序；无分段线时为空）。
  final List<DanceSegmentDetail> segments;

  /// 封面位置：公开标记文件 `meta.coverPositionMs`；缺省或不存在 = 跟随
  /// 首线（有效区间起点）。无有效区间的舞因此落在视频第 0 帧。
  final Duration coverPosition;

  /// 封面缓存是否就绪（该舞缓存图片存在）。false = 渲染占位图，就绪后换真图。
  final bool coverReady;

  /// 卡片封面框的宽高比：就绪时取图片自身比例（竖屏 3:4、横屏 4:3），未就绪
  /// 或头部读不出时为 [kCoverPlaceholderAspectRatio]（3:4 占位）。
  final double coverAspectRatio;

  /// 紧急度（计划文档 DDL 派生；无目标 / 已达成 = null）。
  final DanceUrgency? urgency;

  /// 视频标识（内容哈希）。
  String get videoId => entry.videoId;

  /// 卡片标题：署名显示串，未署名回退文件名。
  String get title => signatureDisplayText(signature, entry.displayName);

  @override
  bool operator ==(Object other) =>
      other is DanceSnapshot &&
      other.entry == entry &&
      other.importOrder == importOrder &&
      other.signature == signature &&
      other.masteryPercent == masteryPercent &&
      other.fullyMastered == fullyMastered &&
      other.practiceTotal == practiceTotal &&
      other.lastPracticedAt == lastPracticedAt &&
      other.averagePracticeCount == averagePracticeCount &&
      _listEquals(other.segments, segments) &&
      other.coverPosition == coverPosition &&
      other.coverReady == coverReady &&
      other.coverAspectRatio == coverAspectRatio &&
      other.urgency == urgency;

  @override
  int get hashCode => Object.hash(
    entry,
    importOrder,
    signature,
    masteryPercent,
    fullyMastered,
    practiceTotal,
    lastPracticedAt,
    averagePracticeCount,
    Object.hashAll(segments),
    coverPosition,
    coverReady,
    coverAspectRatio,
    urgency,
  );
}

/// 整库读面快照：已按排序口径排定的卡片列表。
class DanceLibrarySnapshot {
  const DanceLibrarySnapshot({required this.dances});

  /// 排定次序的卡片列表。
  final List<DanceSnapshot> dances;

  @override
  bool operator ==(Object other) =>
      other is DanceLibrarySnapshot && _listEquals(other.dances, dances);

  @override
  int get hashCode => Object.hashAll(dances);
}

/// 封面位置（唯一口径）：公开标记文件 `meta.coverPositionMs`；缺省或不存在
/// = 跟随首线（有效区间起点）。无有效区间的舞因此落在视频第 0 帧。读面、
/// 缓存就绪判定与写路径（`DanceLibraryWrites.setCoverPosition` 回答写后生效
/// 位置）共用此函数——首线一改位置就变，旧封面随之失效重取。
Duration coverPositionOf(MarkersDocument markers) =>
    Duration(milliseconds: markers.coverPositionMs ?? markers.rangeStartMs);

/// 合成一支舞的读面快照；缺文档 / 缺统计如实兜底。
///
/// [readyAspectRatio] = 就绪封面的图片自身比例；null = 未就绪（封面框按
/// 3:4 占位）。就绪标记由它派生，读面不再各写一份「就绪 + 比例」的取值。
DanceSnapshot composeDanceSnapshot({
  required VideoIndexEntry entry,
  required int importOrder,
  required MarkersDocument markers,
  required LocalDocument local,
  required DancePracticeTotals practice,
  DateTime? planDueDay,
  bool planSettledOnTime = false,
  DateTime? now,
  double? readyAspectRatio,
}) {
  final input = practiceDistributionInputFor(markers, const {});
  final segments = input.segments;
  final beatGrid = input.grid;
  // 相位源整支舞求值一次（网格 + 锚点），各段共用。
  final phase = _beatPhase(markers, beatGrid);
  final fullyMastered = _fullyMastered(segments, local.mastery);
  return DanceSnapshot(
    entry: entry,
    importOrder: importOrder,
    signature: markers.signature ?? entry.signatureCache,
    masteryPercent: _masteryPercent(segments, local.mastery),
    fullyMastered: fullyMastered,
    practiceTotal: practice.total,
    lastPracticedAt: practice.lastPracticedAt,
    averagePracticeCount: _averagePracticeCount(markers, practice.total),
    segments: [
      for (final segment in segments)
        DanceSegmentDetail(
          order: segment.order,
          start: segment.start,
          end: segment.end,
          mastery: learningSegmentMastery(local.mastery, segment.order),
          eightBeatRange: _eightBeatRange(phase, segment),
        ),
    ],
    coverPosition: coverPositionOf(markers),
    coverReady: readyAspectRatio != null,
    coverAspectRatio: readyAspectRatio ?? kCoverPlaceholderAspectRatio,
    // 紧急度在合成舞库快照处接线：由计划文档的目标日、落档
    // 结论与完全掌握算出；无目标即无紧急度，不取时钟。
    urgency: planDueDay == null
        ? null
        : danceUrgencyOf(
            dueDay: planDueDay,
            settledOnTime: planSettledOnTime,
            fullyMastered: fullyMastered,
            now: now ?? DateTime.now(),
          ),
  );
}

/// 练习分布的读面输入（纯件）：当前分段线几何、就绪网格与桶读面。
///
/// 与读面合成共用同一份几何派生；页面按范围重算曲线与逐段值时经
/// `dancePracticeDistributionProvider` 取用。
PracticeDistributionInput practiceDistributionInputFor(
  MarkersDocument markers,
  Map<String, Map<int, SegmentBucketValue>> buckets,
) => PracticeDistributionInput(
  segments: learningSegmentsOf(
    rangeStartMs: markers.rangeStartMs,
    rangeEndMs: markers.rangeEndMs,
    segmentLines: markers.segmentLines,
  ),
  grid: _readyBeatGrid(markers),
  buckets: buckets,
);

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 该段覆盖的八拍区间（详情量）：一个八拍 = 相邻两八拍点之间的半开区间
/// `[p_i, p_{i+1})`，取与段 `[start, end)` **相交**者的最小与最大序数；序数
/// = 八拍点在**全曲时间序**上的位次（1 起）——锚点只改哪些点是八拍点，不重编
/// 序数（本序数是详情页的读数，与节拍轨「段内相对」编号是两个场合）。
///
/// 经八拍点单一相位源（[BeatPhase]，网格 + 公开 beat 段锚点）求值，不自实现
/// 相位；网格未就绪（[phase] 为 null）或段与任何八拍都不相交（整段落在首个
/// 八拍点之前）返回 null——不显示编出来的八拍号。本量是「覆盖区间」，与
/// 播放器侧 `segmentEightBeatCount`（段内八拍**个数**，要求段首段尾皆八拍
/// 整点）是两个量，不是第二条相位口径。
DanceEightBeatRange? _eightBeatRange(
  BeatPhase? phase,
  LearningSegment segment,
) {
  if (phase == null) return null;
  final points = phase.pointsInWindow(Duration.zero, segment.end);
  var first = -1;
  var last = -1;
  for (var i = 0; i < points.length; i++) {
    if (points[i] >= segment.end) break;
    last = i;
    // 该八拍的右端越过段首（末点则无右端）⇒ 与段相交。
    if (first < 0 &&
        (i + 1 >= points.length || points[i + 1] > segment.start)) {
      first = i;
    }
  }
  if (first < 0) return null;
  return DanceEightBeatRange(first: first + 1, last: last + 1);
}

/// 相位源：真实网格已落盘且拍点非空时由 markers `beat` 段 + 八拍锚点求值；
/// 未分析（无 beat 段）或退化空网格返回 null。与播放器侧「真实拍点可用」
/// 谓词（`BeatGridReads.hasRealBeats`）同口径，差别只是舞库读持久化文档
/// 而非会话内存态（文档侧判据写在持久化边界，不经派生格）。[grid] 由调用方
/// 求值一次传入，与分布读面共用同一实例。
BeatPhase? _beatPhase(MarkersDocument markers, BeatGrid? grid) {
  final doc = markers.beat;
  if (doc == null || grid == null) return null;
  return BeatPhase(grid: grid, anchors: doc.anchors);
}

/// 就绪的真实网格（未分析 / 退化空网格 → null）：分布读面与相位源共用同一
/// 就绪判据，不各写一份。
DocumentBeatGrid? _readyBeatGrid(MarkersDocument markers) {
  final grid = markers.beat;
  if (grid == null || grid.beats.isEmpty) return null;
  return DocumentBeatGrid(
    beats: grid.beats,
    shift: grid.shift,
    density: grid.density,
  );
}

/// 平均练习遍数 = 累计墙钟练习时长 ÷ 当前有效区间时长（尾 − 首）；有效区间
/// 未落盘或零长时无分母，返回 null（显示 —）。
double? _averagePracticeCount(MarkersDocument markers, Duration total) {
  final start = Duration(milliseconds: markers.rangeStartMs);
  final end = Duration(milliseconds: markers.rangeEndMs);
  final length = end - start;
  if (length <= Duration.zero) return null;
  return total.inMicroseconds / length.inMicroseconds;
}

/// 平均练习遍数文案：无有效区间显示 —；整数值不带小数位，否则一位小数。
String averagePracticeCountText(double? count) {
  if (count == null) return '—';
  final rounded = count.roundToDouble();
  return count == rounded
      ? '${rounded.toInt()} 遍'
      : '${count.toStringAsFixed(1)} 遍';
}

/// 合成整库读面快照：列表口径 = 索引条目（未落条目的舞不出现；已删视频的
/// 历史统计没有条目可挂，自然不进列表），排序在快照上做。导入次序 = 条目
/// 在索引里的位置。读面不含桶读面：逐段练习值走练习分布读面
/// （`dancePracticeDistributionProvider`），卡片与整库读面都不装。
DanceLibrarySnapshot composeDanceLibrarySnapshot({
  required VideoIndex index,
  required Map<String, MarkersDocument> markersByVideoId,
  required Map<String, LocalDocument> localByVideoId,
  required Map<String, DancePracticeTotals> practiceByVideoId,

  /// 按舞的最近目标（值 = 目标日 + 是否已按时落档）；无目标者缺席。
  Map<String, (DateTime, bool)> planGoalByVideoId = const {},
  DateTime? now,
  Map<String, double> coverAspectRatios = const {},
}) {
  final dances = <DanceSnapshot>[
    for (final (i, entry) in index.entries.indexed)
      composeDanceSnapshot(
        entry: entry,
        importOrder: i,
        markers:
            markersByVideoId[entry.videoId] ?? const MarkersDocument.empty(),
        local: localByVideoId[entry.videoId] ?? const LocalDocument.empty(),
        practice:
            practiceByVideoId[entry.videoId] ?? const DancePracticeTotals(),
        planDueDay: planGoalByVideoId[entry.videoId]?.$1,
        planSettledOnTime: planGoalByVideoId[entry.videoId]?.$2 ?? false,
        now: now,
        readyAspectRatio: coverAspectRatios[entry.videoId],
      ),
  ];
  return DanceLibrarySnapshot(dances: sortDanceSnapshots(dances));
}

/// 舞附件列表次序：按最近打开时间倒序；并列时保持
/// 传入原序（装饰下标做稳定排序）。「最近打开」这一读面序数的唯一出处——
/// 表单页只调用，不另排一份。
List<DanceSnapshot> dancesByRecentOpen(List<DanceSnapshot> dances) {
  final indexed = dances.indexed.toList()
    ..sort((a, b) {
      final byOpen = b.$2.entry.lastOpenedAt.compareTo(a.$2.entry.lastOpenedAt);
      return byOpen != 0 ? byOpen : a.$1.compareTo(b.$1);
    });
  return [for (final (_, dance) in indexed) dance];
}

/// 排序（加紧急层）：逾期组置顶（组内目标日升序）→ 未过未达成按
/// 剩余自然日升序（即目标日升序）→ 其余落回既有「最近练习倒序 → 未练按
/// 导入序 → videoId 稳定次序」。同目标日的并列落回既有次序；已达成与
/// 无目标的舞不带紧急度，只在最后一层出现。
List<DanceSnapshot> sortDanceSnapshots(List<DanceSnapshot> dances) {
  // 紧急层：0 = 逾期置顶，1 = 未过未达成，2 = 其余（既有次序）。
  int rankOf(DanceSnapshot dance) {
    final urgency = dance.urgency;
    if (urgency == null || urgency.achieved) return 2;
    return urgency.overdue ? 0 : 1;
  }

  final sorted = [...dances];
  sorted.sort((a, b) {
    final byRank = rankOf(a).compareTo(rankOf(b));
    if (byRank != 0) return byRank;
    if (rankOf(a) != 2) {
      final byDue = a.urgency!.dueDay.compareTo(b.urgency!.dueDay);
      if (byDue != 0) return byDue;
    }
    final aLast = a.lastPracticedAt;
    final bLast = b.lastPracticedAt;
    if (aLast != null || bLast != null) {
      if (aLast == null) return 1;
      if (bLast == null) return -1;
      final byRecency = bLast.compareTo(aLast);
      if (byRecency != 0) return byRecency;
    }
    final byImport = b.importOrder.compareTo(a.importOrder);
    if (byImport != 0) return byImport;
    return a.entry.videoId.compareTo(b.entry.videoId);
  });
  return List.unmodifiable(sorted);
}

/// 熟练度百分比 = 学习段档位值均值 × 25；无分段线（零段）不显示。
double? _masteryPercent(
  List<LearningSegment> segments,
  Map<int, LearningMastery> mastery,
) {
  if (segments.isEmpty) return null;
  var sum = 0;
  for (final segment in segments) {
    sum += learningSegmentMastery(mastery, segment.order).index;
  }
  return sum / segments.length * 25;
}

/// 完全掌握 = 段集非空且全段最高档；空段集不成立，缺项按未练计入。
bool _fullyMastered(
  List<LearningSegment> segments,
  Map<int, LearningMastery> mastery,
) {
  if (segments.isEmpty) return false;
  return segments.every(
    (segment) =>
        learningSegmentMastery(mastery, segment.order) ==
        LearningMastery.mastered,
  );
}
