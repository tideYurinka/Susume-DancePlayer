import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/stats/practice_stats_summary.dart';
import 'package:flutter_test/flutter_test.dart';

PracticeSessionRecord _session(
  DateTime start,
  double seconds, {
  String videoId = 'hash-a',
}) {
  return PracticeSessionRecord(
    start: start,
    videoId: videoId,
    signature: const SongSignature(song: 'My Love'),
    wallSeconds: seconds,
  );
}

void main() {
  // 2026-09-07 是周一；本周 = 09-07(一) ~ 09-13(日)。
  final now = DateTime(2026, 9, 13, 21);
  final monday = DateTime(2026, 9, 7, 10);
  final tuesday = DateTime(2026, 9, 8, 10);
  final lastSunday = DateTime(2026, 9, 6, 10);

  group('汇总四项', () {
    test('空集：三项时长为零、最长连续为 0', () {
      final summary = summarizePracticeStats(const [], now: now);
      expect(summary.today, Duration.zero);
      expect(summary.week, Duration.zero);
      expect(summary.total, Duration.zero);
      expect(summary.longestStreakDays, 0);
    });

    test('今日 = 本地日当天会话墙钟之和、累计 = 全部记录之和', () {
      final summary = summarizePracticeStats([
        _session(now, 372),
        _session(DateTime(2026, 9, 13, 8), 4500),
        _session(lastSunday, 65),
      ], now: now);
      expect(summary.today, const Duration(seconds: 4872));
      expect(summary.total, const Duration(seconds: 4937));
    });

    test('本周按自然周周一起算：上周日不计、本周一计', () {
      final summary = summarizePracticeStats([
        _session(monday, 300),
        _session(lastSunday, 600),
      ], now: now);
      expect(summary.week, const Duration(seconds: 300));
    });

    test('本周 = 整段自然周（周一至周日），与累计同源', () {
      final summary = summarizePracticeStats([
        _session(monday, 300),
        _session(DateTime(2026, 9, 13, 10), 60),
      ], now: DateTime(2026, 9, 8, 21));
      expect(summary.week, const Duration(seconds: 360));
      expect(summary.total, const Duration(seconds: 360));
    });

    test('跨零点：记录各归自己的本地日，不并入今日', () {
      final summary = summarizePracticeStats([
        _session(DateTime(2026, 9, 13, 23), 120),
        _session(DateTime(2026, 9, 14, 0), 60),
      ], now: now);
      expect(summary.today, const Duration(seconds: 120));
      // 09-14 属于下一自然周。
      expect(summary.week, const Duration(seconds: 120));
      expect(summary.total, const Duration(seconds: 180));
    });
  });

  group('当前连续天数', () {
    test('今天没练即为 0', () {
      final summary = summarizePracticeStats([
        _session(DateTime(2026, 9, 12, 10), 60),
        _session(DateTime(2026, 9, 11, 10), 60),
      ], now: now);
      expect(summary.currentStreakDays, 0);
      expect(summary.longestStreakDays, 2);
    });

    test('昨天为止连续：今天没练不断，缺今天即 0', () {
      final summary = summarizePracticeStats(
        [_session(DateTime(2026, 9, 12, 10), 60)],
        now: now,
      );
      expect(summary.currentStreakDays, 0);
    });

    test('今天练了、以今天为终点向前的连续段长度', () {
      final summary = summarizePracticeStats([
        _session(now, 60),
        _session(DateTime(2026, 9, 12, 10), 60),
        _session(DateTime(2026, 9, 11, 10), 60),
        _session(DateTime(2026, 9, 9, 10), 60),
      ], now: now);
      expect(summary.currentStreakDays, 3);
    });

    test('中间断档：只数最近一段', () {
      final summary = summarizePracticeStats([
        _session(now, 60),
        _session(DateTime(2026, 9, 12, 10), 60),
        _session(DateTime(2026, 9, 10, 10), 60),
      ], now: now);
      expect(summary.currentStreakDays, 2);
    });

    test('跨月跨年连续段不断开', () {
      final summary = summarizePracticeStats([
        _session(DateTime(2026, 9, 1, 10), 60),
        _session(DateTime(2026, 8, 31, 10), 60),
      ], now: DateTime(2026, 9, 1, 21));
      expect(summary.currentStreakDays, 2);

      final acrossYear = summarizePracticeStats([
        _session(DateTime(2027, 1, 1, 10), 60),
        _session(DateTime(2026, 12, 31, 10), 60),
      ], now: DateTime(2027, 1, 1, 21));
      expect(acrossYear.currentStreakDays, 2);
    });

    test('当日练习时长为 0 秒不算一天', () {
      final summary = summarizePracticeStats([
        _session(now, 0),
        _session(DateTime(2026, 9, 12, 10), 60),
      ], now: now);
      expect(summary.currentStreakDays, 0);
    });

    test('既有四项汇总数值不因新增项改变', () {
      final summary = summarizePracticeStats([
        _session(now, 372),
        _session(monday, 300),
        _session(lastSunday, 600),
      ], now: now);
      expect(summary.today, const Duration(seconds: 372));
      expect(summary.week, const Duration(seconds: 672));
      expect(summary.total, const Duration(seconds: 1272));
      expect(summary.longestStreakDays, 2); // 09-06 与 09-07 相邻成段。
      expect(summary.currentStreakDays, 1);
    });
  });

  group('最长连续天数', () {
    test('单日算 1', () {
      final summary = summarizePracticeStats([_session(now, 60)], now: now);
      expect(summary.longestStreakDays, 1);
    });

    test('断档取最长一段，且不因今天没练回退', () {
      // 09-01 ~ 09-03 连续 3 天；09-05 单独一天；今天 09-13 没练。
      final summary = summarizePracticeStats([
        _session(DateTime(2026, 9, 1, 10), 60),
        _session(DateTime(2026, 9, 2, 10), 60),
        _session(DateTime(2026, 9, 3, 10), 60),
        _session(DateTime(2026, 9, 5, 10), 60),
      ], now: now);
      expect(summary.longestStreakDays, 3);
      expect(summary.today, Duration.zero);
    });

    test('当日练习时长为 0 秒不算一天', () {
      final summary = summarizePracticeStats([
        _session(tuesday, 0),
        _session(monday, 0),
      ], now: now);
      expect(summary.longestStreakDays, 0);
    });

    test('同日多条记录合并为一天', () {
      final summary = summarizePracticeStats([
        _session(monday, 60),
        _session(DateTime(2026, 9, 8, 20), 60),
      ], now: now);
      expect(summary.longestStreakDays, 2);
    });

    test('跨周连续段不断开', () {
      final summary = summarizePracticeStats([
        _session(DateTime(2026, 9, 11, 10), 60),
        _session(DateTime(2026, 9, 12, 10), 60),
        _session(DateTime(2026, 9, 13, 10), 60),
        _session(DateTime(2026, 9, 14, 10), 60),
      ], now: now);
      expect(summary.longestStreakDays, 4);
    });
  });
}
