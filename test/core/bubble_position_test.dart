// 气泡二维定位与避让纯件测试：全 App 一条规则、两处调用——
// 统计页柱状图传目标柱的柱体矩形，舞详情练习分布图传选中段的像素区间矩形。
// 纵向中心对齐手指 y 并钳在绘图区内，横向朝远离目标的一侧避让、与该侧不留
// 缝；左右都放不下时钳在绘图区内为止（不相交让位于不越界）。
import 'package:dance_learning_app/core/bubble_position.dart';
import 'package:flutter/widgets.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';

const plotWidth = 264.0;
const plotHeight = 140.0;
const bubbleWidth = 120.0;
const bubbleHeight = 40.0;

/// 目标矩形：`[left, right)` 横向区间 + 覆盖气泡纵向跨度的 y（被避让的读数
/// 就在这一带，不相交断言才有意义）。
Rect target(double left, double right) => Rect.fromLTRB(
  left,
  plotHeight / 2 - bubbleHeight / 2,
  right,
  plotHeight / 2 + bubbleHeight / 2,
);

({double left, double top}) position({
  double fingerY = plotHeight / 2,
  double width = bubbleWidth,
  double height = bubbleHeight,
  required double targetLeft,
  required double targetRight,
}) => avoidingBubblePosition(
  fingerY: fingerY,
  bubbleWidth: width,
  bubbleHeight: height,
  plotWidth: plotWidth,
  plotHeight: plotHeight,
  target: target(targetLeft, targetRight),
);

bool intersects(
  ({double left, double top}) bubble,
  Rect target, {
  double width = bubbleWidth,
  double height = bubbleHeight,
}) =>
    bubble.left < target.right &&
    target.left < bubble.left + width &&
    bubble.top < target.bottom &&
    target.top < bubble.top + height;

void main() {
  group('横向避让：气泡矩形与目标矩形不相交', () {
    test('目标中心在绘图区左半 → 气泡整体靠右，贴目标右缘不留缝', () {
      final r = position(targetLeft: 40, targetRight: 80);
      expect(r.left, 80);
      expect(r.left + bubbleWidth, lessThanOrEqualTo(plotWidth));
    });

    test('目标中心在绘图区右半 → 气泡整体靠左，贴目标左缘不留缝', () {
      final r = position(targetLeft: 180, targetRight: 220);
      expect(r.left + bubbleWidth, 180);
      expect(r.left, greaterThanOrEqualTo(0));
    });

    test('目标居中（恰在正中）→ 有确定一侧（左），仍不相交', () {
      final r = position(targetLeft: 122, targetRight: 142);
      expect(r.left + bubbleWidth, 122);
      expect(intersects(r, target(122, 142)), isFalse);
    });

    test('目标宽到只有一侧放得下 → 贴该侧边缘、不相交', () {
      final r = position(targetLeft: 40, targetRight: 110);
      expect(r.left, 110);
      expect(intersects(r, target(40, 110)), isFalse);
      expect(r.left + bubbleWidth, lessThanOrEqualTo(plotWidth));
    });
  });

  group('左右都放不下：不相交让位于不越界', () {
    test('目标宽到气泡两边都放不下 → 仍完整落在绘图区内（允许相交）', () {
      final r = position(targetLeft: 60, targetRight: 200);
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.left + bubbleWidth, lessThanOrEqualTo(plotWidth));
      expect(intersects(r, target(60, 200)), isTrue, reason: '前提：两侧都不够');
    });

    test('目标覆盖整个绘图区 → 气泡钳在绘图区内，无负值', () {
      final r = position(targetLeft: 0, targetRight: plotWidth);
      expect(r.left, 0);
      expect(r.left + bubbleWidth, lessThanOrEqualTo(plotWidth));
    });

    test('气泡比绘图区还宽 → 贴左缘，不产生负值', () {
      final r = position(
        targetLeft: 40,
        targetRight: 80,
        width: plotWidth + 50,
      );
      expect(r.left, 0);
      // 退化分支如实钉住：气泡比绘图区还宽时右缘必然越出（`maxLeft` 被
      // `max(0, ·)` 夹到 0）。这不是「钳在绘图区内」的反例——不越界以气泡
      // 放得下为前提，与统计页柱状图同款；调用侧靠气泡宽度与字号档绑定，
      // 详情页的实际气泡（三段文案）在支持的字号档内窄于绘图区。
      expect(r.left + plotWidth + 50, greaterThan(plotWidth));
    });
  });

  group('纵向跟手：中心对齐手指 y 并钳在绘图区内', () {
    test('手指在中部 → 气泡中心对齐手指 y', () {
      final r = position(fingerY: 60, targetLeft: 40, targetRight: 80);
      expect(r.top + bubbleHeight / 2, 60);
    });

    test('手指在顶部 / 底部 → 钳在绘图区内', () {
      expect(position(fingerY: 0, targetLeft: 40, targetRight: 80).top, 0);
      final bottom = position(
        fingerY: plotHeight,
        targetLeft: 40,
        targetRight: 80,
      );
      expect(bottom.top + bubbleHeight, plotHeight);
    });

    test('手指 y 越出绘图区（负值 / 超下界）→ 钳在区内', () {
      expect(position(fingerY: -30, targetLeft: 40, targetRight: 80).top, 0);
      final below = position(
        fingerY: plotHeight + 30,
        targetLeft: 40,
        targetRight: 80,
      );
      expect(below.top + bubbleHeight, plotHeight);
    });

    test('气泡比绘图区还高 → top 取 0，确定取值、无负值', () {
      final r = position(
        targetLeft: 40,
        targetRight: 80,
        height: plotHeight + 20,
      );
      expect(r.top, 0);
      expect(r.left, greaterThanOrEqualTo(0));
    });
  });
}
