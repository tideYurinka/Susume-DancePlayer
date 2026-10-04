// 柱状图气泡二维定位与避让纯件测试：气泡纵向中心跟手并钳在
// 绘图区内，横向朝远离目标柱的方向避让、气泡矩形与目标柱矩形不相交。
import 'package:dance_learning_app/stats/heatmap_selection.dart';
import 'package:flutter_test/flutter_test.dart';

const plotWidth = 280.0;
const plotHeight = 106.0;
const bubbleWidth = 120.0;
const bubbleHeight = 48.0;

({double left, double top}) position({
  double fingerY = plotHeight / 2,
  double width = bubbleWidth,
  double height = bubbleHeight,
  int targetIndex = 1,
  int barCount = 7,
}) => barChartBubblePosition(
  fingerY: fingerY,
  bubbleWidth: width,
  bubbleHeight: height,
  plotWidth: plotWidth,
  plotHeight: plotHeight,
  targetIndex: targetIndex,
  barCount: barCount,
);

void main() {
  group('横向避让：气泡矩形与目标柱矩形不相交', () {
    test('目标柱在左半 → 气泡整体靠右', () {
      final r = position(targetIndex: 1, barCount: 7);
      final columnLeft = plotWidth / 7 * 1;
      final columnWidth = plotWidth / 7;
      expect(r.left, columnLeft + columnWidth);
      expect(r.left + bubbleWidth, lessThanOrEqualTo(plotWidth));
    });

    test('目标柱在右半 → 气泡整体靠左', () {
      final r = position(targetIndex: 5, barCount: 7);
      final columnLeft = plotWidth / 7 * 5;
      expect(r.left + bubbleWidth, columnLeft);
      expect(r.left, greaterThanOrEqualTo(0));
    });

    test('首列（最左）→ 气泡在柱右侧', () {
      final r = position(targetIndex: 0, barCount: 7);
      final columnWidth = plotWidth / 7;
      expect(r.left, columnWidth);
    });

    test('末列（最右）→ 气泡在柱左侧且不出绘图区', () {
      final r = position(targetIndex: 6, barCount: 7);
      final columnLeft = plotWidth / 7 * 6;
      expect(r.left + bubbleWidth, columnLeft);
      expect(r.left, greaterThanOrEqualTo(0));
    });

    test('中部柱（恰在正中）→ 有确定一侧（左），仍不相交', () {
      final r = position(targetIndex: 3, barCount: 7);
      final columnLeft = plotWidth / 7 * 3;
      expect(r.left + bubbleWidth, columnLeft);
    });

    test('气泡放不下（左右都不够宽）→ 仍钳在绘图区内、无负值', () {
      final r = position(targetIndex: 3, barCount: 7, width: plotWidth - 4);
      expect(r.left, inInclusiveRange(0, plotWidth - (plotWidth - 4)));
    });

    test('气泡比绘图区还宽 → 贴左缘，不产生负值或溢出', () {
      final r = position(targetIndex: 0, width: plotWidth + 50);
      expect(r.left, 0);
    });
  });

  group('纵向跟手：中心对齐手指 y 并钳在绘图区内', () {
    test('手指在绘图区中部 → 气泡中心对齐手指 y', () {
      final r = position(fingerY: 60);
      expect(r.top + bubbleHeight / 2, 60);
    });

    test('手指在顶部 → 钳在上缘（top = 0）', () {
      final r = position(fingerY: 0);
      expect(r.top, 0);
    });

    test('手指在底部 → 钳在下缘（不出绘图区）', () {
      final r = position(fingerY: plotHeight);
      expect(r.top + bubbleHeight, plotHeight);
    });

    test('手指 y 越出绘图区（负值 / 超下界）→ 钳在区内', () {
      expect(position(fingerY: -30).top, 0);
      expect(position(fingerY: plotHeight + 30).top + bubbleHeight, plotHeight);
    });

    test('气泡比绘图区还高 → top 取 0，确定取值、无负值', () {
      final r = position(height: plotHeight + 20);
      expect(r.top, 0);
      expect(r.left, inInclusiveRange(0, plotWidth));
    });
  });
}
