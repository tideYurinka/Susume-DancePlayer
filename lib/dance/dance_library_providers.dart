/// 舞库装配层：把四个来源的读端口装成整库快照，并承载管理写的写后失效。
///
/// 单支舞入口由整库快照派生（同源是结构而非纪律）；逐段练习值另走
/// 练习分布读面（只读该舞的公开标记文件与四拍桶分片）。读面不设缓存：都
/// autoDispose（页面不在场即释放，进页面重算），每次装入都重新读索引、两份
/// 文档与一次统计聚合；管理写落盘后经 [invalidateDanceLibrary] 作废，页面
/// 在场时下次读重算。
/// 删除一支舞自持写路径 = [deleteDance] / [deleteDanceFrom]。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../import/import_providers.dart' show videoIndexStoreProvider;
import '../persistence/video_index.dart' show VideoIndexStorage;
import '../persistence/four_beat_bucket_providers.dart'
    show fourBeatBucketStoreProvider;
import '../persistence/four_beat_bucket_store.dart'
    show FourBeatBucketShard, FourBeatBucketStore, projectShardToCurrentGrid;
import '../persistence/local_document.dart';
import '../persistence/marker_document.dart';
import '../persistence/material_manifest.dart';
import '../persistence/member_scheme_store.dart'
    show MemberSchemeStorage, memberSchemeStorageProvider;
import '../persistence/practice_plan.dart' show DdlSettlementOutcome;
import '../persistence/practice_plan_providers.dart'
    show practicePlanStoreProvider;
// 练舞统计存取注入点取自持久化层（练舞统计存取替身复用既有 seam、不新增）；
// 舞库对本层只做单符号取用，依赖方向向下、无例外。
import '../persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import '../persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import '../persistence/video_document_store.dart' show VideoDocumentStorage;
import 'cover_frame_providers.dart' show coverCacheProvider;
import 'dance_library.dart';
import 'dance_library_writes.dart';
import 'dance_practice_totals.dart';
import 'practice_distribution.dart';
import 'segment_practice_aggregation.dart';
import 'video_copy_presence.dart';

/// 整库读面：一次装入索引 + 每支舞的公开标记文件与本地文档 +
/// 一次统计聚合，排序在快照上做。封面就绪 = 对应缓存文件存在（封面位置
/// 随快照从公开标记文件读出）；副本丢失 = 条目记录的副本路径不在盘上
/// （存在性判定经注入点问一次，见 `video_copy_presence.dart`）。
final danceLibrarySnapshotProvider =
    FutureProvider.autoDispose<DanceLibrarySnapshot>((ref) async {
      final indexStore = ref.watch(videoIndexStoreProvider);
      final storageFor = ref.watch(videoDocumentStorageFactoryProvider);
      final statsStore = ref.watch(practiceStatsStoreProvider);
      final copyPresence = ref.watch(videoCopyPresenceProvider);

      final index = await indexStore.load();
      final (markersByVideoId, localByVideoId) = await _loadDocuments(
        storageFor,
        [for (final entry in index.entries) entry.videoId],
      );
      final practiceByVideoId = dancePracticeTotalsByVideo(
        await statsStore.records(),
      );
      final (planGoalByVideoId, now) = await _planGoals(ref);

      return composeDanceLibrarySnapshot(
        index: index,
        markersByVideoId: markersByVideoId,
        localByVideoId: localByVideoId,
        practiceByVideoId: practiceByVideoId,
        copyExists: copyPresence.exists,
        planGoalByVideoId: planGoalByVideoId,
        now: now,
        coverAspectRatios: await _coverAspectRatios(ref, {
          for (final entry in index.entries)
            entry.videoId: coverPositionOf(
              markersByVideoId[entry.videoId] ?? const MarkersDocument.empty(),
            ),
        }),
      );
    });

/// 就绪封面的图片比例（键 = 已就绪且生成位置与当前封面位置一致的舞，
/// 值 = 宽 ÷ 高）：位置取读面唯一口径 [coverPositionOf]——首线一改，旧图
/// 不再算就绪，卡片按新位置重取。
///
/// 缓存目录不可解析（读不到本地缓存位置）按「一份封面也没有」处理——封面
/// 是设备本地缓存，取不到缓存不该让整个舞库读面失败；卡片照常出占位图。
Future<Map<String, double>> _coverAspectRatios(
  Ref ref,
  Map<String, Duration> positions,
) async {
  try {
    final cache = await ref.watch(coverCacheProvider.future);
    return await cache.readyCovers(positions);
  } on Object {
    return const <String, double>{};
  }
}

