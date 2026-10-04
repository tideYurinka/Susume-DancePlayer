import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/player/speed_step_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 三段：0–10s、10–20s、20–30s。
  AnnotationTimeline timelineWithLines() => AnnotationTimeline.normalized(
    videoDuration: const Duration(seconds: 30),
    segmentLines: [
      const Duration(seconds: 10),
      const Duration(seconds: 20),
    ].map((p) => SegmentLine(position: p)).toList(),
  );

  group('resolveSpeedStepScope（范围判定）', () {
    test('预览在激活学习段内 → withinActiveScope', () {
      final decision = resolveSpeedStepScope(
        timeline: timelineWithLines(),
        selected: const {0},
        position: const Duration(seconds: 5),
      );
      expect(decision.withinActiveScope, isTrue);
    });

    test('多段激活合并范围内（含激活段之间的段）→ withinActiveScope', () {
      final decision = resolveSpeedStepScope(
        timeline: timelineWithLines(),
        selected: const {0, 1, 2},
        position: const Duration(seconds: 15),
      );
      expect(decision.withinActiveScope, isTrue);
    });

    test('激活段端点仍属激活范围（合并范围端点闭区间）', () {
      for (final position in [
        Duration.zero, // 段首
        const Duration(seconds: 30), // 段尾
      ]) {
        final decision = resolveSpeedStepScope(
          timeline: timelineWithLines(),
          selected: const {0, 1, 2},
          position: position,
        );
        expect(decision.withinActiveScope, isTrue, reason: '$position');
      }
    });

    test('预览在非激活段内（有其他激活）→ 范围外，候选为当前所在段', () {
      final decision = resolveSpeedStepScope(
        timeline: timelineWithLines(),
        selected: const {0},
        position: const Duration(seconds: 15),
      );
      expect(decision.withinActiveScope, isFalse);
      expect(decision.candidateOrder, 1);
    });

    test('无激活但预览在某段内 → 范围外，候选为所在段', () {
      final decision = resolveSpeedStepScope(
        timeline: timelineWithLines(),
        selected: const {},
        position: const Duration(seconds: 25),
      );
      expect(decision.withinActiveScope, isFalse);
      expect(decision.candidateOrder, 2);
    });

    test('预览恰在分段线上 → 候选为分段线后面的那一段（不置灰）', () {
      for (final (position, expected) in const [
        (Duration(seconds: 10), 1), // 第一条分段线后面的段
        (Duration(seconds: 20), 2), // 第二条分段线后面的段
      ]) {
        final decision = resolveSpeedStepScope(
          timeline: timelineWithLines(),
          selected: const {},
          position: position,
        );
        expect(decision.withinActiveScope, isFalse);
        expect(decision.candidateOrder, expected, reason: '$position');
      }
    });

    test('预览在有效练习区间之前 → 候选为第一段', () {
      final timeline = AnnotationTimeline.normalized(
        videoDuration: const Duration(seconds: 30),
        rangeStart: const Duration(seconds: 5),
        segmentLines: [const Duration(seconds: 10)]
            .map((p) => SegmentLine(position: p))
            .toList(),
      );
      final decision = resolveSpeedStepScope(
        timeline: timeline,
        selected: const {},
        position: const Duration(seconds: 2),
      );
      expect(decision.withinActiveScope, isFalse);
      expect(decision.candidateOrder, 0);
    });

    test('预览在有效练习区间之后（其后无段）→ 候选为 null（第一项置灰）', () {
      final timeline = AnnotationTimeline.normalized(
        videoDuration: const Duration(seconds: 30),
        rangeEnd: const Duration(seconds: 25),
        segmentLines: [const Duration(seconds: 10)]
            .map((p) => SegmentLine(position: p))
            .toList(),
      );
      final decision = resolveSpeedStepScope(
        timeline: timeline,
        selected: const {},
        position: const Duration(seconds: 27),
      );
      expect(decision.withinActiveScope, isFalse);
      expect(decision.candidateOrder, isNull);
    });

    test('无分段线（无学习段）→ 范围外、候选为 null', () {
      final decision = resolveSpeedStepScope(
        timeline: AnnotationTimeline.wholeVideo(const Duration(seconds: 30)),
        selected: const {},
        position: const Duration(seconds: 15),
      );
      expect(decision.withinActiveScope, isFalse);
      expect(decision.candidateOrder, isNull);
    });
  });

  group('selectedLearningSegmentRange（合并范围回归）', () {
    test('相邻多段合并范围 = 第一段段首至最后段段尾', () {
      final range = selectedLearningSegmentRange(timelineWithLines(), const {
        0,
        1,
      });
      expect(range!.start, Duration.zero);
      expect(range.end, const Duration(seconds: 20));
    });
  });
}
