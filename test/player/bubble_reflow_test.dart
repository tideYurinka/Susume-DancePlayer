import 'package:dance_learning_app/player/bubble_reflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('气泡族重排判定', () {
    // 并排所需宽取一个任意气泡尺寸即可——判定只看两侧宽度入参。
    const sideBySideWidth = 500.0;

    test('可用宽足够 → 并排', () {
      expect(
        bubbleReflowFor(
          availableWidth: sideBySideWidth + 1,
          sideBySideWidth: sideBySideWidth,
        ),
        BubbleReflow.sideBySide,
      );
    });

    test('可用宽不足 → 上下堆叠', () {
      expect(
        bubbleReflowFor(
          availableWidth: sideBySideWidth - 1,
          sideBySideWidth: sideBySideWidth,
        ),
        BubbleReflow.stacked,
      );
    });

    test('边界宽两侧：恰等于并排所需宽 → 并排；差 1px → 堆叠', () {
      expect(
        bubbleReflowFor(
          availableWidth: sideBySideWidth,
          sideBySideWidth: sideBySideWidth,
        ),
        BubbleReflow.sideBySide,
        reason: '可用宽恰等于并排所需宽时仍并排（断点取 >=）',
      );
      expect(
        bubbleReflowFor(
          availableWidth: sideBySideWidth - 0.001,
          sideBySideWidth: sideBySideWidth,
        ),
        BubbleReflow.stacked,
        reason: '差 1px 放不下即堆叠，不留「并排但缩一点」的中间态',
      );
    });
  });
}
