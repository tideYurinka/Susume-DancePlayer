import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/plan/plan_mark_kind.dart';
import 'package:dance_learning_app/plan/practice_reminders.dart';
import 'package:dance_learning_app/persistence/team_check_gate.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_practice_plan_storage.dart';

DateTime day(String yyyymmdd) => DateTime.parse(yyyymmdd);

ReminderDanceInput dance(
  String videoId, {
  LearningMastery? level,
  DateTime? lastPracticeDay,
  bool reviewReminders = true,
  bool hasGoal = true,
  DanceReminderState? state,
  int? ddlRemainingDays,
}) => ReminderDanceInput(
  videoId: videoId,
  level: level,
  lastPracticeDay: lastPracticeDay,
  reviewReminders: reviewReminders,
  hasGoal: hasGoal,
  state: state,
  ddlRemainingDays: ddlRemainingDays,
);

void main() {
  final now = day('2026-10-10');

  group('阈值表五档与边界天数', () {
    test('五档阈值：掌握 30 / 较熟 14 / 能跟上 7 / 学习中 3 / 未练 3', () {
      expect(reviewReminderThresholdDays(LearningMastery.mastered), 30);
      expect(reviewReminderThresholdDays(LearningMastery.familiar), 14);
      expect(reviewReminderThresholdDays(LearningMastery.keepingUp), 7);
      expect(reviewReminderThresholdDays(LearningMastery.learning), 3);
      expect(reviewReminderThresholdDays(LearningMastery.unlearned), 3);
      expect(reviewReminderThresholdDays(null), 3);
    });

    test('边界天数：差一天不触发，到阈值当天触发', () {
      for (final (level, threshold) in [
        (LearningMastery.mastered, 30),
        (LearningMastery.familiar, 14),
        (LearningMastery.keepingUp, 7),
        (LearningMastery.learning, 3),
      ]) {
        final within = day('2026-10-10')
            .subtract(Duration(days: threshold - 1));
        final at = day('2026-10-10').subtract(Duration(days: threshold));
        expect(
          unpracticedBeyondThreshold(
            lastPracticeDay: within,
            level: level,
            now: now,
          ),
          isFalse,
          reason: '$level 差一天不触发',
        );
        expect(
          unpracticedBeyondThreshold(
            lastPracticeDay: at,
            level: level,
            now: now,
          ),
          isTrue,
          reason: '$level 到阈值当天触发',
        );
      }
    });

    test('从未练视为超阈值；舞档位取最低段档', () {
      expect(
        unpracticedBeyondThreshold(
          lastPracticeDay: null,
          level: null,
          now: now,
        ),
        isTrue,
      );
      expect(
        danceReminderLevel({
          LearningMastery.mastered,
          LearningMastery.learning,
          LearningMastery.familiar,
        }),
        LearningMastery.learning,
      );
      expect(danceReminderLevel(const {}), isNull);
    });
  });

  group('冷却、同日一次与重新计时', () {
    test('无状态且超阈值触发一次，触发即进冷却', () {
      final evaluation = evaluateReminders(
        dances: [
          dance(
            'v1',
            level: LearningMastery.learning,
            lastPracticeDay: day('2026-10-01'),
            ddlRemainingDays: 5,
          ),
        ],
        events: const [],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: now,
      );
      expect(evaluation.items, hasLength(1));
      expect(evaluation.items.single.kind, ReminderKind.review);
      final state = evaluation.nextStates['v1']!;
      expect(state.lastRemindedOn, now);

      // 冷却：次日不重触发（没再练、档位没变）。
      final nextDay = evaluateReminders(
        dances: [
          dance(
            'v1',
            level: LearningMastery.learning,
            lastPracticeDay: day('2026-10-01'),
            state: state,
            ddlRemainingDays: 4,
          ),
        ],
        events: const [],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: day('2026-10-11'),
      );
      expect(nextDay.items, isEmpty);
      expect(nextDay.nextStates, isEmpty);
    });

    test('同日只提醒一次', () {
      final state = danceReminderStateAfterFire(
        lastPracticeDay: day('2026-10-01'),
        level: LearningMastery.learning,
        now: now,
      );
      final evaluation = evaluateReminders(
        dances: [
          dance(
            'v1',
            level: LearningMastery.learning,
            lastPracticeDay: day('2026-10-01'),
            state: state,
          ),
        ],
        events: const [],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: now,
      );
      expect(evaluation.items, isEmpty);
    });

    test('再被练习（练习日前移）后重新计时；未到新阈值不提醒', () {
      final state = danceReminderStateAfterFire(
        lastPracticeDay: day('2026-10-01'),
        level: LearningMastery.learning,
        now: now,
      );
      // 练过一次（10-09）：重新计时，距新练习日 1 天 < 3 天 → 不提醒。
      final repracticed = evaluateReminders(
        dances: [
          dance(
            'v1',
            level: LearningMastery.learning,
            lastPracticeDay: day('2026-10-09'),
            state: state,
          ),
        ],
        events: const [],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: now,
      );
      expect(repracticed.items, isEmpty);
      // 再过 3 天没练：重新触发。
      final later = evaluateReminders(
        dances: [
          dance(
            'v1',
            level: LearningMastery.learning,
            lastPracticeDay: day('2026-10-09'),
            state: state,
          ),
        ],
        events: const [],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: day('2026-10-12'),
      );
      expect(later.items, hasLength(1));
    });

    test('档位变化后重新计时（冷却解除，按新档位阈值判）', () {
      final state = danceReminderStateAfterFire(
        lastPracticeDay: day('2026-10-01'),
        level: LearningMastery.learning,
        now: now,
      );
      // 次日升到较熟：冷却解除，距练习 10 天 < 14 天 → 不提醒。
      final promoted = evaluateReminders(
        dances: [
          dance(
            'v1',
            level: LearningMastery.familiar,
            lastPracticeDay: day('2026-10-01'),
            state: state,
          ),
        ],
        events: const [],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: day('2026-10-11'),
      );
      expect(promoted.items, isEmpty);
      // 升档后过了较熟阈值：提醒。
      final overdue = evaluateReminders(
        dances: [
          dance(
            'v1',
            level: LearningMastery.familiar,
            lastPracticeDay: day('2026-09-20'),
            state: state,
          ),
        ],
        events: const [],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: day('2026-10-11'),
      );
      expect(overdue.items, hasLength(1));
    });
  });

  group('随舞临近、团检临期条件', () {
    PlanEvent social(String date, {List<String> danceIds = const ['v1']}) =>
        PlanEvent(id: 'ev1', date: day(date), danceIds: danceIds);

    PlanEvent teamCheck(
      String date, {
      List<String> danceIds = const ['v1'],
      Map<String, String> gates = const {'v1': 'familiar'},
      String mode = kTeamCheckModeRehearsal,
      DateTime? submittedOn,
    }) => PlanEvent(
      id: 'tc1',
      type: kPlanEventTypeTeamCheck,
      date: day(date),
      danceIds: danceIds,
      danceGates: gates,
      checkMode: mode,
      submittedOn: submittedOn,
    );

    final unpracticed = dance(
      'v1',
      level: null,
      lastPracticeDay: day('2026-01-01'),
    );

    test('随舞 ≤3 天且超阈值未练触发；4 天外与未超阈值不触发', () {
      final evaluation = evaluateReminders(
        dances: [unpracticed],
        events: [social('2026-10-12')],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: now,
      );
      expect(
        evaluation.items.where((item) => item.kind == ReminderKind.socialNear),
        hasLength(1),
      );
      final far = evaluateReminders(
        dances: [unpracticed],
        events: [social('2026-10-14')],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: now,
      );
      expect(
        far.items.where((item) => item.kind == ReminderKind.socialNear),
        isEmpty,
      );
      final practiced = evaluateReminders(
        dances: [
          dance(
            'v1',
            level: LearningMastery.mastered,
            lastPracticeDay: day('2026-10-01'),
          ),
        ],
        events: [social('2026-10-12')],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: now,
      );
      expect(practiced.items, isEmpty);
    });

    test('团检 ≤3 天未达标触发；达标不触发；交作业未提交触发、已提交不触发', () {
      final unmet = evaluateReminders(
        dances: [
          dance('v1', level: LearningMastery.learning, lastPracticeDay: null),
        ],
        events: [teamCheck('2026-10-11')],
        gateStatusOf: (_, _) => DanceGateStatus.unmet,
        now: now,
      );
      expect(
        unmet.items.where((item) => item.kind == ReminderKind.teamCheckNear),
        hasLength(1),
      );
      final met = evaluateReminders(
        dances: [
          dance('v1', level: LearningMastery.learning, lastPracticeDay: null),
        ],
        events: [teamCheck('2026-10-11')],
        gateStatusOf: (_, _) => DanceGateStatus.met,
        now: now,
      );
      expect(
        met.items.where((item) => item.kind == ReminderKind.teamCheckNear),
        isEmpty,
      );
      final unsubmitted = evaluateReminders(
        dances: [
          dance('v1', level: LearningMastery.learning, lastPracticeDay: null),
        ],
        events: [
          teamCheck(
            '2026-10-11',
            mode: kTeamCheckModeVideoSubmission,
            gates: const {'v1': 'unset'},
          ),
        ],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: now,
      );
      expect(
        unsubmitted.items.where(
          (item) => item.kind == ReminderKind.teamCheckNear,
        ),
        hasLength(1),
      );
      final submitted = evaluateReminders(
        dances: [
          dance('v1', level: LearningMastery.learning, lastPracticeDay: null),
        ],
        events: [
          teamCheck(
            '2026-10-11',
            mode: kTeamCheckModeVideoSubmission,
            gates: const {'v1': 'unset'},
            submittedOn: day('2026-10-09'),
          ),
        ],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: now,
      );
      expect(
        submitted.items.where(
          (item) => item.kind == ReminderKind.teamCheckNear,
        ),
        isEmpty,
      );
    });

    test('过日的事件不触发（随舞与团检同口径）', () {
      final evaluation = evaluateReminders(
        dances: [
          dance('v1', level: null, lastPracticeDay: null, hasGoal: false),
        ],
        events: [social('2026-10-09'), teamCheck('2026-10-09')],
        gateStatusOf: (_, _) => DanceGateStatus.unmet,
        now: now,
      );
      expect(evaluation.items, isEmpty);
    });
  });

  group('DDL 加权次序', () {
    test('越接近期限且档位越低排得越前', () {
      expect(
        ddlReminderWeight(remainingDays: 2, level: LearningMastery.unlearned),
        lessThan(
          ddlReminderWeight(remainingDays: 2, level: LearningMastery.mastered),
        ),
      );
      expect(
        ddlReminderWeight(remainingDays: 1, level: LearningMastery.mastered),
        lessThan(
          ddlReminderWeight(remainingDays: 2, level: LearningMastery.mastered),
        ),
      );
      final evaluation = evaluateReminders(
        dances: [
          dance(
            'near-mastered',
            level: LearningMastery.mastered,
            lastPracticeDay: null,
            ddlRemainingDays: 1,
          ),
          dance(
            'far-unlearned',
            level: null,
            lastPracticeDay: null,
            ddlRemainingDays: 1,
          ),
          dance(
            'mid',
            level: LearningMastery.familiar,
            lastPracticeDay: null,
            ddlRemainingDays: 1,
          ),
          dance('no-ddl', level: null, lastPracticeDay: null),
        ],
        events: const [],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: now,
      );
      expect(evaluation.items.map((item) => item.videoId).toList(), [
        'far-unlearned',
        'mid',
        'near-mastered',
        'no-ddl',
      ]);
    });
  });

  group('有目标与静默、逾期不提醒', () {
    test('无目标的舞不参与提醒（哪怕久未练）', () {
      final evaluation = evaluateReminders(
        dances: [
          dance('v1', level: null, lastPracticeDay: null, hasGoal: false),
        ],
        events: const [],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: now,
      );
      expect(evaluation.items, isEmpty);
    });

    test('逾期 DDL 不算目标：不提醒', () {
      final evaluation = evaluateReminders(
        dances: [
          dance(
            'v1',
            level: null,
            lastPracticeDay: null,
            hasGoal: false,
            ddlRemainingDays: null,
          ),
        ],
        events: const [],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: now,
      );
      expect(evaluation.items, isEmpty);
    });

    test('关掉复习提醒的舞不参与遗忘复习与随舞临近，但团检临期照常', () {
      final off = dance(
        'v1',
        level: null,
        lastPracticeDay: null,
        reviewReminders: false,
      );
      final noEvents = evaluateReminders(
        dances: [off],
        events: const [],
        gateStatusOf: (_, _) => DanceGateStatus.notJudged,
        now: now,
      );
      expect(noEvents.items, isEmpty);
      // 团检临期不受开关管（开关只关「遗忘复习与随舞久未练」）。
      final teamCheck = PlanEvent(
        id: 'tc1',
        type: kPlanEventTypeTeamCheck,
        date: day('2026-10-11'),
        danceIds: const ['v1'],
        danceGates: const {'v1': 'familiar'},
      );
      final gated = evaluateReminders(
        dances: [off],
        events: [teamCheck],
        gateStatusOf: (_, _) => DanceGateStatus.unmet,
        now: now,
      );
      expect(gated.items.map((item) => item.kind), [
        ReminderKind.teamCheckNear,
      ]);
      // 团检临期独立触发：不落提醒状态（不压制冷却、无跨类耦合）。
      expect(gated.nextStates, isEmpty);
    });

    test('有目标判定：未落档未过的 DDL 与未到日事件算，逾期 / 已落档不算', () {
      final activeDdl = DanceDdl(date: day('2026-10-20'));
      final settledDdl = DanceDdl(
        date: day('2026-10-20'),
        settlement: DdlSettlement(
          outcome: DdlSettlementOutcome.overdue,
          judgedOn: now,
        ),
      );
      final social = PlanEvent(
        id: 'ev',
        date: day('2026-10-15'),
        danceIds: const ['v1'],
      );
      expect(
        danceHasGoal(ddl: activeDdl, events: const [], videoId: 'v1', now: now),
        isTrue,
      );
      expect(
        danceHasGoal(
          ddl: settledDdl,
          events: const [],
          videoId: 'v1',
          now: now,
        ),
        isFalse,
      );
      expect(
        danceHasGoal(ddl: null, events: [social], videoId: 'v1', now: now),
        isTrue,
      );
      // 完全掌握（全段最高档）本身不改变目标判定：无目标即静默，出现
      // 新目标（事件）重新激活。
      expect(
        danceHasGoal(ddl: null, events: const [], videoId: 'v1', now: now),
        isFalse,
      );
    });

    test('目标类型取 DDL 优先、其次按事件次序；无目标为 null', () {
      final ddl = DanceDdl(date: day('2026-10-20'));
      final settledDdl = DanceDdl(
        date: day('2026-10-20'),
        settlement: DdlSettlement(
          outcome: DdlSettlementOutcome.onTime,
          judgedOn: now,
        ),
      );
      final social = PlanEvent(
        id: 'ev',
        date: day('2026-10-15'),
        danceIds: const ['v1'],
      );
      final teamCheck = PlanEvent(
        id: 'tc',
        type: kPlanEventTypeTeamCheck,
        date: day('2026-10-16'),
        danceIds: const ['v1'],
      );
      final past = PlanEvent(
        id: 'past',
        date: day('2026-10-01'),
        danceIds: const ['v1'],
      );
      PlanMarkKind? kindOf({
        DanceDdl? ddl,
        List<PlanEvent> events = const [],
      }) => danceGoalMarkKind(
        ddl: ddl,
        events: events,
        videoId: 'v1',
        now: now,
      );

      // 有活跃 DDL 即 DDL，即使事件日期更近。
      expect(kindOf(ddl: ddl, events: [teamCheck, social]), PlanMarkKind.ddl);
      expect(kindOf(events: [social]), PlanMarkKind.social);
      expect(kindOf(events: [teamCheck]), PlanMarkKind.teamCheck);
      // 已落档 DDL 与已过日事件不算目标。
      expect(kindOf(ddl: settledDdl, events: [past]), isNull);
      // 与「有目标」同一份事实。
      expect(
        kindOf(events: [social]) != null,
        danceHasGoal(ddl: null, events: [social], videoId: 'v1', now: now),
      );
    });
  });

  group('开关与状态的持久化（store）', () {
    late InMemoryPracticePlanStorage storage;
    late PracticePlanStore store;

    setUp(() {
      storage = InMemoryPracticePlanStorage();
      store = PracticePlanStore(storage);
    });

    test('复习提醒开关默认开；关掉入库、重启仍在', () async {
      expect(await store.reviewRemindersEnabledOf('v1'), isTrue);
      await store.setReviewReminders(videoId: 'v1', enabled: false);
      expect(await store.reviewRemindersEnabledOf('v1'), isFalse);
      final reopened = PracticePlanStore(storage);
      expect(await reopened.reviewRemindersEnabledOf('v1'), isFalse);
    });

    test('触发状态入库并可读回；状态相同不重复写盘', () async {
      final state = danceReminderStateAfterFire(
        lastPracticeDay: day('2026-10-01'),
        level: LearningMastery.learning,
        now: now,
      );
      expect(await store.saveReminderState('v1', state), isTrue);
      expect(await store.reminderStateOf('v1'), state);
      final savesAfterFirst = storage.saveCount;
      await store.saveReminderState('v1', state);
      expect(storage.saveCount, savesAfterFirst);
    });

    test('重开开关后条目再无内容即移除（不留空条目）', () async {
      await store.setReviewReminders(videoId: 'v1', enabled: false);
      await store.setReviewReminders(videoId: 'v1', enabled: true);
      expect(await store.entries(), isEmpty);
    });
  });
}
