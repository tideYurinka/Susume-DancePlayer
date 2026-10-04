/// 每日柱状图与日下钻的派生量（「日下钻」）。
///
/// 与汇总卡同源：柱高 = 当天全部舞的会话墙钟秒之和（含已删除舞的历史），
/// 空日如实为零；窗口含今天，范围切换只换窗口、不换口径。全部为无 IO
/// 纯函数，时钟由调用方注入（[DateTime] `now`）。
library;

import '../core/local_day.dart';
import '../persistence/practice_stats.dart';
import '../persistence/song_signature.dart';
import 'practice_stats_format.dart';

/// 柱状图展示范围（默认近 30 天，可切近 7 / 90 天）。
/// 通用名：它同时驱动柱状图窗口与排行榜统计范围。
enum PracticeStatsWindow {
  last7(7),
  last30(30),
  last90(90);

  const PracticeStatsWindow(this.days);

  /// 窗口天数（含今天）。
  final int days;
}

/// 统计单位：按时间（墙钟时长）或按次数
/// （练习场次，一条有效会话记录记一场）。领域词是「练习场次」，界面
/// 文案用「次数」。
enum StatsMetric { time, count }

/// 一根柱：本地日与当天全部舞的墙钟秒之和与场次数（两个口径的原始值，
/// 单位在渲染时选其一）。
class DailyPracticeBar {
  const DailyPracticeBar({
    required this.day,
    required this.total,
    required this.sessions,
  });

  /// 本地日（零点）。
  final DateTime day;

  /// 当天合计；无练习为 [Duration.zero]。
  final Duration total;

  /// 当天有效会话记录条数（练习场次）；无练习为 0。
  final int sessions;
}

/// 日下钻的一行：当天练过的某支舞的时长与场次（署名快照用于删除舞后
/// 仍可读）。
class DailyPracticeDance {
  const DailyPracticeDance({
    required this.videoId,
    required this.signature,
    required this.total,
    required this.sessions,
  });

  final String videoId;
  final SongSignature signature;
  final Duration total;

  /// 该舞当天的会话记录条数（练习场次）。
  final int sessions;
}

/// 某一天的明细：当天合计与按舞聚合的行（按时长降序）。
class DailyPracticeDetail {
  const DailyPracticeDetail({
    required this.day,
    required this.total,
    required this.sessions,
    required this.dances,
  });

  /// 本地日（零点）。
  final DateTime day;

  /// 当天全部舞的墙钟秒之和。
  final Duration total;

  /// 当天有效会话记录条数（练习场次）。
  final int sessions;

  /// 当天练过的舞（时长降序，同时长按 videoId 升序）；空日为空表。
  final List<DailyPracticeDance> dances;
}

/// 窗口的首个本地日（含今天共 `window.days` 天）——柱状图与排行共用的
/// 唯一窗口起日口径。
DateTime practiceStatsWindowFirstDay(DateTime now, PracticeStatsWindow window) {
  final today = localDay(now);
  return DateTime(today.year, today.month, today.day - window.days + 1);
}

/// 窗口内的逐日柱：自 `今天 - (window.days - 1)` 至今天（含），升序、无缺口。
List<DailyPracticeBar> dailyPracticeBars(
  List<PracticeSessionRecord> records, {
  required DateTime now,
  required PracticeStatsWindow window,
}) {
  final today = localDay(now);
  final totals = dailyPracticeTotals(records);
  final counts = dailyPracticeSessionCounts(records);
  return [
    for (var offset = window.days - 1; offset >= 0; offset--)
      _bar(today, offset, totals, counts),
  ];
}

DailyPracticeBar _bar(
  DateTime today,
  int offset,
  Map<DateTime, Duration> totals,
  Map<DateTime, int> counts,
) {
  final day = DateTime(today.year, today.month, today.day - offset);
  return DailyPracticeBar(
    day: day,
    total: totals[day] ?? Duration.zero,
    sessions: counts[day] ?? 0,
  );
}

