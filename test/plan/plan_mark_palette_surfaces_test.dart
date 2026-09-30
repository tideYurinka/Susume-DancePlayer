import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/plan/plan_mark_kind.dart';
import 'package:dance_learning_app/plan/plan_marker_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 计划标记配色铺到日历圆点、点日下栏与日程列表行首图标。三处都取
/// [planMarkColor] 同一出处，只表达类型；逾期 / 落档 / 完全掌握不改颜色。

DateTime get _today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// 本月 15 号：恒落在月视图网格内，可点选。
DateTime get _day => DateTime(_today.year, _today.month, 15);

VideoIndexEntry _entry(String videoId) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);

/// 该舞文档：3 条分段线切 4 段、全部同档。
InMemoryVideoDocumentStorage _doc(LearningMastery mastery) =>
    InMemoryVideoDocumentStorage(
      markers: MarkersDocument(
        rangeStartMs: 0,
        rangeEndMs: 100000,
        segmentLines: [
          for (var i = 0; i < 3; i++)
            SegmentLine(position: Duration(milliseconds: i * 10000)),
        ],
      ).toJson(),
      local: LocalDocument(mastery: {for (var i = 0; i < 4; i++) i: mastery})
          .toJson(),
    );

DancePlanEntry _ddl(
  String videoId,
  DateTime day, {
  DdlSettlement? settlement,
}) => DancePlanEntry(
  videoId: videoId,
  ddl: DanceDdl(date: day, occasion: '演出', settlement: settlement),
);

PlanEvent _social(
  String id,
  DateTime day, {
  List<String> danceIds = const [],
}) => PlanEvent(id: id, date: day, danceIds: danceIds);

PlanEvent _teamCheck(
  String id,
  DateTime day, {
  List<String> danceIds = const [],
  Map<String, String> gates = const {},
  String checkMode = kTeamCheckModeRehearsal,
  DateTime? submittedOn,
}) => PlanEvent(
  id: id,
  type: kPlanEventTypeTeamCheck,
  date: day,
  danceIds: danceIds,
  danceGates: gates,
  checkMode: checkMode,
  submittedOn: submittedOn,
);

Future<void> _pump(
  WidgetTester tester, {
  required List<String> dances,
  required PracticePlanDocument plan,
  Map<String, InMemoryVideoDocumentStorage> documents = const {},
}) async {
  final planStorage = InMemoryPracticePlanStorage();
  planStorage.rawJson = plan.toJson();
  useNamedViewport(tester, ViewportTier.compact);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        practicePlanStorageProvider.overrideWithValue(planStorage),
        practiceStatsStoreProvider.overrideWithValue(
          PracticeStatsStore(InMemoryPracticeStatsStorage()),
        ),
        videoIndexStoreProvider.overrideWithValue(
          InMemoryVideoIndexStorage(
            initial: VideoIndex(entries: [for (final id in dances) _entry(id)]),
          ),
        ),
        videoDocumentStorageFactoryProvider.overrideWithValue(
          (videoId) => documents[videoId] ?? InMemoryVideoDocumentStorage(),
        ),
        coverCacheProvider.overrideWith((ref) => InMemoryCoverCache()),
      ],
      child: const DanceLearningApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('tab_plan')));
  await tester.pumpAndSettle();
}

Color _dotColor(WidgetTester tester, String dayKey) {
  final container = tester.widget<Container>(
    find.byKey(Key('plan_day_dot_ddl_$dayKey')),
  );
  return (container.decoration! as BoxDecoration).color!;
}

Color _eventDotColor(WidgetTester tester, String dayKey) {
  final container = tester.widget<Container>(
    find.byKey(Key('plan_day_dot_social_$dayKey')),
  );
  return (container.decoration! as BoxDecoration).color!;
}

Color _teamCheckDotColor(WidgetTester tester, String dayKey) {
  final container = tester.widget<Container>(
    find.byKey(Key('plan_day_dot_teamcheck_$dayKey')),
  );
  return (container.decoration! as BoxDecoration).color!;
}

Color _leadingColor(WidgetTester tester, String key) {
  final tile = tester.widget<ListTile>(find.byKey(Key(key)));
  return (tile.leading! as Icon).color!;
}