/// 单支舞入口（舞详情用）：由整库读面派生，未落条目的舞为 null。
/// 与整库入口同源同口径不是靠两处装配对齐，而是同一份快照的选择。
final danceSnapshotProvider = FutureProvider.autoDispose
    .family<DanceSnapshot?, String>((ref, videoId) async {
      final library = await ref.watch(danceLibrarySnapshotProvider.future);
      for (final dance in library.dances) {
        if (dance.videoId == videoId) return dance;
      }
      return null;
    });

/// 该舞的练习分布读面输入（详情页分布图用）：只读这一支舞的公开标记文件与
/// 四拍桶分片——分段线几何、就绪网格与桶读面在这里合流，页面按范围重算
/// 曲线与逐段值时不另读 IO。
final dancePracticeDistributionProvider = FutureProvider.autoDispose
    .family<PracticeDistributionInput, String>((ref, videoId) async {
      final markersJson = await ref
          .watch(videoDocumentStorageFactoryProvider)(videoId)
          .loadMarkers();
      final markers = MarkersDocument.fromJson(markersJson);
      final shard = await ref.watch(fourBeatBucketStoreProvider).shard(videoId);
      return practiceDistributionInputFor(
        markers,
        _bucketReadFace(shard, markers),
      );
    });

/// 紧急度输入：计划文档的按舞最近目标在合成舞库快照处接线，
/// 归一为（目标日 + 是否已按时落档）。时刻在一次装入里取一次，各舞共用
/// 同一口径。团内检查进入同一输入即自动生效。
Future<(Map<String, (DateTime, bool)>, DateTime)> _planGoals(Ref ref) async {
  final now = DateTime.now();
  try {
    final entries = await ref.watch(practicePlanStoreProvider).entries();
    return (
      {
        for (final entry in entries)
          if (entry.ddl case final ddl?)
            entry.videoId: (
              ddl.date,
              ddl.settlement?.outcome == DdlSettlementOutcome.onTime,
            ),
      },
      now,
    );
  } on Object {
    // 计划文档读不到按无目标兜底：紧急层缺席，舞库读面不因此失败。
    return (const <String, (DateTime, bool)>{}, now);
  }
}

/// 桶分片 → 纯值层可聚合读面（本地日 → 当前桶序号 → 值）：存储模型经
/// **读取时投影**（见词条「四拍桶」，装配在
/// [projectShardToCurrentGrid]）转入纯件——历史各倍频档的桶账归入当前
/// 桶格再聚合，磁盘上的桶明细一个字节不动。
Map<String, Map<int, SegmentBucketValue>> _bucketReadFace(
  FourBeatBucketShard shard,
  MarkersDocument? markers,
) => {
  for (final day in projectShardToCurrentGrid(shard, markers).entries)
    day.key: {
      for (final bucket in day.value.entries)
        bucket.key: SegmentBucketValue(
          wallSeconds: bucket.value.wallSeconds,
          sweeps: bucket.value.sweeps,
        ),
    },
};

/// 写后失效：管理写落盘后调用一次，读面与分布读面一起作废，下次读重算。
void invalidateDanceLibrary(Ref ref) {
  ref.invalidate(danceLibrarySnapshotProvider);
  ref.invalidate(dancePracticeDistributionProvider);
}

/// 改名成功后的观察者（装配处注册；舞库域不反向依赖功能层，同
/// `practicePlanStoreObserversProvider` 先例）：每条观察者拿到的舞名以索引
/// 署名缓存为准，故调用点在两条署名写之后。null = 无订阅。
final danceLibraryRenameObserversProvider =
    Provider<List<Future<void> Function()>?>((ref) => null);

