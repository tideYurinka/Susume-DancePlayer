import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/plan/plan_page_layout.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_providers.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/semantics_assertions.dart';

VideoIndexEntry _entry(String videoId) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);

DateTime get _today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// 计划 JSON：v1 有一条后天的 DDL（未过、未落档 = 有目标），可选复习提醒
/// 开关。该舞无练习记录（从未练 = 超阈值）、无学习段（未练档）。
Map<String, dynamic> _planJson({bool reviewReminders = true}) => {
  'version': 1,
  'entries': [
    {
      'videoId': 'v1',
      'ddl': {
        'date': planDayKey(_today.add(const Duration(days: 2))),
        'occasion': '约舞',
      },
      if (!reviewReminders) 'reviewReminders': false,
    },
  ],
  'events': <Object>[],
};

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> planJson,
}) async {
  final planStorage = InMemoryPracticePlanStorage();
  planStorage.rawJson = planJson;
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
            initial: VideoIndex(entries: [_entry('v1')]),
          ),
        ),
        videoDocumentStorageFactoryProvider.overrideWithValue(
          (videoId) => InMemoryVideoDocumentStorage(),
        ),
        coverCacheProvider.overrideWith((ref) => InMemoryCoverCache()),
        playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
        fourBeatBucketStoreProvider.overrideWithValue(
          FourBeatBucketStore(InMemoryFourBeatBucketStorage()),
        ),
      ],
      child: const DanceLearningApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openPlanAndDdlDay(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('tab_plan')));
  await tester.pumpAndSettle();
  final ddlDay = _today.add(const Duration(days: 2));
  // 本月月视图只补位到跨月边：DDL 越出补位区时先翻到它所在的月。
  final visibleDays = buildPlanMonthGrid(_today).weeks.expand((week) => week);
  if (!visibleDays.any((day) => planDayKey(day) == planDayKey(ddlDay))) {
    await tester.tap(find.byKey(const Key('plan_month_next')));
    await tester.pumpAndSettle();
  }
  // 选中 DDL 所在日，让下栏给出进详情的行。
  await tester.tap(find.byKey(Key('plan_day_${planDayKey(ddlDay)}')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('有待提醒项：进入 App 即在计划 Tab 出红点', (tester) async {
    await _pump(tester, planJson: _planJson());
    expect(find.byKey(const Key('tab_plan_dot')), findsOneWidget);
  });

  testWidgets('有待提醒项：计划 Tab 的语义里报得出「待办」', (tester) async {
    await _pump(tester, planJson: _planJson());
    expectSemanticsLabel(
      tester,
      const Key('tab_plan'),
      labelContains: '待办',
      reason: '读屏需要在计划 Tab 上听到有待办状态',
    );
  });

  testWidgets('无待提醒项（复习提醒已关）：不出红点', (tester) async {
    await _pump(tester, planJson: _planJson(reviewReminders: false));
    expect(find.byKey(const Key('tab_plan_dot')), findsNothing);
  });

  testWidgets('进入计划 Tab 再评估一次：触发后状态落下，红点清空', (tester) async {
    await _pump(tester, planJson: _planJson());
    expect(find.byKey(const Key('tab_plan_dot')), findsOneWidget);
    await _openPlanAndDdlDay(tester);
    await tester.tap(find.byKey(const Key('tab_home')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tab_plan_dot')), findsNothing);
  });

  testWidgets('详情页复习提醒开关翻转后提醒集合随之变化：红点消失', (tester) async {
    await _pump(tester, planJson: _planJson());
    expect(find.byKey(const Key('tab_plan_dot')), findsOneWidget);
    // 首页点舞卡进详情页。
    await tester.tap(find.byKey(const Key('dance_card_detail_v1')));
    await tester.pumpAndSettle();
    // 计划区在详情页列表后段：滚到可见再断言。
    await tester.scrollUntilVisible(
      find.byKey(const Key('dance_plan_review_reminders')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('dance_plan_review_reminders')),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('dance_plan_review_reminders')));
    await tester.pumpAndSettle();
    // 关掉后写路径已重评提醒集合：详情页读面即时变化。
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('dance_plan_review_reminders')),
          )
          .value,
      isFalse,
    );
    // 回到根壳：红点消失（该舞已不参与提醒）。
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tab_plan_dot')), findsNothing);
  });
}
