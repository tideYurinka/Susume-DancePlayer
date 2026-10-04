/// 整机备份编排：首页「备份」这一条链路的
/// 采集与装配——全部舞的我的标注方案与组员方案 + 全部**完全私密**字段
/// （ADR-0002），其中练舞统计（`practice_stats.json`）与每舞四拍桶分片
/// 一并纳入；媒体默认不含、可选。
///
/// - **与分享的媒体默认值刻意相反**：分享默认含
///   源视频（对方可能没有这支舞），备份默认不含（这些视频是用户自己导进
///   来的、能重新拿到）。本文件头注释即该理由的实现落点，不得顺手统一。
/// - **备份范围 = 存储原文**：索引、两份文档、组员方案、练舞统计
///   与桶分片、设备级设置与素材清单都按磁盘 JSON 原文进包（陌生键一并
///   带走），恢复侧才能做到全量替换后逐字段相等（恢复归）。
/// - 递出经 `ShareChannel`；云端直连、定时备份不做。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../annotation/compare_materials.dart' show MaterialRecord;
import '../core/atomic_json_file.dart';
import '../core/private_json.dart' show privateJsonStorageProvider;
import '../import/import_providers.dart' show videoIndexStoreProvider;
import '../persistence/index_file_provider.dart' show importIndexFileProvider;
import '../persistence/video_index.dart';
import '../persistence/four_beat_bucket_providers.dart'
    show fourBeatBucketStorageProvider;
import '../persistence/material_manifest.dart';
import '../persistence/member_scheme_store.dart';
import '../persistence/practice_plan_providers.dart'
    show practicePlanStorageProvider;
import '../persistence/practice_stats_providers.dart'
    show practiceStatsStorageProvider;
import '../persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import '../persistence/video_document_store.dart' show VideoDocumentStorage;
import 'susume_package.dart';

/// payload schema 版本（自 v1 起；恢复侧按包格式版本门 + 该值双重判别）。
/// v2 = 纳入练舞统计与每舞四拍桶分片；v1 是此前不含这两项的旧包。v3 =
/// 纳入计划文档。恢复侧仍接受旧版（缺项按空兜底）。
const int kBackupPayloadVersion = 3;

/// 最老的仍可恢复的 payload 版本（不含练舞统计、桶分片与计划文档）。
const int kMinBackupPayloadVersion = 1;

/// 包内媒体文件名的按舞前缀（采集装配与恢复解出共用，两端不得各自漂移）。
String backupMediaName(String videoId, String fileName) =>
    '${videoId}__$fileName';

/// 包内媒体文件名还原成采集前的原文件名（前缀缺失原样返回）。
String backupMediaStrippedName(String videoId, String name) =>
    name.startsWith('${videoId}__') ? name.substring(videoId.length + 2) : name;

/// 备份采集端口：备份范围在这里**收口**——每个端口对应一类完全私密字段
/// 或方案存储。
class BackupPorts {
  const BackupPorts({
    required this.loadIndexJson,
    required this.loadIndex,
    required this.documentStorageFor,
    required this.memberSchemeStorageFor,
    required this.loadBucketShardJson,
    required this.loadPracticeStatsJson,
    required this.loadPracticePlanJson,
    required this.loadDeviceSettings,
    required this.loadMaterialsManifestJson,
    required this.loadMaterialRecords,
    required this.materialsBaseDirectory,
  });

  /// `index.json` 磁盘原文（署名缓存与最近打开、续播位置、镜像状态都在
  /// 条目里）。原文进包：条目扩展字段一并带走。
  final Future<Map<String, Object?>?> Function() loadIndexJson;

  /// 类型化索引（媒体采集用：源视频副本路径与大小）。
  final Future<VideoIndex> Function() loadIndex;

  /// 按舞双文档（`markers_`/`local_<hash>.json`——激活状态、编辑偏好、
  /// 浮层几何、取景取值、练习片段列表、素材自动删除策略；我的标注方案）。
  final VideoDocumentStorage Function(String videoId) documentStorageFor;

  /// 按舞组员方案文件（`schemes_<hash>.json`）。
  final MemberSchemeStorage Function(String videoId) memberSchemeStorageFor;