/// 管理写入口（会话不在场时）：改名与后续的逐段改档共用
/// 同一条自持写路径；一次管理写落盘后经 [invalidateDanceLibraryFrom] 作废
/// 读面。
final danceLibraryWritesProvider = Provider.autoDispose<DanceLibraryWrites>((
  ref,
) {
  final observers = ref.watch(danceLibraryRenameObserversProvider);
  return DanceLibraryWrites(
    indexStore: ref.watch(videoIndexStoreProvider),
    storageFor: ref.watch(videoDocumentStorageFactoryProvider),
    onRenamed: observers == null
        ? null
        : () async {
            for (final observer in observers) {
              await observer();
            }
          },
  );
});

/// 写后失效（页面层入口）：页面自己读到落盘变化（导入的索引落条目、练完
/// 一段）后重算时经此入口——与 [invalidateDanceLibrary] 同一口径：读面与
/// 分布读面仍然一起作废。Riverpod 没有公共的 Ref/WidgetRef 共同超类型，
/// 故这一处列两遍读面（相邻同源，新增读面两处一起加）。
void invalidateDanceLibraryFrom(WidgetRef ref) {
  ref.invalidate(danceLibrarySnapshotProvider);
  ref.invalidate(dancePracticeDistributionProvider);
}

/// 删除动作的依赖端口：四个来源都在本文件既有注入点上，不新增 seam；
/// 两个入口共用同一份装配。副本存在性用读面同一处判定（[VideoCopyPresence]）
/// ——「副本在不在」这个问题全 App 只有这一个答案来源。
typedef _DanceDeletionPorts = ({
  VideoIndexStorage indexStore,
  VideoDocumentStorage Function(String videoId) documentStorageFor,
  Future<Directory> Function() materialsBaseDirectory,
  MaterialManifestStore manifestStore,
  MemberSchemeStorage Function(String videoId) memberSchemeStorageFor,
  FourBeatBucketStore bucketStore,
  VideoCopyPresence copyPresence,
  Future<void> Function(String videoId) deleteCover,
  Future<void> Function(String videoId) deletePlanForDance,
});

final _danceDeletionPortsProvider = Provider<_DanceDeletionPorts>(
  (ref) => (
    indexStore: ref.watch(videoIndexStoreProvider),
    documentStorageFor: ref.watch(videoDocumentStorageFactoryProvider),
    materialsBaseDirectory: ref.watch(materialsBaseDirectoryProvider),
    manifestStore: ref.watch(materialManifestStoreProvider),
    memberSchemeStorageFor: (videoId) =>
        ref.watch(memberSchemeStorageProvider(videoId)),
    bucketStore: ref.watch(fourBeatBucketStoreProvider),
    copyPresence: ref.watch(videoCopyPresenceProvider),
    // 封面缓存目录解析只在这一步发生（缓存不做成 provider 的同步依赖）。
    deleteCover: (videoId) async =>
        (await ref.read(coverCacheProvider.future)).deleteFor(videoId),
    // 计划项清理：经计划 store 的单一写入口。
    deletePlanForDance: (videoId) =>
        ref.watch(practicePlanStoreProvider).removeDance(videoId),
  ),
);

/// 删除一支舞（「管理写」）：次序是结构事实——① 视频索引
/// 条目先写（库立即不再列出该舞）；② 随后 best-effort 删视频副本、公开标记
/// 文件、本地文档、组员方案与该舞练习素材（文件 + 素材清单条目）、
/// 以及该舞的四拍桶分片（见词条「四拍桶」）；③ 练舞统计按时长与署名快照
/// 保留、不清理。
///
/// 索引写失败 = 整个删除不成立、零副作用：此刻尚未动任何文件，异常向上抛，
/// 读面也不作废。文件删除失败不弹错、不回滚索引、不阻断其余步骤，只留孤儿
/// 文件。未落条目的舞 = 无对象：什么都不做。落盘后两个读面一起作废。
Future<void> deleteDance(Ref ref, String videoId) async {
  await _deleteDance(ref.read(_danceDeletionPortsProvider), videoId);
  if (!ref.mounted) return;
  invalidateDanceLibrary(ref);
}

/// 删除一支舞（页面层入口）：与 [deleteDance] 同一动作、同一口径，只是写后
/// 失效入口不同（Riverpod 没有公共的 Ref/WidgetRef 共同超类型）。
Future<void> deleteDanceFrom(WidgetRef ref, String videoId) async {
  await _deleteDance(ref.read(_danceDeletionPortsProvider), videoId);
  invalidateDanceLibraryFrom(ref);
}

