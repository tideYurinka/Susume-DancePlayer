import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/annotation/annotation.dart';

Duration ms(int v) => Duration(milliseconds: v);

AnnotationTimeline timeline({
  List<SegmentLine> lines = const [],
  List<HalfBeatLine> halfBeats = const [],
  Duration? rangeEnd,
}) => AnnotationTimeline.normalized(
      videoDuration: ms(30000),
      rangeEnd: rangeEnd,
      segmentLines: lines,
      halfBeatLines: halfBeats,
    );

void main() {
  group('半拍线时间线模型不变式', () {
    test('归一化：升序、去重、区间外剔除', () {
      final t = timeline(
        halfBeats: [
          HalfBeatLine(position: ms(9000)),
          HalfBeatLine(position: ms(3000)),
          HalfBeatLine(position: ms(9000)),
          HalfBeatLine(position: ms(0)), // 区间外（首边界）剔除
          HalfBeatLine(position: ms(30000)), // 区间外（尾边界）剔除
        ],
      );
      expect(
        t.halfBeatLines,
        [
          HalfBeatLine(position: ms(3000)),
          HalfBeatLine(position: ms(9000)),
        ],
      );
    });

    test('区间收缩剔除界外半拍线（与分段线同规则）', () {
      final t = timeline(
        rangeEnd: ms(20000),
        halfBeats: [
          HalfBeatLine(position: ms(5000)),
          HalfBeatLine(position: ms(25000)),
        ],
      );
      expect(t.halfBeatLines, [HalfBeatLine(position: ms(5000))]);
    });
  });

  group('addHalfBeatLine', () {
    test('区间内新建；同位 no-op 不产生重复线', () {
      final base = timeline();
      final added = addHalfBeatLine(base, ms(2500));
      expect(added.halfBeatLines, [HalfBeatLine(position: ms(2500))]);
      expect(addHalfBeatLine(added, ms(2500)), added);
    });

    test('区间外抛 ArgumentError（新建被拒不是钳制）', () {
      expect(() => addHalfBeatLine(timeline(), ms(0)), throwsArgumentError);
      expect(
        () => addHalfBeatLine(timeline(), ms(30000)),
        throwsArgumentError,
      );
    });

    test('半拍线与分段线可同位（互不排斥、分段几何不受影响）', () {
      final base = timeline(lines: [SegmentLine(position: ms(10000))]);
      final added = addHalfBeatLine(base, ms(10000));
      expect(added.segmentLines, base.segmentLines);
      expect(added.halfBeatLines, [HalfBeatLine(position: ms(10000))]);
    });
  });

  group('moveHalfBeatLine', () {
    test('拖动到开区间内任意位置生效（精调自由落点）', () {
      final base = timeline(halfBeats: [HalfBeatLine(position: ms(2500))]);
      final moved = moveHalfBeatLine(base, 0, ms(2600));
      expect(moved.halfBeatLines, [HalfBeatLine(position: ms(2600))]);
    });

    test('越相邻半拍线 / 触首尾边界 no-op（保持升序互异）', () {
      final base = timeline(
        halfBeats: [
          HalfBeatLine(position: ms(2500)),
          HalfBeatLine(position: ms(7500)),
        ],
      );
      expect(moveHalfBeatLine(base, 0, ms(7500)), base);
      expect(moveHalfBeatLine(base, 0, ms(10000)), base);
      expect(moveHalfBeatLine(base, 1, ms(0)), base);
      expect(moveHalfBeatLine(base, 1, ms(30000)), base);
    });

    test('越分段线不受限（半拍线与分段线互不钳制）', () {
      final base = timeline(
        lines: [SegmentLine(position: ms(5000))],
        halfBeats: [HalfBeatLine(position: ms(2500))],
      );
      final moved = moveHalfBeatLine(base, 0, ms(6000));
      expect(moved.halfBeatLines, [HalfBeatLine(position: ms(6000))]);
    });

    test('索引越界抛 RangeError', () {
      expect(() => moveHalfBeatLine(timeline(), 0, ms(1)), throwsRangeError);
    });
  });

  group('与学习段几何解耦', () {
    test('半拍线增删移不改变学习段派生', () {
      final base = timeline(lines: [SegmentLine(position: ms(10000))]);
      final withHalf = addHalfBeatLine(base, ms(2500));
      expect(deriveLearningSegments(withHalf), deriveLearningSegments(base));
    });
  });
}
