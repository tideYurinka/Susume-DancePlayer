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
import 'package:dance_learning_app/plan/dance_plan_manager_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/plan_wheel_driver.dart';
import '../helpers/semantics_assertions.dart';
import '../helpers/test_clock.dart';

/// 各舞计划管理页部件测试：入口可达、行内容齐全、
/// 两组分组、搜索与筛选、编辑框保存后落盘且本页与计划页刷新、空舞库引导。
void main() {
  VideoIndexEntry entry(String videoId) => VideoIndexEntry(
    videoId: videoId,
    displayName: '$videoId.mp4',
    filePath: '/videos/$videoId.mp4',
    sizeBytes: 1,
    fastKey: 'k-$videoId',
    mirrored: false,
    lastOpenedAt: DateTime(2026, 9, 1),
  );

  /// 全掌握文档：三条分段线切四段，全部最高档。
  InMemoryVideoDocumentStorage masteredDoc() => InMemoryVideoDocumentStorage(
    markers: MarkersDocument(
      rangeStartMs: 0,
      rangeEndMs: 100000,
      segmentLines: [
        for (var i = 0; i < 3; i++)
          SegmentLine(position: Duration(milliseconds: i * 10000)),
      ],
    ).toJson(),
    local: LocalDocument(
      mastery: {for (var i = 0; i < 4; i++) i: LearningMastery.mastered},
    ).toJson(),
  );

  Future<InMemoryPracticePlanStorage> pumpManager(
    WidgetTester tester, {
    VideoIndex index = VideoIndex.empty,
    Map<String, dynamic>? planJson,
    Map<String, InMemoryVideoDocumentStorage> documents = const {},
  }) async {
    final planStorage = InMemoryPracticePlanStorage();
    if (planJson != null) planStorage.rawJson = planJson;
    useNamedViewport(tester, ViewportTier.compact);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...testClockOverrides(),
          practicePlanStorageProvider.overrideWithValue(planStorage),
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(initial: index),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (id) => documents[id] ?? InMemoryVideoDocumentStorage(),
          ),
          coverCacheProvider.overrideWith((ref) => InMemoryCoverCache()),
          practiceStatsStoreProvider.overrideWithValue(
            PracticeStatsStore(InMemoryPracticeStatsStorage()),
          ),
        ],
        child: const MaterialApp(home: DancePlanManagerPage()),
      ),
    );
    await tester.pumpAndSettle();
    return planStorage;
  }

  testWidgets('计划 Tab 右上角入口 push 各舞计划页', (tester) async {
    useNamedViewport(tester, ViewportTier.compact);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...testClockOverrides(),
          practicePlanStorageProvider.overrideWithValue(
            InMemoryPracticePlanStorage(),
          ),
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(initial: VideoIndex.empty),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (id) => InMemoryVideoDocumentStorage(),
          ),
          coverCacheProvider.overrideWith((ref) => InMemoryCoverCache()),
          practiceStatsStoreProvider.overrideWithValue(
            PracticeStatsStore(InMemoryPracticeStatsStorage()),
          ),
        ],
        child: const DanceLearningApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tab_plan')));
    await tester.pumpAndSettle();
    // 空计划页也让入口可达。
    expect(find.byKey(const Key('plan_manage_entry')), findsOneWidget);
    await tester.tap(find.byKey(const Key('plan_manage_entry')));
    await tester.pumpAndSettle();

    expect(find.byType(DancePlanManagerPage), findsOneWidget);
    expect(find.text('各舞计划'), findsOneWidget);
  });

  testWidgets('舞库为空：页内出引导提示', (tester) async {
    await pumpManager(tester);

    expect(find.byKey(const Key('plan_manage_empty_library')), findsOneWidget);
  });

  testWidgets('行内容齐全：DDL 摘要、落档标记、开关提示、百分比与完全掌握勾', (tester) async {
    await pumpManager(
      tester,
      index: VideoIndex(entries: [entry('v1'), entry('v2')]),
      planJson: PracticePlanDocument(
        entries: [
          DancePlanEntry(
            videoId: 'v1',
            ddl: DanceDdl(
              date: DateTime(2026, 10, 1),
              occasion: '演出',
              settlement: DdlSettlement(
                outcome: DdlSettlementOutcome.overdue,
                judgedOn: DateTime(2026, 9, 20),
              ),
            ),
            socialLibrary: false,
          ),
        ],
      ).toJson(),
      documents: {'v2': masteredDoc()},
    );

    expect(find.byKey(const Key('plan_manage_row_v1')), findsOneWidget);
    // 未署名舞名 = 「文件名回落名」（去扩展名）。
    expect(find.text('v1'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_manage_ddl_v1'))).data,
      '2026-10-01 · 演出',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('plan_manage_settlement_v1')))
          .data,
      '落档：逾期',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_manage_hints_v1'))).data,
      '曲库关',
    );
    // v1 无分段线：不显示百分比，也不出勾。
    expect(find.byKey(const Key('plan_manage_mastery_v1')), findsNothing);

    // v2 未设 DDL、完全掌握：摘要标「未设 DDL」，熟练度以勾替。
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_manage_ddl_v2'))).data,
      '未设 DDL',
    );
    expect(
      tester.widget<Icon>(find.byKey(const Key('plan_manage_mastery_v2'))).icon,
      Icons.check_circle,
    );
    expectSemanticsLabel(
      tester,
      const Key('plan_manage_mastery_v2'),
      label: '已完全掌握',
      reason: '行尾勾要报出真值（与舞详情、首页卡片同款）',
    );
    expect(find.byKey(const Key('plan_manage_settlement_v2')), findsNothing);
    expect(find.byKey(const Key('plan_manage_hints_v2')), findsNothing);
  });

  testWidgets('未完全掌握显示百分比；两个开关都关出两条提示', (tester) async {
    await pumpManager(
      tester,
      index: VideoIndex(entries: [entry('v1')]),
      planJson: PracticePlanDocument(
        entries: [
          DancePlanEntry(
            videoId: 'v1',
            socialLibrary: false,
            reviewReminders: false,
          ),
        ],
      ).toJson(),
      documents: {
        'v1': InMemoryVideoDocumentStorage(
          markers: MarkersDocument(
            rangeStartMs: 0,
            rangeEndMs: 100000,
            segmentLines: [
              SegmentLine(position: const Duration(milliseconds: 10000)),
            ],
          ).toJson(),
          local: LocalDocument(
            mastery: const {
              0: LearningMastery.mastered,
              1: LearningMastery.unlearned,
            },
          ).toJson(),
        ),
      },
    );

    // 两段均值 2×25 = 50%。
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_manage_mastery_v1'))).data,
      '50%',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_manage_hints_v1'))).data,
      '曲库关 · 提醒关',
    );
  });

  testWidgets('两组分组：已有计划在前且按 DDL 日期升序，未设计划完全掌握沉底', (tester) async {
    await pumpManager(
      tester,
      index: VideoIndex(
        entries: [entry('v3'), entry('v1'), entry('v2'), entry('v4')],
      ),
      planJson: PracticePlanDocument(
        entries: [
          DancePlanEntry(
            videoId: 'v1',
            ddl: DanceDdl(date: DateTime(2026, 12, 1)),
          ),
          DancePlanEntry(
            videoId: 'v2',
            ddl: DanceDdl(date: DateTime(2020, 1, 1)),
          ),
        ],
      ).toJson(),
      documents: {'v4': masteredDoc()},
    );

    expect(
      find.byKey(const Key('plan_manage_group_with_plan')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('plan_manage_group_without_plan')),
      findsOneWidget,
    );
    // 逾期（2020）按日期排在 2026 之前；两组组头次序「已有计划」在上。
    expect(
      tester.getTopLeft(find.byKey(const Key('plan_manage_row_v2'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('plan_manage_row_v1'))).dy,
      ),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const Key('plan_manage_group_with_plan')))
          .dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('plan_manage_group_without_plan')))
            .dy,
      ),
    );
    // 未设计划组：v3 在前，完全掌握的 v4 沉底。
    expect(
      tester.getTopLeft(find.byKey(const Key('plan_manage_row_v3'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('plan_manage_row_v4'))).dy,
      ),
    );
  });

  testWidgets('标题搜索与「只看未设计划」筛选生效', (tester) async {
    await pumpManager(
      tester,
      index: VideoIndex(entries: [entry('v1'), entry('v2')]),
      planJson: PracticePlanDocument(
        entries: [
          DancePlanEntry(
            videoId: 'v1',
            ddl: DanceDdl(date: DateTime(2026, 10, 1)),
          ),
        ],
      ).toJson(),
    );

    await tester.enterText(find.byKey(const Key('plan_manage_search')), 'v2');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan_manage_row_v2')), findsOneWidget);
    expect(find.byKey(const Key('plan_manage_row_v1')), findsNothing);

    await tester.enterText(find.byKey(const Key('plan_manage_search')), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan_manage_only_unset')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan_manage_row_v1')), findsNothing);
    expect(find.byKey(const Key('plan_manage_row_v2')), findsOneWidget);
    expect(find.byKey(const Key('plan_manage_group_with_plan')), findsNothing);
  });

  testWidgets('点行开编辑框：填 DDL 与两个开关，保存后落盘且行随之刷新', (tester) async {
    final storage = await pumpManager(
      tester,
      index: VideoIndex(entries: [entry('v1')]),
    );

    await tester.tap(find.byKey(const Key('plan_manage_row_v1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dance_plan_dialog')), findsOneWidget);
    // 全屏表单页，不是弹框。
    expect(find.byType(AlertDialog), findsNothing);
    await selectPlanDate(
      tester,
      'dance_plan_dialog_date',
      target: DateTime(2026, 10, 1),
      today: localToday(),
    );
    await scrollPlanEditorTo(tester, const Key('dance_plan_dialog_occasion'));
    await tester.enterText(
      find.byKey(const Key('dance_plan_dialog_occasion')),
      '演出',
    );
    // 管理页编辑框同源控件：两个开关与清单编辑器在场（compact 档视口
    // 更矮，逐个滚入视口后断言）。
    await scrollPlanEditorTo(tester, const Key('dance_plan_review_reminders'));
    expect(
      find.byKey(const Key('dance_plan_review_reminders')),
      findsOneWidget,
    );
    await scrollPlanEditorTo(tester, const Key('plan_manage_checklist_input'));
    expect(
      find.byKey(const Key('plan_manage_checklist_input')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('plan_manage_checklist_input')),
      '带扇子',
    );
    await tester.tap(find.byKey(const Key('plan_manage_checklist_add')));
    await tester.pumpAndSettle();
    await scrollPlanEditorTo(tester, const Key('dance_plan_social_library'));
    expect(find.byKey(const Key('dance_plan_social_library')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dance_plan_social_library')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dance_plan_dialog_save')));
    await tester.pumpAndSettle();

    final store = PracticePlanStore(storage);
    final ddl = await store.ddlOf('v1');
    expect(ddl!.date, DateTime(2026, 10, 1));
    expect(ddl.occasion, '演出');
    expect(ddl.checklist.single.text, '带扇子');
    expect(await store.socialLibraryEnabledOf('v1'), isFalse);

    // 本页刷新：行摘要与开关提示随之更新。
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_manage_ddl_v1'))).data,
      '2026-10-01 · 演出',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_manage_hints_v1'))).data,
      '曲库关',
    );
    expect(
      find.byKey(const Key('plan_manage_group_with_plan')),
      findsOneWidget,
    );
  });

  testWidgets('无 DDL 的舞：编辑页日期滚轮默认今天，改开关保存即落 DDL 与开关', (tester) async {
    final storage = await pumpManager(
      tester,
      index: VideoIndex(entries: [entry('v1')]),
    );

    await tester.tap(find.byKey(const Key('plan_manage_row_v1')));
    await tester.pumpAndSettle();
    await scrollPlanEditorTo(tester, const Key('dance_plan_review_reminders'));
    await tester.tap(find.byKey(const Key('dance_plan_review_reminders')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dance_plan_dialog_save')));
    await tester.pumpAndSettle();

    final store = PracticePlanStore(storage);
    expect(
      (await store.ddlOf('v1'))!.date,
      localToday(),
      reason: '新建 DDL 默认今天',
    );
    expect(await store.reviewRemindersEnabledOf('v1'), isFalse);
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_manage_hints_v1'))).data,
      '提醒关',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_manage_ddl_v1'))).data,
      '${planDayKey(localToday())} · 约舞',
    );
  });

  testWidgets('编辑框保存后计划页同步刷新：页内提示 → 时间轴与当日 DDL', (tester) async {
    final storage = InMemoryPracticePlanStorage();
    useNamedViewport(tester, ViewportTier.compact);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...testClockOverrides(),
          practicePlanStorageProvider.overrideWithValue(storage),
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(
              initial: VideoIndex(entries: [entry('v1')]),
            ),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (id) => InMemoryVideoDocumentStorage(),
          ),
          coverCacheProvider.overrideWith((ref) => InMemoryCoverCache()),
          practiceStatsStoreProvider.overrideWithValue(
            PracticeStatsStore(InMemoryPracticeStatsStorage()),
          ),
        ],
        child: const DanceLearningApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tab_plan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan_empty_hint')), findsOneWidget);
    expect(find.byKey(const Key('plan_timeline')), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan_manage_entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan_manage_row_v1')));
    await tester.pumpAndSettle();

    final ddlDay = DateTime(testToday.year, testToday.month, 15);
    await selectPlanDate(
      tester,
      'dance_plan_dialog_date',
      target: ddlDay,
      today: localToday(),
    );
    await tester.tap(find.byKey(const Key('dance_plan_dialog_save')));
    await tester.pumpAndSettle();

    // 返回计划页：提示条消失，时间轴与日历出现，当日可点出 DDL。
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan_empty_hint')), findsNothing);
    expect(find.byKey(const Key('plan_timeline')), findsOneWidget);
    expect(
      find.byKey(Key('plan_timeline_marker_${planDayKey(ddlDay)}')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(Key('plan_day_${planDayKey(ddlDay)}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan_panel_ddl_v1')), findsOneWidget);
  });
}
