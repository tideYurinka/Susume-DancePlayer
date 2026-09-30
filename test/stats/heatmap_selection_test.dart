import 'package:dance_learning_app/stats/practice_stats_daily.dart';
import 'package:dance_learning_app/stats/heatmap_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('格子坐标 ↔ 索引换算', () {
    test('落在格中心读出所在列与行', () {
      final index = heatmapCellIndexAt(
        const Offset(0.5 * heatmapCellPitch + 1, 3 * heatmapCellPitch + 1),
        columnCount: 53,
        rowCount: 7,
      );
      expect(index.column, 0);
      expect(index.row, 3);
    });

    test('第 10 列第 6 行（周六）读出 (10, 6)', () {
      final index = heatmapCellIndexAt(
        const Offset(10 * heatmapCellPitch + 6, 6 * heatmapCellPitch + 6),
        columnCount: 53,
        rowCount: 7,
      );
      expect(index.column, 10);
      expect(index.row, 6);
    });

    test('首列钳制：负坐标（含滚动过头）落到第 0 列', () {
      final index = heatmapCellIndexAt(
        const Offset(-30, 0),
        columnCount: 53,
        rowCount: 7,
      );
      expect(index.column, 0);
      expect(index.row, 0);
    });

    test('末列钳制：越界坐标落到最后一列、最后一行', () {
      final index = heatmapCellIndexAt(
        const Offset(53 * heatmapCellPitch, 7 * heatmapCellPitch),
        columnCount: 53,
        rowCount: 7,
      );
      expect(index.column, 52);
      expect(index.row, 6);
    });
  });

  group('气泡水平偏移 + 钳制', () {
    // 卡片宽 360：网格前置（内边距 + 星期标签列）40，气泡宽 120。
    const cardWidth = 360.0;
    const leading = 40.0;
    const bubbleWidth = 120.0;
    const margin = 8.0;

    double left({
      double cellCenterX = 10 * heatmapCellPitch + 6,
      double scrollOffset = 0,
    }) =>
        heatmapBubbleLeftInCard(
          cellCenterX: cellCenterX,
          scrollOffset: scrollOffset,
          leadingInset: leading,
          bubbleWidth: bubbleWidth,
          cardWidth: cardWidth,
        );

    test('居中放得下：气泡中心对准格子中心', () {
      // 格中心内容坐标 146，减滚动 0 加前置 40 = 卡内 186；居中左缘 126。
      expect(left(), 186 - bubbleWidth / 2);
    });

    test('滚动偏移参与换算：滚动 28px 气泡随格左移 28px', () {
      expect(left(scrollOffset: 28), 186 - 28 - bubbleWidth / 2);
    });

    test('左缘钳制：首列的气泡不越出卡片左缘', () {
      final actual = left(cellCenterX: 1 * heatmapCellPitch, scrollOffset: 0);
      expect(actual, margin);
    });

    test('右缘钳制：末列的气泡夹在卡片内', () {
      final actual = heatmapBubbleLeftInCard(
        cellCenterX: 52 * heatmapCellPitch,
        scrollOffset: 0,
        leadingInset: leading,
        bubbleWidth: bubbleWidth,
        cardWidth: cardWidth,
      );
      expect(actual, cardWidth - margin - bubbleWidth);
    });

    test('气泡比卡片还宽：贴左缘留边', () {
      final actual = heatmapBubbleLeftInCard(
        cellCenterX: cardWidth / 2,
        scrollOffset: 0,
        leadingInset: 0,
        bubbleWidth: cardWidth,
        cardWidth: cardWidth,
      );
      expect(actual, margin);
    });
  });

  group('气泡文案', () {
    final day = DateTime(2026, 7, 10);

    test('按时间：7月10日 · 练习 42:30', () {
      expect(
        heatmapBubbleText(
          StatsMetric.time,
          day,
          total: const Duration(minutes: 42, seconds: 30),
          sessions: 1,
        ),
        '7月10日 · 练习 42:30',
      );
    });

    test('按次数：7月10日 · 练习 3 次', () {
      expect(
        heatmapBubbleText(StatsMetric.count, day, total: Duration.zero, sessions: 3),
        '7月10日 · 练习 3 次',
      );
    });

    test('无练习日：7月10日 · 这天没有练习', () {
      expect(
        heatmapBubbleText(StatsMetric.time, day, total: Duration.zero, sessions: 0),
        '7月10日 · 这天没有练习',
      );
      expect(
        heatmapBubbleText(StatsMetric.count, day, total: Duration.zero, sessions: 0),
        '7月10日 · 这天没有练习',
      );
    });
  });
}
