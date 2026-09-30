import 'package:dance_learning_app/plan/system_push.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_push_port.dart';

DateTime day(String yyyymmdd) => DateTime.parse(yyyymmdd);

DancePlanEntry entry(
  String videoId, {
  DateTime? ddlDate,
  int? leadDays,
  DdlSettlement? settlement,
}) => DancePlanEntry(
  videoId: videoId,
  ddl: ddlDate == null
      ? null
      : DanceDdl(date: ddlDate, leadDays: leadDays, settlement: settlement),
);

PlanEvent social(
  String id, {
  required DateTime date,
  String? startTime,
  int? leadDays,
}) => PlanEvent(
  id: id,
  type: kPlanEventTypeSocial,
  date: date,
  startTime: startTime,
  leadDays: leadDays,
);

PlanEvent teamCheck(
  String id, {
  required DateTime date,
  int? leadDays,
}) => PlanEvent(
  id: id,
  type: kPlanEventTypeTeamCheck,
  date: date,
  leadDays: leadDays,
);

void main() {
  final now = day('2026-10-10').add(const Duration(hours: 12));

  group('planPushSchedules 纯件：两条来源的排程口径', () {
    test('DDL 提前 N 天：投递在目标日减 N 天的当地 09:00', () {
      final schedules = planPushSchedules(
        entries: [entry('v1', ddlDate: day('2026-10-20'), leadDays: 3)],
        events: const [],
        fullyMasteredIds: const {},
        now: now,
      );
      expect(schedules.keys, ['ddl-lead:v1']);
      expect(schedules['ddl-lead:v1']!.deliverAt, day('2026-10-17 09:00'));
    });

    test('自动规则：DDL 剩 0–3 天且未完全掌握，投递在 DDL 日 09:00', () {
      final at3 = planPushSchedules(
        entries: [entry('v1', ddlDate: day('2026-10-13'))],
        events: const [],
        fullyMasteredIds: const {},
        now: now,
      );
      expect(at3.keys, ['ddl-auto:v1']);
      expect(at3['ddl-auto:v1']!.deliverAt, day('2026-10-13 09:00'));

      final at0 = planPushSchedules(
        entries: [entry('v1', ddlDate: day('2026-10-10'))],
        events: const [],
        fullyMasteredIds: const {},
        now: now.subtract(const Duration(hours: 12)),
      );
      expect(at0.keys, ['ddl-auto:v1']);
    });

    test('剩余超 3 天、已落档、完全掌握：自动规则都不排', () {
      final far = planPushSchedules(
        entries: [entry('v1', ddlDate: day('2026-10-14'))],
        events: const [],
        fullyMasteredIds: const {},
        now: now,
      );
      expect(far, isEmpty, reason: '剩 4 天不排');

      final settled = planPushSchedules(
        entries: [
          entry(
            'v1',
            ddlDate: day('2026-10-13'),
            settlement: DdlSettlement(
              outcome: DdlSettlementOutcome.overdue,
              judgedOn: day('2026-10-10'),
            ),
          ),
        ],
        events: const [],
        fullyMasteredIds: const {},
        now: now,
      );
      expect(settled, isEmpty, reason: '已落档不排自动规则');

      final mastered = planPushSchedules(
        entries: [entry('v1', ddlDate: day('2026-10-13'))],
        events: const [],
        fullyMasteredIds: const {'v1'},
        now: now,
      );
      expect(mastered, isEmpty, reason: '完全掌握不排自动规则');
    });

    test('随舞事件填了开始时间：按开始时间提前 N 天投递', () {
      final schedules = planPushSchedules(
        entries: const [],
        events: [
          social(
            'e1',
            date: day('2026-10-20'),
            startTime: '19:30',
            leadDays: 2,
          ),
        ],
        fullyMasteredIds: const {},
        now: now,
      );
      expect(schedules.keys, ['event-lead:e1']);
      expect(
        schedules['event-lead:e1']!.deliverAt,
        day('2026-10-18 19:30'),
      );
    });

    test('团内检查与未填开始时间的随舞事件：投递在目标日减 N 天的 09:00', () {
      final schedules = planPushSchedules(
        entries: const [],
        events: [
          teamCheck('t1', date: day('2026-10-20'), leadDays: 1),
          social('e1', date: day('2026-10-20'), leadDays: 1),
        ],
        fullyMasteredIds: const {},
        now: now,
      );
      expect(schedules['event-lead:t1']!.deliverAt, day('2026-10-19 09:00'));
      expect(schedules['event-lead:e1']!.deliverAt, day('2026-10-19 09:00'));
    });

    test('投递时刻已过的排程不产生（含提前量落在过去）', () {
      final schedules = planPushSchedules(
        entries: [entry('v1', ddlDate: day('2026-10-10'), leadDays: 5)],
        events: [
          social('e1', date: day('2026-10-10'), leadDays: 1),
        ],
        fullyMasteredIds: const {},
        now: now,
      );
      expect(schedules, isEmpty);
    });

    test('未设提前量：只剩自动规则一条来源', () {
      final schedules = planPushSchedules(
        entries: [entry('v1', ddlDate: day('2026-10-13'), leadDays: null)],
        events: [social('e1', date: day('2026-10-20'))],
        fullyMasteredIds: const {},
        now: now,
      );
      expect(schedules.keys, ['ddl-auto:v1']);
    });

    test('DDL 两条来源标题用舞名；表里查不到退回 videoId', () {
      final named = planPushSchedules(
        entries: [entry('v1', ddlDate: day('2026-10-12'), leadDays: 1)],
        events: const [],
        fullyMasteredIds: const {},
        now: now,
        displayNames: const {'v1': '「如」My Love'},
      );
      expect(named['ddl-lead:v1']!.title, '临近目标：「如」My Love');
      expect(named['ddl-auto:v1']!.title, '临近目标：「如」My Love');

      final missing = planPushSchedules(
        entries: [entry('v1', ddlDate: day('2026-10-12'), leadDays: 1)],
        events: const [],
        fullyMasteredIds: const {},
        now: now,
      );
      expect(missing['ddl-lead:v1']!.title, '临近目标：v1');
      expect(missing['ddl-auto:v1']!.title, '临近目标：v1');
    });

    test('舞名为空串：退回 videoId，不产出空标题', () {
      final schedules = planPushSchedules(
        entries: [entry('v1', ddlDate: day('2026-10-12'), leadDays: null)],
        events: const [],
        fullyMasteredIds: const {},
        now: now,
        displayNames: const {'v1': ''},
      );
      expect(schedules['ddl-auto:v1']!.title, '临近目标：v1');
      expect(schedules['ddl-auto:v1']!.title, isNot('临近目标：'));
    });

    test('随舞与团检事件标题不带舞名：名字表不影响它们', () {
      final schedules = planPushSchedules(
        entries: const [],
        events: [
          teamCheck('t1', date: day('2026-10-20'), leadDays: 1),
          social('e1', date: day('2026-10-20'), leadDays: 1),
        ],
        fullyMasteredIds: const {},
        now: now,
        displayNames: const {'t1': '不该出现在事件标题里'},
      );
      expect(schedules['event-lead:t1']!.title, '团内检查临近');
      expect(schedules['event-lead:e1']!.title, '随舞临近');
    });
  });

  group('SystemPushPlanner：端口收到的安排与取消', () {
    test('首次同步按期望排程；再同步不变则不重复调用端口', () async {
      final port = InMemoryPushPort();
      final planner = SystemPushPlanner(port);
      // DDL 剩 2 天（≤3，自动规则生效）且提前 1 天的投递时刻仍在将来。
      final entries = [entry('v1', ddlDate: day('2026-10-12'), leadDays: 1)];
      await planner.sync(
        entries: entries,
        events: const [],
        fullyMasteredIds: const {},
        now: now,
      );
      expect(port.scheduled.keys, ['ddl-lead:v1', 'ddl-auto:v1']);
      expect(port.cancelled, isEmpty);
      expect(port.scheduleCalls, 2);

      await planner.sync(
        entries: entries,
        events: const [],
        fullyMasteredIds: const {},
        now: now.add(const Duration(minutes: 1)),
      );
      expect(port.scheduleCalls, 2, reason: '期望未变不再排');
    });

    test('清除 DDL：其两条排程被取消', () async {
      final port = InMemoryPushPort();
      final planner = SystemPushPlanner(port);
      final entries = [entry('v1', ddlDate: day('2026-10-12'), leadDays: 1)];
      await planner.sync(
        entries: entries,
        events: const [],
        fullyMasteredIds: const {},
        now: now,
      );
      await planner.sync(
        entries: const [],
        events: const [],
        fullyMasteredIds: const {},
        now: now,
      );
      expect(port.cancelled, ['ddl-lead:v1', 'ddl-auto:v1']);
      expect(port.scheduled, isEmpty);
    });

    test('改期：旧时刻取消、新时刻重排', () async {
      final port = InMemoryPushPort();
      final planner = SystemPushPlanner(port);
      await planner.sync(
        entries: [entry('v1', ddlDate: day('2026-10-12'), leadDays: 1)],
        events: const [],
        fullyMasteredIds: const {},
        now: now,
      );
      await planner.sync(
        entries: [entry('v1', ddlDate: day('2026-10-25'), leadDays: 3)],
        events: const [],
        fullyMasteredIds: const {},
        now: now,
      );
      // 改期后剩 15 天，自动规则排程随旧 DDL 一并取消。
      expect(port.cancelled, ['ddl-lead:v1', 'ddl-auto:v1']);
      expect(
        port.scheduled['ddl-lead:v1']!.deliverAt,
        day('2026-10-22 09:00'),
      );
    });

    test('删除事件：其排程被取消', () async {
      final port = InMemoryPushPort();
      final planner = SystemPushPlanner(port);
      final events = [
        social('e1', date: day('2026-10-20'), startTime: '19:30', leadDays: 2),
      ];
      await planner.sync(
        entries: const [],
        events: events,
        fullyMasteredIds: const {},
        now: now,
      );
      await planner.sync(
        entries: const [],
        events: const [],
        fullyMasteredIds: const {},
        now: now,
      );
      expect(port.cancelled, ['event-lead:e1']);
      expect(port.scheduled, isEmpty);
    });

    test('完全掌握后自动规则排程被撤销，用户设的提前提醒保留', () async {
      final port = InMemoryPushPort();
      final planner = SystemPushPlanner(port);
      final entries = [entry('v1', ddlDate: day('2026-10-12'), leadDays: 1)];
      await planner.sync(
        entries: entries,
        events: const [],
        fullyMasteredIds: const {},
        now: now,
      );
      await planner.sync(
        entries: entries,
        events: const [],
        fullyMasteredIds: const {'v1'},
        now: now,
      );
      expect(port.cancelled, ['ddl-auto:v1']);
      expect(port.scheduled.keys, ['ddl-lead:v1']);
    });

    test('权限被拒：ensureReminderPermission 返回 false，后续同步照常记录、'
        '不阻塞其余功能', () async {
      final port = InMemoryPushPort()
        ..requestPermissionResult = false
        ..permissionGrantedResult = false;
      final planner = SystemPushPlanner(port);
      expect(await planner.ensureReminderPermission(), isFalse);
      await planner.sync(
        entries: [entry('v1', ddlDate: day('2026-10-12'), leadDays: 1)],
        events: const [],
        fullyMasteredIds: const {},
        now: now,
      );
      expect(port.scheduled.keys, ['ddl-lead:v1', 'ddl-auto:v1']);
    });

    test('权限请求只发生一次：后续 ensureReminderPermission 不再弹', () async {
      final port = InMemoryPushPort()
        ..requestPermissionResult = true
        ..permissionGrantedResult = true;
      final planner = SystemPushPlanner(port);
      expect(await planner.ensureReminderPermission(), isTrue);
      expect(await planner.ensureReminderPermission(), isTrue);
      expect(port.requestPermissionCalls, 1);
    });

    test('端口收到的排程标题用舞名；查不到退回 videoId', () async {
      final port = InMemoryPushPort();
      final planner = SystemPushPlanner(port);
      final entries = [entry('v1', ddlDate: day('2026-10-12'), leadDays: 1)];

      await planner.sync(
        entries: entries,
        events: const [],
        fullyMasteredIds: const {},
        now: now,
        displayNames: const {'v1': '旧名'},
      );
      expect(port.scheduled['ddl-lead:v1']!.title, '临近目标：旧名');
      expect(port.scheduled['ddl-auto:v1']!.title, '临近目标：旧名');
    });

    test('改名：同名 id 的已排通知被取消并按新舞名重排', () async {
      final port = InMemoryPushPort();
      final planner = SystemPushPlanner(port);
      final entries = [entry('v1', ddlDate: day('2026-10-12'), leadDays: 1)];

      await planner.sync(
        entries: entries,
        events: const [],
        fullyMasteredIds: const {},
        now: now,
        displayNames: const {'v1': '旧名'},
      );
      await planner.sync(
        entries: entries,
        events: const [],
        fullyMasteredIds: const {},
        now: now,
        displayNames: const {'v1': '新名'},
      );

      expect(port.cancelled, ['ddl-lead:v1', 'ddl-auto:v1']);
      expect(port.scheduled['ddl-lead:v1']!.title, '临近目标：新名');
      expect(port.scheduled['ddl-auto:v1']!.title, '临近目标：新名');
    });
  });
}
