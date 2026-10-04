import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/segment_selection.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('恢复收紧连续性', () {
    test('不连续段序只保留含最小段序的那一段连续块', () {
      expect(contiguousBlockFromMin(const {1, 3, 4, 6}), const {1});
      expect(contiguousBlockFromMin(const {0, 2, 3}), const {0});
    });

    test('连续段序整块保留；单段与空集原样', () {
      expect(contiguousBlockFromMin(const {3, 4, 5}), const {3, 4, 5});
      expect(contiguousBlockFromMin(const {2}), const {2});
      expect(contiguousBlockFromMin(const {}), isEmpty);
    });

    test('乱序入参同样从最小段序起收连续块', () {
      expect(contiguousBlockFromMin(const {5, 4, 0, 9}), const {0});
    });
  });

  group('学习段选中（点击＝清空后单选）', () {
    AnnotationTimeline timelineWithLines(
      List<Duration> positions, {
      int totalSeconds = 30,
    }) {
      return AnnotationTimeline.normalized(
        videoDuration: Duration(seconds: totalSeconds),
        segmentLines: [
          for (final position in positions) SegmentLine(position: position),
        ],
      );
    }

    /// 7 段等长时间线：段 n = [10n, 10n+10)，总 70s。
    AnnotationTimeline sevenSegments() => timelineWithLines([
      for (var i = 1; i <= 6; i++) Duration(seconds: i * 10),
    ], totalSeconds: 70);

    test('空选中点一段：只选中这一段，循环范围＝这一段', () {
      final timeline = timelineWithLines([
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);

      final selected = toggleLearningSegmentSelection(const {}, timeline, 1);
      final range = selectedLearningSegmentRange(timeline, selected);

      expect(selected, const {1});
      expect(range?.start, const Duration(seconds: 10));
      expect(range?.end, const Duration(seconds: 20));
    });

    test('单选点另一段：换成那一段，不把中间段并进来', () {
      final timeline = sevenSegments();

      var selected = toggleLearningSegmentSelection(const {}, timeline, 2);
      selected = toggleLearningSegmentSelection(selected, timeline, 5);

      expect(selected, const {5});
      expect(selected, isNot(contains(3)));
      expect(selected, isNot(contains(4)));
      final range = selectedLearningSegmentRange(timeline, selected);
      expect(range?.start, const Duration(seconds: 50));
      expect(range?.end, const Duration(seconds: 60));
    });

    test('点另一段不把范围外远处的段带进来', () {
      final timeline = sevenSegments();

      var selected = toggleLearningSegmentSelection(const {}, timeline, 0);
      selected = toggleLearningSegmentSelection(selected, timeline, 6);

      expect(selected, const {6});
    });

    test('点已选中的那一段：清空选中，循环随之关掉', () {
      final timeline = timelineWithLines([
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);

      var selected = toggleLearningSegmentSelection(const {}, timeline, 0);
      selected = toggleLearningSegmentSelection(selected, timeline, 0);

      expect(selected, isEmpty);
      expect(selectedLearningSegmentRange(timeline, selected), isNull);
    });

    test('点在多段范围里的某一段：整体清空（不移出单段、不缩范围）', () {
      final timeline = sevenSegments();

      final selected = toggleLearningSegmentSelection(
        const {2, 3, 4, 5},
        timeline,
        3,
      );

      expect(selected, isEmpty);
      expect(selectedLearningSegmentRange(timeline, selected), isNull);
    });

    test('点击结果恒为单元素集合或空集（连续不变量成立）', () {
      final timeline = sevenSegments();

      var selected = toggleLearningSegmentSelection(const {}, timeline, 4);
      expect(selected.length, 1);
      selected = toggleLearningSegmentSelection(selected, timeline, 1);
      expect(selected.length, 1);
      selected = toggleLearningSegmentSelection(selected, timeline, 1);
      expect(selected, isEmpty);
    });

    test('段序越界仍抛范围错误', () {
      final timeline = sevenSegments();

      expect(
        () => toggleLearningSegmentSelection(const {}, timeline, 7),
        throwsRangeError,
      );
      expect(
        () => toggleLearningSegmentSelection(const {}, timeline, -1),
        throwsRangeError,
      );
    });

    test('拖出判定包含段首与段尾端点', () {
      final timeline = timelineWithLines([
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      final range = selectedLearningSegmentRange(timeline, const {1})!;

      expect(range.contains(const Duration(seconds: 10)), isTrue);
      expect(range.contains(const Duration(seconds: 20)), isTrue);
      expect(range.contains(const Duration(milliseconds: 9999)), isFalse);
      expect(range.contains(const Duration(milliseconds: 20001)), isFalse);
    });
  });

  group('长按拖动圈选区间代数', () {
    test('跨多段：起点到手指之间的全部连续段，含两端', () {
      expect(contiguousSelectionBetween(2, 5, 7), const {2, 3, 4, 5});
    });

    test('方向对称：从右往左拖与从左往右拖结果一致', () {
      expect(contiguousSelectionBetween(5, 2, 7), const {2, 3, 4, 5});
    });

    test('单段：起止同段＝只含这一段', () {
      expect(contiguousSelectionBetween(3, 3, 7), const {3});
    });

    test('超界钳制：拖出末段方向圈到末段为止', () {
      expect(contiguousSelectionBetween(4, 99, 7), const {4, 5, 6});
    });

    test('超界钳制：拖出首段方向圈到首段为止；负段序同钳', () {
      expect(contiguousSelectionBetween(2, -1, 7), const {0, 1, 2});
      expect(contiguousSelectionBetween(-9, 1, 7), const {0, 1});
    });

    test('结果恒连续（含满段与单段边界）', () {
      for (var start = 0; start < 7; start++) {
        for (var end = 0; end < 7; end++) {
          final result = contiguousSelectionBetween(start, end, 7);
          expect(result.length, (start - end).abs() + 1);
          for (var i = result.first; i <= result.last; i++) {
            expect(result.contains(i), isTrue);
          }
        }
      }
      expect(contiguousSelectionBetween(0, 6, 7), {0, 1, 2, 3, 4, 5, 6});
    });

    test('零段几何返回空集，不抛错', () {
      expect(contiguousSelectionBetween(0, 3, 0), isEmpty);
    });
  });
}