/// 删除动作本体：两个入口共用（管理写只有一条路径）。
Future<void> _deleteDance(_DanceDeletionPorts ports, String videoId) async {
  final entry = (await ports.indexStore.load()).findById(videoId);
  if (entry == null) return; // 无对象：零副作用，也不写索引。

  // ① 索引先写；失败向上抛，此刻文件原样（零副作用）。
  await ports.indexStore.update((index) => index.remove(videoId));

  // ② 文件 best-effort：单步失败静默吞掉，不回滚索引、不阻断其余步骤。
  await _bestEffort(
    () => _deleteVideoCopy(ports.copyPresence, entry.filePath),
  ); // 视频副本（副本丢失的舞此处是空操作，删除照常成立）
  await _bestEffort(() => ports.documentStorageFor(videoId).delete()); // 两份文档
  await _bestEffort(
    () => ports.memberSchemeStorageFor(videoId).delete(),
  ); // 组员方案文件（随舞删除）
  await _bestEffort(
    () => ports.bucketStore.deleteShard(videoId),
  ); // 四拍桶分片（见词条「四拍桶」：随舞删除；按天会话保留）
  await _bestEffort(() => ports.deleteCover(videoId)); // 封面缓存（随舞删除，不留再也进不去的画面）
  await _bestEffort(
    () => ports.deletePlanForDance(videoId),
  ); // 计划项（该舞 DDL 与清单随舞删除）
  await _deleteDanceMaterials(ports, videoId);
  // ③ 练舞统计不动：该舞的历史时长与署名快照按时长留在统计里。
}

/// 删除该舞的全部素材：① 清单条目一次删净（一次原子读改写）；② 素材文件
/// 按舞分目录整目录删净（清单条目外的录制残留一并消失，不留孤儿素材）。两步
/// 各自 best-effort：失败只留孤儿文件/条目，不回滚索引、不阻断另一步。
Future<void> _deleteDanceMaterials(
  _DanceDeletionPorts ports,
  String videoId,
) async {
  await _bestEffort(() => ports.manifestStore.removeByVideo(videoId));
  await _bestEffort(() async {
    final base = await ports.materialsBaseDirectory();
    await deleteMaterialFilesForVideo(base.path, videoId);
  });
}

/// best-effort 执行一步删除：失败静默——只留孤儿文件，不影响库的一致性。
Future<void> _bestEffort(Future<void> Function() step) async {
  try {
    await step();
  } on Object {
    // 文件删除失败不弹错、不回滚索引。
  }
}

/// 删除视频副本；副本不在（**副本丢失**）视作已删，是空操作——删一支丢失的
/// 舞照常成立，不留半个残骸。存在性问的是 [VideoCopyPresence] 那一处判定。
/// 删除本身是同步文件操作：widget 测试的 fake async 时钟下异步文件 IO 不可
/// 完成（与素材库删除同款）。
///
/// 空操作由本步自己保证，不指望调用方的兜底：判定说在、删的一刻恰好不在
/// （竞态）时，只有「文件不存在」一类错误被吞掉，别的错误照旧向上走。
Future<void> _deleteVideoCopy(VideoCopyPresence presence, String path) async {
  if (!presence.exists(path)) return;
  try {
    File(path).deleteSync();
  } on PathNotFoundException {
    // 谓词判在、删的一刻文件恰好没了：对不存在的文件删除是空操作。
  }
}

/// 按 videoId 读该舞的两份文档（缺失/损坏由文档层兜底为空态）。
Future<(Map<String, MarkersDocument>, Map<String, LocalDocument>)>
_loadDocuments(
  VideoDocumentStorage Function(String videoId) storageFor,
  List<String> videoIds,
) async {
  final markersByVideoId = <String, MarkersDocument>{};
  final localByVideoId = <String, LocalDocument>{};
  await Future.wait([
    for (final videoId in videoIds)
      () async {
        final storage = storageFor(videoId);
        final markersJson = await storage.loadMarkers();
        final localJson = await storage.loadLocal();
        markersByVideoId[videoId] = MarkersDocument.fromJson(markersJson);
        localByVideoId[videoId] = LocalDocument.fromJson(localJson);
      }(),
  ]);
  return (markersByVideoId, localByVideoId);
}
