import 'dart:io';

import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/dance/cover_cache.dart';
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:dance_learning_app/dance/dance_library_providers.dart';
import 'package:dance_learning_app/dance/video_copy_presence.dart';
import 'package:dance_learning_app/import/import_providers.dart'
    show videoIndexStoreProvider;
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart'
    show practicePlanStorageProvider;
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_video_copy_presence.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/jpeg_bytes.dart';

/// 舞库装配层直测：provider 经注入的读端口（既有内存替身）装配四个来源，
/// 脱离 widget 与真实文件。
void main() {
  test('整库入口：一次装入索引 + 两份文档 + 一次统计聚合，卡片量齐全', () async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(
            signature: const SongSignature(dancer: '如', song: '真值名'),
            rangeStartMs: 10000,
            rangeEndMs: 120000,
            segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
          ),
          local: const LocalDocument(
            mastery: {
              0: LearningMastery.mastered,
              1: LearningMastery.keepingUp,
            },
          ),
        ),
      },
      records: [_record('v1', DateTime(2026, 9, 10, 20), wallSeconds: 180)],
    );
    addTearDown(harness.container.dispose);

    final snapshot = await harness.container.read(
      danceLibrarySnapshotProvider.future,
    );

    expect(snapshot.dances, hasLength(2));
    // 练过的舞在前；没练过的排在其类别尾部。
    expect([for (final dance in snapshot.dances) dance.videoId], ['v1', 'v2']);
    final practiced = snapshot.dances.first;
    expect(practiced.title, '「如」真值名');
    expect(practiced.masteryPercent, 75.0);
    expect(practiced.fullyMastered, isFalse);
    expect(practiced.practiceTotal, const Duration(minutes: 3));
    expect(practiced.lastPracticedAt, DateTime(2026, 9, 10, 20, 3));
    expect(practiced.coverPosition, const Duration(seconds: 10));

    // 缺文档、缺统计的舞如实兜底。
    final untouched = snapshot.dances.last;
    expect(untouched.masteryPercent, isNull);
    expect(untouched.fullyMastered, isFalse);
    expect(untouched.practiceTotal, Duration.zero);
    expect(untouched.lastPracticedAt, isNull);
    // 未署名：标题回退「文件名回落名」（去扩展名）。
    expect(untouched.title, 'v2');
  });

  test('封面引用：位置取公开标记文件的 meta 字段，就绪取缓存文件是否存在', () async {
    final coverDirectory = await Directory.systemTemp.createTemp(
      'provider_cover_test',
    );
    addTearDown(() => coverDirectory.delete(recursive: true));
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      documents: {
        'v1': _documents(
          markers: const MarkersDocument(
            rangeStartMs: 10000,
            rangeEndMs: 120000,
            coverPositionMs: 42000,
          ),
          local: const LocalDocument.empty(),
        ),
      },
      coverDirectory: coverDirectory,
    );
    addTearDown(harness.container.dispose);
    // v1 有缓存图片（横屏 4:3）、v2 没有；v1 的封面位置是显式值。
    final temp = await harness.coverCache.tempFileFor('v1');
    await temp.writeAsBytes(fakeJpegBytes(width: 720, height: 540));
    await harness.coverCache.writeFrom('v1', temp, const Duration(seconds: 42));

    final snapshot = await harness.container.read(
      danceLibrarySnapshotProvider.future,
    );
    final byId = {for (final dance in snapshot.dances) dance.videoId: dance};

    expect(byId['v1']!.coverPosition, const Duration(seconds: 42));
    expect(byId['v1']!.coverReady, isTrue);
    expect(byId['v1']!.coverAspectRatio, closeTo(4 / 3, 1e-9));
    // v2 无文档：位置缺省跟随首线（无有效区间 ⇒ 第 0 帧），缓存未就绪。
    expect(byId['v2']!.coverPosition, Duration.zero);
    expect(byId['v2']!.coverReady, isFalse);
    expect(byId['v2']!.coverAspectRatio, 3 / 4);

    // 单支舞入口同源同口径。
    final single = await harness.container.read(
      danceSnapshotProvider('v1').future,
    );
    expect(single, byId['v1']);
  });

  test('紧急度接线：计划文档的 DDL 装进整库与单舞读面', () async {
    final today = DateTime.now();
    final due = DateTime(today.year, today.month, today.day + 2);
    final dueKey =
        '${due.year.toString().padLeft(4, '0')}-'
        '${due.month.toString().padLeft(2, '0')}-'
        '${due.day.toString().padLeft(2, '0')}';
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      planRawJson: {
        'version': 1,
        'entries': [
          {
            'videoId': 'v1',
            'ddl': {'date': dueKey, 'occasion': '约舞'},
          },
        ],
      },
    );
    addTearDown(harness.container.dispose);

    final snapshot = await harness.container.read(
      danceLibrarySnapshotProvider.future,
    );
    final byId = {for (final dance in snapshot.dances) dance.videoId: dance};
    expect(byId['v1']!.urgency!.dueDay, due);
    expect(byId['v1']!.urgency!.overdue, isFalse);
    expect(byId['v2']!.urgency, isNull);

    final single = await harness.container.read(
      danceSnapshotProvider('v1').future,
    );
    expect(single, byId['v1']);
    // 有 DDL 的舞排到无目标者前面。
    expect(snapshot.dances.first.videoId, 'v1');
  });

  test('单支舞入口与批量结果一致；未落条目的舞返回 null', () async {
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(
            rangeEndMs: 120000,
            segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
          ),
          local: const LocalDocument(
            mastery: {0: LearningMastery.mastered, 1: LearningMastery.mastered},
          ),
        ),
      },
      records: [_record('v1', DateTime(2026, 9, 10), wallSeconds: 60)],
    );
    addTearDown(harness.container.dispose);

    final batch = await harness.container.read(
      danceLibrarySnapshotProvider.future,
    );
    final single = await harness.container.read(
      danceSnapshotProvider('v1').future,
    );

    expect(single, batch.dances.single);
    expect(
      await harness.container.read(danceSnapshotProvider('missing').future),
      isNull,
    );
  });

  test('副本丢失：一次装入里逐舞问一次存在性，读数带丢失事实', () async {
    final copyPresence = FakeVideoCopyPresence(
      missingPaths: const {'/videos/v2.mp4'},
    );
    final harness = _Harness(
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      copyPresence: copyPresence,
    );
    addTearDown(harness.container.dispose);

    final snapshot = await harness.container.read(
      danceLibrarySnapshotProvider.future,
    );
    final byId = {for (final dance in snapshot.dances) dance.videoId: dance};

    expect(byId['v1']!.copyMissing, isFalse);
    expect(byId['v2']!.copyMissing, isTrue);
    // 无巡检、无轮询：这一次装入里每支舞按条目路径问一次，问完即止。
    expect(copyPresence.consulted, ['/videos/v1.mp4', '/videos/v2.mp4']);
  });

  test('恢复不带媒体的整机备份：条目与文档都在、副本不在 ⇒ 以丢失呈现', () async {
    // 恢复把条目与两份文档写了回来，媒体目录是空的（备份未带媒体）：
    // 存在性判定走生产实现，读面如实带出丢失事实。
    final mediaDir = await Directory.systemTemp.createTemp('restored_no_media');
    addTearDown(() => mediaDir.delete(recursive: true));
    final harness = _Harness(
      index: VideoIndex(
        entries: [_entry('v1', filePath: '${mediaDir.path}/v1.mp4')],
      ),
      documents: {
        'v1': _documents(
          markers: MarkersDocument(
            rangeEndMs: 120000,
            segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
          ),
          local: const LocalDocument(mastery: {0: LearningMastery.mastered}),
        ),
      },
      copyPresence: const FileVideoCopyPresence(),
    );
    addTearDown(harness.container.dispose);

    final snapshot = await harness.container.read(
      danceLibrarySnapshotProvider.future,
    );

    expect(snapshot.dances.single.copyMissing, isTrue);
    // 丢的是视频副本，不是标注：文档读面照常（两段里第 0 段「掌握」= 50）。
    expect(snapshot.dances.single.masteryPercent, 50.0);
  });

  test('写后失效：管理写落盘后 invalidate，两个读面一起重算', () async {
    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    addTearDown(harness.container.dispose);
    final ref = harness.container.read(_refProvider);
    // 页面在场：订阅保持读面存活（autoDispose 的存活条件）。
    final batchSub = harness.container.listen(
      danceLibrarySnapshotProvider,
      (_, _) {},
    );
    final singleSub = harness.container.listen(
      danceSnapshotProvider('v1'),
      (_, _) {},
    );
    addTearDown(batchSub.close);
    addTearDown(singleSub.close);

    final beforeBatch = await harness.container.read(
      danceLibrarySnapshotProvider.future,
    );
    expect(beforeBatch.dances.single.practiceTotal, Duration.zero);
    final beforeSingle = await harness.container.read(
      danceSnapshotProvider('v1').future,
    );
    expect(beforeSingle!.practiceTotal, Duration.zero);

    // 写侧：练舞统计落盘（本切片不含管理写路径，模拟写后状态变化）。
    await harness.store.recordPlaying(
      videoId: 'v1',
      signature: const SongSignature(song: 's'),
      start: DateTime(2026, 9, 10, 20),
      end: DateTime(2026, 9, 10, 20, 3),
    );
    await harness.store.settle();

    invalidateDanceLibrary(ref);

    final afterBatch = await harness.container.read(
      danceLibrarySnapshotProvider.future,
    );
    expect(afterBatch.dances.single.practiceTotal, const Duration(minutes: 3));
    expect(
      afterBatch.dances.single.lastPracticedAt,
      DateTime(2026, 9, 10, 20, 3),
    );
    final afterSingle = await harness.container.read(
      danceSnapshotProvider('v1').future,
    );
    expect(afterSingle, afterBatch.dances.single);
  });

  test('页面不在场即释放：重新订阅时重算（进页面重算）', () async {
    final harness = _Harness(index: VideoIndex(entries: [_entry('v1')]));
    addTearDown(harness.container.dispose);

    final batchSub = harness.container.listen(
      danceLibrarySnapshotProvider,
      (_, _) {},
    );
    final first = await harness.container.read(
      danceLibrarySnapshotProvider.future,
    );
    expect(first.dances.single.importOrder, 0);
    batchSub.close();
    await Future<void>.delayed(Duration.zero);

    // 释放后索引变化：下次订阅（进页面）读到新的一支舞。
    await harness.indexStorage.update((index) => index.upsert(_entry('v2')));

    final second = await harness.container.read(
      danceLibrarySnapshotProvider.future,
    );
    // 重算看到新导入的舞；未练组按导入次序倒序（后导入在前）。
    expect([for (final dance in second.dances) dance.videoId], ['v2', 'v1']);
  });
}

