import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/core/atomic_json_file.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/import/picked_video.dart';
import 'package:dance_learning_app/import/video_importer.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/package/package_picker.dart';
import 'package:dance_learning_app/package/scheme_import.dart';
import 'package:dance_learning_app/package/susume_package.dart';
import 'package:dance_learning_app/package/whole_machine_backup.dart';
import 'package:dance_learning_app/package/whole_machine_restore.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/level_control.dart'
    show
        screenBrightnessControllerProvider,
        systemMediaVolumeControllerProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_beat_pipeline.dart';
import '../helpers/fake_brightness.dart';
import '../helpers/fake_package_picker.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fake_system_volume.dart';
import '../helpers/fake_video_picker.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_member_scheme_storage.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/package_flow_menu.dart';
import '../helpers/poll.dart';

/// 备份包与方案包经「恢复备份」入口的页面流程部件测试：真实
/// [WholeMachineRestorer]/[SchemeImporter] 接在临时目录端口上，页面只负责
/// 分流与提示；断言落盘结果（本机文档被替换、留档出现在留档目录、取消后
/// 逐字段不变）。编排本体另归 `whole_machine_restore_test.dart` 直测。

PickedVideo _pickedFor(File file) =>
    PickedVideo(name: file.uri.pathSegments.last, sourceUri: file.uri);