/// 某一天的明细：按舞聚合当天记录、按时长降序（同时长按 videoId 升序）；
/// 合计不大于零的舞不出行，空日返回空明细。
DailyPracticeDetail dailyPracticeDetail(
  List<PracticeSessionRecord> records,
  DateTime day,
) {
  final target = localDay(day);
  final byVideo =
      <
        String,
        ({
          SongSignature signature,
          DateTime start,
          Duration total,
          int sessions,
        })
      >{};
  var total = Duration.zero;
  var sessions = 0;
  for (final record in records) {
    if (localDay(record.start) != target) continue;
    total += record.wallDuration;
    if (record.wallSeconds > 0) sessions++;
    final current = byVideo[record.videoId];
    // 署名快照取当天该舞最近一条记录：删除舞后的展示名不随输入次序变化。
    final latest = current == null || !record.start.isBefore(current.start);
    byVideo[record.videoId] = (
      signature: latest ? record.signature : current.signature,
      start: latest ? record.start : current.start,
      total: (current?.total ?? Duration.zero) + record.wallDuration,
      sessions: (current?.sessions ?? 0) + (record.wallSeconds > 0 ? 1 : 0),
    );
  }
  final dances =
      [
        for (final entry in byVideo.entries)
          if (entry.value.total > Duration.zero)
            DailyPracticeDance(
              videoId: entry.key,
              signature: entry.value.signature,
              total: entry.value.total,
              sessions: entry.value.sessions,
            ),
      ]..sort((a, b) {
        final byTotal = b.total.compareTo(a.total);
        return byTotal != 0 ? byTotal : a.videoId.compareTo(b.videoId);
      });
  return DailyPracticeDetail(
    day: target,
    total: total,
    sessions: sessions,
    dances: List.unmodifiable(dances),
  );
}

/// 按本地日汇总全部记录的墙钟时长（柱状图与热力图共用的「每日合计」口径）。
Map<DateTime, Duration> dailyPracticeTotals(
  List<PracticeSessionRecord> records,
) {
  final totals = <DateTime, Duration>{};
  for (final record in records) {
    final day = localDay(record.start);
    totals[day] = (totals[day] ?? Duration.zero) + record.wallDuration;
  }
  return totals;
}

/// 按本地日统计练习场次：一条有效会话记录（`wallSeconds > 0`）记一场；
/// 并入与跨零点拆条的语义由存储层的记录形状承载，聚合侧只数条数。
Map<DateTime, int> dailyPracticeSessionCounts(
  List<PracticeSessionRecord> records,
) {
  final counts = <DateTime, int>{};
  for (final record in records) {
    if (record.wallSeconds <= 0) continue;
    final day = localDay(record.start);
    counts[day] = (counts[day] ?? 0) + 1;
  }
  return counts;
}

/// 单位 → 量（同一把尺）：时长取微秒、场次取场次数。供柱高归一、分位
/// 分档与排序共用，避免各处各写一份 switch。
int statsMetricValue(Duration total, int sessions, StatsMetric metric) =>
    switch (metric) {
      StatsMetric.time => total.inMicroseconds,
      StatsMetric.count => sessions,
    };

/// 单位 → 量：同一把尺供排序与归一（时长取微秒、场次取场次）。
/// 柱按当前单位取量（柱高归一的分子与分母同尺）。
extension DailyPracticeBarMetric on DailyPracticeBar {
  /// 当前单位下的量（时长为微秒，场次为场次数）。
  int valueFor(StatsMetric metric) => statsMetricValue(total, sessions, metric);
}

/// 明细列表内当前单位的最大值（日下钻进度条归一的基准，与排行归一
/// 同构）；空表为 0。
int dayDetailMaxValue(List<DailyPracticeDance> dances, StatsMetric metric) =>
    dances.fold(0, (max, dance) {
      final value = dance.valueFor(metric);
      return value > max ? value : max;
    });

/// 明细行按当前单位取量、取文案、比较（降序 + videoId 升序稳定次序）。
extension DailyPracticeDanceMetric on DailyPracticeDance {
  /// 当前单位下的量（时长为微秒，场次为场次数）。
  int valueFor(StatsMetric metric) => statsMetricValue(total, sessions, metric);

  /// 当前单位下的展示文案（界面口径：「次数」）。
  String textFor(StatsMetric metric) => switch (metric) {
    StatsMetric.time => statsDurationText(total),
    StatsMetric.count => '$sessions 次',
  };

  /// 按当前单位降序、并列按 videoId 升序。
  int compareByThenVideoId(DailyPracticeDance other, StatsMetric metric) {
    final byMetric = other.valueFor(metric).compareTo(valueFor(metric));
    return byMetric != 0 ? byMetric : videoId.compareTo(other.videoId);
  }
}

/// 日合计按当前单位取文案（「N 次」为界面口径）。
extension DailyPracticeDetailMetric on DailyPracticeDetail {
  /// 当天各舞按当前单位降序（并列 videoId 升序）：气泡分解行与明细卡
  /// 共用同一份排序，防两处口径漂移。
  List<DailyPracticeDance> dancesSortedBy(StatsMetric metric) =>
      [...dances]..sort((a, b) => a.compareByThenVideoId(b, metric));

  /// 当前单位下的展示文案。
  String textFor(StatsMetric metric) => switch (metric) {
    StatsMetric.time => statsDurationText(total),
    StatsMetric.count => '$sessions 次',
  };
}
