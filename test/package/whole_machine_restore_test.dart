import 'dart:io';

import 'package:dance_learning_app/core/atomic_json_file.dart';
import 'package:dance_learning_app/help/guide_state.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/package/susume_package.dart';
import 'package:dance_learning_app/package/whole_machine_backup.dart';
import 'package:dance_learning_app/package/whole_machine_restore.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 整机恢复编排测试：经临时目录真实 zip 往返，
/// 断言恢复的对外结果——留档先行且失败即中止、全量替换逐字段相等、
/// 本机多出的舞被清掉。页面分流归部件测试，这里不启 widget。
void main() {
  late Directory tempDir;
  late Directory local; // 恢复目标机（本机）
  late Directory sender; // 备份来源机

  Map<String, Object?> indexJson({
    required String videoId,
    required String filePath,
    String displayName = 'v.mp4',
  }) =>
      {
        'version': 1,
        'extra': {'keptKey': 'kept'},
        'entries': [
          {
            'videoId': videoId,
            'displayName': displayName,
            'filePath': filePath,
            'sizeBytes': 64,
            'fastKey': 'k',
            'mirrored': false,
            'mirrorAsked': true,
            'lastOpenedAt': '2026-09-15T08:00:00.000Z',
            'signatureCache': {'dancer': '如', 'song': '海草舞', 'remark': ''},
            'lastPositionMs': 42000,
          },
        ],
      };

  final markersJson = <String, Object?>{
    'version': 9,
    'meta': {
      'signature': {'song': '海草舞'},
      'framingSelection': {
        'left': 0.2,
        'top': 0.1,
        'right': 0.7,
        'bottom': 0.6,
      },
    },
  };
  final localJson = <String, Object?>{
    'version': 3,
    'session': {
      'mastery': {'0': 3},
      'activatedSegments': [0],
    },
    'prefs': {
      'previewSnapEnabled': false,
      'overlay': {'x': 12.0, 'y': 30.0},
      'framingSource': {'scale': 2.5, 'offsetX': 0.1, 'offsetY': -0.05},
      'framingPractice': {'scale': 1.5, 'offsetX': 0.0, 'offsetY': 0.0},
    },
  };
  final schemesJson = <String, Object?>{
    'version': 1,
    'schemes': [
      {'schemeId': 's1', 'memberName': '小舞'},
    ],
  };
  final deviceJson = <String, Object?>{
    'mirrorDefault': true,
    'surfaceBasisKey': 'front_camera_preview',
    // 引导状态位随整机备份原样携带：恢复后不再重新引导。
    'onboarding': {
      for (final field in onboardingFlagFields.values) field: true,
    },
  };
  final materialsManifestJson = <String, Object?>{
    'version': 2,
    'materials': {
      'entries': [
        {'id': 'm1', 'videoId': 'v1', 'fileName': 'rec_1.mp4', 'sizeBytes': 32},
      ],
    },
  };
  // 发送机的桶分片与练舞统计；本机另有一份内容不同的同名分片（证明覆盖
  // 而非合并）与 v2 的分片（证明随舞删除）。
  final senderBucketsJson = <String, Object?>{
    'version': 1,
    'signature': {'dancer': '如', 'song': '海草舞', 'remark': ''},
    'ledger': {
      'days': {
        '2026-09-15': {
          '4': {'wallSeconds': 12.5, 'sweeps': 2},
        },
      },
    },
  };
  final senderStatsJson = <String, Object?>{
    'version': 2,
    'sessions': [
      {
        'start': '2026-09-15T08:00:00.000',
        'videoId': 'v1',
        'dancer': '如',
        'song': '海草舞',
        'remark': '',
        'wallSeconds': 60.0,
      },
    ],
  };
  final localBucketsJson = <String, Object?>{
    'version': 1,
    'signature': {'dancer': '海', 'song': '本机的舞', 'remark': ''},
    'ledger': {
      'days': {
        '2026-09-14': {
          '9': {'wallSeconds': 3.0, 'sweeps': 1},
        },
      },
    },
  };
  final localStatsJson = <String, Object?>{
    'version': 2,
    'sessions': [
      {
        'start': '2026-09-14T08:00:00.000',
        'videoId': 'v2',
        'dancer': '海',
        'song': '本机的舞',
        'remark': '',
        'wallSeconds': 9.0,
      },
    ],
  };
  // 计划文档：发送机只有 v1 的 DDL；本机有 v2 与
  // 一支本机才有计划的 v-ghost 的 DDL（恢复后应随全量替换 + 清理消失）。
  final senderPlanJson = <String, Object?>{
    'version': 1,
    'entries': [
      {
        'videoId': 'v1',
        'ddl': {'date': '2026-10-01', 'occasion': '演出', 'remark': '道具扇子'},
      },
    ],
    'events': [
      {
        'id': 'e1',
        'date': '2026-11-08',
        'danceIds': ['v1', 'v2'],
      },
    ],
    'keptSenderPlanKey': true,
  };
  final localPlanJson = <String, Object?>{
    'version': 1,
    'entries': [
      {
        'videoId': 'v2',
        'ddl': {'date': '2026-11-05', 'remark': '本机的计划'},
      },
      {
        'videoId': 'v-ghost',
        'ddl': {'date': '2026-12-01'},
      },
    ],
  };

  /// 在 [root] 下布置一台「机器」的磁盘数据。
  Future<void> seedMachine(
    Directory root, {
    required String videoId,
    required Map<String, Object?> markers,
    required Map<String, Object?> local,
  }) async {
    await AtomicJsonFile(File('${root.path}/index.json'))
        .write(indexJson(videoId: videoId, filePath: '${root.path}/videos/v.mp4'));
    final documents = AtomicVideoDocumentStorage(
      markersFile: File('${root.path}/markers_$videoId.json'),
      localFile: File('${root.path}/local_$videoId.json'),
    );
    await documents.saveMarkers(markers);
    await documents.saveLocal(local);
    await MemberSchemeFileStore(File('${root.path}/schemes_$videoId.json'))
        .save(schemesJson);
    await AtomicJsonFile(File('${root.path}/global_private.json'))
        .write(deviceJson);
    await AtomicJsonFile(File('${root.path}/manifest.json'))
        .write(materialsManifestJson);
  }

  BackupPorts senderPorts() => BackupPorts(
        loadIndexJson: () async =>
            (await AtomicJsonFile(File('${sender.path}/index.json'))
                    .readOrNull()) ??
            {},
        loadIndex: () async => VideoIndex(entries: [
          VideoIndexEntry(
            videoId: 'v1',
            displayName: 'v.mp4',
            filePath: '${sender.path}/videos/v.mp4',
            sizeBytes: 64,
            fastKey: 'k',
            mirrored: false,
            mirrorAsked: true,
            lastOpenedAt: DateTime(2026, 9, 15, 8),
          ),
        ]),
        documentStorageFor: (videoId) => AtomicVideoDocumentStorage(
          markersFile: File('${sender.path}/markers_$videoId.json'),
          localFile: File('${sender.path}/local_$videoId.json'),
        ),
        memberSchemeStorageFor: (videoId) => MemberSchemeFileStore(
          File('${sender.path}/schemes_$videoId.json'),
        ),
        loadBucketShardJson: (videoId) async =>
            await AtomicJsonFile(
              File('${sender.path}/four_beat_buckets_$videoId.json'),
            ).readOrNull(),
        loadPracticeStatsJson: () async =>
            await AtomicJsonFile(File('${sender.path}/practice_stats.json'))
                .readOrNull(),
        loadPracticePlanJson: () async =>
            await AtomicJsonFile(File('${sender.path}/practice_plan.json'))
                .readOrNull(),
        loadDeviceSettings: () async => await AtomicJsonFile(
          File('${sender.path}/global_private.json'),
        ).read(),
        loadMaterialsManifestJson: () async =>
            await AtomicJsonFile(File('${sender.path}/manifest.json'))
                .readOrNull(),
        loadMaterialRecords: () async => const [],
        materialsBaseDirectory: () async => Directory('${sender.path}/materials'),
      );

  /// 用「发送机」的磁盘数据装配一个备份包，返回包文件。
  Future<File> buildBackupPackage() async {
    final collected = await collectWholeMachineBackup(
      senderPorts(),
      includeMedia: false,
    );
    return assembleWholeMachineBackup(
      outputDir: Directory('${sender.path}/out'),
      payload: collected.payload,
      media: collected.media,
      now: DateTime(2026, 9, 15, 9),
    );
  }

  /// 本机自己的采集端口（留档采集的是本机当前数据）。
  BackupPorts localBackupPorts() => BackupPorts(
        loadIndexJson: () async =>
            (await AtomicJsonFile(File('${local.path}/index.json'))
                    .readOrNull()) ??
            {},
        loadIndex: () async => VideoIndex(entries: [
          VideoIndexEntry(
            videoId: 'v2',
            displayName: 'v.mp4',
            filePath: '${local.path}/videos/v.mp4',
            sizeBytes: 64,
            fastKey: 'k',
            mirrored: false,
            mirrorAsked: true,
            lastOpenedAt: DateTime(2026, 9, 15, 8),
          ),
        ]),
        documentStorageFor: (videoId) => AtomicVideoDocumentStorage(
          markersFile: File('${local.path}/markers_$videoId.json'),
          localFile: File('${local.path}/local_$videoId.json'),
        ),
        memberSchemeStorageFor: (videoId) => MemberSchemeFileStore(
          File('${local.path}/schemes_$videoId.json'),
        ),
        loadBucketShardJson: (videoId) async =>
            await AtomicJsonFile(
              File('${local.path}/four_beat_buckets_$videoId.json'),
            ).readOrNull(),
        loadPracticeStatsJson: () async =>
            await AtomicJsonFile(File('${local.path}/practice_stats.json'))
                .readOrNull(),
        loadPracticePlanJson: () async =>
            await AtomicJsonFile(File('${local.path}/practice_plan.json'))
                .readOrNull(),
        loadDeviceSettings: () async => await AtomicJsonFile(
          File('${local.path}/global_private.json'),
        ).read(),
        loadMaterialsManifestJson: () async =>
            await AtomicJsonFile(File('${local.path}/manifest.json'))
                .readOrNull(),
        loadMaterialRecords: () async => const [],
        materialsBaseDirectory: () async => Directory('${local.path}/materials'),
      );

  RestorePorts localPorts({BackupPorts? backup, bool failPlanReplace = false}) =>
      RestorePorts(
        backup: backup ?? localBackupPorts(),
        indexFile: () async => File('${local.path}/index.json'),
        documentStorageFor: (videoId) => AtomicVideoDocumentStorage(
          markersFile: File('${local.path}/markers_$videoId.json'),
          localFile: File('${local.path}/local_$videoId.json'),
        ),
        memberSchemeStorageFor: (videoId) => MemberSchemeFileStore(
          File('${local.path}/schemes_$videoId.json'),
        ),
        bucketStorage: AtomicFourBeatBucketStorage(
          (videoId) async =>
              File('${local.path}/four_beat_buckets_$videoId.json'),
        ),
        practiceStatsStorage: AtomicPracticeStatsStorage(
          () async => File('${local.path}/practice_stats.json'),
        ),
        practicePlanReplace: (json) async {
          if (failPlanReplace) throw StateError('计划文档写盘失败');
          await PracticePlanStore(
            AtomicPracticePlanStorage(
              () async => File('${local.path}/practice_plan.json'),
            ),
          ).replaceWithJson(json);
        },
        practicePlanRetainDances: (videoIds) => PracticePlanStore(
          AtomicPracticePlanStorage(
            () async => File('${local.path}/practice_plan.json'),
          ),
        ).retainDances(videoIds),
        deviceSettingsStorage: AtomicJsonFile(
          File('${local.path}/global_private.json'),
        ),
        materialsStorage: MaterialManifestFileStore(
          File('${local.path}/manifest.json'),
        ),
        materialsBaseDirectory: () async => Directory('${local.path}/materials'),
        archiveDirectory: () async => Directory('${local.path}/恢复留档'),
        videosDirectory: () async => Directory('${local.path}/videos'),
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('whole_machine_restore');
    sender = Directory('${tempDir.path}/sender');
    local = Directory('${tempDir.path}/local');
    await sender.create(recursive: true);
    await local.create(recursive: true);
    // 两台机器各有各的数据：发送机 v1、本机 v2，内容互不相同。
    await seedMachine(
      sender,
      videoId: 'v1',
      markers: markersJson,
      local: localJson,
    );
    await seedMachine(
      local,
      videoId: 'v2',
      markers: {'version': 8, 'meta': {'signature': {'song': '本机的舞'}}},
      local: {'version': 3},
    );
    // 发送机：v1 的桶分片与练舞统计。
    await AtomicJsonFile(File('${sender.path}/four_beat_buckets_v1.json'))
        .write(senderBucketsJson);
    await AtomicJsonFile(File('${sender.path}/practice_stats.json'))
        .write(senderStatsJson);
    // 本机：同名分片内容不同（覆盖不合并），v2 也有分片（随舞删除），
    // 练舞统计内容与发送机不同。
    await AtomicJsonFile(File('${local.path}/four_beat_buckets_v1.json'))
        .write(localBucketsJson);
    await AtomicJsonFile(File('${local.path}/four_beat_buckets_v2.json'))
        .write(localBucketsJson);
    await AtomicJsonFile(File('${local.path}/practice_stats.json'))
        .write(localStatsJson);
    await AtomicJsonFile(File('${sender.path}/practice_plan.json'))
        .write(senderPlanJson);
    await AtomicJsonFile(File('${local.path}/practice_plan.json'))
        .write(localPlanJson);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('全量替换：恢复后本机各文件与备份逐字段相等，留档先行落在固定位置且可清',
      () async {
    final package = await buildBackupPackage();

    final outcome = await WholeMachineRestorer(ports: localPorts()).restore(
      package: await readSusumePackage(package.path),
      packagePath: package.path,
    );

    expect(outcome, isA<RestoreCompleted>());

    // 留档：恢复前本机（v2）的数据在固定位置，可解析、可删除。
    final archiveDir = Directory('${local.path}/恢复留档');
    final archiveFile =
        archiveDir.listSync().whereType<File>().toList();
    expect(archiveFile, hasLength(1));
    expect(archiveFile.single.path, endsWith('.susume'));
    final archived = await readSusumePackage(archiveFile.single.path);
    expect(archived.backup!['dances'], hasLength(1));
    expect(
      (archived.backup!['dances'] as List).first['markers'],
      {'version': 8, 'meta': {'signature': {'song': '本机的舞'}}},
      reason: '留档是恢复前的本机数据',
    );
    // 留档也含练舞统计与四拍桶分片：留档范围与备份范围同源，不作废。
    expect(archived.backup!['practiceStats'], localStatsJson);
    expect(archived.backup!['practicePlan'], localPlanJson,
        reason: '留档带着恢复前本机的计划文档');
    expect(
      (archived.backup!['dances'] as List).first['buckets'],
      localBucketsJson,
      reason: '留档带着恢复前本机的桶分片',
    );
    await archiveFile.single.delete();
    expect(archiveFile.single.existsSync(), isFalse, reason: '留档可手动清');

    // 全量替换：本机就是备份那一刻的样子。
    expect(
      await AtomicJsonFile(File('${local.path}/index.json')).readOrNull(),
      indexJson(videoId: 'v1', filePath: '${sender.path}/videos/v.mp4'),
    );
    final documents = AtomicVideoDocumentStorage(
      markersFile: File('${local.path}/markers_v1.json'),
      localFile: File('${local.path}/local_v1.json'),
    );
    expect(await documents.loadMarkers(), markersJson);
    expect(await documents.loadLocal(), localJson);
    // 恢复是原样 JSON 进出，读取走同一迁移路径（打开会话用的协调器读面）：
    // 旧备份里的取景两键复位。
    final restoredLocal = await VideoDocumentCoordinator(documents).readLocal();
    final restoredJson = restoredLocal.toJson();
    expect(restoredJson['version'], 4);
    final restoredPrefs = restoredJson['prefs'] as Map;
    expect(restoredPrefs['previewSnapEnabled'], isFalse);
    expect(restoredPrefs.containsKey('framingSource'), isFalse);
    expect(restoredPrefs.containsKey('framingPractice'), isFalse);
    expect(
      await MemberSchemeFileStore(File('${local.path}/schemes_v1.json')).load(),
      schemesJson,
    );
    expect(
      await AtomicJsonFile(File('${local.path}/global_private.json'))
          .read(),
      deviceJson,
    );
    expect(
      await MaterialManifestFileStore(File('${local.path}/manifest.json'))
          .load(),
      materialsManifestJson,
    );
    // 桶分片与练舞统计同样全量替换：本机同名分片被包内容整份覆盖。
    expect(
      await AtomicJsonFile(File('${local.path}/four_beat_buckets_v1.json'))
          .read(),
      senderBucketsJson,
    );
    expect(
      await AtomicJsonFile(File('${local.path}/practice_stats.json')).read(),
      senderStatsJson,
    );
    // 计划文档全量替换 + 备份外舞清理的组合结果：本机条目只剩 v1（DDL 原
    // 文落位），事件条目保留、v2 的关联项被摘（关联清单允许为空）。清理后
    // 经 store 重编码落盘：缺省键按编码口径补齐。
    expect(
      await AtomicJsonFile(File('${local.path}/practice_plan.json')).read(),
      {
        'version': 1,
        'entries': [
          {
            'videoId': 'v1',
            'ddl': {
              'date': '2026-10-01',
              'occasion': '演出',
              'remark': '道具扇子',
              'checklist': [],
            },
          },
        ],
        'events': [
          {
            'id': 'e1',
            'type': 'socialDanceEvent',
            'date': '2026-11-08',
            'location': '',
            'remark': '',
            'danceIds': ['v1'],
            'checklist': [],
            'checkMode': 'rehearsal',
          },
        ],
        'keptSenderPlanKey': true,
      },
    );
  });

  test('恢复整机备份：本机那份读不懂的原文在整份覆盖前先留档', () async {
    // 本机已有一份 v1 文档读不懂（高于本版）：恢复是绕过版本政策的整份
    // 替换，留档须在覆盖前把原文另存。
    await AtomicJsonFile(File('${local.path}/markers_v1.json')).write(const {
      'version': 99,
      'meta': {'signature': {'song': '本机读不懂的舞'}},
    });
    final before =
        await File('${local.path}/markers_v1.json').readAsString();

    final package = await buildBackupPackage();
    final outcome = await WholeMachineRestorer(ports: localPorts()).restore(
      package: await readSusumePackage(package.path),
      packagePath: package.path,
    );
    expect(outcome, isA<RestoreCompleted>());

    final sidecars = local
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('.quarantine-'))
        .toList();
    expect(sidecars, hasLength(1), reason: '只读原文在整份覆盖前留档一份');
    expect(await sidecars.single.readAsString(), before);
    expect(
      await AtomicJsonFile(File('${local.path}/markers_v1.json')).read(),
      markersJson,
      reason: '全量替换照常发生（留档不阻断恢复）',
    );
  });

  test('全量替换：本机多出的舞被清掉——索引不再列出，文档、组员方案、桶分片消失',
      () async {
    final package = await buildBackupPackage();

    await WholeMachineRestorer(ports: localPorts()).restore(
      package: await readSusumePackage(package.path),
      packagePath: package.path,
    );

    expect(
      (await AtomicJsonFile(File('${local.path}/index.json')).readOrNull())!,
      isNot(contains('v2')),
    );
    expect(File('${local.path}/markers_v2.json').existsSync(), isFalse);
    expect(File('${local.path}/local_v2.json').existsSync(), isFalse);
    expect(File('${local.path}/schemes_v2.json').existsSync(), isFalse);
    expect(
      File('${local.path}/four_beat_buckets_v2.json').existsSync(),
      isFalse,
    );
    // 「备份里没有的舞」清理同时清掉计划项：本机计划里 v2 与 v-ghost 的
    // DDL 条目被清，v1 的保留；事件条目保留、只摘掉 v2 的关联项。
    final planAfter = PracticePlanDocument.fromJson(
      await AtomicJsonFile(File('${local.path}/practice_plan.json')).read(),
    );
    expect(
      [for (final e in planAfter.entries) e.videoId],
      containsAllInOrder(['v1']),
    );
    expect(planAfter.entries, hasLength(1));
    expect(planAfter.events.single.id, 'e1');
    expect(planAfter.events.single.danceIds, ['v1'],
        reason: '事件保留、关联清单少一项');
  });

  test('恢复清理：备份计划文档里指向「备份里没有的舞」的条目也被清（全量替换 + 保留集）',
      () async {
    final package = await buildBackupPackage();
    final parsed = await readSusumePackage(package.path);
    final payload = Map<String, Object?>.from(parsed.backup!)
      ..['practicePlan'] = {
        'version': 1,
        'entries': [
          for (final videoId in ['v1', 'v2'])
            {
              'videoId': videoId,
              'ddl': {'date': '2026-10-01'},
            },
        ],
      };
    final doctored = File('${tempDir.path}/doctored.susume');
    await writeSusumePackage(
      output: doctored,
      manifest: const SusumeManifest(
        kind: SusumePackageKind.backup,
        videoId: '',
        schemeName: '',
        schemeId: '',
      ),
      markers: const {},
      backup: payload,
    );

    final outcome = await WholeMachineRestorer(ports: localPorts()).restore(
      package: await readSusumePackage(doctored.path),
      packagePath: doctored.path,
    );

    expect(outcome, isA<RestoreCompleted>());
    final planAfter = PracticePlanDocument.fromJson(
      await AtomicJsonFile(File('${local.path}/practice_plan.json')).read(),
    );
    expect(
      [for (final e in planAfter.entries) e.videoId],
      ['v1'],
      reason: 'v2 不在备份里：它的计划项被清',
    );
  });

  test('老包（payload v1）：缺桶与统计不拒绝，恢复后本机桶为空、统计清零',
      () async {
    final package = await buildBackupPackage();
    final parsed = await readSusumePackage(package.path);
    final legacyDances = [
      for (final raw in parsed.backup!['dances'] as List)
        (raw as Map).cast<String, Object?>()..remove('buckets'),
    ];
    final legacyPayload = Map<String, Object?>.from(parsed.backup!)
      ..['payloadVersion'] = 1
      ..['dances'] = legacyDances
      ..remove('practiceStats');
    final legacyFile = File('${tempDir.path}/legacy.susume');
    await writeSusumePackage(
      output: legacyFile,
      manifest: const SusumeManifest(
        kind: SusumePackageKind.backup,
        videoId: '',
        schemeName: '',
        schemeId: '',
      ),
      markers: const {},
      backup: legacyPayload,
    );

    final outcome = await WholeMachineRestorer(ports: localPorts()).restore(
      package: await readSusumePackage(legacyFile.path),
      packagePath: legacyFile.path,
    );

    expect(outcome, isA<RestoreCompleted>(), reason: '老包不拒绝');
    // 全量替换语义：包内没有的桶恢复成空——本机同名与多出的分片都没了。
    expect(
      File('${local.path}/four_beat_buckets_v1.json').existsSync(),
      isFalse,
    );
    expect(
      File('${local.path}/four_beat_buckets_v2.json').existsSync(),
      isFalse,
    );
    final stats =
        await AtomicJsonFile(File('${local.path}/practice_stats.json'))
            .readOrNull();
    expect(
      PracticeStatsDocument.fromJson(stats ?? const {}).sessions,
      isEmpty,
    );
    // 旧包没有计划文档键：恢复后本机计划文档为空态（本机旧计划不残留）。
    final plan = PracticePlanDocument.fromJson(
      (await AtomicJsonFile(File('${local.path}/practice_plan.json'))
              .readOrNull()) ??
          const {},
    );
    expect(plan.entries, isEmpty);
  });

  test('计划文档替换失败：恢复折成明确失败，不静默半恢复', () async {
    final package = await buildBackupPackage();

    final outcome = await WholeMachineRestorer(
      ports: localPorts(failPlanReplace: true),
    ).restore(
      package: await readSusumePackage(package.path),
      packagePath: package.path,
    );

    expect(outcome, isA<RestoreFailed>());
    // 本机计划文档未被半写：仍是恢复前的本机计划（留档可退回）。
    expect(
      await AtomicJsonFile(File('${local.path}/practice_plan.json')).read(),
      localPlanJson,
    );
  });

  test('留档失败即中止恢复：本机数据一个字节都没动', () async {
    final package = await buildBackupPackage();
    final brokenBackup = senderPorts();
    final broken = BackupPorts(
      loadIndexJson: brokenBackup.loadIndexJson,
      loadIndex: () async => const VideoIndex(entries: []),
      documentStorageFor: brokenBackup.documentStorageFor,
      memberSchemeStorageFor: brokenBackup.memberSchemeStorageFor,
      loadBucketShardJson: brokenBackup.loadBucketShardJson,
      loadPracticeStatsJson: brokenBackup.loadPracticeStatsJson,
      loadPracticePlanJson: brokenBackup.loadPracticePlanJson,
      // 留档采集触达设备设置时炸：留档失败。
      loadDeviceSettings: () async => throw StateError('磁盘满'),
      loadMaterialsManifestJson: brokenBackup.loadMaterialsManifestJson,
      loadMaterialRecords: brokenBackup.loadMaterialRecords,
      materialsBaseDirectory: brokenBackup.materialsBaseDirectory,
    );

    final outcome = await WholeMachineRestorer(
      ports: localPorts(backup: broken),
    ).restore(
      package: await readSusumePackage(package.path),
      packagePath: package.path,
    );

    expect(outcome, isA<RestoreFailed>());
    expect((outcome as RestoreFailed).message, contains('留档失败'));
    // 本机数据原样：v2 还在，v1 没进来。
    expect(File('${local.path}/markers_v2.json').existsSync(), isTrue);
    expect(File('${local.path}/markers_v1.json').existsSync(), isFalse);
    final untouched =
        await AtomicJsonFile(File('${local.path}/index.json')).readOrNull();
    expect(
      [
        for (final entry in (untouched!['entries'] as List))
          (entry as Map)['videoId'],
      ],
      contains('v2'),
    );
  });

  test('未带媒体的舞：本机原视频还在盘上则索引指向本机副本，退路接得回',
      () async {
    final localVideo = File('${local.path}/videos/v.mp4')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(64, 9));
    // 本机也有 v1 这支舞（视频在盘），只是数据比备份旧。
    await AtomicJsonFile(File('${local.path}/index.json')).write({
      'version': 1,
      'entries': [
        {
          'videoId': 'v1',
          'displayName': 'v.mp4',
          'filePath': localVideo.path,
          'sizeBytes': 64,
          'fastKey': 'k',
          'mirrored': false,
          'mirrorAsked': true,
          'lastOpenedAt': '2026-09-14T08:00:00.000Z',
        },
        {
          'videoId': 'v2',
          'displayName': 'v.mp4',
          'filePath': '${local.path}/videos/v2.mp4',
          'sizeBytes': 1,
          'fastKey': 'k2',
          'mirrored': false,
          'mirrorAsked': true,
          'lastOpenedAt': '2026-09-14T08:00:00.000Z',
        },
      ],
    });

    final package = await buildBackupPackage();
    final outcome = await WholeMachineRestorer(ports: localPorts()).restore(
      package: await readSusumePackage(package.path),
      packagePath: package.path,
    );

    expect(outcome, isA<RestoreCompleted>());
    final restoredIndex =
        await AtomicJsonFile(File('${local.path}/index.json')).readOrNull();
    final entry =
        ((restoredIndex!['entries'] as List).single as Map<String, Object?>);
    expect(entry['videoId'], 'v1');
    expect(entry['filePath'], localVideo.path,
        reason: '本机原视频尚在，恢复后仍打得开，退路真实可用');
    expect(localVideo.existsSync(), isTrue);
  });

  test('payload 版本不符：明确报错，不静默半恢复', () async {
    final package = await buildBackupPackage();
    final parsed = await readSusumePackage(package.path);
    final badPayload = {...parsed.backup!, 'payloadVersion': 999};
    final badPackageFile = File('${tempDir.path}/bad.susume');
    await writeSusumePackage(
      output: badPackageFile,
      manifest: const SusumeManifest(
        kind: SusumePackageKind.backup,
        videoId: '',
        schemeName: '',
        schemeId: '',
      ),
      markers: const {},
      backup: badPayload,
    );

    final outcome = await WholeMachineRestorer(ports: localPorts()).restore(
      package: await readSusumePackage(badPackageFile.path),
      packagePath: badPackageFile.path,
    );

    expect(outcome, isA<RestoreFailed>());
    expect(File('${local.path}/markers_v1.json').existsSync(), isFalse);
  });

  test('带媒体的备份：源视频解出进本机视频目录，索引 filePath 指向本机副本',
      () async {
    final video = File('${sender.path}/videos/v.mp4')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(64, 7));
    final collected = await collectWholeMachineBackup(
      senderPorts(),
      includeMedia: true,
    );
    final package = await assembleWholeMachineBackup(
      outputDir: Directory('${sender.path}/out'),
      payload: collected.payload,
      media: collected.media,
      now: DateTime(2026, 9, 15, 9),
    );
    expect(video.existsSync(), isTrue);

    final outcome = await WholeMachineRestorer(ports: localPorts()).restore(
      package: await readSusumePackage(package.path),
      packagePath: package.path,
    );

    expect(outcome, isA<RestoreCompleted>());
    final restoredIndex =
        await AtomicJsonFile(File('${local.path}/index.json')).readOrNull();
    final entry =
        ((restoredIndex!['entries'] as List).single as Map<String, Object?>);
    final restored = File(entry['filePath'] as String);
    expect(restored.existsSync(), isTrue);
    expect(restored.readAsBytesSync(), video.readAsBytesSync());
  });
}
