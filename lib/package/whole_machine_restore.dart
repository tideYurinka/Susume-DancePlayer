/// 整机恢复编排：导入路径识别出备份包后
/// 走恢复这一条链路——恢复不单独设入口。次序是结构事实：
///
/// 1. **留档先行**：用整机备份的采集端口把当前数据打成一份备份包落在固定
///    目录（`恢复留档/`，不进任何索引，用户可手动清）。留档不含媒体——
///    这些视频能重新拿到，留档只保「标注与设置」这份退路。**留档失败即
///    中止恢复**：此刻尚未动本机任何文件，异常折成明确失败向上报。
/// 2. **全量替换**：索引、每支舞的两份文档与组员方案、四拍桶
///    分片、练舞统计、设备级设置、素材清单都按备份原文整份覆盖写
///    （ADR-0002 完全私密字段随之归位），不合并、不保留本机较新值；包内
///    没有的桶（老包 v1）恢复成空。本机多出的舞（索引有条目而备份没有）
///    按「随舞删除」的口径 best-effort 清掉文档、组员方案、桶
///    分片、素材与视频副本。
/// 3. **媒体**：备份默认不含媒体；勾了媒体的包把源视频解出进本机视频
///    目录并把索引 `filePath` 指向本机副本、练习录像解出进素材目录。
///    未带媒体的舞恢复后索引里的 `filePath` 悬空（视频可重新导入，内容
///    哈希一致即回到同一条目）。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/atomic_json_file.dart';
import '../core/private_json.dart';
import '../import/import_providers.dart' show importVideosDirectoryProvider;
import '../persistence/index_file_provider.dart' show importIndexFileProvider;
import '../persistence/four_beat_bucket_providers.dart'
    show fourBeatBucketStorageProvider;
import '../persistence/four_beat_bucket_store.dart'
    show FourBeatBucketStorage;
import '../persistence/material_manifest.dart';
import '../persistence/member_scheme_store.dart';
import '../persistence/practice_stats.dart' show PracticeStatsStorage;
import '../persistence/practice_stats_providers.dart'
    show practiceStatsStorageProvider;
import '../persistence/practice_plan_providers.dart'
    show practicePlanStoreProvider;
import '../persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import '../persistence/video_document_store.dart'
    show VideoDocumentStorage;
import 'susume_package.dart';
import 'whole_machine_backup.dart';

/// 恢复的写端口 + 留档来源（留档复用整机备份的采集端口 [BackupPorts]）。
class RestorePorts {
  const RestorePorts({
    required this.backup,
    required this.indexFile,
    required this.documentStorageFor,
    required this.memberSchemeStorageFor,
    required this.bucketStorage,
    required this.practiceStatsStorage,
    required this.practicePlanReplace,
    required this.practicePlanRetainDances,
    required this.deviceSettingsStorage,
    required this.materialsStorage,
    required this.materialsBaseDirectory,
    required this.archiveDirectory,
    required this.videosDirectory,
  });

  /// 留档采集端口（[backupPortsProvider] 的生产来源）。
  final BackupPorts backup;

  /// `index.json`（整份原文覆盖写，条目扩展字段随备份原文保留）。
  final Future<File> Function() indexFile;

  /// 按舞双文档写入口。
  final VideoDocumentStorage Function(String videoId) documentStorageFor;

  final MemberSchemeStorage Function(String videoId) memberSchemeStorageFor;

  /// 按舞四拍桶分片存取（整份覆盖写；包内无该舞分片时删除本机分片）。
  final FourBeatBucketStorage bucketStorage;

  /// 练舞统计存取（整份覆盖写；老包缺该键时写空文档）。
  final PracticeStatsStorage practiceStatsStorage;

  /// 计划文档全量替换：按备份原文整份覆盖写，经
  /// 计划 store 单一写入口（老包缺该键时原文为空对象 = 空态）。
  final Future<void> Function(Map<String, Object?> json) practicePlanReplace;

  /// 「备份里没有的舞」的计划项清理：保留集之外的
  /// 舞条目整条清掉，事件条目保留、只摘掉这些舞的关联项。
  final Future<void> Function(Set<String> videoIds) practicePlanRetainDances;

