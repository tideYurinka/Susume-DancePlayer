import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/dance/cover_cache.dart';
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:dance_learning_app/dance/dance_library_providers.dart';
import 'package:dance_learning_app/dance/dance_practice_totals.dart';
import 'package:dance_learning_app/import/import_providers.dart'
    show videoIndexStoreProvider;
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_providers.dart'
    show fourBeatBucketStoreProvider;
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart'
    show practicePlanStoreProvider;
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/stats/four_beat_bucket.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_member_scheme_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';

/// 舞库删除动作直测（「管理写」）：次序 = 索引条目先写、
/// 随后 best-effort 删文件；素材连带删除、练舞统计保留；索引写失败 =
/// 零副作用。经注入的读端口与内存替身，脱离 widget 与真实文件（素材与
/// 视频副本用临时目录里的真实文件，断言「文件真没了」）。
void main() {
  late Directory tempDir;
  late Directory materials;
  late File videoFileV1;
  late File materialFileV1;
  late File materialFileV2;
  late File orphanMaterialFile;
  late Map<String, InMemoryMemberSchemeStorage> schemeStorages;
  late MemoryManifestStorage manifestStorage;
  late InMemoryVideoIndexStorage indexStorage;
  late Map<String, InMemoryVideoDocumentStorage> documents;
  late InMemoryPracticeStatsStorage statsStorage;
  late PracticeStatsStore statsStore;
  late InMemoryPracticePlanStorage planStorage;
  late PracticePlanStore planStore;
  late InMemoryFourBeatBucketStorage bucketStorage;
  late FourBeatBucketStore bucketStore;
  late CoverCache coverCache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dance_delete_test');
    materials = Directory(p.join(tempDir.path, 'materials'));
    videoFileV1 = File(p.join(tempDir.path, 'v1.mp4'))
      ..writeAsStringSync('video-bytes');
    materialFileV1 = File(p.join(materials.path, 'v1', 'rec_1.mp4'))
      ..createSync(recursive: true)
      ..writeAsStringSync('material-v1');
    materialFileV2 = File(p.join(materials.path, 'v2', 'rec_2.mp4'))
      ..createSync(recursive: true)
      ..writeAsStringSync('material-v2');
    // 未入清单的录制残留（录制中断 / 清单写失败产物）：随该舞目录一并删净。
    orphanMaterialFile = File(p.join(materials.path, 'v1', 'rec_orphan.tmp'))
      ..writeAsStringSync('orphan');
    manifestStorage = MemoryManifestStorage();
    indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(
        entries: [
          _entry('v1', videoFileV1.path),
          _entry('v2', p.join(tempDir.path, 'v2.mp4')),
        ],
      ),
    );
    documents = {
      'v1': _documents(
        markers: MarkersDocument(
          rangeEndMs: 120000,
          segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
        ),
        local: const LocalDocument(mastery: {0: LearningMastery.mastered}),
      ),
      'v2': _documents(
        markers: const MarkersDocument(rangeEndMs: 60000),
        local: const LocalDocument.empty(),
      ),
    };
    statsStorage = InMemoryPracticeStatsStorage()
      ..rawJson = PracticeStatsDocument(
        sessions: [
          PracticeSessionRecord(
            start: DateTime(2026, 9, 10, 20),
            videoId: 'v1',
            signature: const SongSignature(song: 'v1 的歌'),
            wallSeconds: 180,
          ),
          PracticeSessionRecord(
            start: DateTime(2026, 9, 1, 20),
            videoId: 'v2',
            signature: const SongSignature(song: 'v2 的歌'),
            wallSeconds: 60,
          ),
        ],
      ).toJson();
    statsStore = PracticeStatsStore(statsStorage);
    planStorage = InMemoryPracticePlanStorage();
    planStore = PracticePlanStore(planStorage);
    // 计划条目：两支舞各有一条 DDL，断言删 v1 只清 v1 的。
    await planStore.setDdl(
      videoId: 'v1',
      ddl: DanceDdl(date: DateTime(2026, 10, 1), remark: 'v1 的计划'),
    );
    await planStore.setDdl(
      videoId: 'v2',
      ddl: DanceDdl(date: DateTime(2026, 11, 5), remark: 'v2 的计划'),
    );
    // 一场关联了两支舞的随舞事件：断言删 v1 只摘 v1 的关联项，事件保留。
    await planStore.saveEvent(
      PlanEvent(
        id: 'e1',
        date: DateTime(2026, 11, 8),
        danceIds: const ['v1', 'v2'],
      ),
    );
    bucketStorage = InMemoryFourBeatBucketStorage();
    bucketStore = FourBeatBucketStore(bucketStorage);
    for (final videoId in ['v1', 'v2']) {
      await bucketStore.recordCredits(
        videoId: videoId,
        signature: SongSignature(song: '$videoId 的歌'),
        credits: [
          FourBeatBucketCredit(
            day: DateTime(2026, 9, 10),
            bucket: 1,
            wallSeconds: 12,
            sweeps: 1,
          ),
        ],
      );
    }
    await bucketStore.settle();
    final manifest = MaterialManifestStore(manifestStorage);
    await manifest.append(_material('m1', 'v1', 'rec_1.mp4'));
    await manifest.append(_material('m2', 'v2', 'rec_2.mp4'));
    schemeStorages = {
      'v1': InMemoryMemberSchemeStorage(),
      'v2': InMemoryMemberSchemeStorage(),
    };
    await MemberSchemeStore(schemeStorages['v1']!).upsert(_scheme('s1'));
    await MemberSchemeStore(schemeStorages['v2']!).upsert(_scheme('s2'));
    // 封面缓存：临时目录里的真实文件——断言「该舞图片真没了」。
    coverCache = FileCoverCache(() async => tempDir);
    for (final videoId in ['v1', 'v2']) {
      final temp = await coverCache.tempFileFor(videoId);
      await temp.writeAsString('cover-$videoId');
      await coverCache.writeFrom(videoId, temp, Duration.zero);
    }
  });

  tearDown(() async => tempDir.delete(recursive: true));

  ProviderContainer container({
    VideoIndexStorage? indexOverride,
    Map<String, InMemoryVideoDocumentStorage>? documentsOverride,
  }) {
    final container = ProviderContainer(
      overrides: [
        videoIndexStoreProvider.overrideWithValue(
          indexOverride ?? indexStorage,
        ),
        videoDocumentStorageFactoryProvider.overrideWithValue(
          (videoId) =>
              (documentsOverride ?? documents)[videoId] ??
              InMemoryVideoDocumentStorage(),
        ),
        practiceStatsStoreProvider.overrideWithValue(statsStore),
        practicePlanStoreProvider.overrideWithValue(planStore),
        fourBeatBucketStoreProvider.overrideWithValue(bucketStore),
        materialsBaseDirectoryProvider.overrideWithValue(() async => materials),
        materialManifestStorageProvider.overrideWithValue(manifestStorage),
        memberSchemeStorageProvider.overrideWith(
          (ref, videoId) => schemeStorages.putIfAbsent(
            videoId,
            InMemoryMemberSchemeStorage.new,
          ),
        ),
        coverCacheProvider.overrideWith((ref) => coverCache),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('删除：索引条目先写 → 视频副本 / 两份文档 / 该舞素材与清单条目一并删除，其余舞不受影响', () async {
    final harness = container();

    await deleteDance(harness.read(_refProvider), 'v1');

    // 索引：条目没了，另一支还在。
    expect(indexStorage.current.entries.map((e) => e.videoId), ['v2']);
    // 视频副本没了。
    expect(videoFileV1.existsSync(), isFalse);
    // 两份文档没了（读回空态）；另一支的文档还在。
    expect(await documents['v1']!.loadMarkersOrNull(), isNull);
    expect(await documents['v1']!.loadLocal(), isEmpty);
    expect(documents['v2']!.markersSnapshot, isNotEmpty);
    // 该舞素材：清单条目对应的文件、未入清单的录制残留与整个素材目录一并
    // 消失（不留再也进不去的孤儿素材）；别的舞素材还在。
    expect(materialFileV1.existsSync(), isFalse);
    expect(orphanMaterialFile.existsSync(), isFalse);
    expect(Directory(p.join(materials.path, 'v1')).existsSync(), isFalse);
    expect(materialFileV2.existsSync(), isTrue);
    // 清单条目：只剩另一支舞的。
    final manifest = await MaterialManifestStore(manifestStorage).read();
    expect(manifest.materials.map((m) => m.videoId), ['v2']);
    // 组员方案文件随舞删除：v1 的清了，v2 的还在。
    expect(
      await MemberSchemeStore(schemeStorages['v1']!).read(),
      MemberSchemesDocument.empty,
    );
    expect(
      (await MemberSchemeStore(schemeStorages['v2']!).read()).schemes,
      hasLength(1),
    );
    // 四拍桶分片随舞删除（见词条「四拍桶」）：v1 的清空、v2 的还在。
    expect((await bucketStore.shard('v1')).days, isEmpty);
    expect((await bucketStore.shard('v2')).days, isNotEmpty);
    // 封面缓存随舞删除：v1 的没了、v2 的还在。
    expect(await coverCache.readyCover('v1', Duration.zero), isNull);
    expect(await coverCache.readyCover('v2', Duration.zero), isNotNull);
    // 计划项随舞删除：v1 的 DDL 条目整条清掉、v2 的
    // 还在；事件条目保留、关联清单少一项。
    expect(await planStore.ddlOf('v1'), isNull);
    expect(
      await planStore.ddlOf('v2'),
      DanceDdl(date: DateTime(2026, 11, 5), remark: 'v2 的计划'),
    );
    final events = await planStore.events();
    expect(events.single.id, 'e1');
    expect(events.single.danceIds, ['v2']);
  });

  test('删除这支舞：只读原文（读不懂、写不回去）先留档再删，原件可捞回', () async {
    final harness = container();
    final storage = documents['v1']!;
    // 本机这支舞的公开标记文件读不懂（高于本版）：常规写回会被版本政策挡住，
    // 但用户显式删除是一条绕过版本政策的破坏性路径——留档须盖住它。
    await storage.saveMarkers(const {
      'version': 99,
      'meta': {'signature': {'song': '读不懂的旧舞'}},
    });
    expect(storage.quarantined, isEmpty, reason: '写入可写文件不留档');

    await deleteDance(harness.read(_refProvider), 'v1');

    expect(storage.quarantined, hasLength(1), reason: '删除只读原文前先留档');
    expect(storage.quarantined.values.single, contains('"version":99'));
    expect(await storage.loadMarkersOrNull(), isNull, reason: '文档照常删除');
  });

  test('练舞统计不清理：该舞历史时长与署名快照保留，总练习量不随删除缩水', () async {
    final harness = container();

    await deleteDance(harness.read(_refProvider), 'v1');

    final records = await statsStore.records();
    final kept = records.where((r) => r.videoId == 'v1').toList();
    expect(kept, hasLength(1));
    expect(kept.single.wallSeconds, 180);
    expect(kept.single.signature.song, 'v1 的歌');
    final totals = dancePracticeTotalsByVideo(records);
    expect(totals['v1']?.total, const Duration(minutes: 3));
    expect(totals['v2']?.total, const Duration(minutes: 1));
  });

  test('索引写失败：整个删除不成立、零副作用（索引先写的可观察面）', () async {
    final harness = container(
      indexOverride: _ThrowingUpdateIndexStorage(indexStorage),
    );

    await expectLater(
      deleteDance(harness.read(_refProvider), 'v1'),
      throwsA(isA<StateError>()),
    );

    expect(indexStorage.current.entries.map((e) => e.videoId), ['v1', 'v2']);
    expect(videoFileV1.existsSync(), isTrue);
    expect(await documents['v1']!.loadMarkersOrNull(), isNotNull);
    expect(materialFileV1.existsSync(), isTrue);
    expect(orphanMaterialFile.existsSync(), isTrue);
    final manifest = await MaterialManifestStore(manifestStorage).read();
    expect(manifest.materials.map((m) => m.videoId), ['v1', 'v2']);
  });

  test('未落条目的舞：无对象、零副作用（不写索引、不动文件）', () async {
    final harness = container();

    await deleteDance(harness.read(_refProvider), 'missing');

    expect(indexStorage.updateCount, 0);
    expect(videoFileV1.existsSync(), isTrue);
    expect(materialFileV1.existsSync(), isTrue);
    final manifest = await MaterialManifestStore(manifestStorage).read();
    expect(manifest.materials, hasLength(2));
  });

  test('文件删除失败：不回滚索引、不阻断其余删除、不向调用方抛错', () async {
    final throwingDocuments = {...documents, 'v1': _ThrowingDeleteStorage()};
    final harness = container(documentsOverride: throwingDocuments);

    await deleteDance(harness.read(_refProvider), 'v1');

    expect(indexStorage.current.entries.map((e) => e.videoId), ['v2']);
    expect(videoFileV1.existsSync(), isFalse);
    // 文档删除失败只留孤儿文档，素材删除继续执行。
    expect(throwingDocuments['v1']!.markersSnapshot, isNotEmpty);
    expect(materialFileV1.existsSync(), isFalse);
    expect(materialFileV2.existsSync(), isTrue);
    final manifest = await MaterialManifestStore(manifestStorage).read();
    expect(manifest.materials.map((m) => m.videoId), ['v2']);
    // 组员方案文件随舞删除：v1 的清了，v2 的还在。
    expect(
      await MemberSchemeStore(schemeStorages['v1']!).read(),
      MemberSchemesDocument.empty,
    );
    expect(
      (await MemberSchemeStore(schemeStorages['v2']!).read()).schemes,
      hasLength(1),
    );
  });

  test('写后失效：删除后整库读面与单支读面不再列出该舞', () async {
    final harness = container();
    final ref = harness.read(_refProvider);
    final batchSub = harness.listen(danceLibrarySnapshotProvider, (_, _) {});
    final singleSub = harness.listen(danceSnapshotProvider('v1'), (_, _) {});
    addTearDown(batchSub.close);
    addTearDown(singleSub.close);

    final before = await harness.read(danceLibrarySnapshotProvider.future);
    expect(before.dances.map((d) => d.videoId), ['v1', 'v2']);

    await deleteDance(ref, 'v1');

    final after = await harness.read(danceLibrarySnapshotProvider.future);
    expect(after.dances.map((d) => d.videoId), ['v2']);
    expect(await harness.read(danceSnapshotProvider('v1').future), isNull);
    expect(
      (await harness.read(danceSnapshotProvider('v2').future))?.videoId,
      'v2',
    );
  });
}

final _refProvider = Provider<Ref>((ref) => ref);

/// 写即失败的索引存储（索引写失败路径用）。
class _ThrowingUpdateIndexStorage implements VideoIndexStorage {
  _ThrowingUpdateIndexStorage(this._inner);

  final VideoIndexStorage _inner;

  @override
  Future<VideoIndex> load() => _inner.load();

  @override
  Future<VideoIndex> update(
    FutureOr<VideoIndex> Function(VideoIndex current) mutate,
  ) async => throw StateError('索引写失败');
}

/// 删除即失败的文档存储（文件删除失败 best-effort 路径用）。
class _ThrowingDeleteStorage extends InMemoryVideoDocumentStorage {
  _ThrowingDeleteStorage() : super(markers: const {'version': 1});

  @override
  Future<void> delete() async => throw FileSystemException('locked');
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

MaterialRecord _material(String id, String videoId, String fileName) =>
    MaterialRecord(
      id: id,
      videoId: videoId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      durationMs: 8000,
      sourceStartMs: 0,
      fileName: fileName,
      sizeBytes: 42,
    );

InMemoryVideoDocumentStorage _documents({
  required MarkersDocument markers,
  required LocalDocument local,
}) => InMemoryVideoDocumentStorage(
  markers: markers.toJson(),
  local: local.toJson(),
);

MemberSchemeRecord _scheme(String schemeId) => MemberSchemeRecord(
      schemeId: schemeId,
      memberName: '小如',
      importedAt: DateTime(2026, 9, 1),
      markers: const {'version': 3},
    );
