import 'package:dance_learning_app/dance/dance_library_providers.dart';
import 'package:dance_learning_app/import/import_providers.dart'
    show videoIndexStoreProvider;
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart'
    show
        practicePlanMasteryResolverProvider,
        practicePlanStorageProvider,
        practicePlanStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/plan/system_push_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_push_port.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 推送同步接线：舞名表从视频索引的署名缓存读出（未署名回退
/// 文件名，与卡片标题同一处口径）；改名成功后补一次同步，已排标题随新名
/// 重排。装配只轻量读一份索引，不读整份舞库快照。
void main() {
  late InMemoryPushPort port;
  late InMemoryVideoDocumentStorage documents;
  late int snapshotReads;

  setUp(() {
    port = InMemoryPushPort();
    documents = InMemoryVideoDocumentStorage();
    snapshotReads = 0;
  });

  /// 装配 `main.dart` 里与舞库改名有关的那条接线
  /// （`danceLibraryRenameObserversProvider` → 推送同步）；计划写盘观察者不接
  /// ——本测试自己调同步，不必借计划写盘触发。索引读面换内存替身，整份舞库
  /// 快照一旦被读即计数。
  ProviderContainer build(VideoIndex index) {
    final container = ProviderContainer(
      overrides: [
        systemPushPortProvider.overrideWithValue(port),
        videoIndexStoreProvider.overrideWithValue(
          InMemoryVideoIndexStorage(initial: index),
        ),
        videoDocumentStorageFactoryProvider.overrideWithValue((_) => documents),
        practicePlanStorageProvider.overrideWithValue(
          InMemoryPracticePlanStorage(),
        ),
        practicePlanMasteryResolverProvider.overrideWithValue(
          (String videoId) async => null,
        ),
        danceLibraryRenameObserversProvider.overrideWith(
          (ref) => [ref.watch(planPushSyncProvider)],
        ),
        // 轻量读取的护栏：一旦本同步读了整份舞库快照，这里就会计数。
        danceLibrarySnapshotProvider.overrideWith((ref) {
          snapshotReads++;
          throw StateError('计划写盘不该读整份舞库快照');
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 落一条目标在 3 天后、提前 1 天提醒的 DDL（提前与自动两条来源都落在
  /// 将来）。
  Future<void> seedDdl(ProviderContainer container) async {
    final now = DateTime.now();
    await container
        .read(practicePlanStoreProvider)
        .setDdl(
          videoId: 'v1',
          ddl: DanceDdl(
            date: DateTime(now.year, now.month, now.day + 3),
            leadDays: 1,
          ),
        );
  }

  test('已署名：标题用索引署名缓存；不读整份舞库快照', () async {
    final container = build(
      VideoIndex(
        entries: [
          _entry(
            'v1',
            signatureCache: const SongSignature(dancer: '如', song: 'My Love'),
          ),
        ],
      ),
    );
    await seedDdl(container);

    await container.read(planPushSyncProvider)();

    expect(port.scheduled['ddl-lead:v1']!.title, '临近目标：「如」My Love');
    expect(port.scheduled['ddl-auto:v1']!.title, '临近目标：「如」My Love');
    expect(snapshotReads, 0, reason: '同步只读一份索引，不重建舞库读面');
  });

  test('未署名：标题与卡片同口径回退文件名', () async {
    final container = build(VideoIndex(entries: [_entry('v1')]));
    await seedDdl(container);

    await container.read(planPushSyncProvider)();

    expect(port.scheduled['ddl-lead:v1']!.title, '临近目标：v1.mp4');
  });

  test('改名成功即补同步：已排通知取消并按新舞名重排', () async {
    final index = VideoIndex(
      entries: [_entry('v1', signatureCache: const SongSignature(song: '旧名'))],
    );
    final container = build(index);
    await seedDdl(container);
    // 先按旧名排一次（改名前的在飞排程）。
    await container.read(planPushSyncProvider)();
    expect(port.scheduled['ddl-lead:v1']!.title, '临近目标：旧名');
    final listen = container.listen(danceLibraryWritesProvider, (_, _) {});
    addTearDown(listen.close);

    final renamed = await container
        .read(danceLibraryWritesProvider)
        .rename(
          entry: index.entries.single,
          input: const SongSignature(song: '新名'),
        );

    expect(renamed, isTrue);
    expect(port.cancelled, contains('ddl-lead:v1'));
    expect(port.scheduled['ddl-lead:v1']!.title, '临近目标：新名');
    expect(port.scheduled['ddl-auto:v1']!.title, '临近目标：新名');
    expect(snapshotReads, 0);
  });
}

VideoIndexEntry _entry(String videoId, {SongSignature? signatureCache}) =>
    VideoIndexEntry(
      videoId: videoId,
      displayName: '$videoId.mp4',
      filePath: '/videos/$videoId.mp4',
      sizeBytes: 1,
      fastKey: 'k-$videoId',
      mirrored: false,
      localMirrorEnabled: true,
      lastOpenedAt: DateTime(2026, 9, 1),
      signatureCache: signatureCache,
    );