  /// 按舞四拍桶分片原文（`four_beat_buckets_<videoId>.json`，完全私密级；
  /// 该舞无分片时为 null）。
  final Future<Map<String, Object?>?> Function(String videoId)
  loadBucketShardJson;

  /// 练舞统计原文（`practice_stats.json`，完全私密级；文件缺失时为 null）。
  final Future<Map<String, Object?>?> Function() loadPracticeStatsJson;

  /// 计划文档原文（`practice_plan.json`，完全私密级；
  /// 文件缺失时为 null）。
  final Future<Map<String, Object?>?> Function() loadPracticePlanJson;

  /// 设备级设置（`global_private.json` 原文：镜像默认、基准键、速度预设等
  /// 全部顶层键，含将来未知的键）。
  final Future<Map<String, Object?>> Function() loadDeviceSettings;

  /// 素材清单原文（payload 保真用：陌生键一并带走；缺失为 null）。
  final Future<Map<String, Object?>?> Function() loadMaterialsManifestJson;

  /// 类型化素材条目（媒体采集用；字段解码单处走清单模型的 RecordCodec）。
  final Future<List<MaterialRecord>> Function() loadMaterialRecords;

  /// 私有素材基目录（媒体采集用）。
  final Future<Directory> Function() materialsBaseDirectory;
}

/// 一支舞在备份 payload 里的条目。
class BackupDancePayload {
  const BackupDancePayload({
    required this.videoId,
    required this.markers,
    required this.local,
    required this.schemes,
    this.buckets = const {},
    this.media = const [],
  });

  final String videoId;

  /// 我的标注方案原文。
  final Map<String, Object?> markers;

  /// 本地文档原文（完全私密字段所在）。
  final Map<String, Object?> local;

  /// 组员方案文件原文。
  final Map<String, Object?> schemes;

  /// 该舞四拍桶分片原文（无分片为空）。
  final Map<String, Object?> buckets;

  /// 勾了媒体时该舞装入的包内条目文件名（未勾为空）。
  final List<String> media;

  Map<String, Object?> toJson() => {
    'videoId': videoId,
    'markers': markers,
    'local': local,
    'schemes': schemes,
    'buckets': buckets,
    'media': media,
  };
}

/// 整机备份 payload：包内 `backup.json` 的值。
class WholeMachineBackupPayload {
  const WholeMachineBackupPayload({
    required this.index,
    required this.dances,
    required this.deviceSettings,
    this.practiceStats = const {},
    this.practicePlan = const {},
    this.materialsManifest,
  });

  /// `index.json` 原文。
  final Map<String, Object?> index;

  /// 全部舞（含我的方案、组员方案、该舞的完全私密字段与四拍桶分片）。
  final List<BackupDancePayload> dances;

  /// 设备级设置原文。
  final Map<String, Object?> deviceSettings;

  /// 练舞统计原文（无记录为空）。
  final Map<String, Object?> practiceStats;

  /// 计划文档原文（无计划数据为空）。
  final Map<String, Object?> practicePlan;

  /// 素材清单原文；素材目录为空时为 null（键省略）。
  final Map<String, Object?>? materialsManifest;

  Map<String, Object?> toJson() => {
    'payloadVersion': kBackupPayloadVersion,
    'index': index,
    'dances': [for (final d in dances) d.toJson()],
    'device': deviceSettings,
    'practiceStats': practiceStats,
    'practicePlan': practicePlan,
    'materialsManifest': ?materialsManifest,
  };