  /// 设备级设置（`global_private.json` 整份覆盖写）。
  final PrivateJsonStorage deviceSettingsStorage;

  /// 素材清单（整份覆盖写）。
  final MaterialManifestStorage materialsStorage;

  /// 素材基目录（练习录像解出落位与本机多余舞的素材清理）。
  final Future<Directory> Function() materialsBaseDirectory;

  /// 留档的固定位置（可手动清：目录里的包文件就是全部留档）。
  final Future<Directory> Function() archiveDirectory;

  /// 本机视频目录（源视频副本解出落位）。
  final Future<Directory> Function() videosDirectory;
}

/// 恢复结果（对外可观察值）：完成或明确失败。message 为可直接展示的
/// 用户话术。
sealed class RestoreOutcome {
  const RestoreOutcome();
}

/// 恢复完成：[archiveFile] 是恢复前那份留档的位置。
class RestoreCompleted extends RestoreOutcome {
  const RestoreCompleted({required this.archiveFile});

  final File archiveFile;
}

/// 明确失败：留档失败（本机数据未动）或替换中途失败。
class RestoreFailed extends RestoreOutcome {
  const RestoreFailed(this.message);

  final String message;
}

/// 整机恢复编排。测试注入 fake 覆盖 [restore] 即可走通页面流程。
class WholeMachineRestorer {
  WholeMachineRestorer({required this.ports});

  final RestorePorts ports;

  /// 完整恢复：留档 → 全量替换 → 清本机多余舞。包解析已由导入路径完成
  /// （版本门与损坏报错归包模块），payload 版本门在这里。
  Future<RestoreOutcome> restore({
    required SusumePackage package,
    required String packagePath,
  }) async {
    final WholeMachineBackupPayload payload;
    try {
      payload = WholeMachineBackupPayload.fromJson(package.backup!);
    } on SusumePackageException catch (error) {
      return RestoreFailed(restoreErrorMessage(error));
    }

    // ① 留档先行；失败即中止——此刻尚未动本机任何文件。
    final File archiveFile;
    try {
      archiveFile = await _archiveCurrentData();
    } on Object {
      return const RestoreFailed('留档失败，已中止恢复，本机数据未改动');
    }

    // 全量替换前先记下本机现有的舞：索引被替换后就分不清哪些是本机多出的。
    final currentEntries = await _currentIndexEntries();
    // 本机尚在盘上的源视频（videoId → 路径）：未带媒体的舞替换后仍指向
    // 本机副本，「恢复错了还能退回去」才接得回视频（故事 50）。
    final localVideoPaths = _existingVideoFilesOf(currentEntries);

    // ② 全量替换。索引里的源视频路径按解出的本机副本改指；包里没带媒体
    // 而本机原视频尚在的，改指本机原视频。
    try {
      final videoPaths = await _extractMedia(package, packagePath, payload);
      await _replace(payload, videoPaths, localVideoPaths);
    } on Object catch (error) {
      return RestoreFailed(
        '恢复失败：$error。当前数据已留档在「恢复留档」，'
        '重新导入留档包可退回',
      );
    }

    // ③ 本机多出的舞 best-effort 清理：失败只留孤儿文件，不回滚。
    await _cleanupDancesNotInBackup(payload, currentEntries);
    return RestoreCompleted(archiveFile: archiveFile);
  }

  /// 当前索引条目原文（清理「本机多出的舞」的依据；缺失/损坏兜底空）。
  Future<List<Object?>> _currentIndexEntries() async {
    final indexJson =
        await AtomicJsonFile(await ports.indexFile()).readOrNull() ?? {};
    final entries = indexJson['entries'];
    return entries is List ? entries : const [];
  }

  /// 本机尚在盘上的源视频：videoId → 磁盘上确实存在的文件路径。
  Map<String, String> _existingVideoFilesOf(List<Object?> entries) {
    final paths = <String, String>{};
    for (final raw in entries) {
      if (raw is! Map) continue;
      final videoId = raw['videoId'];
      final filePath = raw['filePath'];
      if (videoId is! String || filePath is! String) continue;
      if (File(filePath).existsSync()) paths[videoId] = filePath;
    }
    return paths;
  }