Map<String, Object?> _jsonOf(File file) =>
    (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();

InMemoryVideoIndexStorage _seededIndexStorage() => InMemoryVideoIndexStorage(
  initial: VideoIndex(
    entries: [
      VideoIndexEntry(
        videoId: 'hash-v1',
        displayName: 'hash-v1.mp4',
        filePath: '/videos/hash-v1.mp4',
        sizeBytes: 1,
        fastKey: 'k',
        mirrored: false,
        lastOpenedAt: DateTime(2026, 9, 1),
      ),
    ],
  ),
);

void main() {
  late Directory tempDir;
  late Directory local; // 恢复目标机（本机）
  late Directory sender; // 备份来源机
  late File backupPackage;
  late File dancePackage;

  final senderMarkers = <String, Object?>{
    'version': 9,
    'meta': {
      'signature': {'song': '海草舞'},
    },
  };
  final senderLocal = <String, Object?>{
    'version': 3,
    'session': {
      'mastery': {'0': 3},
    },
  };
  final senderSchemes = <String, Object?>{
    'version': 1,
    'schemes': [
      {'schemeId': 's1', 'memberName': '小舞'},
    ],
  };
  final senderDevice = <String, Object?>{'mirrorDefault': true};
  final localMarkers = <String, Object?>{
    'version': 8,
    'meta': {
      'signature': {'song': '本机的舞'},
    },
  };
  final localLocal = <String, Object?>{'version': 3};
  final localSchemes = <String, Object?>{
    'version': 1,
    'schemes': [
      {'schemeId': 'local-s', 'memberName': '我'},
    ],
  };
  final localDevice = <String, Object?>{'mirrorDefault': false};
  final danceMarkers = <String, Object?>{
    'version': 3,
    'segmentLines': <Object?>[],
  };

  Map<String, Object?> machineIndexJson(
    Directory root,
    String videoId,
    String extraKey,
  ) => {
    'version': 1,
    'extra': {extraKey: true},
    'entries': [
      {
        'videoId': videoId,
        'displayName': 'v.mp4',
        'filePath': '${root.path}/videos/v.mp4',
        'sizeBytes': 64,
        'fastKey': 'k',
        'mirrored': false,
        'mirrorAsked': true,
        'lastOpenedAt': '2026-09-15T08:00:00.000Z',
      },
    ],
  };

  VideoIndexEntry senderEntry() => VideoIndexEntry(
    videoId: 'v1',
    displayName: 'v.mp4',
    filePath: '${sender.path}/videos/v.mp4',
    sizeBytes: 64,
    fastKey: 'k',
    mirrored: false,
    mirrorAsked: true,
    lastOpenedAt: DateTime(2026, 9, 15, 8),
  );

  VideoIndexEntry localEntry() => VideoIndexEntry(
    videoId: 'v2',
    displayName: 'v.mp4',
    filePath: '${local.path}/videos/v.mp4',
    sizeBytes: 64,
    fastKey: 'k',
    mirrored: false,
    mirrorAsked: true,
    lastOpenedAt: DateTime(2026, 9, 15, 8),
  );

  /// 发送机的采集端口：数据在内存里就不必落盘，装配出的包照样是真实 zip。
  BackupPorts senderPorts() => BackupPorts(
    loadIndexJson: () async => machineIndexJson(sender, 'v1', 'keptSenderKey'),
    loadIndex: () async => VideoIndex(entries: [senderEntry()]),
    documentStorageFor: (_) =>
        InMemoryVideoDocumentStorage(markers: senderMarkers, local: senderLocal),
    memberSchemeStorageFor: (_) => InMemoryMemberSchemeStorage(senderSchemes),
    loadBucketShardJson: (_) async => null,
    loadPracticeStatsJson: () async => null,
    loadPracticePlanJson: () async => null,
    loadDeviceSettings: () async => senderDevice,
    loadMaterialsManifestJson: () async => null,
    loadMaterialRecords: () async => const [],
    materialsBaseDirectory: () async => Directory('${sender.path}/materials'),
  );

  /// 本机的采集端口（留档采集的是恢复前的本机磁盘原文）。
  BackupPorts localBackupPorts() => BackupPorts(
    loadIndexJson: () async =>
        await AtomicJsonFile(File('${local.path}/index.json')).readOrNull() ??
        {},
    loadIndex: () async => VideoIndex(entries: [localEntry()]),
    documentStorageFor: (videoId) => AtomicVideoDocumentStorage(
      markersFile: File('${local.path}/markers_$videoId.json'),
      localFile: File('${local.path}/local_$videoId.json'),
    ),
    memberSchemeStorageFor: (videoId) =>
        MemberSchemeFileStore(File('${local.path}/schemes_$videoId.json')),
    loadBucketShardJson: (_) async => null,
    loadPracticeStatsJson: () async => null,
    loadPracticePlanJson: () async => null,
    loadDeviceSettings: () async => await AtomicJsonFile(
      File('${local.path}/global_private.json'),
    ).read(),
    loadMaterialsManifestJson: () async => null,
    loadMaterialRecords: () async => const [],
    materialsBaseDirectory: () async => Directory('${local.path}/materials'),
  );

  /// 留档采集触达设备设置时炸：留档失败即中止（还原「本机未动」）。
  BackupPorts brokenBackupPorts() {
    final base = localBackupPorts();
    return BackupPorts(
      loadIndexJson: base.loadIndexJson,
      loadIndex: base.loadIndex,
      documentStorageFor: base.documentStorageFor,
      memberSchemeStorageFor: base.memberSchemeStorageFor,
      loadBucketShardJson: base.loadBucketShardJson,
      loadPracticeStatsJson: base.loadPracticeStatsJson,
      loadPracticePlanJson: base.loadPracticePlanJson,
      loadDeviceSettings: () async => throw StateError('磁盘满'),
      loadMaterialsManifestJson: base.loadMaterialsManifestJson,
      loadMaterialRecords: base.loadMaterialRecords,
      materialsBaseDirectory: base.materialsBaseDirectory,
    );
  }

  late InMemoryPracticePlanStorage planStorage;
  late InMemoryPracticeStatsStorage statsStorage;
  late InMemoryFourBeatBucketStorage bucketStorage;
  late InMemoryPrivateJsonStorage deviceStorage;
  late MemoryManifestStorage materialsStorage;

  RestorePorts localPorts({bool failArchive = false}) => RestorePorts(
    backup: failArchive ? brokenBackupPorts() : localBackupPorts(),
    indexFile: () async => File('${local.path}/index.json'),
    documentStorageFor: (videoId) => AtomicVideoDocumentStorage(
      markersFile: File('${local.path}/markers_$videoId.json'),
      localFile: File('${local.path}/local_$videoId.json'),
    ),
    memberSchemeStorageFor: (videoId) =>
        MemberSchemeFileStore(File('${local.path}/schemes_$videoId.json')),
    bucketStorage: bucketStorage,
    practiceStatsStorage: statsStorage,
    practicePlanReplace: (json) async => planStorage.save(json),
    practicePlanRetainDances: (videoIds) =>
        PracticePlanStore(planStorage).retainDances(videoIds),
    deviceSettingsStorage: deviceStorage,
    materialsStorage: materialsStorage,
    materialsBaseDirectory: () async => Directory('${local.path}/materials'),
    archiveDirectory: () async => Directory('${local.path}/恢复留档'),
    videosDirectory: () async => Directory('${local.path}/videos'),
  );

  WholeMachineRestorer restorer({bool failArchive = false}) =>
      WholeMachineRestorer(ports: localPorts(failArchive: failArchive));

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('restore_flow_test');
    local = Directory('${tempDir.path}/local')..createSync(recursive: true);
    sender = Directory('${tempDir.path}/sender')..createSync(recursive: true);
    planStorage = InMemoryPracticePlanStorage();
    statsStorage = InMemoryPracticeStatsStorage();
    bucketStorage = InMemoryFourBeatBucketStorage();
    deviceStorage = InMemoryPrivateJsonStorage();
    materialsStorage = MemoryManifestStorage();

    File('${local.path}/index.json')
        .writeAsStringSync(jsonEncode(machineIndexJson(local, 'v2', 'keptLocalKey')));
    File('${local.path}/markers_v2.json')
        .writeAsStringSync(jsonEncode(localMarkers));
    File('${local.path}/local_v2.json').writeAsStringSync(jsonEncode(localLocal));
    File('${local.path}/schemes_v2.json')
        .writeAsStringSync(jsonEncode(localSchemes));
    File('${local.path}/global_private.json')
        .writeAsStringSync(jsonEncode(localDevice));

    final collected = await collectWholeMachineBackup(
      senderPorts(),
      includeMedia: false,
    );
    backupPackage = await assembleWholeMachineBackup(
      outputDir: Directory('${sender.path}/out'),
      payload: collected.payload,
      media: collected.media,
      now: DateTime(2026, 9, 15, 9),
    );

    final sourceVideo = File('${tempDir.path}/dance.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    dancePackage = File('${tempDir.path}/测试歌.susume');
    await writeSusumePackage(
      output: dancePackage,
      manifest: SusumeManifest(
        videoId: 'sender-new',
        schemeName: '测试歌',
        schemeId: 'scheme-1',
        memberName: '小如',
        media: [
          SusumeMediaEntry(
            kind: SusumeMediaKind.sourceVideo,
            fileName: 'dance.mp4',
            sizeBytes: 3,
            file: sourceVideo,
          ),
        ],
      ),
      markers: danceMarkers,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> awaitRestoreConfirm(WidgetTester tester) =>
      tester.runAsync(() async {
        await pollUntil(
          () => find.byKey(const Key('restore_confirm_dialog')).evaluate().isNotEmpty,
          onTick: () => tester.pump(),
          reason: '应弹恢复确认面',
        );
      });

  testWidgets('备份包：列出将发生什么，确认后完成恢复并留档', (tester) async {
    final harness = _Harness(
      restorer: restorer(),
      picked: _pickedFor(backupPackage),
    );
    await harness.pumpHome(tester);

    await openRestoreBackupFromHomeMenu(tester);
    await awaitRestoreConfirm(tester);

    expect(find.byKey(const Key('restore_confirm_dialog')), findsOneWidget);
    expect(find.textContaining('整体替换'), findsOneWidget);
    expect(find.textContaining('留一份档'), findsOneWidget);
    expect(find.textContaining('练舞统计'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('restore_confirm_button')));
      await pollUntil(
        () => find.textContaining('恢复完成').evaluate().isNotEmpty,
        onTick: () => tester.pump(),
        reason: '恢复完成提示',
      );
    });

    // 全量替换：本机就是备份那一刻的样子（文档逐字段等于包内容）。
    expect(_jsonOf(File('${local.path}/markers_v1.json')), senderMarkers);
    expect(_jsonOf(File('${local.path}/local_v1.json')), senderLocal);
    expect(_jsonOf(File('${local.path}/schemes_v1.json')), senderSchemes);
    final restoredIndex = _jsonOf(File('${local.path}/index.json'));
    expect((restoredIndex['entries'] as List).single['videoId'], 'v1');
    expect(restoredIndex['extra'], {'keptSenderKey': true});
    expect(File('${local.path}/markers_v2.json').existsSync(), isFalse);

    // 留档：恢复前的本机数据落在固定目录，可解析、可清。
    final archiveDir = Directory('${local.path}/恢复留档');
    final archivedFiles = archiveDir.listSync().whereType<File>().toList();
    expect(archivedFiles, hasLength(1));
    expect(archivedFiles.single.path, endsWith('.susume'));
    final archived = await tester.runAsync(
      () => readSusumePackage(archivedFiles.single.path),
    );
    expect(
      (archived!.backup!['dances'] as List).single['markers'],
      localMarkers,
      reason: '留档是恢复前的本机数据',
    );
  });

  testWidgets('备份包：取消确认面则什么都不做', (tester) async {
    final indexBefore = File('${local.path}/index.json').readAsStringSync();
    final markersBefore = File('${local.path}/markers_v2.json').readAsStringSync();
    final harness = _Harness(
      restorer: restorer(),
      picked: _pickedFor(backupPackage),
    );
    await harness.pumpHome(tester);

    await openRestoreBackupFromHomeMenu(tester);
    await awaitRestoreConfirm(tester);
    await tester.tap(find.byKey(const Key('restore_cancel')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    // 索引与文档逐字段不变。
    expect(File('${local.path}/index.json').readAsStringSync(), indexBefore);
    expect(File('${local.path}/markers_v2.json').readAsStringSync(), markersBefore);
    expect(File('${local.path}/markers_v1.json').existsSync(), isFalse);
    expect(Directory('${local.path}/恢复留档').existsSync(), isFalse);
  });

  testWidgets('留档失败：以短暂提示中止并说明本机数据未改动', (tester) async {
    final markersBefore = File('${local.path}/markers_v2.json').readAsStringSync();
    final harness = _Harness(
      restorer: restorer(failArchive: true),
      picked: _pickedFor(backupPackage),
    );
    await harness.pumpHome(tester);

    await openRestoreBackupFromHomeMenu(tester);
    await awaitRestoreConfirm(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('restore_confirm_button')));
      await pollUntil(
        () => find
            .text('留档失败，已中止恢复，本机数据未改动')
            .evaluate()
            .isNotEmpty,
        onTick: () => tester.pump(),
        reason: '留档失败应明确出声',
      );
    });

    expect(File('${local.path}/markers_v2.json').readAsStringSync(), markersBefore);
    expect(File('${local.path}/markers_v1.json').existsSync(), isFalse);
  });

  testWidgets('普通包：不弹恢复确认面，按导入分支树走', (tester) async {
    final harness = _Harness(
      restorer: restorer(),
      picked: _pickedFor(dancePackage),
      videosDir: Directory('${tempDir.path}/videos'),
    );
    await harness.pumpHome(tester);

    await openRestoreBackupFromHomeMenu(tester);
    await tester.runAsync(() async {
      await pollUntil(
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        onTick: () => tester.pump(),
        reason: '普通包应直接走导入并出声',
      );
    });

    expect(find.byKey(const Key('restore_confirm_dialog')), findsNothing);
    // 无舞无熟练度：直接建舞写成我的，不弹任何面。
    expect(find.byKey(const Key('scheme_import_ownership_dialog')), findsNothing);
    expect(find.byKey(const Key('scheme_import_dialog')), findsNothing);
    expect(find.textContaining('已把 小如 的标注写成我的'), findsOneWidget);
    // 落盘结果：包里的公开标注整份写进新建舞的 markers。
    expect(harness.documents['hash-v1']!.markersSnapshot, danceMarkers);
  });

  testWidgets('空库：不依赖先有舞，从 ⋯ 恢复仍完整可达', (tester) async {
    final harness = _Harness(
      restorer: restorer(),
      picked: _pickedFor(backupPackage),
      seeded: false,
    );
    await harness.pumpHome(tester);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dance_library_empty')), findsOneWidget);

    await openRestoreBackupFromHomeMenu(tester);
    await awaitRestoreConfirm(tester);

    expect(find.byKey(const Key('restore_confirm_dialog')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('restore_confirm_button')));
      await pollUntil(
        () => find.textContaining('恢复完成').evaluate().isNotEmpty,
        onTick: () => tester.pump(),
        reason: '恢复完成提示',
      );
    });
    expect(find.textContaining('恢复完成'), findsOneWidget);
    expect(File('${local.path}/markers_v1.json').existsSync(), isTrue);
  });
}

