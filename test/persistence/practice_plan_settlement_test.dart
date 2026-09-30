import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/persistence/practice_plan_settlement.dart';
import 'package:flutter_test/flutter_test.dart';

/// 落档判定纯件用例（假时钟零 IO）：剩余自然日口径、
/// 临期边界、判定结果与判定日期。到期时刻 = 该本地日的结束，当天整天不算
/// 逾期。
void main() {
  final dueDay = DateTime(2026, 10, 1);

  group('剩余自然日', () {
    test('今天到期为 0', () {
      expect(
        planRemainingDays(dueDay: dueDay, now: DateTime(2026, 10, 1, 21, 30)),
        0,
      );
    });

    test('临期边界：剩 3 天为 3、剩 4 天为 4', () {
      expect(planRemainingDays(dueDay: dueDay, now: DateTime(2026, 9, 28)), 3);
      expect(planRemainingDays(dueDay: dueDay, now: DateTime(2026, 9, 27)), 4);
    });

    test('昨天为负', () {
      expect(planRemainingDays(dueDay: dueDay, now: DateTime(2026, 10, 2)), -1);
    });
  });

  group('临期口径', () {
    test('剩余 0–3 天为临期，负与 4 天不是', () {
      expect(planIsNearDeadline(0), isTrue);
      expect(planIsNearDeadline(3), isTrue);
      expect(planIsNearDeadline(4), isFalse);
      expect(planIsNearDeadline(-1), isFalse);
    });
  });

  group('落档判定', () {
    test('到期当天不判定（未到期不预判）', () {
      expect(
        judgeDdlSettlement(
          segmentMasteries: const {LearningMastery.mastered},
          dueDay: dueDay,
          now: DateTime(2026, 10, 1, 23, 59),
        ),
        isNull,
      );
    });

    test('全段掌握 → 按时，判定日期为当日', () {
      final settlement = judgeDdlSettlement(
        segmentMasteries: const {LearningMastery.mastered},
        dueDay: dueDay,
        now: DateTime(2026, 10, 2, 8, 0),
      );
      expect(settlement!.outcome, DdlSettlementOutcome.onTime);
      expect(settlement.judgedOn, DateTime(2026, 10, 2));
    });

    test('一段未达 → 逾期', () {
      final settlement = judgeDdlSettlement(
        segmentMasteries: const {
          LearningMastery.mastered,
          LearningMastery.familiar,
        },
        dueDay: dueDay,
        now: DateTime(2026, 10, 2),
      );
      expect(settlement!.outcome, DdlSettlementOutcome.overdue);
    });

    test('零段舞（空档位集合）→ 逾期（与完全掌握「空段集不成立」同口径）', () {
      final settlement = judgeDdlSettlement(
        segmentMasteries: const {},
        dueDay: dueDay,
        now: DateTime(2026, 10, 2),
      );
      expect(settlement!.outcome, DdlSettlementOutcome.overdue);
    });

    test('段中含未练档 → 逾期', () {
      final settlement = judgeDdlSettlement(
        segmentMasteries: const {
          LearningMastery.mastered,
          LearningMastery.unlearned,
        },
        dueDay: dueDay,
        now: DateTime(2026, 10, 3),
      );
      expect(settlement!.outcome, DdlSettlementOutcome.overdue);
      expect(settlement.judgedOn, DateTime(2026, 10, 3));
    });
  });
}
