import 'dart:io';

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/home/dance_detail_page.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/index_file_provider.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_providers.dart'
    show fourBeatBucketStoreProvider;
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart'
    show practicePlanStorageProvider;
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/stats/four_beat_bucket.dart';
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/in_memory_cover_cache.dart';
import '../helpers/device_viewport.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_member_scheme_storage.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';

/// 部件级闭环：首页舞库 → 卡片角进详情 → 二次确认删除 → 回首页
/// 卡片消失；视频副本、该舞素材文件与清单条目一并没了；练舞统计保留；
/// 「重开」（同一持久化存储、新容器）该舞仍不出现、素材不复活。
///
/// 复用素材库既有删除测试形态（真实临时目录 + 内存清单存储）与打开恢复的
/// 部件级闭环形态（同一存储重新装配）。
void main() {
  testWidgets('删除闭环：确认后卡片消失、文件与清单条目没了、统计保留；重开不出现', (tester) async {
    useNamedViewport(tester, ViewportTier.compact);
    final tempDir = Directory.systemTemp.createTempSync('dance_delete_flow');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final materialsBase = Directory(p.join(tempDir.path, 'materials'));
    final videoFile = File(p.join(tempDir.path, 'v1.mp4'))
      ..writeAsStringSync('video-bytes');
    final indexFile = File(p.join(tempDir.path, 'index.json'));
    final materialFile = File(p.join(materialsBase.path, 'v1', 'rec_1.mp4'))
      ..createSync(recursive: true)
      ..writeAsStringSync('material-v1');

    final indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [_entry('v1', videoFile.path)]),
    );
    final documents = {
      'v1': InMemoryVideoDocumentStorage(
        markers: const MarkersDocument(rangeEndMs: 120000).toJson(),
        local: const LocalDocument.empty().toJson(),
      ),
    };
    final statsStorage = InMemoryPracticeStatsStorage()
      ..rawJson = PracticeStatsDocument(
        sessions: [
          PracticeSessionRecord(
            start: DateTime(2026, 9, 10, 20),
            videoId: 'v1',
            signature: const SongSignature(song: 'v1 的歌'),
            wallSeconds: 180,
          ),
        ],
      ).toJson();
    final statsStore = PracticeStatsStore(statsStorage);
    final bucketStorage = InMemoryFourBeatBucketStorage();
    final bucketStore = FourBeatBucketStore(bucketStorage);
    await bucketStore.recordCredits(
      videoId: 'v1',
      signature: const SongSignature(song: 'v1 的歌'),
      credits: [
        FourBeatBucketCredit(
          day: DateTime(2026, 9, 10),
          bucket: 2,
          wallSeconds: 30,
          sweeps: 1,
        ),
      ],
    );
    await bucketStore.settle();
    final manifestStorage = MemoryManifestStorage();
    final planStorage = InMemoryPracticePlanStorage();
    await MaterialManifestStore(manifestStorage).append(
      MaterialRecord(
        id: 'm1',
        videoId: 'v1',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        durationMs: 8000,
        sourceStartMs: 0,
        fileName: 'rec_1.mp4',
        sizeBytes: 42,
      ),
    );

    Future<void> pumpApp({Key? key}) async {
      await tester.pumpWidget(
        ProviderScope(
          key: key,
          overrides: [
            videoIndexStoreProvider.overrideWithValue(indexStorage),
            importIndexFileProvider.overrideWithValue(Future.value(indexFile)),
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => documents[videoId] ?? InMemoryVideoDocumentStorage(),
            ),
            coverCacheProvider.overrideWith((ref) => InMemoryCoverCache()),
            practiceStatsStoreProvider.overrideWithValue(statsStore),
            fourBeatBucketStoreProvider.overrideWithValue(bucketStore),
            materialsBaseDirectoryProvider.overrideWithValue(
              () async => materialsBase,
            ),
            materialManifestStorageProvider.overrideWithValue(manifestStorage),
            memberSchemeStorageProvider.overrideWith(
              (ref, videoId) => InMemoryMemberSchemeStorage(),
            ),
            // 计划项清理注入内存存储：测试环境不走
            // 真实 path_provider。
            practicePlanStorageProvider.overrideWithValue(planStorage),
          ],
          child: const DanceLearningApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpApp();
    expect(find.byKey(const Key('dance_card_v1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dance_card_detail_v1')));
    await tester.pumpAndSettle();
    expect(find.byType(DanceDetailPage), findsOneWidget);

    await tester.tap(find.byKey(const Key('dance_detail_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dance_detail_delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dance_delete_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dance_delete_confirm')));
    await tester.pumpAndSettle();

    // 回到首页：卡片消失、空态出现。
    expect(find.byType(DanceDetailPage), findsNothing);
    expect(find.byKey(const Key('dance_card_v1')), findsNothing);
    expect(find.byKey(const Key('dance_library_empty')), findsOneWidget);
    // 文件真没了：视频副本 + 该舞素材文件。
    expect(videoFile.existsSync(), isFalse);
    expect(materialFile.existsSync(), isFalse);
    // 组员方案随舞删除：注入的存储读回空态。
    // 素材清单条目没了。
    expect(
      (await MaterialManifestStore(manifestStorage).read()).materials,
      isEmpty,
    );
    // 练舞统计保留该舞的历史时长与署名快照；四拍桶分片随舞删除。
    final records = await statsStore.records();
    expect(records, hasLength(1));
    expect(records.single.videoId, 'v1');
    expect(records.single.signature.song, 'v1 的歌');
    expect((await bucketStore.shard('v1')).days, isEmpty);

    // 重开：同一持久化存储、新容器 → 该舞仍不出现、素材不复活。
    await pumpApp(key: UniqueKey());
    expect(find.byKey(const Key('dance_card_v1')), findsNothing);
    expect(find.byKey(const Key('dance_library_empty')), findsOneWidget);
    expect(materialFile.existsSync(), isFalse);
    expect(
      (await FourBeatBucketStore(bucketStorage).shard('v1')).days,
      isEmpty,
    );
  });
}

VideoIndexEntry _entry(String videoId, String filePath) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: filePath,
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);
