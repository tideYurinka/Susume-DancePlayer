import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/stats/practice_stats_daily.dart';
import 'package:flutter_test/flutter_test.dart';

PracticeSessionRecord _session(
  DateTime start,
  double seconds, {
  String videoId = 'hash-a',
  String song = 'My Love',
}) {
  return PracticeSessionRecord(
    start: start,
    videoId: videoId,
    signature: SongSignature(song: song),
    wallSeconds: seconds,
  );
}

void main() {
  // 2026-09-13 是周日。
  final now = DateTime(2026, 9, 13, 21);

  List<DateTime> days(List<DailyPracticeBar> bars) => [
    for (final bar in bars) bar.day,
  ];

  group('柱状图窗口', () {
    test('近 7 天：含今天共 7 根，首根为 6 天前', () {
      final bars = dailyPracticeBars(
        const [],
        now: now,
        window: PracticeStatsWindow.last7,
      );
      expect(bars, hasLength(7));
      expect(bars.first.day, DateTime(2026, 9, 7));
      expect(bars.last.day, DateTime(2026, 9, 13));
    });

    test('近 30 天：含今天共 30 根，首根 2026-08-15', () {
      final bars = dailyPracticeBars(
        const [],
        now: now,
        window: PracticeStatsWindow.last30,
      );
      expect(bars, hasLength(30));
      expect(bars.first.day, DateTime(2026, 8, 15));
      expect(bars.last.day, DateTime(2026, 9, 13));
    });

    test('近 90 天：含今天共 90 根，首根 2026-06-16', () {
      final bars = dailyPracticeBars(
        const [],
        now: now,
        window: PracticeStatsWindow.last90,
      );
      expect(bars, hasLength(90));
      expect(bars.first.day, DateTime(2026, 6, 16));
      expect(bars.last.day, DateTime(2026, 9, 13));
    });

    test('跨月：月初的今天仍回退到上月末', () {
      final bars = dailyPracticeBars(
        const [],
        now: DateTime(2026, 3, 2, 9),
        window: PracticeStatsWindow.last7,
      );
      expect(days(bars), [
        DateTime(2026, 2, 24),
        DateTime(2026, 2, 25),
        DateTime(2026, 2, 26),
        DateTime(2026, 2, 27),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 2),
      ]);
    });

    test('跨年：元旦的今天回退到上一年末', () {
      final bars = dailyPracticeBars(
        const [],
        now: DateTime(2026, 1, 2, 9),
        window: PracticeStatsWindow.last7,
      );
      expect(days(bars), [
        DateTime(2025, 12, 27),
        DateTime(2025, 12, 28),
        DateTime(2025, 12, 29),
        DateTime(2025, 12, 30),
        DateTime(2025, 12, 31),
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2),
      ]);
    });

    test('窗口外与未来的记录不入柱', () {
      final bars = dailyPracticeBars([
        _session(DateTime(2026, 9, 6, 10), 300), // 窗口前一天
        _session(DateTime(2026, 9, 14, 10), 300), // 明天
        _session(DateTime(2026, 9, 13, 10), 60),
      ], now: now, window: PracticeStatsWindow.last7);
      expect(bars.last.total, const Duration(seconds: 60));
      expect(
        bars.fold(Duration.zero, (sum, bar) => sum + bar.total),
        const Duration(seconds: 60),
      );
    });
  });

  group('每日合计', () {
    test('空日为零且保留在窗口内', () {
      final bars = dailyPracticeBars([
        _session(DateTime(2026, 9, 9, 10), 120),
        _session(DateTime(2026, 9, 13, 10), 60),
      ], now: now, window: PracticeStatsWindow.last7);
      expect(bars[0].total, Duration.zero); // 09-07
      expect(bars[1].total, Duration.zero); // 09-08
      expect(bars[2].total, const Duration(seconds: 120)); // 09-09
      expect(bars[6].total, const Duration(seconds: 60)); // 09-13
    });

    test('柱高 = 当天全部舞墙钟秒之和（同舞多条、多舞合并）', () {
      final bars = dailyPracticeBars([
        _session(DateTime(2026, 9, 13, 10), 100, videoId: 'a'),
        _session(DateTime(2026, 9, 13, 11), 200, videoId: 'a'),
        _session(DateTime(2026, 9, 13, 12), 50, videoId: 'b'),
      ], now: now, window: PracticeStatsWindow.last7);
      expect(bars.last.total, const Duration(seconds: 350));
    });

    test('跨月归日：月末与月初各归自己的柱', () {
      final bars = dailyPracticeBars([
        _session(DateTime(2026, 2, 28, 23), 100),
        _session(DateTime(2026, 3, 1, 0), 200),
      ], now: DateTime(2026, 3, 2, 9), window: PracticeStatsWindow.last7);
      expect(bars[4].day, DateTime(2026, 2, 28));
      expect(bars[4].total, const Duration(seconds: 100));
      expect(bars[5].day, DateTime(2026, 3, 1));
      expect(bars[5].total, const Duration(seconds: 200));
    });
  });

  group('当天明细行归一最大值', () {
    test('两种单位下的最大值：时长取微秒、场次取场次数', () {
      final detail = dailyPracticeDetail([
        _session(DateTime(2026, 9, 13, 10), 100, videoId: 'a', song: 'Alpha'),
        _session(DateTime(2026, 9, 13, 11), 300, videoId: 'b', song: 'Beta'),
        _session(DateTime(2026, 9, 13, 12), 60, videoId: 'a', song: 'Alpha'),
      ], DateTime(2026, 9, 13));
      expect(
        dayDetailMaxValue(detail.dances, StatsMetric.time),
        const Duration(seconds: 300).inMicroseconds,
      );
      // a 两条记录并成两场。
      expect(dayDetailMaxValue(detail.dances, StatsMetric.count), 2);
    });

    test('空集合为 0', () {
      expect(dayDetailMaxValue(const [], StatsMetric.time), 0);
      expect(dayDetailMaxValue(const [], StatsMetric.count), 0);
    });
  });

  group('日下钻明细', () {
    test('按舞聚合、按时长降序，同舞多条合并', () {
      final detail = dailyPracticeDetail([
        _session(DateTime(2026, 9, 13, 10), 100, videoId: 'a', song: 'Alpha'),
        _session(DateTime(2026, 9, 13, 11), 200, videoId: 'b', song: 'Beta'),
        _session(DateTime(2026, 9, 13, 12), 50, videoId: 'a', song: 'Alpha'),
      ], DateTime(2026, 9, 13));
      expect(detail.day, DateTime(2026, 9, 13));
      expect(detail.total, const Duration(seconds: 350));
      expect(detail.dances, hasLength(2));
      expect(detail.dances[0].videoId, 'b');
      expect(detail.dances[0].total, const Duration(seconds: 200));
      expect(detail.dances[0].signature.song, 'Beta');
      expect(detail.dances[1].videoId, 'a');
      expect(detail.dances[1].total, const Duration(seconds: 150));
    });

    test('只取当天：其它日期不混入', () {
      final detail = dailyPracticeDetail([
        _session(DateTime(2026, 9, 12, 10), 100, videoId: 'a'),
        _session(DateTime(2026, 9, 13, 10), 60, videoId: 'b'),
      ], DateTime(2026, 9, 13));
      expect(detail.dances, hasLength(1));
      expect(detail.dances.single.videoId, 'b');
      expect(detail.total, const Duration(seconds: 60));
    });

    test('空日返回空明细', () {
      final detail = dailyPracticeDetail([
        _session(DateTime(2026, 9, 12, 10), 100),
      ], DateTime(2026, 9, 13));
      expect(detail.dances, isEmpty);
      expect(detail.total, Duration.zero);
    });

    test('当天 0 秒记录不冒充练过的舞', () {
      final detail = dailyPracticeDetail([
        _session(DateTime(2026, 9, 13, 10), 0, videoId: 'a'),
      ], DateTime(2026, 9, 13));
      expect(detail.dances, isEmpty);
      expect(detail.total, Duration.zero);
    });

    test('时长相同按 videoId 升序，结果稳定', () {
      final detail = dailyPracticeDetail([
        _session(DateTime(2026, 9, 13, 10), 60, videoId: 'z'),
        _session(DateTime(2026, 9, 13, 11), 60, videoId: 'a'),
      ], DateTime(2026, 9, 13));
      expect([for (final dance in detail.dances) dance.videoId], ['a', 'z']);
    });

    test('署名快照取当天最近一条记录，与输入次序无关', () {
      final detail = dailyPracticeDetail([
        _session(DateTime(2026, 9, 13, 11), 60, song: '新名'),
        _session(DateTime(2026, 9, 13, 9), 120, song: '旧名'),
      ], DateTime(2026, 9, 13));
      expect(detail.dances.single.signature.song, '新名');
      expect(detail.dances.single.total, const Duration(seconds: 180));
    });
  });

  group('练习场次口径', () {
    test('一场 = 一条有效会话记录：并入后的同日多条播放记为一场', () {
      // 存储层已把同日同舞同署名、间隔 <5 分钟的播放并入同一条记录；
      // 这里钉死聚合侧口径：一条记录记一场。
      final counts = dailyPracticeSessionCounts([
        _session(DateTime(2026, 9, 13, 10), 100),
        _session(DateTime(2026, 9, 12, 10), 100),
      ]);
      expect(counts[DateTime(2026, 9, 13)], 1);
      expect(counts[DateTime(2026, 9, 12)], 1);
    });

    test('同日改名的两次练习（两条记录）记两场', () {
      final counts = dailyPracticeSessionCounts([
        _session(DateTime(2026, 9, 13, 9), 100, song: '旧名'),
        _session(DateTime(2026, 9, 13, 10), 100, song: '新名'),
      ]);
      expect(counts[DateTime(2026, 9, 13)], 2);
    });

    test('跨零点按午夜拆成的两条记录各归各日、各记一场', () {
      final counts = dailyPracticeSessionCounts([
        _session(DateTime(2026, 9, 12, 23, 50), 100),
        _session(DateTime(2026, 9, 13, 0, 5), 100),
      ]);
      expect(counts[DateTime(2026, 9, 12)], 1);
      expect(counts[DateTime(2026, 9, 13)], 1);
    });

    test('只数有效记录：0 秒记录不记场次', () {
      final counts = dailyPracticeSessionCounts([
        _session(DateTime(2026, 9, 13, 10), 0),
        _session(DateTime(2026, 9, 13, 11), 100),
      ]);
      expect(counts[DateTime(2026, 9, 13)], 1);
    });

    test('柱同时携带时长与场次两个口径', () {
      final bars = dailyPracticeBars([
        _session(DateTime(2026, 9, 13, 10), 100, videoId: 'a'),
        _session(DateTime(2026, 9, 13, 11), 200, videoId: 'b'),
        _session(DateTime(2026, 9, 13, 12), 0, videoId: 'c'),
      ], now: now, window: PracticeStatsWindow.last7);
      expect(bars.last.total, const Duration(seconds: 300));
      expect(bars.last.sessions, 2);
      expect(bars.first.sessions, 0);
    });

    test('明细行同时携带时长与场次，日合计亦然', () {
      final detail = dailyPracticeDetail([
        _session(DateTime(2026, 9, 13, 10), 100, videoId: 'a', song: 'Alpha'),
        _session(DateTime(2026, 9, 13, 11), 200, videoId: 'b', song: 'Beta'),
        _session(DateTime(2026, 9, 13, 12), 50, videoId: 'a', song: 'Alpha'),
        _session(DateTime(2026, 9, 13, 13), 0, videoId: 'a', song: 'Alpha'),
      ], DateTime(2026, 9, 13));
      expect(detail.total, const Duration(seconds: 350));
      expect(detail.sessions, 3);
      expect(detail.dances[0].videoId, 'b');
      expect(detail.dances[0].sessions, 1);
      expect(detail.dances[1].videoId, 'a');
      expect(detail.dances[1].sessions, 2);
    });

    test('场次与时长是两个口径：场次多不等于时长长', () {
      final detail = dailyPracticeDetail([
        _session(DateTime(2026, 9, 13, 10), 10, videoId: 'a', song: 'Alpha'),
        _session(DateTime(2026, 9, 13, 11), 10, videoId: 'a', song: 'Alpha'),
        _session(DateTime(2026, 9, 13, 12), 60, videoId: 'b', song: 'Beta'),
      ], DateTime(2026, 9, 13));
      // 明细按当前单位排序（默认按时长）：时长长者在前面。
      expect(detail.dances.first.videoId, 'b');
    });
  });
}