void main() {
  testWidgets('日历三类圆点取配色映射，同日多类并排各一色', (tester) async {
    final dayKey = planDayKey(_day);
    await _pump(
      tester,
      dances: const ['v1'],
      plan: PracticePlanDocument(
        entries: [_ddl('v1', _day)],
        events: [_social('ev1', _day), _teamCheck('tc1', _day)],
      ),
    );

    expect(_dotColor(tester, dayKey), planMarkColor(PlanMarkKind.ddl));
    expect(_eventDotColor(tester, dayKey), planMarkColor(PlanMarkKind.social));
    expect(
      _teamCheckDotColor(tester, dayKey),
      planMarkColor(PlanMarkKind.teamCheck),
    );
    // 三类互不相同：同日并排也分得清。
    final colors = {
      _dotColor(tester, dayKey),
      _eventDotColor(tester, dayKey),
      _teamCheckDotColor(tester, dayKey),
    };
    expect(colors, hasLength(3));
  });

  testWidgets('点日下栏三类行首图标取配色映射', (tester) async {
    await _pump(
      tester,
      dances: const ['v1'],
      plan: PracticePlanDocument(
        entries: [_ddl('v1', _day)],
        events: [_social('ev1', _day), _teamCheck('tc1', _day)],
      ),
    );
    await tester.tap(find.byKey(Key('plan_day_${planDayKey(_day)}')));
    await tester.pumpAndSettle();

    expect(
      _leadingColor(tester, 'plan_panel_ddl_v1'),
      planMarkColor(PlanMarkKind.ddl),
    );
    expect(
      _leadingColor(tester, 'plan_panel_event_ev1'),
      planMarkColor(PlanMarkKind.social),
    );
    expect(
      _leadingColor(tester, 'plan_panel_teamcheck_tc1'),
      planMarkColor(PlanMarkKind.teamCheck),
    );
  });

  testWidgets('日程列表三组行首图标取配色映射，待复习按目标类型', (tester) async {
    final near = _today.add(const Duration(days: 1));
    final soon = _today.add(const Duration(days: 2));
    final later = _today.add(const Duration(days: 3));
    await _pump(
      tester,
      dances: const ['v1', 'v2', 'v3'],
      plan: PracticePlanDocument(
        entries: [
          _ddl('v1', soon),
          // v2 / v3 无 DDL，仅有事件目标。
        ],
        events: [
          _teamCheck('tc1', near, danceIds: const ['v2']),
          _social('ev1', later, danceIds: const ['v3']),
        ],
      ),
    );

    expect(
      _leadingColor(tester, 'plan_agenda_due_v1'),
      planMarkColor(PlanMarkKind.ddl),
    );
    expect(
      _leadingColor(tester, 'plan_agenda_due_tc1'),
      planMarkColor(PlanMarkKind.teamCheck),
    );
    expect(
      _leadingColor(tester, 'plan_agenda_review_v1'),
      planMarkColor(PlanMarkKind.ddl),
    );
    expect(
      _leadingColor(tester, 'plan_agenda_review_v2'),
      planMarkColor(PlanMarkKind.teamCheck),
    );
    expect(
      _leadingColor(tester, 'plan_agenda_review_v3'),
      planMarkColor(PlanMarkKind.social),
    );
    expect(
      _leadingColor(tester, 'plan_agenda_social_ev1'),
      planMarkColor(PlanMarkKind.social),
    );
  });

  testWidgets('逾期 / 落档 / 完全掌握与团检达标状态都不改这三处颜色', (tester) async {
    final overdue = DateTime(_today.year, _today.month, 16);
    final active = DateTime(_today.year, _today.month, 17);
    final mastered = DateTime(_today.year, _today.month, 18);
    await _pump(
      tester,
      dances: const ['v1', 'v2', 'v3'],
      plan: PracticePlanDocument(
        entries: [
          _ddl(
            'v1',
            overdue,
            settlement: DdlSettlement(
              outcome: DdlSettlementOutcome.overdue,
              judgedOn: _today,
            ),
          ),
          _ddl('v2', active),
          _ddl('v3', mastered),
        ],
        events: [
          // 同一团检的达标（待定）与未达标两种状态：行首图标同色。
          _teamCheck('tcPending', overdue),
          _teamCheck(
            'tcUnmet',
            overdue,
            danceIds: const ['v2'],
            gates: const {'v2': 'mastered'},
          ),
        ],
      ),
      documents: {
        'v2': _doc(LearningMastery.learning),
        'v3': _doc(LearningMastery.mastered),
      },
    );

    // 日历：逾期落档 / 活跃 / 完全掌握三种状态的 DDL 圆点同色。
    final ddlColor = planMarkColor(PlanMarkKind.ddl);
    expect(_dotColor(tester, planDayKey(overdue)), ddlColor);
    expect(_dotColor(tester, planDayKey(active)), ddlColor);
    expect(_dotColor(tester, planDayKey(mastered)), ddlColor);

    await tester.tap(find.byKey(Key('plan_day_${planDayKey(overdue)}')));
    await tester.pumpAndSettle();

    // 下栏：逾期落档的 DDL 行与两种达标状态的团检行都取类型色。
    expect(_leadingColor(tester, 'plan_panel_ddl_v1'), ddlColor);
    final teamCheckColor = planMarkColor(PlanMarkKind.teamCheck);
    expect(
      _leadingColor(tester, 'plan_panel_teamcheck_tcPending'),
      teamCheckColor,
    );
    expect(
      _leadingColor(tester, 'plan_panel_teamcheck_tcUnmet'),
      teamCheckColor,
    );
    // 状态只改文案（达标 / 未达标 / 待定），不改图标颜色。
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('plan_panel_teamcheck_tcPending_status')),
          )
          .data,
      '待定',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('plan_panel_teamcheck_tcUnmet_status')),
          )
          .data,
      '未达标',
    );
  });
}