/// 页面流程不触真实管道时的建舞桩：构造即报错的桩，防止误走真实文件 IO。
VideoImporter _stubVideoImporter(VideoIndexStorage indexStore) => VideoImporter(
  FakeVideoPicker(null),
  () async => throw StateError('该用例不走建舞分支'),
  indexStore: indexStore,
  hasher: const FixedHasher('stub'),
);

class _Harness {
  _Harness({
    required this.restorer,
    required this.picked,
    this.videosDir,
    bool seeded = true,
  }) : indexStorage = seeded
           ? _seededIndexStorage()
           : InMemoryVideoIndexStorage();

  final WholeMachineRestorer restorer;
  final PickedVideo picked;
  final Directory? videosDir;

  final InMemoryVideoIndexStorage indexStorage;
  final documents = <String, InMemoryVideoDocumentStorage>{};
  final schemeStorages = <String, InMemoryMemberSchemeStorage>{};
  final statsStorage = InMemoryPracticeStatsStorage();
  late final statsStore = PracticeStatsStore(statsStorage);
  final engine = FakePlaybackEngine();

  late final SchemeImporter importer = SchemeImporter(
    indexStore: indexStorage,
    videoImporter: videosDir == null
        ? _stubVideoImporter(indexStorage)
        : VideoImporter(
            FakeVideoPicker(null),
            () async => videosDir!,
            indexStore: indexStorage,
            hasher: const FixedHasher('hash-v1'),
          ),
    schemeStoreFor: (videoId) =>
        MemberSchemeStore(schemeStorages.putIfAbsent(
          videoId,
          InMemoryMemberSchemeStorage.new,
        )),
    documentStorageFor: (videoId) => documents.putIfAbsent(
      videoId,
      InMemoryVideoDocumentStorage.new,
    ),
    now: () => DateTime(2026, 9, 15, 14, 5),
  );

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practicePlanStorageProvider.overrideWithValue(
            InMemoryPracticePlanStorage(),
          ),
          coverCacheProvider.overrideWith((ref) async => InMemoryCoverCache()),
          videoIndexStoreProvider.overrideWithValue(indexStorage),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => documents[videoId] ?? InMemoryVideoDocumentStorage(),
          ),
          practiceStatsStoreProvider.overrideWithValue(statsStore),
          playbackEngineProvider.overrideWithValue(engine),
          beatAnalysisPipelineProvider.overrideWithValue(FakeBeatPipeline()),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          screenBrightnessControllerProvider.overrideWithValue(
            FakeScreenBrightnessController(),
          ),
          systemMediaVolumeControllerProvider.overrideWithValue(
            FakeSystemMediaVolumeController(),
          ),
          packagePickerProvider.overrideWithValue(FakePackagePicker(picked)),
          schemeImporterProvider.overrideWithValue(importer),
          wholeMachineRestorerProvider.overrideWithValue(restorer),
        ],
        child: const DanceLearningApp(),
      ),
    );
    await tester.pumpAndSettle();
  }
}
