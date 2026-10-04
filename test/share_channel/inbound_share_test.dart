import 'dart:io';

import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/import/video_importer.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/package/package_picker.dart';
import 'package:dance_learning_app/package/scheme_import.dart';
import 'package:dance_learning_app/package/susume_package.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/level_control.dart'
    show
        screenBrightnessControllerProvider,
        systemMediaVolumeControllerProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/share_channel/share_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_beat_pipeline.dart';
import '../helpers/fake_brightness.dart';
import '../helpers/fake_package_picker.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_share_channel.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fake_system_volume.dart';
import '../helpers/fake_video_picker.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_member_scheme_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/poll.dart';

/// 入站分享页面接线：经 Fake 通道（平台边界）喂真实包文件，
/// 页面接真实 [SchemeImporter]（内存存储 + 真实视频管道）——冷启动拉取与
/// 热启动推送两条路径都断言「收到包即进导入流程并落盘」；非 Susume 包明确
/// 拒绝不崩、物化失败出声。注册声明与原生通道归 manifest 测试与真机验收。

const _sourceVideoEntry = SusumeMediaEntry(
  kind: SusumeMediaKind.sourceVideo,
  fileName: 'dance.mp4',
  sizeBytes: 3,
);

const _markers = {'version': 3, 'segmentLines': <Object?>[]};

VideoIndexEntry _entry(String videoId) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);

InMemoryVideoIndexStorage _seededIndex() => InMemoryVideoIndexStorage(
  initial: VideoIndex(entries: [_entry('hash-v1')]),
);

/// 通道的物化目标与 [FakeShareChannel.materialize] 同款路径；把真实包字节
/// 放进去，真实 [SchemeImporter.readPackage] 才读得到。
File _materializeBytes(List<int> bytes, String contentUri) {
  final dest = File(
    '${Directory.systemTemp.path}/susume_inbound/'
    '${inboundMaterializedName(contentUri)}',
  );
  dest.createSync(recursive: true);
  dest.writeAsBytesSync(bytes);
  return dest;
}

