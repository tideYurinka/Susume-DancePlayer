import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dance_learning_app/annotation/compare_materials.dart'
    show MaterialRecord;
import 'package:dance_learning_app/cast/cast_render_cache.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:dance_learning_app/core/atomic_json_file.dart';
import 'package:dance_learning_app/package/susume_package.dart';
import 'package:dance_learning_app/package/whole_machine_backup.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/share/dance_share.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// **投屏缓存不进任何包**（ADR-0005：「两条载荷清单因此一个字都不用改」）。
///
/// 盘上真放着一份投屏副本（经缓存自己的公开面落在生产布局
/// `<支持目录>/cast_render/<键摘要>/<源片名>`）时：
///
/// - **分享包的载荷清单逐位不变**：zip 条目与清单键都按字面量逐位相等——
///   多一个键、少一个键、多一个条目都会被抓住；
/// - **整机备份的载荷清单逐位不变**：payload 键、每舞条目的键、媒体条目与
///   zip 条目同样逐位相等，且整份 payload 里不出现缓存区路径；
/// - 两条链路 **不动缓存区**：组装完包，那份副本还在原处（它只在本机盘上）。
void main() {
  late Directory support;
  late File sourceVideo;
  late Directory materialsBase;

  setUp(() {
    // 假装的应用支持目录：缓存区与其余数据的相对位置与生产一致。
    support = Directory.systemTemp.createTempSync('cast_cache_payload');
    sourceVideo = File(p.join(support.path, 'videos', 'v1.mp4'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(64, 1));
    materialsBase = Directory(p.join(support.path, 'materials', 'v1'))
      ..createSync(recursive: true);
    File(p.join(materialsBase.path, 'rec_1.mp4'))
      ..createSync()
      ..writeAsBytesSync(List.filled(32, 2));
  });

  tearDown(() {
    if (support.existsSync()) support.deleteSync(recursive: true);
  });

  final markersJson = <String, Object?>{
    'version': 9,
    'meta': <String, Object?>{'coverPositionMs': 42000},
  };
  final localJson = <String, Object?>{
    'version': 3,
    'prefs': <String, Object?>{'mirror': true},
  };
  final schemesJson = <String, Object?>{'version': 1, 'schemes': <Object?>[]};
  final deviceJson = <String, Object?>{'mirrorDefault': true};
  final materialsManifestJson = <String, Object?>{
    'version': 1,
    'materials': <Object?>[
      <String, Object?>{
        'id': 'm1',
        'videoId': 'v1',
        'fileName': 'rec_1.mp4',
        'sizeBytes': 32,
        'durationMs': 8000,
        'sourceStartMs': 0,
        'createdAt': '1970-01-01T00:00:00.000Z',
      },
    ],
  };

  /// 索引原文（`filePath` 指向本次的临时目录，所以在 setUp 之后才取值）。
  Map<String, Object?> indexJson() => <String, Object?>{
    'version': 1,
    'entries': <Object?>[
      <String, Object?>{
        'videoId': 'v1',
        'displayName': 'v1.mp4',
        'filePath': sourceVideo.path,
        'sizeBytes': 64,
        'fastKey': 'k',
        'mirrored': false,
        'mirrorAsked': true,
      },
    ],
  };

  /// 一份真落在缓存区里的投屏副本（经缓存自己的公开面：半成品 → 落定）。
  Future<File> populateCastCache() async {
    final cache = CastRenderCache(
      directory: () async => Directory(p.join(support.path, 'cast_render')),
    );
    final request = CastRenderRequest(
      videoPath: sourceVideo.path,
      videoId: 'v1',
      duration: const Duration(seconds: 8),
      choices: const CastRenderChoices.all(),
      speedTier: CastSpeedTier.full,
      settings: const CastRenderSettings(),
      annotationFingerprint: 'fp-1',
    );
    final part = await cache.partFileFor(request);
    part.writeAsBytesSync(List.filled(4096, 7));
    final product = await cache.promote(part, request);
    expect(await cache.usageBytes(), 4096, reason: '缓存区里真有一份副本');
    return product;
  }

  /// 分享链路的落盘数据（与生产同形：索引、两份文档、设备级设置、素材清单）。
  Future<void> writeSharedData() async {
    await AtomicJsonFile(File(p.join(support.path, 'index.json')))
        .write(indexJson());
    final documents = AtomicVideoDocumentStorage(
      markersFile: File(p.join(support.path, 'markers_v1.json')),
      localFile: File(p.join(support.path, 'local_v1.json')),
    );
    await documents.saveMarkers(markersJson);
    await documents.saveLocal(localJson);
    await MemberSchemeFileStore(File(p.join(support.path, 'schemes_v1.json')))
        .save(schemesJson);
    await AtomicJsonFile(File(p.join(support.path, 'global_private.json')))
        .write(deviceJson);
    await AtomicJsonFile(
      File(p.join(materialsBase.parent.path, 'manifest.json')),
    ).write(materialsManifestJson);
  }

  BackupPorts ports() => BackupPorts(
    loadIndexJson: () async =>
        (await AtomicJsonFile(File(p.join(support.path, 'index.json')))
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
      markersFile: File(p.join(support.path, 'markers_$videoId.json')),
      localFile: File(p.join(support.path, 'local_$videoId.json')),
    ),
    memberSchemeStorageFor: (videoId) => MemberSchemeFileStore(
      File(p.join(support.path, 'schemes_$videoId.json')),
    ),
    loadBucketShardJson: (videoId) async => await AtomicJsonFile(
      File(p.join(support.path, 'four_beat_buckets_$videoId.json')),
    ).readOrNull(),
    loadPracticeStatsJson: () async =>
        await AtomicJsonFile(File(p.join(support.path, 'practice_stats.json')))
            .readOrNull(),
    loadPracticePlanJson: () async =>
        await AtomicJsonFile(File(p.join(support.path, 'practice_plan.json')))
            .readOrNull(),
    loadDeviceSettings: () =>
        AtomicJsonFile(File(p.join(support.path, 'global_private.json')))
            .read(),
    loadMaterialsManifestJson: () async => await AtomicJsonFile(
      File(p.join(materialsBase.parent.path, 'manifest.json')),
    ).readOrNull(),
    loadMaterialRecords: () async => [
      MaterialRecord(
        id: 'm1',
        videoId: 'v1',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        durationMs: 8000,
        sourceStartMs: 0,
        fileName: 'rec_1.mp4',
        sizeBytes: 32,
      ),
    ],
    materialsBaseDirectory: () async => materialsBase.parent,
  );

  List<String> entryNamesOf(File package) => ZipDecoder()
      .decodeBytes(package.readAsBytesSync())
      .files
      .map((f) => f.name)
      .toList();

  Map<String, Object?> jsonEntryOf(File package, String name) {
    final file = ZipDecoder()
        .decodeBytes(package.readAsBytesSync())
        .files
        .firstWhere((f) => f.name == name);
    return (jsonDecode(utf8.decode(file.content)) as Map)
        .cast<String, Object?>();
  }

  test('分享包：盘上有投屏副本时，载荷清单仍逐位不变，且不动缓存区', () async {
    final product = await populateCastCache();

    final output = await assembleDancePackage(
      outputDir: Directory(p.join(support.path, 'out')),
      manifest: SusumeManifest(
        videoId: 'v1',
        schemeName: '海草舞',
        schemeId: 's1',
        media: [
          SusumeMediaEntry(
            kind: SusumeMediaKind.sourceVideo,
            fileName: 'v1.mp4',
            sizeBytes: 64,
            file: sourceVideo,
          ),
        ],
      ),
      markers: markersJson,
      videoFileName: 'v1.mp4',
    );

    // 条目清单逐位：清单、标注、勾选的媒体；没有缓存区里的任何一件。
    expect(entryNamesOf(output), [
      'manifest.json',
      'markers.json',
      'media/v1.mp4',
    ]);
    // 清单键逐位：share 链路一个字段都没变（kind 只在整机包上出现）。
    expect(jsonEntryOf(output, 'manifest.json').keys.toList(), [
      'version',
      'videoId',
      'schemeName',
      'schemeDancer',
      'schemeRemark',
      'schemeId',
      'media',
    ]);
    expect(jsonEntryOf(output, 'markers.json'), markersJson);
    expect(product.existsSync(), isTrue, reason: '组装分享包不该动缓存区：那份副本还在原处');
    expect(product.lengthSync(), 4096);
  });

  test('整机备份：盘上有投屏副本时，载荷清单仍逐位不变，且不动缓存区', () async {
    final product = await populateCastCache();
    await writeSharedData();

    final collected = await collectWholeMachineBackup(
      ports(),
      includeMedia: true,
    );
    final output = await assembleWholeMachineBackup(
      outputDir: Directory(p.join(support.path, 'out')),
      payload: collected.payload,
      media: collected.media,
      now: DateTime(2026, 9, 15, 9, 5),
    );

    // payload 键逐位：没有为缓存新增任何一节。
    expect(collected.payload.toJson().keys.toList(), [
      'payloadVersion',
      'index',
      'dances',
      'device',
      'practiceStats',
      'practicePlan',
      'materialsManifest',
    ]);
    // 每舞条目的键逐位。
    expect(collected.payload.dances.single.toJson().keys.toList(), [
      'videoId',
      'markers',
      'local',
      'schemes',
      'buckets',
      'media',
    ]);
    // 媒体清单逐位：只有源视频与练习录像这两种可选媒体。
    expect(collected.media.map((m) => m.fileName).toList(), [
      'v1__v1.mp4',
      'v1__rec_1.mp4',
    ]);
    // 包内条目逐位。
    expect(entryNamesOf(output), [
      'manifest.json',
      'backup.json',
      'media/v1__v1.mp4',
      'media/v1__rec_1.mp4',
    ]);
    // 整份 payload 里不出现缓存区：那份副本连路径都不进包。
    expect(
      jsonEncode(collected.payload.toJson()),
      isNot(contains('cast_render')),
    );
    expect(product.existsSync(), isTrue, reason: '备份不该动缓存区');
    expect(product.lengthSync(), 4096);
  });
}
