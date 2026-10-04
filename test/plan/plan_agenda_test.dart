import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/home/dance_detail_page.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_providers.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/test_clock.dart';

VideoIndexEntry _entry(String videoId) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);

/// 虚拟今天：本文件的日期全部由它派生，不读真实日期。
DateTime get _today => testToday;

/// 该舞文档：3 条分段线切 4 段、全部同档——档位阈值随档位而定。
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

Map<String, dynamic> _planJson() => {
  'version': 1,
  'entries': [
    {
      'videoId': 'v1',
      'ddl': {
        'date': planDayKey(_today.add(const Duration(days: 2))),
        'occasion': '约舞',
      },
    },
    {
      'videoId': 'v2',
      'ddl': {
        'date': planDayKey(_today.add(const Duration(days: 4))),
        'occasion': '演出',
      },
    },
  ],
  'events': [
    {
      'id': 'tc1',
      'type': 'teamCheck',
      'date': planDayKey(_today.add(const Duration(days: 1))),
      'danceIds': ['v1'],
      'danceGates': {'v1': 'mastered'},
      'checkMode': 'rehearsal',
    },
    {
      'id': 'ev1',
      'type': 'socialDanceEvent',
      'date': planDayKey(_today.add(const Duration(days: 6))),
      'location': '公园',
      'danceIds': ['v1', 'v2'],
    },
  ],
};

Future<void> _pumpPlan(
  WidgetTester tester, {
  required Map<String, dynamic> planJson,
  List<PracticeSessionRecord> records = const [],
  Map<String, InMemoryVideoDocumentStorage> documents = const {},
}) async {
  final planStorage = InMemoryPracticePlanStorage();
  planStorage.rawJson = planJson;
  final statsStorage = InMemoryPracticeStatsStorage();
  if (records.isNotEmpty) {
    statsStorage.rawJson = PracticeStatsDocument(sessions: records).toJson();
  }
  useNamedViewport(tester, ViewportTier.compact);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...testClockOverrides(),
        practicePlanStorageProvider.overrideWithValue(planStorage),
        practiceStatsStoreProvider.overrideWithValue(
          PracticeStatsStore(statsStorage),
        ),
        videoIndexStoreProvider.overrideWithValue(
          InMemoryVideoIndexStorage(
            initial: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
          ),
        ),
        videoDocumentStorageFactoryProvider.overrideWithValue(
          (videoId) => documents[videoId] ?? _doc(LearningMastery.familiar),
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
  await tester.tap(find.byKey(const Key('tab_plan')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('三组各自渲染、组内排序正确', (tester) async {
    await _pumpPlan(tester, planJson: _planJson());
    // 即将到期：团检（剩 1）→ v1 DDL（剩 2）→ v2 DDL（剩 4）。
    expect(find.byKey(const Key('plan_agenda_due_header')), findsOneWidget);
    expect(find.byKey(const Key('plan_agenda_due_tc1')), findsOneWidget);
    expect(find.byKey(const Key('plan_agenda_due_v1')), findsOneWidget);
    expect(find.byKey(const Key('plan_agenda_due_v2')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('plan_agenda_due_tc1'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('plan_agenda_due_v1'))).dy,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('plan_agenda_due_v1'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('plan_agenda_due_v2'))).dy,
      ),
    );
    // 待复习：两支舞都有目标且从未练（视为超阈值）→ 都进组。
    expect(find.byKey(const Key('plan_agenda_review_header')), findsOneWidget);
    expect(find.byKey(const Key('plan_agenda_review_v1')), findsOneWidget);
    expect(find.byKey(const Key('plan_agenda_review_v2')), findsOneWidget);
    // 随舞临近：ev1 未到日进组。
    expect(find.byKey(const Key('plan_agenda_social_header')), findsOneWidget);
    expect(find.byKey(const Key('plan_agenda_social_ev1')), findsOneWidget);
  });

  testWidgets('行内容：舞名 + 目标类型 + 剩余天数 / 事件名 + 关联舞数', (tester) async {
    await _pumpPlan(tester, planJson: _planJson());
    final dueTile = tester.widget<ListTile>(
      find.byKey(const Key('plan_agenda_due_v1')),
    );
    expect(
      // 未署名舞名 = 「文件名回落名」（去扩展名）。
      dueTile.title is Text && (dueTile.title as Text).data == 'v1',
      isTrue,
    );
    expect((dueTile.subtitle! as Text).data, contains('约舞'));
    expect((dueTile.subtitle! as Text).data, contains('剩 2 天'));
    final reviewTile = tester.widget<ListTile>(
      find.byKey(const Key('plan_agenda_review_v1')),
    );
    expect((reviewTile.subtitle! as Text).data, contains('较熟'));
    final socialTile = tester.widget<ListTile>(
      find.byKey(const Key('plan_agenda_social_ev1')),
    );
    expect((socialTile.title! as Text).data, contains('公园'));
    expect((socialTile.subtitle! as Text).data, contains('2 支舞'));
  });

  testWidgets('空组不渲染：无事件且最近练过 → 团检 / 随舞组与待复习组不出现', (tester) async {
    await _pumpPlan(
      tester,
      planJson: {
        'version': 1,
        'entries': [
          {
            'videoId': 'v1',
            'ddl': {'date': planDayKey(_today.add(const Duration(days: 2)))},
          },
        ],
        'events': <Object>[],
      },
      // 昨天 1 小时练过 v1：较熟阈值 14 天内 → 不进待复习。
      records: [
        PracticeSessionRecord(
          start: _today.subtract(const Duration(days: 1)),
          videoId: 'v1',
          signature: const SongSignature(song: 'Alpha'),
          wallSeconds: 600,
        ),
      ],
    );
    expect(find.byKey(const Key('plan_agenda_due_header')), findsOneWidget);
    expect(find.byKey(const Key('plan_agenda_review_header')), findsNothing);
    expect(find.byKey(const Key('plan_agenda_social_header')), findsNothing);
  });

  testWidgets('点 DDL 行与待复习行进舞详情', (tester) async {
    await _pumpPlan(tester, planJson: _planJson());
    await tester.tap(find.byKey(const Key('plan_agenda_due_v1')));
    await tester.pumpAndSettle();
    expect(find.byType(DanceDetailPage), findsOneWidget);
  });

  testWidgets('点随舞临近行进事件编辑框', (tester) async {
    await _pumpPlan(tester, planJson: _planJson());
    await tester.ensureVisible(find.byKey(const Key('plan_agenda_social_ev1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan_agenda_social_ev1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan_event_dialog')), findsOneWidget);
  });
}
