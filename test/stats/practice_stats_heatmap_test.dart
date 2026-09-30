import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/stats/practice_stats_daily.dart';
import 'package:dance_learning_app/stats/practice_stats_heatmap.dart';
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

  HeatmapCell cellAt(List<HeatmapWeek> weeks, DateTime day) =>
      weeks.expand((week) => week.cells).firstWhere((cell) => cell.day == day);

  group('热力图窗口', () {
    test('滚动近 53 周：53 列、每列 7 格', () {
      final weeks = yearHeatmapWeeks(const [], now: now);
      expect(weeks, hasLength(53));
      for (final week in weeks) {
        expect(week.cells, hasLength(7));
      }
    });

    test('首列 = 本周一 − 52 周，末列 = 本周一，今天落在末列周日', () {
      final weeks = yearHeatmapWeeks(const [], now: now);
      expect(weeks.first.start, DateTime(2025, 9, 8));
      expect(weeks.last.start, DateTime(2026, 9, 7));
      expect(weeks.last.cells.first.day, DateTime(2026, 9, 7));
      expect(weeks.last.cells.last.day, DateTime(2026, 9, 13));
      expect(cellAt(weeks, DateTime(2026, 9, 13)).day, DateTime(2026, 9, 13));
    });

    test('每周起始日固定为周一，格序为周一→周日无缺口', () {
      final weeks = yearHeatmapWeeks(const [], now: now);
      for (final week in weeks) {
        expect(week.start.weekday, DateTime.monday);
        for (var i = 0; i < 7; i++) {
          expect(
            week.cells[i].day,
            DateTime(week.start.year, week.start.month, week.start.day + i),
          );
        }
      }
    });

    test('跨年边界：窗口首列落在上一年，末列跨到下一年', () {
      final weeks = yearHeatmapWeeks(
        const [],
        now: DateTime(2026, 1, 2, 9), // 周五
      );
      expect(weeks.first.start, DateTime(2024, 12, 30));
      expect(weeks.last.start, DateTime(2025, 12, 29));
      expect(weeks.last.cells[4].day, DateTime(2026, 1, 2));
      expect(weeks.last.cells.last.day, DateTime(2026, 1, 4));
      expect(cellAt(weeks, DateTime(2026, 1, 1)).day, DateTime(2026, 1, 1));
    });

    test('今天所在周之后的格子为空，且未来记录不入格', () {
      // 今天为周五：本周六、周日是本周内的未来格。
      final weeks = yearHeatmapWeeks([
        _session(DateTime(2026, 9, 12, 10), 300), // 明天
      ], now: DateTime(2026, 9, 11, 21));
      expect(weeks.last.start, DateTime(2026, 9, 7));
      expect(cellAt(weeks, DateTime(2026, 9, 12)).total, Duration.zero);
      expect(cellAt(weeks, DateTime(2026, 9, 12)).level, 0);
      expect(cellAt(weeks, DateTime(2026, 9, 12)).isFuture, isTrue);
      expect(cellAt(weeks, DateTime(2026, 9, 11)).day, DateTime(2026, 9, 11));
      expect(cellAt(weeks, DateTime(2026, 9, 11)).isFuture, isFalse);
      expect(cellAt(weeks, DateTime(2026, 9, 10)).isFuture, isFalse);
    });

    test('窗口外（53 周之前）的记录不入格', () {
      final weeks = yearHeatmapWeeks([
        _session(DateTime(2025, 9, 7, 10), 600),
      ], now: now);
      expect(
        weeks
            .expand((week) => week.cells)
            .fold(Duration.zero, (sum, cell) => sum + cell.total),
        Duration.zero,
      );
    });
  });

  group('每日时长与空格', () {
    test('无练习的记录集合：全部格子为零且档 0', () {
      final weeks = yearHeatmapWeeks(const [], now: now);
      for (final cell in weeks.expand((week) => week.cells)) {
        expect(cell.total, Duration.zero);
        expect(cell.level, 0);
      }
    });

    test('与柱状图同源：同一天的柱高与热力格合计相等', () {
      final records = [
        _session(DateTime(2026, 9, 13, 10), 100, videoId: 'a'),
        _session(DateTime(2026, 9, 13, 11), 200, videoId: 'b'),
      ];
      final bars = dailyPracticeBars(
        records,
        now: now,
        window: PracticeStatsWindow.last7,
      );
      final weeks = yearHeatmapWeeks(records, now: now);
      expect(bars.last.day, DateTime(2026, 9, 13));
      expect(cellAt(weeks, DateTime(2026, 9, 13)).total, bars.last.total);
    });

    test('同一天多条与多舞合并为当日墙钟秒之和', () {
      final weeks = yearHeatmapWeeks([
        _session(DateTime(2026, 9, 13, 10), 100, videoId: 'a'),
        _session(DateTime(2026, 9, 13, 11), 200, videoId: 'a'),
        _session(DateTime(2026, 9, 13, 12), 50, videoId: 'b'),
      ], now: now);
      expect(
        cellAt(weeks, DateTime(2026, 9, 13)).total,
        const Duration(seconds: 350),
      );
    });

    test('跨月归日：月末与月初各归自己的格', () {
      final weeks = yearHeatmapWeeks([
        _session(DateTime(2026, 8, 31, 23), 100),
        _session(DateTime(2026, 9, 1, 0), 200),
      ], now: now);
      expect(
        cellAt(weeks, DateTime(2026, 8, 31)).total,
        const Duration(seconds: 100),
      );
      expect(
        cellAt(weeks, DateTime(2026, 9, 1)).total,
        const Duration(seconds: 200),
      );
    });
  });

  group('动态分档', () {
    // 按时间的边界单位是微秒（与 Duration 同尺）。
    int us(int seconds) => seconds * 1000 * 1000;

    // 2026-09-07（周一）到 2026-09-13（周日）共 7 天，全部在窗口内。
    final records = [
      _session(DateTime(2026, 9, 7, 10), 100),
      _session(DateTime(2026, 9, 8, 10), 200),
      _session(DateTime(2026, 9, 9, 10), 300),
      _session(DateTime(2026, 9, 10, 10), 400),
    ];

    test('三档边界取 P25/P50/P75 位置上的实际观测值（最近秩，不插值）', () {
      final bounds = heatmapQuantileBounds(records, now: now);
      // 非零日升序 [100, 200, 300, 400]：ceil(0.25*4)=1、ceil(0.5*4)=2、
      // ceil(0.75*4)=3 → 实测值 100、200、300。
      expect(bounds, [us(100), us(200), us(300)]);
    });

    test('边界可重复：重复值让部分档位自然空缺，不额外造档', () {
      final bounds = heatmapQuantileBounds([
        _session(DateTime(2026, 9, 7, 10), 100),
        _session(DateTime(2026, 9, 8, 10), 100),
        _session(DateTime(2026, 9, 9, 10), 500),
        _session(DateTime(2026, 9, 10, 10), 500),
      ], now: now);
      expect(bounds, [us(100), us(100), us(500)]);
      // 100 → 严格小于它的边界 0 个 → 档 1；500 = P75 边界 → 2 个 → 档 3。
      expect(heatmapLevelFor(us(100), bounds), 1);
      expect(heatmapLevelFor(us(500), bounds), 3);
    });

    test('全部非零日同值：统一落最低非零档，不伪造梯度', () {
      final same = [
        _session(DateTime(2026, 9, 7, 10), 300),
        _session(DateTime(2026, 9, 8, 10), 300),
      ];
      final bounds = heatmapQuantileBounds(same, now: now);
      expect(bounds, [us(300), us(300), us(300)]);
      final weeks = yearHeatmapWeeks(same, now: now);
      expect(cellAt(weeks, DateTime(2026, 9, 7)).level, 1);
      expect(cellAt(weeks, DateTime(2026, 9, 8)).level, 1);
    });

    test('档位 = 1 + 严格小于该值的边界个数（上限 4）', () {
      final bounds = heatmapQuantileBounds(records, now: now);
      expect(heatmapLevelFor(0, bounds), 0);
      expect(heatmapLevelFor(us(100), bounds), 1);
      expect(heatmapLevelFor(us(150), bounds), 2);
      expect(heatmapLevelFor(us(250), bounds), 3);
      expect(heatmapLevelFor(us(900), bounds), 4);
    });

    test('窗口内无练习：边界为空表，全部格子档 0', () {
      expect(heatmapQuantileBounds(const [], now: now), isEmpty);
      final weeks = yearHeatmapWeeks(const [], now: now);
      for (final cell in weeks.expand((week) => week.cells)) {
        expect(cell.level, 0);
      }
    });

    test('0 秒记录与非零日一起不算进分位集合', () {
      final bounds = heatmapQuantileBounds([
        _session(DateTime(2026, 9, 7, 10), 0),
        _session(DateTime(2026, 9, 8, 10), 100),
        _session(DateTime(2026, 9, 9, 10), 300),
      ], now: now);
      // 非零集合 [100, 300]：三个分位都落在其中的实测值上。
      expect(bounds, [us(100), us(100), us(300)]);
    });

    test('按次数：分位集合是场次、边界为整数场次', () {
      final bounds = heatmapQuantileBounds([
        _session(DateTime(2026, 9, 7, 10), 10),
        _session(DateTime(2026, 9, 8, 10), 10),
        _session(DateTime(2026, 9, 8, 11), 10),
        _session(DateTime(2026, 9, 8, 12), 10),
        _session(DateTime(2026, 9, 9, 10), 10),
      ], now: now, metric: StatsMetric.count);
      // 场次集合 [1, 1, 3]：P25=1、P50=1、P75=3。
      expect(bounds, [1, 1, 3]);
    });

    test('窗口外的记录不入分位集合', () {
      final outside = [
        ...records,
        _session(DateTime(2025, 9, 7, 10), 99900),
      ];
      expect(heatmapQuantileBounds(outside, now: now), [
        us(100),
        us(200),
        us(300),
      ]);
    });

    test('未来日不入分位集合、不入合计', () {
      // 今天是周五（2026-09-11）：周六、周日是未来日。
      final friday = DateTime(2026, 9, 11, 21);
      final weeks = yearHeatmapWeeks([
        _session(DateTime(2026, 9, 12, 10), 500),
        _session(DateTime(2026, 9, 10, 10), 100),
        _session(DateTime(2026, 9, 9, 10), 300),
      ], now: friday);
      final visible = weeks
          .expand((week) => week.cells)
          .where((cell) => !cell.isFuture)
          .map((cell) => cell.total.inSeconds)
          .where((seconds) => seconds > 0)
          .toList()
        ..sort();
      expect(visible, [100, 300]);
      expect(
        heatmapWindowTotal(weeks).total,
        const Duration(seconds: 400),
      );
      // 未来日的场次也不进合计。
      expect(heatmapWindowTotal(weeks).sessions, 2);
    });
  });

  group('色深分档（动态）', () {
    test('0 秒为空格（档 0），非零日按窗口内相对位置分档', () {
      final weeks = yearHeatmapWeeks([
        _session(DateTime(2026, 9, 7, 10), 0),
        _session(DateTime(2026, 9, 8, 10), 10),
        _session(DateTime(2026, 9, 9, 10), 600),
        _session(DateTime(2026, 9, 10, 10), 1800),
        _session(DateTime(2026, 9, 11, 10), 3600),
      ], now: now);
      // 非零升序 [10, 600, 1800, 3600] → 边界 [10, 600, 1800]。
      expect(cellAt(weeks, DateTime(2026, 9, 7)).level, 0);
      expect(cellAt(weeks, DateTime(2026, 9, 8)).level, 1);
      expect(cellAt(weeks, DateTime(2026, 9, 9)).level, 2);
      expect(cellAt(weeks, DateTime(2026, 9, 10)).level, 3);
      expect(cellAt(weeks, DateTime(2026, 9, 11)).level, 4);
    });

    test('档界随窗口内分布浮动：加一天最长日把其它日压向低档', () {
      final alone = yearHeatmapWeeks([
        _session(DateTime(2026, 9, 9, 10), 900),
      ], now: now);
      final withBigDay = yearHeatmapWeeks([
        _session(DateTime(2026, 9, 13, 10), 7200),
        _session(DateTime(2026, 9, 9, 10), 900),
      ], now: now);
      // 单日窗口：自己就是全部三个边界 → 档 1；加入更大的日子后它落到档 1，
      // 大日子 = P75 边界 → 严格小于它的边界 2 个 → 档 3。
      expect(cellAt(alone, DateTime(2026, 9, 9)).level, 1);
      expect(cellAt(withBigDay, DateTime(2026, 9, 9)).level, 1);
      expect(cellAt(withBigDay, DateTime(2026, 9, 13)).level, 3);
    });

    test('显式传入边界时按给定边界定档', () {
      final bounds = [1, 2, 3];
      final weeks = yearHeatmapWeeks([
        _session(DateTime(2026, 9, 9, 10), 30),
      ], now: now, bounds: bounds);
      // 30 秒（微秒）严格大于全部边界 → 档 4。
      expect(cellAt(weeks, DateTime(2026, 9, 9)).level, 4);
    });
  });

  group('单位口径', () {
    test('按次数：色深按窗口内场次的分位动态分档', () {
      final weeks = yearHeatmapWeeks([
        _session(DateTime(2026, 9, 7, 10), 0),
        _session(DateTime(2026, 9, 8, 10), 10),
        _session(DateTime(2026, 9, 8, 11), 10),
        _session(DateTime(2026, 9, 8, 12), 10),
        _session(DateTime(2026, 9, 9, 10), 10),
      ], now: now, metric: StatsMetric.count);
      // 场次集合 [1, 3] → 边界 [1, 1, 3]：3 场档 3、1 场档 1、空档 0。
      expect(cellAt(weeks, DateTime(2026, 9, 7)).sessions, 0);
      expect(cellAt(weeks, DateTime(2026, 9, 8)).level, 3);
      expect(cellAt(weeks, DateTime(2026, 9, 9)).level, 1);
    });

    test('按时间：档由时长决定，与场次无关', () {
      final weeks = yearHeatmapWeeks([
        // 三个短场次共 90 秒；窗口内还有一天 10 秒。
        _session(DateTime(2026, 9, 8, 10), 10),
        _session(DateTime(2026, 9, 9, 10), 30),
        _session(DateTime(2026, 9, 9, 11), 30),
        _session(DateTime(2026, 9, 9, 12), 30),
      ], now: now, metric: StatsMetric.time);
      // 时长集合 [10, 90] 秒 → 边界 [10, 10, 90] 秒：90 秒档 3、10 秒档 1。
      expect(cellAt(weeks, DateTime(2026, 9, 9)).level, 3);
      expect(cellAt(weeks, DateTime(2026, 9, 8)).level, 1);
      expect(cellAt(weeks, DateTime(2026, 9, 9)).sessions, 3);
    });

    test('0 秒记录不计场次：按次数仍是空格', () {
      final weeks = yearHeatmapWeeks([
        _session(DateTime(2026, 9, 9, 10), 0),
      ], now: now, metric: StatsMetric.count);
      expect(cellAt(weeks, DateTime(2026, 9, 9)).level, 0);
    });
  });
}
