import '../core/local_day.dart';
import '../persistence/practice_stats.dart';

/// 统计页仪表盘的派生量：今日 / 本周 / 累计时长与当前 /
/// 最长连续天数。全部由会话记录派生，时钟由调用方注入（[now]）。
class PracticeStatsSummary {
  const PracticeStatsSummary({
    required this.today,
    required this.week,
    required this.total,
    required this.currentStreakDays,
    required this.longestStreakDays,
  });

  /// 今日：本地日当天会话墙钟之和。
  final Duration today;

  /// 本周：本自然周（周一 00:00 起至下周一 00:00 前）会话墙钟之和。
  final Duration week;

  /// 累计：全部会话墙钟之和（含已删除舞的历史）。
  final Duration total;

  /// 当前连续天数：以今天为终点、在「当日练习时长 > 0 秒」的本地日集合上
  /// 向前的连续段长度；今天没练即为 0。与 [longestStreakDays] 共用同一判据
  /// 与同一份日合计。
  final int currentStreakDays;

  /// 最长连续天数：在「当日练习时长 > 0 秒」的本地日集合上的最长连续段，
  /// 是历史最长，不因今天还没练而回退。
  final int longestStreakDays;
}

/// 汇总四项。时钟经 [now] 注入，无 IO、无 Flutter。
///
/// 记录按 [PracticeSessionRecord.start] 的本地日归日（口径见
/// [localDay]）。
PracticeStatsSummary summarizePracticeStats(
  List<PracticeSessionRecord> records, {
  required DateTime now,
}) {
  final today = localDay(now);
  final weekStart = practiceStatsWeekStart(today);
  final weekEnd = DateTime(weekStart.year, weekStart.month, weekStart.day + 7);

  final dayTotals = <DateTime, Duration>{};
  var total = Duration.zero;
  for (final record in records) {
    final duration = record.wallDuration;
    final day = localDay(record.start);
    dayTotals[day] = (dayTotals[day] ?? Duration.zero) + duration;
    total += duration;
  }

  var todayTotal = Duration.zero;
  var weekTotal = Duration.zero;
  for (final entry in dayTotals.entries) {
    if (entry.key == today) todayTotal = entry.value;
    if (!entry.key.isBefore(weekStart) && entry.key.isBefore(weekEnd)) {
      weekTotal += entry.value;
    }
  }

  return PracticeStatsSummary(
    today: todayTotal,
    week: weekTotal,
    total: total,
    longestStreakDays: _longestStreak(dayTotals),
    currentStreakDays: _currentStreak(dayTotals, today),
  );
}

/// 练习日集合（当日合计 > 0 秒）上，以 [today] 为终点向前的连续段长度；
/// 今天没练即为 0。
int _currentStreak(Map<DateTime, Duration> dayTotals, DateTime today) {
  if ((dayTotals[today] ?? Duration.zero) <= Duration.zero) return 0;
  var streak = 1;
  var day = today;
  for (;;) {
    final previous = DateTime(day.year, day.month, day.day - 1);
    if ((dayTotals[previous] ?? Duration.zero) <= Duration.zero) break;
    streak++;
    day = previous;
  }
  return streak;
}

/// 练习日集合（当日合计 > 0 秒）上求最长连续段。
int _longestStreak(Map<DateTime, Duration> dayTotals) {
  final days = [
    for (final entry in dayTotals.entries)
      if (entry.value > Duration.zero) entry.key,
  ]..sort();
  var longest = 0;
  var current = 0;
  DateTime? previous;
  for (final day in days) {
    current = previous != null && _isNextDay(previous, day) ? current + 1 : 1;
    if (current > longest) longest = current;
    previous = day;
  }
  return longest;
}

/// [day] 是否恰为 [previous] 的次日（按本地日历日比较，不受时区偏移影响）。
bool _isNextDay(DateTime previous, DateTime day) =>
    day == DateTime(previous.year, previous.month, previous.day + 1);
