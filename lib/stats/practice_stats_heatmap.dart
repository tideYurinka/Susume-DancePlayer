/// 年热力图（GitHub 式）的派生量。
///
/// 窗口 = 滚动近 53 个自然周，末列是今天所在周；列按周、行按周一到周日。
/// 与汇总卡、柱状图同源：每格 = 当天全部舞的会话墙钟秒之和（含已删除舞的
/// 历史），无练习为空格；色深按窗口内非零日的最近秩分位动态分档，只在本
/// 窗口内相对可比。全部为无 IO 纯函数，时钟由调用方注入（[DateTime] `now`）。
library;

import 'dart:math' as math;

import '../core/local_day.dart';
import '../persistence/practice_stats.dart';
import 'practice_stats_daily.dart';

/// 周列数（滚动近 1 年 = 53 周，30）与每列格数（周一到周日）。
const int _weekCount = 53;
const int _daysPerWeek = 7;

/// 热力图的一格：本地日、当天合计、场次数与色深档。
class HeatmapCell {
  const HeatmapCell({
    required this.day,
    required this.total,
    required this.sessions,
    required this.level,
    required this.isFuture,
  });

  /// 本地日（零点）。
  final DateTime day;

  /// 当天全部舞墙钟秒之和；无练习为 [Duration.zero]。
  final Duration total;

  /// 当天练习场次（有效会话记录条数）；无练习为 0。
  final int sessions;

  /// 色深档：0 = 空格，1–4 随当前单位的当日量递增。
  final int level;

  /// 今天之后（本周内的未来日）：恒为空，且不是可下钻的「那一天」。
  final bool isFuture;
}

/// 热力图的一列：一周 7 格（周一→周日）与本周周一零点。
class HeatmapWeek {
  const HeatmapWeek({required this.start, required this.cells});

  /// 本周周一（零点）。
  final DateTime start;

  /// 周一→周日 7 格，无缺口。
  final List<HeatmapCell> cells;
}

/// 窗口内动态分档的三档边界（升序）：按时间为微秒、按次数为场次数；
/// 窗口内无练习（无非零日）为空表。供热力图色深定档使用。
List<int> heatmapQuantileBounds(
  List<PracticeSessionRecord> records, {
  required DateTime now,
  StatsMetric metric = StatsMetric.time,
}) {
  final today = localDay(now);
  final weekStart = practiceStatsWeekStart(today);
  final firstDay = DateTime(
    weekStart.year,
    weekStart.month,
    weekStart.day - (_weekCount - 1) * _daysPerWeek,
  );
  final totals = dailyPracticeTotals(records);
  final counts = dailyPracticeSessionCounts(records);
  final values = [
    for (final entry in totals.entries)
      // 窗口（滚动 53 周）外与今天之后的非零日都不入分位集合。
      if (!entry.key.isBefore(firstDay) && !entry.key.isAfter(today))
        statsMetricValue(entry.value, counts[entry.key] ?? 0, metric),
  ].where((value) => value > 0).toList()..sort();
  return [
    for (final p in const [0.25, 0.50, 0.75]) _nearestRank(values, p),
  ].whereType<int>().toList();
}

/// 最近秩分位：升序集合第 `ceil(p · n)` 个（1 起）观测值；不插值、不取整，
/// 空集合无观测值（返回 null）。
int? _nearestRank(List<int> sorted, double p) {
  if (sorted.isEmpty) return null;
  final rank = (p * sorted.length).ceil();
  return sorted[(rank - 1).clamp(0, sorted.length - 1)];
}

/// 档位：0 = 无练习（空格）；非零值 = 1 + 严格小于该值的边界个数（上限 4）。
/// 边界重复时部分档位自然空缺；全部同值时统一落档 1，不伪造梯度。
int heatmapLevelFor(int value, List<int> bounds) {
  if (value <= 0) return 0;
  var below = 0;
  for (final bound in bounds) {
    if (bound < value) below++;
  }
  return math.min(1 + below, 4);
}

/// 窗口合计：只累加今天及以前的日子（未来日 total/sessions 恒 0）。
/// 标题「过去一年已练习 …」的合计与色深分档共用同一份窗口几何。
({Duration total, int sessions}) heatmapWindowTotal(List<HeatmapWeek> weeks) {
  var total = Duration.zero;
  var sessions = 0;
  for (final cell in weeks.expand((week) => week.cells)) {
    if (cell.isFuture) continue;
    total += cell.total;
    sessions += cell.sessions;
  }
  return (total: total, sessions: sessions);
}

/// 滚动近 53 周的逐日热力图：末列是今天所在周，未来日与无练习日都是空格
/// （档 0）；窗口外的记录不入格。窗口与几何不随时间维度变化；色深的量随
/// [metric] 重算，档界由 [bounds] 提供（缺省时按
/// 窗口内非零日现算）。
List<HeatmapWeek> yearHeatmapWeeks(
  List<PracticeSessionRecord> records, {
  required DateTime now,
  StatsMetric metric = StatsMetric.time,
  List<int>? bounds,
}) {
  final today = localDay(now);
  final resolvedBounds =
      bounds ?? heatmapQuantileBounds(records, now: now, metric: metric);
  final totals = dailyPracticeTotals(records);
  final counts = dailyPracticeSessionCounts(records);
  final thisMonday = practiceStatsWeekStart(today);
  return [
    for (var weeksBack = _weekCount - 1; weeksBack >= 0; weeksBack--)
      _week(
        thisMonday,
        weeksBack,
        today,
        totals,
        counts,
        metric,
        resolvedBounds,
      ),
  ];
}

HeatmapWeek _week(
  DateTime thisMonday,
  int weeksBack,
  DateTime today,
  Map<DateTime, Duration> totals,
  Map<DateTime, int> counts,
  StatsMetric metric,
  List<int> bounds,
) {
  final start = DateTime(
    thisMonday.year,
    thisMonday.month,
    thisMonday.day - weeksBack * _daysPerWeek,
  );
  return HeatmapWeek(
    start: start,
    cells: List.unmodifiable([
      for (var dayOffset = 0; dayOffset < _daysPerWeek; dayOffset++)
        _cell(start, dayOffset, today, totals, counts, metric, bounds),
    ]),
  );
}

HeatmapCell _cell(
  DateTime weekStart,
  int dayOffset,
  DateTime today,
  Map<DateTime, Duration> totals,
  Map<DateTime, int> counts,
  StatsMetric metric,
  List<int> bounds,
) {
  final day = DateTime(
    weekStart.year,
    weekStart.month,
    weekStart.day + dayOffset,
  );
  // 今日之后的格子（本周内的未来日）恒为空，且不可下钻。
  final isFuture = day.isAfter(today);
  final total = isFuture ? Duration.zero : totals[day] ?? Duration.zero;
  final sessions = isFuture ? 0 : counts[day] ?? 0;
  return HeatmapCell(
    day: day,
    total: total,
    sessions: sessions,
    level: heatmapLevelFor(statsMetricValue(total, sessions, metric), bounds),
    isFuture: isFuture,
  );
}
