import 'dart:io';

import 'package:dance_learning_app/core/atomic_json_file.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/package/susume_package.dart';
import 'package:dance_learning_app/annotation/compare_materials.dart'
    show MaterialRecord;
import 'package:dance_learning_app/package/whole_machine_backup.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime never = DateTime.fromMillisecondsSinceEpoch(0);

/// 整机备份编排测试：经临时目录真实采集与 zip 往返，
/// 断言备份包解析回来覆盖到全部完全私密字段、不含练舞统计、媒体默认不含
/// 可选。恢复侧归，这里只断言备份产物自身。
void main() {
  late Directory tempDir;
  late File sourceVideo;
  late File clipFile;
  late Directory materialsBase;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('whole_machine_backup');
    sourceVideo = File('${tempDir.path}/videos/v1.mp4')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(64, 1));
    materialsBase = Directory('${tempDir.path}/materials/v1')
      ..createSync(recursive: true);
    clipFile = File('${materialsBase.path}/rec_1.mp4')
      ..writeAsBytesSync(List.filled(32, 2));
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  final indexJson = <String, Object?>{
    'version': 1,
    'extra': <String, Object?>{'keptKey': 'kept'},
    'entries': <Object?>[
      <String, Object?>{
        'videoId': 'v1',
        'displayName': 'v1.mp4',
        'filePath': 'PLACEHOLDER',
        'sizeBytes': 64,
        'fastKey': 'k',
        'mirrored': false,
        'mirrorAsked': true,
        'lastOpenedAt': '2026-09-15T08:00:00.000Z',
        'signatureCache': <String, Object?>{
          'dancer': '如',
          'song': '海草舞',
          'remark': '',
        },
        'lastPositionMs': 42000,
      },
    ],
  };

  final markersJson = <String, Object?>{
    'version': 9,
    'meta': <String, Object?>{
      'signature': <String, Object?>{'song': '海草舞'},
      // 封面位置（完全公开）：随我的标注方案原文进包。
      'coverPositionMs': 42000,
      // 源画面取景选区：随公开标记原文进包。
      'framingSelection': <String, Object?>{
        'left': 0.2,
        'top': 0.1,
        'right': 0.7,
        'bottom': 0.6,
      },
    },
  };
  final localJson = <String, Object?>{
    'version': 3,
    'session': <String, Object?>{
      'mastery': <String, Object?>{'0': 3},
      'activatedSegments': <Object?>[0],
    },
    'prefs': <String, Object?>{
      'previewSnapEnabled': false,
      'overlay': <String, Object?>{'x': 12.0, 'y': 30.0},
      'framing': <String, Object?>{'source': <String, Object?>{}},
      'practiceClips': <Object?>[
        <String, Object?>{'materialId': 'm1', 'clipId': 'c1'},
      ],
      'autoDelete': <String, Object?>{'mode': 'count', 'keepCount': 30},
    },
  };
  final schemesJson = <String, Object?>{
    'version': 1,
    'schemes': <Object?>[
      <String, Object?>{'schemeId': 's1', 'memberName': '小舞'},
    ],
  };
  // 四拍桶分片与练舞统计的磁盘原文：含将来未知键，断言按存储原文进包。
  final bucketsJson = <String, Object?>{
    'version': 1,
    'signature': <String, Object?>{'dancer': '如', 'song': '海草舞', 'remark': ''},
    'ledger': <String, Object?>{
      'days': <String, Object?>{
        '2026-09-15': <String, Object?>{
          '4': <String, Object?>{
            'wallSeconds': 12.5,
            'sweeps': 2,
            'futureKey': 'x',
          },
        },
      },
      'keptLedgerKey': 7,
    },
  };
  final practiceStatsJson = <String, Object?>{
    'version': 2,
    'sessions': <Object?>[
      <String, Object?>{
        'start': '2026-09-15T08:00:00.000',
        'videoId': 'v1',
        'dancer': '如',
        'song': '海草舞',
        'remark': '',
        'wallSeconds': 60.0,
      },
    ],
    'keptStatsKey': true,
  };
  final deviceJson = <String, Object?>{
    'mirrorDefault': true,
    'surfaceBasisKey': 'front_camera_preview',
  };
  // 计划文档：完全私密、按磁盘原文进包（陌生键一并
  // 带走）。
  final practicePlanJson = <String, Object?>{
    'version': 1,
    'entries': <Object?>[
      <String, Object?>{
        'videoId': 'v1',
        'socialLibrary': false,
        'ddl': <String, Object?>{
          'date': '2026-10-01',
          'occasion': '演出',
          'remark': '道具扇子',
          'leadDays': 3,
          'checklist': <Object?>[
            <String, Object?>{'text': '带水', 'checked': true},
          ],
          'settlement': <String, Object?>{
            'outcome': 'onTime',
            'judgedOn': '2026-10-02',
          },
        },
      },
    ],
    'events': <Object?>[
      <String, Object?>{
        'id': 'e1',
        'type': 'socialDanceEvent',
        'date': '2026-11-08',
        'startTime': '19:30',
        'location': '滨江区',
        'remark': '带音箱',
        'danceIds': <Object?>['v1'],
        'checklist': <Object?>[
          <String, Object?>{'text': '充电宝', 'checked': true},
        ],
      },
    ],
    'keptPlanKey': true,
  };
  final materialsManifestJson = <String, Object?>{
    'version': 2,
    'materials': <String, Object?>{
      'entries': <Object?>[
        <String, Object?>{
          'id': 'm1',
          'videoId': 'v1',
          'fileName': 'rec_1.mp4',
          'sizeBytes': 32,
        },
      ],
    },
  };

  Future<void> writeFixtures() async {
    await AtomicJsonFile(File('${tempDir.path}/index.json')).write({
      ...indexJson,
      'entries': [
        {
          ...(indexJson['entries'] as List).first as Map<String, Object?>,
          'filePath': sourceVideo.path,
        },
      ],
    });
    final documents = AtomicVideoDocumentStorage(
      markersFile: File('${tempDir.path}/markers_v1.json'),
      localFile: File('${tempDir.path}/local_v1.json'),
    );
    await documents.saveMarkers(markersJson);
    await documents.saveLocal(localJson);
    await MemberSchemeFileStore(File('${tempDir.path}/schemes_v1.json'))
        .save(schemesJson);
    await AtomicJsonFile(File('${tempDir.path}/four_beat_buckets_v1.json'))
        .write(bucketsJson);
    await AtomicJsonFile(File('${tempDir.path}/practice_stats.json'))
        .write(practiceStatsJson);
    await AtomicJsonFile(File('${tempDir.path}/global_private.json'))
        .write(deviceJson);
    await AtomicJsonFile(File('${tempDir.path}/practice_plan.json'))
        .write(practicePlanJson);
    await AtomicJsonFile(File('${materialsBase.parent.path}/manifest.json'))
        .write(materialsManifestJson);
    // 封面缓存图片与文档同级：它是设备本地缓存，不该进包（也不是媒体种类）。
    File('${tempDir.path}/cover_v1.jpg').writeAsBytesSync(List.filled(16, 9));
  }

  BackupPorts ports() => BackupPorts(
    loadIndexJson: () async =>
        (await AtomicJsonFile(File('${tempDir.path}/index.json'))
            .readOrNull()) ??
        {},
    loadIndex: () async => VideoIndex(
      entries: [
        VideoIndexEntry(
          videoId: 'v1',
          displayName: 'v1.mp4',
          filePath: sourceVideo.path,
          sizeBytes: 64,
          fastKey: 'k',
          mirrored: false,
          mirrorAsked: true,
          lastOpenedAt: DateTime(2026, 9, 15, 8),
          signatureCache: const SongSignature(dancer: '如', song: '海草舞'),
          lastPositionMs: 42000,
        ),
      ],
    ),
    documentStorageFor: (videoId) => AtomicVideoDocumentStorage(
      markersFile: File('${tempDir.path}/markers_$videoId.json'),
      localFile: File('${tempDir.path}/local_$videoId.json'),
    ),
    memberSchemeStorageFor: (videoId) =>
        MemberSchemeFileStore(File('${tempDir.path}/schemes_$videoId.json')),
    loadBucketShardJson: (videoId) async => await AtomicJsonFile(
      File('${tempDir.path}/four_beat_buckets_$videoId.json'),
    ).readOrNull(),
    loadPracticeStatsJson: () async =>
        await AtomicJsonFile(File('${tempDir.path}/practice_stats.json'))
            .readOrNull(),
    loadPracticePlanJson: () async =>
        await AtomicJsonFile(File('${tempDir.path}/practice_plan.json'))
            .readOrNull(),
    loadDeviceSettings: () async =>
        await AtomicJsonFile(File('${tempDir.path}/global_private.json'))
            .read(),
    loadMaterialsManifestJson: () async =>
        await AtomicJsonFile(File('${materialsBase.parent.path}/manifest.json'))
            .readOrNull(),
    loadMaterialRecords: () async => [
      MaterialRecord(
        id: 'm1',
        videoId: 'v1',
        createdAt: never,
        durationMs: 8000,
        sourceStartMs: 0,
        fileName: 'rec_1.mp4',
        sizeBytes: 32,
      ),
    ],
    materialsBaseDirectory: () async => materialsBase.parent,
  );

  Map<String, Object?> expectedDance({
    List<Object?> media = const [],
    Map<String, Object?>? buckets,
  }) => {
    'videoId': 'v1',
    'markers': markersJson,
    'local': localJson,
    'schemes': schemesJson,
    'buckets': buckets ?? bucketsJson,
    'media': media,
  };

  test('默认不含媒体：解析回来覆盖全部完全私密字段、含练舞统计与桶分片', () async {
    await writeFixtures();
    final collected = await collectWholeMachineBackup(
      ports(),
      includeMedia: false,
    );
    final output = await assembleWholeMachineBackup(
      outputDir: Directory('${tempDir.path}/out'),
      payload: collected.payload,
      media: collected.media,
      now: DateTime(2026, 9, 15, 9, 5),
    );

    expect(output.path, endsWith('Susume备份_20260915-0905.susume'));
    final parsed = await readSusumePackage(output.path);
    expect(parsed.isBackup, isTrue);
    expect(parsed.manifest.kind, SusumePackageKind.backup);
    expect(parsed.manifest.media, isEmpty);
    // 桶分片、练舞统计与计划文档按存储原文进包（陌生键一并带走），payload
    // 版本升到 3；键集合逐项钉死，多/少一个键都会被这条断言抓住。
    expect(parsed.backup, {
      'payloadVersion': 3,
      'index': {
        'version': 1,
        'extra': {'keptKey': 'kept'},
        'entries': [
          {
            'videoId': 'v1',
            'displayName': 'v1.mp4',
            'filePath': sourceVideo.path,
            'sizeBytes': 64,
            'fastKey': 'k',
            'mirrored': false,
            'mirrorAsked': true,
            'lastOpenedAt': '2026-09-15T08:00:00.000Z',
            'signatureCache': {'dancer': '如', 'song': '海草舞', 'remark': ''},
            'lastPositionMs': 42000,
          },
        ],
      },
      'dances': [expectedDance()],
      'device': deviceJson,
      'practiceStats': practiceStatsJson,
      'practicePlan': practicePlanJson,
      'materialsManifest': materialsManifestJson,
    });
  });

  test('桶分片、练舞统计与计划文档文件缺失：payload 对应键为空、采集不失败', () async {
    await writeFixtures();
    File('${tempDir.path}/four_beat_buckets_v1.json').deleteSync();
    File('${tempDir.path}/practice_stats.json').deleteSync();
    File('${tempDir.path}/practice_plan.json').deleteSync();
    final collected = await collectWholeMachineBackup(
      ports(),
      includeMedia: false,
    );
    final output = await assembleWholeMachineBackup(
      outputDir: Directory('${tempDir.path}/out'),
      payload: collected.payload,
      media: collected.media,
      now: DateTime(2026, 9, 15, 9, 5),
    );

    final parsed = await readSusumePackage(output.path);
    expect(parsed.backup!['practiceStats'], <String, Object?>{});
    expect(parsed.backup!['practicePlan'], <String, Object?>{});
    expect(
      (parsed.backup!['dances'] as List).single,
      expectedDance(buckets: const {}),
    );
  });

  test('可选媒体：勾上后源视频与练习录像进包，条目按舞前缀、payload 记录归属', () async {
    await writeFixtures();
    final collected = await collectWholeMachineBackup(
      ports(),
      includeMedia: true,
    );
    final output = await assembleWholeMachineBackup(
      outputDir: Directory('${tempDir.path}/out'),
      payload: collected.payload,
      media: collected.media,
      now: DateTime(2026, 9, 15, 9, 5),
    );

    final parsed = await readSusumePackage(output.path);
    expect(parsed.manifest.media.map((m) => (m.kind, m.fileName)).toSet(), {
      (SusumeMediaKind.sourceVideo, 'v1__v1.mp4'),
      (SusumeMediaKind.practiceClip, 'v1__rec_1.mp4'),
    });
    expect(parsed.backup!['dances'], [
      expectedDance(media: ['v1__v1.mp4', 'v1__rec_1.mp4']),
    ]);
    // 封面图片是设备本地缓存：不进包（媒体清单里没有它的位置）。
    expect(
      parsed.manifest.media.map((m) => m.fileName),
      isNot(contains(contains('cover'))),
    );
    // 媒体条目能按名解出，字节与源文件一致。
    final extracted = File('${tempDir.path}/extracted.mp4');
    await extractMediaEntry(output.path, 'media/v1__rec_1.mp4', extracted);
    expect(extracted.readAsBytesSync(), clipFile.readAsBytesSync());
  });

  test('素材文件已不在磁盘：跳过该条媒体，采集与装配不失败', () async {
    await writeFixtures();
    clipFile.deleteSync();
    final collected = await collectWholeMachineBackup(
      ports(),
      includeMedia: true,
    );
    expect(collected.media.map((m) => m.fileName), ['v1__v1.mp4']);
  });

  test('索引没有条目、目录里没有任何舞：空备份照常装配', () async {
    final empty = BackupPorts(
      loadIndexJson: () async => {'version': 1, 'entries': []},
      loadIndex: () async => VideoIndex.empty,
      documentStorageFor: (videoId) => throw StateError('不该触达'),
      memberSchemeStorageFor: (videoId) => throw StateError('不该触达'),
      loadBucketShardJson: (videoId) => throw StateError('不该触达'),
      loadPracticeStatsJson: () async => null,
      loadPracticePlanJson: () async => null,
      loadDeviceSettings: () async => {'mirrorDefault': false},
      loadMaterialsManifestJson: () async => null,
      loadMaterialRecords: () async => const [],
      materialsBaseDirectory: () async => materialsBase,
    );
    final collected = await collectWholeMachineBackup(
      empty,
      includeMedia: false,
    );
    final output = await assembleWholeMachineBackup(
      outputDir: Directory('${tempDir.path}/out'),
      payload: collected.payload,
      media: collected.media,
      now: DateTime(2026, 9, 15, 9, 5),
    );
    final parsed = await readSusumePackage(output.path);
    expect(parsed.backup!['dances'], isEmpty);
    expect(parsed.backup!['index'], {'version': 1, 'entries': []});
    expect(parsed.backup!['practiceStats'], isEmpty);
    expect(parsed.backup!['practicePlan'], isEmpty);
    expect(parsed.backup!['materialsManifest'], isNull);
  });
}
