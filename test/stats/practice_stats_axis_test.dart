import 'package:dance_learning_app/stats/practice_stats_axis.dart';
import 'package:dance_learning_app/stats/practice_stats_daily.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('y 轴刻度（按时间，分钟）', () {
    test('全零窗口：最小步长、上界为最小步长，刻度只有 0 与上界', () {
      final axis = barChartAxis(maxValue: 0, metric: StatsMetric.time);
      expect(axis.step, 1);
      expect(axis.upperBound, 1);
      expect(axis.ticks, [0, 1]);
    });

    test('极小值 1 分钟：步长 1、上界 1', () {
      final axis = barChartAxis(maxValue: 1, metric: StatsMetric.time);
      expect(axis.step, 1);
      expect(axis.upperBound, 1);
      expect(axis.ticks, [0, 1]);
    });

    test('恰好 5 档（区间 5 个）：5 分钟取步长 1、上界 5，共 6 条刻度值', () {
      final axis = barChartAxis(maxValue: 5, metric: StatsMetric.time);
      expect(axis.step, 1);
      expect(axis.upperBound, 5);
      expect(axis.ticks, [0, 1, 2, 3, 4, 5]);
    });

    test('6 分钟：步长 1 会 6 档超限，改取步长 2、上界 6', () {
      final axis = barChartAxis(maxValue: 6, metric: StatsMetric.time);
      expect(axis.step, 2);
      expect(axis.upperBound, 6);
      expect(axis.ticks, [0, 2, 4, 6]);
    });

    test('13 分钟：步长 5、上界 15', () {
      final axis = barChartAxis(maxValue: 13, metric: StatsMetric.time);
      expect(axis.step, 5);
      expect(axis.upperBound, 15);
      expect(axis.ticks, [0, 5, 10, 15]);
    });

    test('90 分钟：步长 30、上界 90', () {
      final axis = barChartAxis(maxValue: 90, metric: StatsMetric.time);
      expect(axis.step, 30);
      expect(axis.upperBound, 90);
      expect(axis.ticks, [0, 30, 60, 90]);
    });

    test('极大值 400 分钟：小步长全部超限，取 120、上界 480', () {
      final axis = barChartAxis(maxValue: 400, metric: StatsMetric.time);
      expect(axis.step, 120);
      expect(axis.upperBound, 480);
      expect(axis.ticks, [0, 120, 240, 360, 480]);
    });

    test('上界不小于最大值：91 分钟时上界盖住最大值', () {
      final axis = barChartAxis(maxValue: 91, metric: StatsMetric.time);
      expect(axis.upperBound, greaterThanOrEqualTo(91));
    });
  });

  group('y 轴刻度（按次数，场次）', () {
    test('1 场：步长 1、上界 1', () {
      final axis = barChartAxis(maxValue: 1, metric: StatsMetric.count);
      expect(axis.step, 1);
      expect(axis.upperBound, 1);
      expect(axis.ticks, [0, 1]);
    });

    test('7 场：步长 1 会 7 档超限，改取步长 2、上界 8', () {
      final axis = barChartAxis(maxValue: 7, metric: StatsMetric.count);
      expect(axis.step, 2);
      expect(axis.upperBound, 8);
      expect(axis.ticks, [0, 2, 4, 6, 8]);
    });

    test('60 场：步长 20、上界 60', () {
      final axis = barChartAxis(maxValue: 60, metric: StatsMetric.count);
      expect(axis.step, 20);
      expect(axis.upperBound, 60);
      expect(axis.ticks, [0, 20, 40, 60]);
    });

    test('全零窗口按次数：最小步长、上界 1', () {
      final axis = barChartAxis(maxValue: 0, metric: StatsMetric.count);
      expect(axis.step, 1);
      expect(axis.upperBound, 1);
      expect(axis.ticks, [0, 1]);
    });
  });

  group('由窗口逐日柱取轴（barChartAxisForBars）', () {
    DailyPracticeBar bar(
      DateTime day, {
      Duration total = Duration.zero,
      int sessions = 0,
    }) => DailyPracticeBar(day: day, total: total, sessions: sessions);

    test('按时长：轴以分钟取档，向上取整保证上界盖住真实柱值', () {
      // 窗口最长 290s → 上取整按 5 分钟取档。
      final bars = [
        bar(DateTime(2026, 9, 13), total: const Duration(seconds: 290)),
        bar(DateTime(2026, 9, 12), total: const Duration(seconds: 60)),
      ];
      final axis = barChartAxisForBars(bars, StatsMetric.time);
      expect(axis.upperBound, 5);
      expect(axis.upperInValue(StatsMetric.time), 5 * 60 * 1000000);
    });

    test('按次数：轴直接取场次数为档', () {
      final bars = [
        bar(
          DateTime(2026, 9, 13),
          total: const Duration(minutes: 10),
          sessions: 1,
        ),
        bar(
          DateTime(2026, 9, 12),
          total: const Duration(minutes: 20),
          sessions: 2,
        ),
      ];
      final axis = barChartAxisForBars(bars, StatsMetric.count);
      expect(axis.step, 1);
      expect(axis.upperBound, 2);
      expect(axis.upperInValue(StatsMetric.count), 2);
    });

    test('窗口切换后上界重算：同一批数据下小窗口上界变小', () {
      final longAgo = bar(
        DateTime(2026, 6, 20),
        total: const Duration(minutes: 90),
      );
      final recent = bar(
        DateTime(2026, 9, 13),
        total: const Duration(minutes: 5),
      );
      // 近 90 天窗口：最大 90 分 → 步长 30、上界 90。
      final wide = barChartAxisForBars([longAgo, recent], StatsMetric.time);
      expect(wide.step, 30);
      expect(wide.upperBound, 90);
      expect(wide.ticks, [0, 30, 60, 90]);

      // 只留近 7 天那根：最大 5 分 → 步长 1、上界 5。
      final narrow = barChartAxisForBars([recent], StatsMetric.time);
      expect(narrow.step, 1);
      expect(narrow.upperBound, 5);
      expect(narrow.ticks, [0, 1, 2, 3, 4, 5]);
    });

    test('全零窗口：最小步长单档', () {
      final axis = barChartAxisForBars(
        [bar(DateTime(2026, 9, 13))],
        StatsMetric.time,
      );
      expect(axis.step, 1);
      expect(axis.upperBound, 1);
    });
  });
}