  /// 当前数据留一份档：复用整机备份的采集与装配，落在 [RestorePorts
  /// .archiveDirectory]。
  Future<File> _archiveCurrentData() async {
    final collected = await collectWholeMachineBackup(
      ports.backup,
      includeMedia: false,
    );
    final archiveDir = await ports.archiveDirectory();
    await archiveDir.create(recursive: true);
    return assembleWholeMachineBackup(
      outputDir: archiveDir,
      payload: collected.payload,
      media: collected.media,
      now: DateTime.now(),
    );
  }

  /// 解出包内媒体：源视频进本机视频目录、练习录像进素材目录，返回
  /// videoId → 源视频本机路径（索引改指用）。
  Future<Map<String, String>> _extractMedia(
    SusumePackage package,
    String packagePath,
    WholeMachineBackupPayload payload,
  ) async {
    final videoPaths = <String, String>{};
    for (final dance in payload.dances) {
      if (dance.media.isEmpty) continue;
      final videos = await ports.videosDirectory();
      await videos.create(recursive: true);
      for (final name in dance.media) {
        final entry = package.manifest.media
            .where((candidate) => candidate.fileName == name)
            .firstOrNull;
        if (entry == null) continue;
        switch (entry.kind) {
          case SusumeMediaKind.sourceVideo:
            final dest = File(p.join(videos.path, name));
            await extractMediaEntry(packagePath, entry.entryName, dest);
            videoPaths[dance.videoId] = dest.path;
          case SusumeMediaKind.practiceClip:
            final base = await ports.materialsBaseDirectory();
            final dest = File(
              p.join(base.path, dance.videoId, backupMediaStrippedName(dance.videoId, name)),
            );
            await dest.parent.create(recursive: true);
            await extractMediaEntry(packagePath, entry.entryName, dest);
        }
      }
    }
    return videoPaths;
  }

  /// 全量替换：整份覆盖写，不合并。[videoPaths] = 包内解出的源视频改指；
  /// 包里没带媒体的舞回落 [localVideoPaths]（本机原视频尚在才改指）。
  Future<void> _replace(
    WholeMachineBackupPayload payload,
    Map<String, String> videoPaths,
    Map<String, String> localVideoPaths,
  ) async {
    final indexJson = Map<String, dynamic>.from(payload.index);
    final entries = indexJson['entries'];
    if (entries is List) {
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        if (entry is! Map) continue;
        final videoId = entry['videoId'];
        final repoint =
            videoPaths[videoId] ?? localVideoPaths[videoId];
        if (repoint != null) {
          entries[i] = {
            ...entry.cast<String, Object?>(),
            'filePath': repoint,
          };
        }
      }
    }
    await AtomicJsonFile(await ports.indexFile())
        .write(Map<String, dynamic>.from(indexJson));

