import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/plan/agenda_list.dart';
import 'package:dance_learning_app/plan/plan_mark_kind.dart';
import 'package:dance_learning_app/plan/practice_reminders.dart';
import 'package:dance_learning_app/persistence/team_check_gate.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime get _today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DancePlanEntry _ddlEntry(
  String videoId,
  DateTime day, {
  DdlSettlement? settlement,
  String occasion = '约舞',
}) => DancePlanEntry(videoId: videoId, ddl: DanceDdl(date: day, occasion: occasion, settlement: settlement));

PlanEvent _social(
  String id,
  DateTime day, {
  List<String> danceIds = const ['v1'],
  String location = '',
}) => PlanEvent(id: id, date: day, danceIds: danceIds, location: location);

PlanEvent _teamCheck(String id, DateTime day, {List<String> danceIds = const ['v1']}) =>
    PlanEvent(id: id, type: kPlanEventTypeTeamCheck, date: day, danceIds: danceIds);

void main() {
  group('即将到期', () {
    test('列未过且未达成的 DDL 与团内检查，按剩余自然日升序', () {
      final now = _today;
      final items = agendaDueItems(
        entries: [
          _ddlEntry('vFar', now.add(const Duration(days: 5))),
          _ddlEntry('vNear', now.add(const Duration(days: 1))),
        ],
        events: [
          _teamCheck('tc1', now.add(const Duration(days: 3))),
        ],
        teamCheckAchieved: (_) => false,
        now: now,
      );
      expect(
        items.map((i) => i.videoId ?? i.event!.id).toList(),
        ['vNear', 'tc1', 'vFar'],
      );
      expect(items.every((i) => i.remainingDays >= 0), isTrue);
    });

    test('已落档、已逾期与已达成的目标不进组；今天到期剩余 0 天', () {
      final now = _today;
      final items = agendaDueItems(
        entries: [
          _ddlEntry('vDone', now.add(const Duration(days: 1)),
              settlement: DdlSettlement(
                  outcome: DdlSettlementOutcome.onTime, judgedOn: now)),
          _ddlEntry('vPast', now.subtract(const Duration(days: 1))),
          _ddlEntry('vToday', now),
        ],
        events: [
          _teamCheck('tcMet', now.add(const Duration(days: 1))),
        ],
        teamCheckAchieved: (event) => event.id == 'tcMet',
        now: now,
      );
      expect(items.single.videoId, 'vToday');
      expect(items.single.remainingDays, 0);
    });

    test('剩余天数并列时保持输入次序（稳定）', () {
      final now = _today;
      final day = now.add(const Duration(days: 2));
      final items = agendaDueItems(
        entries: [_ddlEntry('vA', day), _ddlEntry('vB', day)],
        events: const [],
        teamCheckAchieved: (_) => false,
        now: now,
      );
      expect(items.map((i) => i.videoId).toList(), ['vA', 'vB']);
    });
  });

  group('待复习', () {
    AgendaReviewDance dance(
      String videoId, {
      LearningMastery? level = LearningMastery.learning,
      DateTime? lastPracticeDay,
      PlanMarkKind? goalKind = PlanMarkKind.ddl,
    }) => AgendaReviewDance(
      videoId: videoId,
      level: level,
      lastPracticeDay: lastPracticeDay,
      goalKind: goalKind,
    );

    test('列超出档位阈值的有目标舞，按超出天数从多到少', () {
      final now = _today;
      final items = agendaReviewItems(
        dances: [
          // 学习中阈值 3 天：练过 4 天前 = 超 1 天。
          dance('vSmall', lastPracticeDay: now.subtract(const Duration(days: 4))),
          // 练过 8 天前 = 超 5 天。
          dance('vBig', lastPracticeDay: now.subtract(const Duration(days: 8))),
          // 练过 2 天前 = 未超阈值。
          dance('vFresh', lastPracticeDay: now.subtract(const Duration(days: 2))),
        ],
        now: now,
      );
      expect(items.map((i) => i.videoId).toList(), ['vBig', 'vSmall']);
      expect(items[0].exceedDays, 5);
      expect(items[1].exceedDays, 1);
    });

    test('无目标舞与完全掌握不超阈值舞不进组', () {
      final now = _today;
      final items = agendaReviewItems(
        dances: [
          dance('vNoGoal', lastPracticeDay: now.subtract(const Duration(days: 40)), goalKind: null),
          // 掌握阈值 30 天：29 天未练未超阈值；无目标者即使超阈也不进。
          dance('vMastered',
              level: LearningMastery.mastered,
              lastPracticeDay: now.subtract(const Duration(days: 29))),
          dance('vMasteredNoGoal',
              level: LearningMastery.mastered, goalKind: null),
        ],
        now: now,
      );
      expect(items, isEmpty);
    });

    test('条目带上目标类型，供行首图标取色', () {
      final now = _today;
      final items = agendaReviewItems(
        dances: [
          dance('vDdl', lastPracticeDay: null, goalKind: PlanMarkKind.ddl),
          dance('vTc', lastPracticeDay: null, goalKind: PlanMarkKind.teamCheck),
          dance('vSocial', lastPracticeDay: null, goalKind: PlanMarkKind.social),
        ],
        now: now,
      );
      expect(
        {for (final item in items) item.videoId: item.goalKind},
        {
          'vDdl': PlanMarkKind.ddl,
          'vTc': PlanMarkKind.teamCheck,
          'vSocial': PlanMarkKind.social,
        },
      );
    });

    test('从未练视为超阈值排在末尾；超出天数并列保持输入次序', () {
      final now = _today;
      final items = agendaReviewItems(
        dances: [
          dance('vNever', lastPracticeDay: null),
          dance('vA', lastPracticeDay: now.subtract(const Duration(days: 6))),
          dance('vB', lastPracticeDay: now.subtract(const Duration(days: 6))),
        ],
        now: now,
      );
      expect(items.map((i) => i.videoId).toList(), ['vA', 'vB', 'vNever']);
      expect(items[2].exceedDays, isNull);
    });
  });

  group('随舞临近', () {
    test('列未到日的随舞事件，按日期升序；已过日不进', () {
      final now = _today;
      final items = agendaSocialItems(
        events: [
          _social('ev3', now.add(const Duration(days: 3))),
          _social('ev1', now),
          _social('evPast', now.subtract(const Duration(days: 1))),
          _teamCheck('tc', now.add(const Duration(days: 1))),
        ],
        now: now,
      );
      expect(items.map((e) => e.id).toList(), ['ev1', 'ev3']);
    });
  });

  group('团检已达成判定', () {
    DanceGateStatus gateStatus(String videoId) =>
        videoId == 'vMet' ? DanceGateStatus.met : DanceGateStatus.unmet;

    test('事件级达标即达成', () {
      expect(
        teamCheckAchieved(
          event: _teamCheck('tc', _today, danceIds: const ['vMet']),
          gateStatusOf: gateStatus,
        ),
        isTrue,
      );
    });

    test('录视频提交类已提交即达成，与达标门无关', () {
      expect(
        teamCheckAchieved(
          event: PlanEvent(
            id: 'tc',
            type: kPlanEventTypeTeamCheck,
            date: _today,
            danceIds: const ['vUnmet'],
            checkMode: kTeamCheckModeVideoSubmission,
            submittedOn: _today,
          ),
          gateStatusOf: gateStatus,
        ),
        isTrue,
      );
    });

    test('未达标与无可判定数据都不算达成', () {
      expect(
        teamCheckAchieved(
          event: _teamCheck('tc', _today, danceIds: const ['vUnmet']),
          gateStatusOf: gateStatus,
        ),
        isFalse,
      );
      expect(
        teamCheckAchieved(
          event: _teamCheck('tc', _today),
          gateStatusOf: gateStatus,
        ),
        isFalse,
      );
    });
  });
}
