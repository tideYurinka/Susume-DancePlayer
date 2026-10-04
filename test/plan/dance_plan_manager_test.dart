import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/plan/dance_plan_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// 各舞计划管理页纯件测试：分组与组内次序、标题过滤、
/// 「只看未设计划」筛选，以及行内 DDL 摘要与落档文案。零 Flutter、时钟不参与。
void main() {
  DancePlanManagerDance dance(
    String videoId, {
    String? title,
    DateTime? ddl,
    double? masteryPercent,
    bool fullyMastered = false,
    bool socialLibrary = true,
    bool reviewReminders = true,
  }) => DancePlanManagerDance(
    videoId: videoId,
    title: title ?? videoId,
    ddl: ddl == null ? null : DanceDdl(date: ddl),
    masteryPercent: masteryPercent,
    fullyMastered: fullyMastered,
    socialLibrary: socialLibrary,
    reviewReminders: reviewReminders,
  );

  group('分组与组内次序', () {
    test('有 DDL 进「已有计划」，无 DDL 进「未设计划」', () {
      final groups = dancePlanManagerGroups(
        dances: [
          dance('v1', ddl: DateTime(2026, 10, 1)),
          dance('v2'),
        ],
      );

      expect([for (final d in groups.withPlan) d.videoId], ['v1']);
      expect([for (final d in groups.withoutPlan) d.videoId], ['v2']);
    });

    test('已有计划按 DDL 日期升序：逾期（过去日期）仍按日期在最前', () {
      final groups = dancePlanManagerGroups(
        dances: [
          dance('late', ddl: DateTime(2026, 12, 1)),
          dance('overdue', ddl: DateTime(2020, 1, 1)),
          dance('soon', ddl: DateTime(2026, 10, 1)),
        ],
      );

      expect(
        [for (final d in groups.withPlan) d.videoId],
        ['overdue', 'soon', 'late'],
      );
    });

    test('同日 DDL 保持舞库次序', () {
      final groups = dancePlanManagerGroups(
        dances: [
          dance('v1', ddl: DateTime(2026, 10, 1)),
          dance('v2', ddl: DateTime(2026, 10, 1)),
        ],
      );

      expect([for (final d in groups.withPlan) d.videoId], ['v1', 'v2']);
    });

    test('未设计划：完全掌握沉底，其余按舞库次序', () {
      final groups = dancePlanManagerGroups(
        dances: [
          dance('v1'),
          dance('mastered-1', fullyMastered: true),
          dance('v2'),
          dance('mastered-2', fullyMastered: true),
        ],
      );

      // 掌握的两支沉底（彼此仍按舞库次序），未掌握的按输入（舞库）次序。
      expect(
        [for (final d in groups.withoutPlan) d.videoId],
        ['v1', 'v2', 'mastered-1', 'mastered-2'],
      );
    });
  });

  group('标题过滤与只看未设计划', () {
    final library = [
      dance('v1', title: 'Alpha', ddl: DateTime(2026, 10, 1)),
      dance('v2', title: 'Beta'),
      dance('v3', title: 'alpha 2'),
    ];

    test('标题子串过滤，大小写不敏感；空白查询不过滤', () {
      expect(
        [
          for (final d in dancePlanManagerGroups(
            dances: library,
            query: 'ALPHA',
          ).withPlan)
            d.videoId,
        ],
        ['v1'],
      );
      final filtered = dancePlanManagerGroups(dances: library, query: 'alpha');
      expect(
        [
          ...[for (final d in filtered.withPlan) d.videoId],
          ...[for (final d in filtered.withoutPlan) d.videoId],
        ],
        ['v1', 'v3'],
      );
      final blank = dancePlanManagerGroups(dances: library, query: '   ');
      expect(blank.withPlan.length + blank.withoutPlan.length, 3);
    });

    test('只看未设计划：滤掉已有计划，未设计划组照常', () {
      final groups = dancePlanManagerGroups(
        dances: library,
        onlyWithoutPlan: true,
      );

      expect(groups.withPlan, isEmpty);
      expect([for (final d in groups.withoutPlan) d.videoId], ['v2', 'v3']);
    });

    test('过滤与只看未设计划同时生效', () {
      final groups = dancePlanManagerGroups(
        dances: library,
        query: 'alpha',
        onlyWithoutPlan: true,
      );

      // v3 命中标题且未设计划；v1 命中但已有计划被滤掉。
      expect([for (final d in groups.withoutPlan) d.videoId], ['v3']);
    });
  });

  group('行内文案', () {
    test('DDL 摘要：日期与场合，未设为「未设 DDL」', () {
      expect(dancePlanDdlSummary(null), '未设 DDL');
      expect(
        dancePlanDdlSummary(
          DanceDdl(date: DateTime(2026, 10, 1), occasion: '演出'),
        ),
        '2026-10-01 · 演出',
      );
      expect(
        dancePlanDdlSummary(DanceDdl(date: DateTime(2026, 10, 1))),
        '2026-10-01',
      );
    });

    test('落档文案：无落档不显示，按时 / 逾期各一枚', () {
      expect(dancePlanSettlementLabel(null), isNull);
      expect(
        dancePlanSettlementLabel(
          DdlSettlement(
            outcome: DdlSettlementOutcome.onTime,
            judgedOn: DateTime(2026, 9, 20),
          ),
        ),
        '落档：按时',
      );
      expect(
        dancePlanSettlementLabel(
          DdlSettlement(
            outcome: DdlSettlementOutcome.overdue,
            judgedOn: DateTime(2026, 9, 20),
          ),
        ),
        '落档：逾期',
      );
    });

    test('开关状态提示：关才提示，开不出提示', () {
      expect(
        dancePlanSwitchHints(socialLibrary: true, reviewReminders: true),
        isEmpty,
      );
      expect(
        dancePlanSwitchHints(socialLibrary: false, reviewReminders: true),
        ['曲库关'],
      );
      expect(
        dancePlanSwitchHints(socialLibrary: true, reviewReminders: false),
        ['提醒关'],
      );
      expect(
        dancePlanSwitchHints(socialLibrary: false, reviewReminders: false),
        ['曲库关', '提醒关'],
      );
    });
  });
}