final _refProvider = Provider<Ref>((ref) => ref);

class _Harness {
  _Harness({
    required VideoIndex index,
    Map<String, InMemoryVideoDocumentStorage> documents = const {},
    List<PracticeSessionRecord> records = const [],
    Directory? coverDirectory,
    Map<String, dynamic>? planRawJson,
    VideoCopyPresence? copyPresence,
  }) : statsStorage = InMemoryPracticeStatsStorage() {
    if (records.isNotEmpty) {
      statsStorage.rawJson = PracticeStatsDocument(sessions: records).toJson();
    }
    store = PracticeStatsStore(statsStorage);
    indexStorage = InMemoryVideoIndexStorage(initial: index);
    coverCache = FileCoverCache(
      () async => coverDirectory ?? Directory.systemTemp,
    );
    planStorage = InMemoryPracticePlanStorage()..rawJson = planRawJson;
    container = ProviderContainer(
      overrides: [
        videoIndexStoreProvider.overrideWithValue(indexStorage),
        videoDocumentStorageFactoryProvider.overrideWithValue(
          (videoId) => documents[videoId] ?? InMemoryVideoDocumentStorage(),
        ),
        practiceStatsStoreProvider.overrideWithValue(store),
        coverCacheProvider.overrideWith((ref) => coverCache),
        practicePlanStorageProvider.overrideWithValue(planStorage),
        // 缺省 = 副本都在场（既有用例的条目路径都是假的）；丢失用例显式喂假
        // 或换生产实现。
        videoCopyPresenceProvider.overrideWithValue(
          copyPresence ?? FakeVideoCopyPresence(),
        ),
      ],
    );
  }

  late final InMemoryPracticePlanStorage planStorage;

  final InMemoryPracticeStatsStorage statsStorage;
  late final InMemoryVideoIndexStorage indexStorage;
  late final PracticeStatsStore store;
  late final FileCoverCache coverCache;
  late final ProviderContainer container;
}

VideoIndexEntry _entry(String videoId, {String? filePath}) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: filePath ?? '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);

InMemoryVideoDocumentStorage _documents({
  required MarkersDocument markers,
  required LocalDocument local,
}) => InMemoryVideoDocumentStorage(
  markers: markers.toJson(),
  local: local.toJson(),
);

PracticeSessionRecord _record(
  String videoId,
  DateTime start, {
  required double wallSeconds,
}) => PracticeSessionRecord(
  start: start,
  videoId: videoId,
  signature: const SongSignature(song: 's'),
  wallSeconds: wallSeconds,
);
