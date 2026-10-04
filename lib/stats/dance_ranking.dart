/// 统计页单舞排行的派生量（起按「窗口 × 单位」求值）。
///
/// 列表口径 = 现存舞库快照 × 窗口内的会话记录：窗口内时长按舞累加、场次按
/// 舞计数；窗口内当前单位值为 0 的现存舞不出行；已删舞的历史没有条目可挂，
/// 自然不进排行，但仍进汇总卡与图表。排序在快照上做，本文件无 IO、无
/// Flutter。
library;

import '../core/local_day.dart';
import '../dance/dance_library.dart';
import '../persistence/practice_stats.dart';
import 'practice_stats_daily.dart';
import 'practice_stats_format.dart';

/// 排行的一行：舞名、窗口内时长与场次两个口径的原始值。
class DanceRankingRow {
  const DanceRankingRow({
    required this.videoId,
    required this.title,
    required this.total,
    required this.sessions,
  });

  final String videoId;

  /// 舞名（署名真值优先，未署名回退文件名）。
  final String title;

  /// 窗口内墙钟练习时长；窗口内没练过为 [Duration.zero]。
  final Duration total;

  /// 窗口内练习场次（有效会话记录条数）；窗口内没练过为 0。
  final int sessions;

  /// 现行单位的展示值（排行行主数值）；口径落在本层，页面只渲染。
  String valueTextFor(StatsMetric metric) => switch (metric) {
    StatsMetric.time => statsDurationText(total),
    StatsMetric.count => '$sessions 次',
  };

  /// 当前单位下的量（时长为微秒，场次为场次数）。
  int valueFor(StatsMetric metric) => switch (metric) {
    StatsMetric.time => total.inMicroseconds,
    StatsMetric.count => sessions,
  };
}

/// 排行列表内当前单位的最大值（进度条归一的基准）；空表为 0。
int rankingMaxValue(List<DanceRankingRow> rows, StatsMetric metric) =>
    rows.fold(0, (max, row) {
      final value = row.valueFor(metric);
      return value > max ? value : max;
    });

/// 现存舞排行：窗口内按 [metric] 降序（并列按 videoId 升序稳定次序）；
/// 窗口内当前单位值为 0 的舞不出行，空窗口为空表。
List<DanceRankingRow> windowDanceRanking(
  List<DanceSnapshot> dances,
  List<PracticeSessionRecord> records, {
  required DateTime now,
  required PracticeStatsWindow window,
  required StatsMetric metric,
}) {
  final firstDay = practiceStatsWindowFirstDay(now, window);
  final lastDay = localDay(now);
  final totalByVideo = <String, Duration>{};
  final sessionsByVideo = <String, int>{};
  for (final record in records) {
    final day = localDay(record.start);
    if (day.isBefore(firstDay) || day.isAfter(lastDay)) continue;
    final videoId = record.videoId;
    totalByVideo[videoId] =
        (totalByVideo[videoId] ?? Duration.zero) + record.wallDuration;
    if (record.wallSeconds > 0) {
      sessionsByVideo[videoId] = (sessionsByVideo[videoId] ?? 0) + 1;
    }
  }
  bool inWindow(DanceRankingRow row) => row.valueFor(metric) > 0;
  final rows =
      [
        for (final dance in dances)
          DanceRankingRow(
            videoId: dance.videoId,
            title: dance.title,
            total: totalByVideo[dance.videoId] ?? Duration.zero,
            sessions: sessionsByVideo[dance.videoId] ?? 0,
          ),
      ].where(inWindow).toList()..sort((a, b) {
        final byMetric = b.valueFor(metric).compareTo(a.valueFor(metric));
        return byMetric != 0 ? byMetric : a.videoId.compareTo(b.videoId);
      });
  return List.unmodifiable(rows);
}