    for (final dance in payload.dances) {
      final storage = ports.documentStorageFor(dance.videoId);
      await storage.saveMarkers(Map<String, dynamic>.from(dance.markers));
      await storage.saveLocal(Map<String, dynamic>.from(dance.local));
      await ports
          .memberSchemeStorageFor(dance.videoId)
          .save(Map<String, dynamic>.from(dance.schemes));
      // 桶分片全量替换：包内有该舞分片就整份覆盖；没有（旧包/无记录）就
      // 删掉本机分片——恢复后就是备份那一刻的样子，不合并。
      if (dance.buckets.isEmpty) {
        await ports.bucketStorage.delete(dance.videoId);
      } else {
        await ports.bucketStorage.save(
          dance.videoId,
          Map<String, dynamic>.from(dance.buckets),
        );
      }
    }
    await ports.practiceStatsStorage
        .save(Map<String, dynamic>.from(payload.practiceStats));
    await ports.practicePlanReplace(payload.practicePlan);
    await ports.deviceSettingsStorage
        .write(Map<String, dynamic>.from(payload.deviceSettings));
    await ports.materialsStorage
        .save(Map<String, dynamic>.from(payload.materialsManifest ?? {}));
  }

  /// 本机有而备份没有的舞：文档、组员方案、素材、视频副本按
  /// 「随舞删除」口径清掉，其计划项一并清。与舞库
  /// 删除同款 best-effort：单步失败静默吞掉。
  Future<void> _cleanupDancesNotInBackup(
    WholeMachineBackupPayload payload,
    List<Object?> currentEntries,
  ) async {
    final backupIds = {for (final d in payload.dances) d.videoId};
    Future<void> bestEffort(Future<void> Function() step) async {
      try {
        await step();
      } on Object {
        // 清理失败只留孤儿文件，不阻断其余步骤、不回滚恢复。
      }
    }

    for (final raw in currentEntries) {
      if (raw is! Map) continue;
      final videoId = raw['videoId'];
      if (videoId is! String || backupIds.contains(videoId)) continue;

      await bestEffort(() => ports.documentStorageFor(videoId).delete());
      await bestEffort(
        () => ports.memberSchemeStorageFor(videoId).delete(),
      );
      await bestEffort(() => ports.bucketStorage.delete(videoId));
      await bestEffort(() async {
        final base = await ports.materialsBaseDirectory();
        await deleteMaterialFilesForVideo(base.path, videoId);
      });
      await bestEffort(() async {
        final filePath = raw['filePath'];
        if (filePath is String) {
          final video = File(filePath);
          if (video.existsSync()) video.deleteSync();
        }
      });
    }
    // 计划项是全局一份文档：按保留集一次清净（在逐舞循环之外，失败只留
    // 孤儿条目，不回滚恢复）。
    await bestEffort(() => ports.practicePlanRetainDances(backupIds));
  }
}

/// 恢复报错 → 用户话术（与导入侧 [translateSusumePackageError] 同源口径，
/// 恢复语境独立成句，不与之合并）。
String restoreErrorMessage(SusumePackageException error) =>
    switch (error.kind) {
      SusumePackageError.versionMismatch =>
        '这份备份来自更新版本的 Susume，请先升级',
      SusumePackageError.notZip ||
      SusumePackageError.corrupt =>
        '备份内容损坏或不是 Susume 包，无法恢复',
    };

/// 恢复注入点：全部生产来源都在既有 provider 上，不新建路径。
final wholeMachineRestorerProvider = Provider<WholeMachineRestorer>((ref) {
  return WholeMachineRestorer(
    ports: RestorePorts(
      backup: ref.watch(backupPortsProvider),
      indexFile: () => ref.watch(importIndexFileProvider),
      documentStorageFor: ref.watch(videoDocumentStorageFactoryProvider),
      memberSchemeStorageFor: (videoId) =>
          ref.watch(memberSchemeStorageProvider(videoId)),
      bucketStorage: ref.watch(fourBeatBucketStorageProvider),
      practiceStatsStorage: ref.watch(practiceStatsStorageProvider),
      // 替换失败折成恢复失败向上报（与练舞统计的覆盖写失败同口径）：此刻
      // 已留档，重新导入留档包可退回。
      practicePlanReplace: (json) async {
        final ok = await ref
            .watch(practicePlanStoreProvider)
            .replaceWithJson(json);
        if (!ok) throw StateError('计划文档写盘失败');
      },
      practicePlanRetainDances: (videoIds) => ref
          .watch(practicePlanStoreProvider)
          .retainDances(videoIds),
      deviceSettingsStorage: ref.watch(privateJsonStorageProvider),
      materialsStorage: ref.watch(materialManifestStorageProvider),
      materialsBaseDirectory: () =>
          ref.watch(materialsBaseDirectoryProvider)(),
      archiveDirectory: () async {
        final indexFile = await ref.watch(importIndexFileProvider);
        return Directory(p.join(indexFile.parent.path, '恢复留档'));
      },
      videosDirectory: () => ref.watch(importVideosDirectoryProvider.future),
    ),
  );
});
