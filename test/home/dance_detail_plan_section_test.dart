import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/home/dance_detail_page.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/plan/system_push_provider.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/level_control.dart'
    show
        screenBrightnessControllerProvider,
        systemMediaVolumeControllerProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_providers.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';
import '../helpers/fake_beat_pipeline.dart';
import '../helpers/fake_brightness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_cover_generator.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fake_system_volume.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_member_scheme_storage.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_push_port.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/plan_wheel_driver.dart';
import '../helpers/semantics_assertions.dart';
import '../helpers/test_clock.dart';

/// 舞详情计划区部件测试：只断言 DDL 设 / 改 / 清
/// 与清单打勾后读面随之变化、无 DDL 时的入口态；落盘口径归存储层直测。
void main() {
  late InMemoryPracticePlanStorage planStorage;

  setUp(() {
    planStorage = InMemoryPracticePlanStorage();
  });

  /// 计划区收在页尾：点它的控件前先滚到可见。
  Future<void> scrollTo(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> pumpSection(
    WidgetTester tester, {
    String videoId = 'v1',
    InMemoryPushPort? pushPort,
  }) async {
    useNamedViewport(tester, ViewportTier.compact);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...testClockOverrides(),
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(initial: VideoIndex(entries: [_entry])),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (id) => InMemoryVideoDocumentStorage(),
          ),
          coverCacheProvider.overrideWith((ref) => InMemoryCoverCache()),
          coverGeneratorProvider.overrideWith(
            (ref) async => FakeCoverGenerator(cache: InMemoryCoverCache()),
          ),
          practiceStatsStoreProvider.overrideWithValue(
            PracticeStatsStore(InMemoryPracticeStatsStorage()),
          ),
          fourBeatBucketStoreProvider.overrideWithValue(
            FourBeatBucketStore(InMemoryFourBeatBucketStorage()),
          ),
          memberSchemeStoreProvider.overrideWith(
            (ref, videoId) => MemberSchemeStore(InMemoryMemberSchemeStorage()),
          ),
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
          beatAnalysisPipelineProvider.overrideWithValue(FakeBeatPipeline()),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          screenBrightnessControllerProvider.overrideWithValue(
            FakeScreenBrightnessController(),
          ),
          systemMediaVolumeControllerProvider.overrideWithValue(
            FakeSystemMediaVolumeController(),
          ),
          practicePlanStorageProvider.overrideWithValue(planStorage),
          if (pushPort != null)
            systemPushPortProvider.overrideWithValue(pushPort),
        ],
        child: MaterialApp(home: DanceDetailPage(videoId: videoId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('无 DDL：计划区给出可设入口', (tester) async {
    await pumpSection(tester);
    expect(find.byKey(const Key('dance_plan_set')), findsOneWidget);
    expect(find.byKey(const Key('dance_plan_date')), findsNothing);
  });

  testWidgets('设「提前 N 天」提醒：首次保存时请求通知权限，权限被拒仍保存', (tester) async {
    final pushPort = InMemoryPushPort()..requestPermissionResult = false;
    await pumpSection(tester, pushPort: pushPort);
    await scrollTo(tester, 'dance_plan_set');
    await tester.tap(find.byKey(const Key('dance_plan_set')));
    await tester.pumpAndSettle();
    await selectPlanDate(
      tester,
      'dance_plan_dialog_date',
      target: DateTime(2026, 10, 1),
      today: localToday(),
    );
    await scrollTo(tester, 'dance_plan_dialog_lead');
    await selectPlanLead(
      tester,
      const Key('dance_plan_dialog_lead_wheel'),
      target: 3,
    );
    await tester.tap(find.byKey(const Key('dance_plan_dialog_save')));
    await tester.pumpAndSettle();

    expect(pushPort.requestPermissionCalls, 1);
    expect(find.text('提前 3 天'), findsOneWidget, reason: '被拒不阻塞保存');

    // 同一进程再次保存不再重复弹。
    await scrollTo(tester, 'dance_plan_edit');
    await tester.tap(find.byKey(const Key('dance_plan_edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dance_plan_dialog_save')));
    await tester.pumpAndSettle();
    expect(pushPort.requestPermissionCalls, 1);
  });

  testWidgets('设 DDL 不带提前 N 天：不请求通知权限', (tester) async {
    final pushPort = InMemoryPushPort();
    await pumpSection(tester, pushPort: pushPort);
    await scrollTo(tester, 'dance_plan_set');
    await tester.tap(find.byKey(const Key('dance_plan_set')));
    await tester.pumpAndSettle();
    await selectPlanDate(
      tester,
      'dance_plan_dialog_date',
      target: DateTime(2026, 10, 1),
      today: localToday(),
    );
    await tester.tap(find.byKey(const Key('dance_plan_dialog_save')));
    await tester.pumpAndSettle();
    expect(pushPort.requestPermissionCalls, 0);
  });

  testWidgets('设 DDL：五要素经编辑框写入，计划区读面随之更新', (tester) async {
    await pumpSection(tester);
    await scrollTo(tester, 'dance_plan_set');
    await tester.tap(find.byKey(const Key('dance_plan_set')));
    await tester.pumpAndSettle();

    await selectPlanDate(
      tester,
      'dance_plan_dialog_date',
      target: DateTime(2026, 10, 1),
      today: localToday(),
    );
    await tester.enterText(
      find.byKey(const Key('dance_plan_dialog_occasion')),
      '演出',
    );
    await tester.enterText(
      find.byKey(const Key('dance_plan_dialog_remark')),
      '带扇子',
    );
    await scrollTo(tester, 'dance_plan_dialog_lead');
    await selectPlanLead(
      tester,
      const Key('dance_plan_dialog_lead_wheel'),
      target: 3,
    );
    await tester.tap(find.byKey(const Key('dance_plan_dialog_save')));
    await tester.pumpAndSettle();

    expect(find.text('2026-10-01'), findsOneWidget);
    expect(find.text('演出'), findsOneWidget);
    expect(find.text('带扇子'), findsOneWidget);
    expect(find.text('提前 3 天'), findsOneWidget);
    expect(find.byKey(const Key('dance_plan_edit')), findsOneWidget);
    expect(find.byKey(const Key('dance_plan_clear')), findsOneWidget);

    // 落盘可重启读回。
    final read = await PracticePlanStore(planStorage).ddlOf('v1');
    expect(read!.date, DateTime(2026, 10, 1));
    expect(read.occasion, '演出');
    expect(read.leadDays, 3);
  });

  testWidgets('改期：编辑页滚轮先滚到当前值，滑选后按新日期重读', (tester) async {
    planStorage.rawJson = PracticePlanDocument(
      entries: [
        DancePlanEntry(
          videoId: 'v1',
          ddl: DanceDdl(date: DateTime(2026, 10, 1), occasion: '约舞'),
        ),
      ],
    ).toJson();
    await pumpSection(tester);
    expect(find.text('2026-10-01'), findsOneWidget);

    // 不动滚轮直接保存：值不变，证明年 / 月 / 日已先滚到既有值。
    await scrollTo(tester, 'dance_plan_edit');
    await tester.tap(find.byKey(const Key('dance_plan_edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dance_plan_dialog_save')));
    await tester.pumpAndSettle();
    expect(
      (await PracticePlanStore(planStorage).ddlOf('v1'))!.date,
      DateTime(2026, 10, 1),
    );

    // 滑选到新日期。
    await scrollTo(tester, 'dance_plan_edit');
    await tester.tap(find.byKey(const Key('dance_plan_edit')));
    await tester.pumpAndSettle();
    await selectPlanDate(
      tester,
      'dance_plan_dialog_date',
      target: DateTime(2026, 11, 11),
      today: localToday(),
    );
    await tester.tap(find.byKey(const Key('dance_plan_dialog_save')));
    await tester.pumpAndSettle();

    expect(find.text('2026-11-11'), findsOneWidget);
    expect(find.text('2026-10-01'), findsNothing);
  });

  testWidgets('清除 DDL：回到可设入口态', (tester) async {
    planStorage.rawJson = PracticePlanDocument(
      entries: [
        DancePlanEntry(
          videoId: 'v1',
          ddl: DanceDdl(date: DateTime(2026, 10, 1)),
        ),
      ],
    ).toJson();
    await pumpSection(tester);
    await scrollTo(tester, 'dance_plan_clear');
    await tester.tap(find.byKey(const Key('dance_plan_clear')));
    await tester.pumpAndSettle();
    // 先确认：取消 = DDL 不变。
    expect(find.byKey(const Key('dance_plan_clear_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dance_plan_clear_cancel')));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-01'), findsOneWidget);
    expect(
      (await PracticePlanStore(planStorage).ddlOf('v1'))!.date,
      DateTime(2026, 10, 1),
    );

    // 确认后才清除落盘。
    await scrollTo(tester, 'dance_plan_clear');
    await tester.tap(find.byKey(const Key('dance_plan_clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dance_plan_clear_confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dance_plan_set')), findsOneWidget);
    expect(await PracticePlanStore(planStorage).ddlOf('v1'), isNull);
  });

  testWidgets('改期只换 DDL 字段：既有清单与勾选态保留', (tester) async {
    planStorage.rawJson = PracticePlanDocument(
      entries: [
        DancePlanEntry(
          videoId: 'v1',
          ddl: DanceDdl(
            date: DateTime(2026, 10, 1),
            checklist: const [PlanChecklistItem(text: '充电宝', checked: true)],
          ),
        ),
      ],
    ).toJson();
    await pumpSection(tester);

    await scrollTo(tester, 'dance_plan_edit');
    await tester.tap(find.byKey(const Key('dance_plan_edit')));
    await tester.pumpAndSettle();
    await selectPlanDate(
      tester,
      'dance_plan_dialog_date',
      target: DateTime(2026, 11, 11),
      today: localToday(),
    );
    await tester.tap(find.byKey(const Key('dance_plan_dialog_save')));
    await tester.pumpAndSettle();

    expect(find.text('充电宝'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('dance_plan_check_0')))
          .value,
      isTrue,
    );
    final read = await PracticePlanStore(planStorage).ddlOf('v1');
    expect(read!.date, DateTime(2026, 11, 11));
    expect(
      read.checklist.single,
      const PlanChecklistItem(text: '充电宝', checked: true),
    );
  });

  testWidgets('场合预设：点「演出」chip 即代入标签框，保存后落盘', (tester) async {
    await pumpSection(tester);
    await scrollTo(tester, 'dance_plan_set');
    await tester.tap(find.byKey(const Key('dance_plan_set')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dance_plan_occasion_preset_演出')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('dance_plan_dialog_occasion')),
          )
          .controller!
          .text,
      '演出',
    );

    await selectPlanDate(
      tester,
      'dance_plan_dialog_date',
      target: DateTime(2026, 10, 1),
      today: localToday(),
    );
    await tester.tap(find.byKey(const Key('dance_plan_dialog_save')));
    await tester.pumpAndSettle();
    // 滚轮只产出合法值：无格式报错分支，保存直接关页并落盘。
    expect(find.byKey(const Key('dance_plan_dialog')), findsNothing);
    expect(find.text('演出'), findsOneWidget);
  });

  testWidgets('准备清单：可加项、可打勾，勾选态写回存储', (tester) async {
    planStorage.rawJson = PracticePlanDocument(
      entries: [
        DancePlanEntry(
          videoId: 'v1',
          ddl: DanceDdl(date: DateTime(2026, 10, 1)),
        ),
      ],
    ).toJson();
    await pumpSection(tester);

    await tester.enterText(
      find.byKey(const Key('dance_plan_checklist_input')),
      '充电宝',
    );
    await scrollTo(tester, 'dance_plan_checklist_add');
    await tester.tap(find.byKey(const Key('dance_plan_checklist_add')));
    await tester.pumpAndSettle();
    expect(find.text('充电宝'), findsOneWidget);

    // 清单删除钮报出主动语态中文名。
    await scrollTo(tester, 'dance_plan_check_remove_0');
    expectButtonSemantics(
      tester,
      const Key('dance_plan_check_remove_0'),
      label: '删除该清单项',
    );

    await scrollTo(tester, 'dance_plan_check_0');
    await tester.tap(find.byKey(const Key('dance_plan_check_0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('dance_plan_check_0')))
          .value,
      isTrue,
    );

    final read = await PracticePlanStore(planStorage).ddlOf('v1');
    expect(
      read!.checklist.single,
      const PlanChecklistItem(text: '充电宝', checked: true),
    );
  });

  testWidgets('落档只读展示：状态与判定日期逐行可见', (tester) async {
    planStorage.rawJson = PracticePlanDocument(
      entries: [
        DancePlanEntry(
          videoId: 'v1',
          ddl: DanceDdl(
            date: DateTime(2026, 10, 1),
            settlement: DdlSettlement(
              outcome: DdlSettlementOutcome.overdue,
              judgedOn: DateTime(2026, 9, 20),
            ),
          ),
        ),
      ],
    ).toJson();
    await pumpSection(tester);

    expect(find.byKey(const Key('dance_plan_settlement')), findsOneWidget);
    expect(find.text('落档：逾期（判定 2026-09-20）'), findsOneWidget);
  });

  testWidgets('装载补判接线：已过未落档的 DDL 打开详情页即补判并显示', (tester) async {
    planStorage.rawJson = PracticePlanDocument(
      entries: [
        DancePlanEntry(
          videoId: 'v1',
          ddl: DanceDdl(date: DateTime(2020, 1, 1)),
        ),
      ],
    ).toJson();
    await pumpSection(tester);

    // 文档无学习段（零段舞）→ 判逾期；落档已写回存储。
    expect(find.byKey(const Key('dance_plan_settlement')), findsOneWidget);
    expect(find.textContaining('落档：逾期'), findsOneWidget);
    final read = await PracticePlanStore(planStorage).ddlOf('v1');
    expect(read!.settlement!.outcome, DdlSettlementOutcome.overdue);
  });

  testWidgets('随舞曲库开关默认开；关掉写盘、重启读回关', (tester) async {
    await pumpSection(tester);
    await scrollTo(tester, 'dance_plan_social_library');
    // SwitchListTile 里的 Switch 子件继承其值。
    final switchFinder = find.descendant(
      of: find.byKey(const Key('dance_plan_social_library')),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(switchFinder).value, isTrue);

    await tester.tap(find.byKey(const Key('dance_plan_social_library')));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(switchFinder).value, isFalse);
    // 重启（新 store 同一存储）读回仍是关。
    expect(
      await PracticePlanStore(planStorage).socialLibraryEnabledOf('v1'),
      isFalse,
    );
  });

  testWidgets('随舞曲库开关关着的舞：DDL 与清单读面原样', (tester) async {
    planStorage.rawJson = {
      'version': PracticePlanDocument.versionPolicy.currentVersion,
      'entries': [
        {
          'videoId': 'v1',
          'socialLibrary': false,
          'ddl': {
            'date': '2026-10-01',
            'checklist': [
              {'text': '带水'},
            ],
          },
        },
      ],
    };
    await pumpSection(tester);
    await scrollTo(tester, 'dance_plan_date');
    expect(find.text('2026-10-01'), findsOneWidget);
    expect(find.text('带水'), findsOneWidget);
  });
}

final _entry = VideoIndexEntry(
  videoId: 'v1',
  displayName: 'v1.mp4',
  filePath: '/videos/v1.mp4',
  sizeBytes: 1,
  fastKey: 'k-v1',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);
