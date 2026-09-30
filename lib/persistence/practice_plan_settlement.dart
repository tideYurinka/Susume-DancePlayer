import '../annotation/learning_segment_attributes.dart';
import '../core/local_day.dart';
import 'practice_plan.dart';

/// 到期落档判定纯件：零 IO、时钟经 [now] 注入。
/// 到期时刻 = 该本地日的结束（当天整天不算逾期）；剩余天数与临期口径取
/// `plan_calendar.dart`（阈值只在纯件定义一次，页面与推送都从同一处取值）。

// 剩余天数与临期口径在 `plan_calendar.dart`；此处 re-export，既有取用不受影响。
export 'plan_calendar.dart'
    show planRemainingDays, planIsNearDeadline, kPlanNearDeadlineDays;

/// 到期落档判定：未到期返回 null（不预判）；已过到期日按当时段熟练度判
/// 一次——全部学习段为掌握即按时，否则逾期（含零段舞，与「完全掌握 =
/// 段集非空且全段最高档」同口径）。判定日期取当日本地日。
DdlSettlement? judgeDdlSettlement({
  required Set<LearningMastery> segmentMasteries,
  required DateTime dueDay,
  required DateTime now,
}) {
  if (planRemainingDays(dueDay: dueDay, now: now) >= 0) return null;
  final onTime =
      segmentMasteries.isNotEmpty &&
      segmentMasteries.every((mastery) => mastery == LearningMastery.mastered);
  return DdlSettlement(
    outcome: onTime
        ? DdlSettlementOutcome.onTime
        : DdlSettlementOutcome.overdue,
    judgedOn: localDay(now),
  );
}