  /// 恢复侧解码：与 [toJson] 同一份 schema 的读向。
  /// payloadVersion 不在 [kMinBackupPayloadVersion]..[kBackupPayloadVersion]
  /// 即明确报错（包格式版本门之外的第二道门）；v1 旧包缺练舞统计与桶分片，
  /// 按空兜底、不拒绝。本版必填键缺失或类型不符按损坏报错，不静默半恢复。
  factory WholeMachineBackupPayload.fromJson(Map<String, Object?> json) {
    final version = json['payloadVersion'];
    if (version is! int ||
        version < kMinBackupPayloadVersion ||
        version > kBackupPayloadVersion) {
      throw SusumePackageException(
        SusumePackageError.versionMismatch,
        '备份内容版本不符：$version'
        '（本机支持 $kMinBackupPayloadVersion–$kBackupPayloadVersion）',
      );
    }
    final legacy = version < kBackupPayloadVersion;
    Map<String, Object?> map(Object? value, String key) {
      if (value is! Map) {
        throw SusumePackageException(
          SusumePackageError.corrupt,
          '备份内容缺少必填字段 $key 或类型不符',
        );
      }
      return value.cast<String, Object?>();
    }

    // 旧包缺的是本版新增项：按空兜底；本版包内缺键则按损坏报错。
    Map<String, Object?> addedInV2(Object? value, String key) =>
        legacy ? const {} : map(value, key);
    final legacyV2 = version < 3;
    Map<String, Object?> addedInV3(Object? value, String key) =>
        legacyV2 ? const {} : map(value, key);

    final dancesRaw = json['dances'];
    if (dancesRaw is! List) {
      throw const SusumePackageException(
        SusumePackageError.corrupt,
        '备份内容 dances 字段类型不符',
      );
    }
    return WholeMachineBackupPayload(
      index: map(json['index'], 'index'),
      dances: [
        for (final danceRaw in dancesRaw)
          () {
            final dance = map(danceRaw, 'dances');
            final videoId = dance['videoId'];
            if (videoId is! String || videoId.isEmpty) {
              throw const SusumePackageException(
                SusumePackageError.corrupt,
                '备份内容舞条目缺少 videoId',
              );
            }
            final mediaRaw = dance['media'];
            return BackupDancePayload(
              videoId: videoId,
              markers: map(dance['markers'], 'markers'),
              local: map(dance['local'], 'local'),
              schemes: map(dance['schemes'], 'schemes'),
              buckets: addedInV2(dance['buckets'], 'buckets'),
              media: mediaRaw is List
                  ? [for (final name in mediaRaw) name as String]
                  : const <String>[],
            );
          }(),
      ],
      deviceSettings: map(json['device'], 'device'),
      practiceStats: addedInV2(json['practiceStats'], 'practiceStats'),
      practicePlan: addedInV3(json['practicePlan'], 'practicePlan'),
      materialsManifest: json['materialsManifest'] == null
          ? null
          : map(json['materialsManifest'], 'materialsManifest'),
    );
  }
}

/// 采集 + 装配的产物。
typedef CollectedWholeMachineBackup = ({
  WholeMachineBackupPayload payload,
  List<SusumeMediaEntry> media,
});

/// 采集整机数据：[includeMedia] 为 false 即不含任何媒体（备份默认值）；
/// 为 true 时每支舞装入源视频副本与练习录像，包内文件名以
/// `<videoId>__` 前缀避免跨舞同名。已不在磁盘上的素材文件跳过（素材自动
/// 删除可能已清掉文件而清单条目尚在），不构成失败。
Future<CollectedWholeMachineBackup> collectWholeMachineBackup(
  BackupPorts ports, {
  required bool includeMedia,
}) async {
  final reads = await Future.wait<Object?>([
    ports.loadIndex(),
    ports.loadIndexJson(),
    ports.loadDeviceSettings(),
    ports.loadMaterialsManifestJson(),
    ports.loadPracticeStatsJson(),
    ports.loadPracticePlanJson(),
  ]);
  final index = reads[0] as VideoIndex;
  final indexJson = reads[1] as Map<String, Object?>?;
  final deviceSettings = reads[2] as Map<String, Object?>;
  final materialsManifest = reads[3] as Map<String, Object?>?;
  final practiceStats =
      (reads[4] as Map<String, Object?>?) ?? const <String, Object?>{};
  final practicePlan =
      (reads[5] as Map<String, Object?>?) ?? const <String, Object?>{};

  // 素材清单同一采集过程中不变：装载一次，逐舞只筛。
  final materialRecords = includeMedia
      ? await ports.loadMaterialRecords()
      : const <MaterialRecord>[];

  final dances = <BackupDancePayload>[];
  final media = <SusumeMediaEntry>[];
  for (final entry in index.entries) {
    final videoId = entry.videoId;
    final storage = ports.documentStorageFor(videoId);
    final danceReads = await Future.wait<Object?>([
      storage.loadMarkers(),
      storage.loadLocal(),
      ports.memberSchemeStorageFor(videoId).load(),
      ports.loadBucketShardJson(videoId),
    ]);
    final markers = danceReads[0] as Map<String, Object?>;
    final local = danceReads[1] as Map<String, Object?>;
    final schemes = danceReads[2] as Map<String, Object?>;
    final buckets = (danceReads[3] as Map<String, Object?>?) ?? const {};

    var danceMedia = const <String>[];
    if (includeMedia) {
      final names = <String>[];
      final source = File(entry.filePath);
      if (source.existsSync()) {
        final name = backupMediaName(videoId, entry.displayName);
        names.add(name);
        media.add(
          SusumeMediaEntry(
            kind: SusumeMediaKind.sourceVideo,
            fileName: name,
            sizeBytes: entry.sizeBytes,
            file: source,
          ),
        );
      }
      final base = (await ports.materialsBaseDirectory()).path;
      for (final record in materialRecords.where(
        (record) => record.videoId == videoId,
      )) {
        final file = File(materialFilePathIn(base, videoId, record.fileName));
        if (!file.existsSync()) continue;
        final name = backupMediaName(videoId, record.fileName);
        names.add(name);
        media.add(
          SusumeMediaEntry(
            kind: SusumeMediaKind.practiceClip,
            fileName: name,
            sizeBytes: record.sizeBytes,
            file: file,
          ),
        );
      }
      danceMedia = names;
    }

    dances.add(
      BackupDancePayload(
        videoId: videoId,
        markers: markers,
        local: local,
        schemes: schemes,
        buckets: buckets,
        media: danceMedia,
      ),
    );
  }

  return (
    payload: WholeMachineBackupPayload(
      index: indexJson ?? {},
      dances: dances,
      deviceSettings: deviceSettings,
      practiceStats: practiceStats,
      practicePlan: practicePlan,
      materialsManifest: materialsManifest,
    ),
    media: media,
  );
}