void main() {
  late Directory tempDir;
  late Directory videosDir;
  late Map<String, InMemoryMemberSchemeStorage> schemeStorages;
  late Map<String, InMemoryVideoDocumentStorage> documents;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('inbound_share_test');
    videosDir = Directory('${tempDir.path}/videos');
    schemeStorages = {};
    documents = {};
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File sourceVideo() =>
      File('${tempDir.path}/dance.mp4')..writeAsBytesSync([1, 2, 3]);

  /// 真实写出包文件（调用方须在 `tester.runAsync` 的真实事件循环里调用）。
  Future<File> writePackage(
    SusumeManifest manifest, {
    String fileName = '测试歌.susume',
  }) async {
    final file = File('${tempDir.path}/$fileName');
    await writeSusumePackage(
      output: file,
      manifest: SusumeManifest(
        videoId: manifest.videoId,
        schemeName: manifest.schemeName,
        schemeId: manifest.schemeId,
        memberName: manifest.memberName,
        mastery: manifest.mastery,
        media: [
          for (final entry in manifest.media)
            SusumeMediaEntry(
              kind: entry.kind,
              fileName: entry.fileName,
              sizeBytes: entry.sizeBytes,
              file: entry.kind == SusumeMediaKind.sourceVideo
                  ? sourceVideo()
                  : null,
            ),
        ],
      ),
      markers: _markers,
    );
    return file;
  }

  SchemeImporter importer(VideoIndexStorage indexStore) => SchemeImporter(
    indexStore: indexStore,
    videoImporter: VideoImporter(
      FakeVideoPicker(null),
      () async => videosDir,
      indexStore: indexStore,
      hasher: const FixedHasher('hash-v1'),
    ),
    schemeStoreFor: (videoId) => MemberSchemeStore(
      schemeStorages.putIfAbsent(videoId, InMemoryMemberSchemeStorage.new),
    ),
    documentStorageFor: (videoId) =>
        documents.putIfAbsent(videoId, InMemoryVideoDocumentStorage.new),
    now: () => DateTime(2026, 9, 15, 14, 5),
  );

  testWidgets('冷启动：原生留存的入站包被拉取，物化后进导入流程并落盘', (tester) async {
    const contentUri = 'content://com.tencent.mm/测试歌.susume';
    final channel = FakeShareChannel(
      pendingScript: [const InboundShare(contentUri: contentUri)],
    );
    final packageFile = (await tester.runAsync(
      () => writePackage(
        const SusumeManifest(
          videoId: 'hash-v1',
          schemeName: '测试歌',
          schemeId: 'scheme-1',
          memberName: '小如',
          media: [_sourceVideoEntry],
        ),
      ),
    ))!;
    _materializeBytes(packageFile.readAsBytesSync(), contentUri);

    final indexStore = _seededIndex();
    final harness = _Harness(
      channel: channel,
      indexStorage: indexStore,
      documents: documents,
      importer: importer(indexStore),
    );
    await harness.pumpHome(tester);
    await tester.runAsync(() async {
      await pollUntil(
        () => find
            .byKey(const Key('scheme_import_ownership_dialog'))
            .evaluate()
            .isNotEmpty,
        onTick: tester.pump,
        reason: '本机已有这支舞，归属选择面应出现',
      );
    });

    // 收到包即进导入流程；入站物化先于解析：包已被整份复制进应用目录。
    expect(
      find.byKey(const Key('scheme_import_ownership_dialog')),
      findsOneWidget,
    );
    expect(channel.materializedTo, hasLength(1));

    // 「留成TA的方案」之后才进组员名对话框。
    await tester.tap(find.byKey(const Key('scheme_import_keep_as_member')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scheme_import_dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('scheme_import_confirm')));
    await tester.pumpAndSettle();

    // 落盘：组员方案存储出现该 schemeId / 成员名的条目。
    final doc = await MemberSchemeStore(schemeStorages['hash-v1']!).read();
    expect(doc.schemes.single.schemeId, 'scheme-1');
    expect(doc.schemes.single.memberName, '小如');
  });

  testWidgets('热启动：App 已开时 onNewIntent 推送同样进导入流程并落盘', (tester) async {
    const contentUri = 'content://com.tencent.mm/b.susume';
    final channel = FakeShareChannel();
    final packageFile = (await tester.runAsync(
      () => writePackage(
        const SusumeManifest(
          videoId: 'sender-new',
          schemeName: '测试歌',
          schemeId: 'scheme-1',
          media: [_sourceVideoEntry],
        ),
      ),
    ))!;
    _materializeBytes(packageFile.readAsBytesSync(), contentUri);

    final indexStore = _seededIndex();
    final harness = _Harness(
      channel: channel,
      indexStorage: indexStore,
      documents: documents,
      importer: importer(indexStore),
    );
    await harness.pumpHome(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scheme_import_dialog')), findsNothing);

    await tester.runAsync(() async {
      // 模拟原生 onNewIntent 推送。
      channel.push(const InboundShare(contentUri: contentUri));
      await pollUntil(
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        onTick: tester.pump,
        reason: '推送的包应走完导入并出声',
      );
    });

    expect(
      find.byKey(const Key('scheme_import_ownership_dialog')),
      findsNothing,
      reason: '无舞无熟练度：直接建舞写成我的，不弹任何面',
    );
    expect(channel.takePendingCalls, 1, reason: '冷启动拉取照常发生（取尽为空）');
    // 落盘：包里的公开标注整份写进新建舞的 markers。
    expect(documents['hash-v1']!.markersSnapshot, _markers);
  });

  testWidgets('非 Susume 包：明确拒绝、不崩、不进导入编排', (tester) async {
    const contentUri = 'content://com.tencent.mm/随手投.bin';
    final channel = FakeShareChannel(
      pendingScript: [const InboundShare(contentUri: contentUri)],
    );
    _materializeBytes([0, 1, 2, 3], contentUri);

    final indexStore = _seededIndex();
    final harness = _Harness(
      channel: channel,
      indexStorage: indexStore,
      documents: documents,
      importer: importer(indexStore),
    );
    await harness.pumpHome(tester);
    await tester.runAsync(() async {
      await pollUntil(
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        onTick: tester.pump,
        reason: '非包应明确拒绝并出声',
      );
    });

    expect(find.byKey(const Key('scheme_import_dialog')), findsNothing);
    expect(find.text('文件损坏或不是 Susume 包，无法导入'), findsOneWidget);
    expect(schemeStorages, isEmpty);
    expect(documents, isEmpty);
  });

  testWidgets('物化失败（content 读不开）：明确出声、不崩', (tester) async {
    const contentUri = 'content://com.tencent.mm/a.susume';
    final channel = FakeShareChannel(
      pendingScript: [const InboundShare(contentUri: contentUri)],
    )..materializeFails = true;
    final indexStore = _seededIndex();
    final harness = _Harness(
      channel: channel,
      indexStorage: indexStore,
      documents: documents,
      importer: importer(indexStore),
    );
    await harness.pumpHome(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scheme_import_dialog')), findsNothing);
    expect(find.text('收到的文件复制不进来，导入中止'), findsOneWidget);
  });
}

class _Harness {
  _Harness({
    required this.channel,
    required this.indexStorage,
    required this.importer,
    required this.documents,
  });

  final FakeShareChannel channel;
  final InMemoryVideoIndexStorage indexStorage;
  final SchemeImporter importer;
  final Map<String, InMemoryVideoDocumentStorage> documents;

  final statsStorage = InMemoryPracticeStatsStorage();
  late final statsStore = PracticeStatsStore(statsStorage);
  final engine = FakePlaybackEngine();

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
          packagePickerProvider.overrideWithValue(FakePackagePicker(null)),
          shareChannelProvider.overrideWithValue(channel),
          schemeImporterProvider.overrideWithValue(importer),
        ],
        child: const DanceLearningApp(),
      ),
    );
    await tester.pump();
  }
}