/// 装配整机包到 [outputDir]：文件名见 [susumeBackupFileName]。返回落盘文件。
Future<File> assembleWholeMachineBackup({
  required Directory outputDir,
  required WholeMachineBackupPayload payload,
  required List<SusumeMediaEntry> media,
  required DateTime now,
}) async {
  await outputDir.create(recursive: true);
  final output = File(p.join(outputDir.path, susumeBackupFileName(now: now)));
  await writeSusumePackage(
    output: output,
    manifest: SusumeManifest(
      kind: SusumePackageKind.backup,
      videoId: '',
      schemeName: '',
      schemeId: '',
      media: media,
    ),
    markers: const {},
    backup: payload.toJson(),
  );
  return output;
}

/// 备份端口注入点：备份范围的生产来源全部在既有注入点上，不新建路径。
/// 测试覆盖 [backupPortsProvider] 即可整体替换采集来源。
final backupPortsProvider = Provider<BackupPorts>((ref) {
  return BackupPorts(
    loadIndexJson: () async =>
        (await AtomicJsonFile(await ref.watch(importIndexFileProvider))
            .readOrNull()) ??
        {},
    loadIndex: () => ref.watch(videoIndexStoreProvider).load(),
    documentStorageFor: ref.watch(videoDocumentStorageFactoryProvider),
    memberSchemeStorageFor: (videoId) =>
        ref.watch(memberSchemeStorageProvider(videoId)),
    loadBucketShardJson: (videoId) async =>
        await ref.watch(fourBeatBucketStorageProvider).loadOrNull(videoId),
    loadPracticeStatsJson: () async =>
        await ref.watch(practiceStatsStorageProvider).loadOrNull(),
    loadPracticePlanJson: () async =>
        await ref.watch(practicePlanStorageProvider).loadOrNull(),
    loadDeviceSettings: () => ref.watch(privateJsonStorageProvider).read(),
    loadMaterialsManifestJson: () async =>
        await AtomicJsonFile(await _materialsManifestFile(ref)).readOrNull(),
    loadMaterialRecords: () async =>
        (await ref.watch(materialManifestStoreProvider).read()).materials,
    materialsBaseDirectory: () => ref.watch(materialsBaseDirectoryProvider)(),
  );
});

Future<File> _materialsManifestFile(Ref ref) async {
  final base = await ref.watch(materialsBaseDirectoryProvider)();
  return File(p.join(base.path, 'manifest.json'));
}
