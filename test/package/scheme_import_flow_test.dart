import 'dart:io';

import 'package:dance_learning_app/app.dart';
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
import 'package:dance_learning_app/persistence/four_beat_bucket_providers.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart'
    show practicePlanStorageProvider;
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
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

import '../helpers/device_viewport.dart';
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
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/package_flow_menu.dart';
import '../helpers/poll.dart';

/// 方案包页面流程部件测试：真实 [SchemeImporter]（内存
/// index/文档/方案存储 + 固定哈希管道）接在包文件上——包用
/// `writeSusumePackage` 真实写出、`FakePackagePicker` 递入，页面流程经
/// `runAsync` 完成导入；断言落盘结果（组员方案条目、markers 文档整份替换、
/// 拒绝分支存储为空）。对话框出现与否、出口文案、预填组员名这些纯 UI 断言
/// 原样保留；编排的落盘细节另归 `scheme_import_test.dart` 直测。

const _sourceVideoEntry = SusumeMediaEntry(
  kind: SusumeMediaKind.sourceVideo,
  fileName: 'dance.mp4',
  sizeBytes: 3,
);

const _markers = {'version': 3, 'segmentLines': <Object?>[]};

PickedVideo _pickedFor(File file) =>
    PickedVideo(name: '测试歌.susume', sourceUri: file.uri);

/// 包解析是真实文件 IO：在真实事件循环里等页面弹出对应确认面。
Future<void> _awaitDialog(WidgetTester tester, Key key) =>
    tester.runAsync(() async {
      await pollUntil(
        () => find.byKey(key).evaluate().isNotEmpty,
        onTick: tester.pump,
        reason: '应弹出 ${key.toString()}',
      );
    });

VideoIndexEntry _entry(String videoId) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
  signatureCache: const SongSignature(song: '测试歌'),
);

InMemoryVideoIndexStorage _seededIndex() => InMemoryVideoIndexStorage(
  initial: VideoIndex(entries: [_entry('hash-v1')]),
);

void main() {
  late Directory tempDir;
  late Directory videosDir;
  late Map<String, InMemoryMemberSchemeStorage> schemeStorages;
  late Map<String, InMemoryVideoDocumentStorage> documents;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('scheme_import_flow_test');
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
        // 源视频条目一律指向同一份夹具视频：真实解出才走得通建舞分支。
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

  /// 真实编排：内存 index/文档/方案存储 + 复制、哈希全真的视频管道。
  SchemeImporter importer({
    required VideoIndexStorage indexStore,
    Future<bool> Function(String videoId, SongSignature signature)? titleWriter,
  }) => SchemeImporter(
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
    titleWriter: titleWriter,
    now: () => DateTime(2026, 9, 15, 14, 5),
  );

  testWidgets('本机没有这支舞、包里没带熟练度：直接建舞写成我的，不弹任何面', (tester) async {
    final packageFile = (await tester.runAsync(
      () => writePackage(
        const SusumeManifest(
          videoId: 'sender-new',
          schemeName: '测试歌',
          schemeId: 'scheme-1',
          memberName: '小如改',
          media: [_sourceVideoEntry],
        ),
      ),
    ))!;
    final indexStore = _seededIndex();
    final harness = _Harness(
      indexStorage: indexStore,
      picked: _pickedFor(packageFile),
      documents: documents,
      importer: importer(
        indexStore: indexStore,
        titleWriter: (videoId, signature) async {
          await indexStore.update(
            (index) => index.setSignatureCacheByFilePath(
              index.findById(videoId)!.filePath,
              signature,
            ),
          );
          return true;
        },
      ),
    );
    await harness.pumpHome(tester);

    await openRestoreBackupFromHomeMenu(tester);
    await tester.runAsync(() async {
      await pollUntil(
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        onTick: () => tester.pump(),
        reason: '导入完成后应出声',
      );
    });

    // 不问归属、不问组员名：包收下即导入。
    expect(
      find.byKey(const Key('scheme_import_ownership_dialog')),
      findsNothing,
    );
    expect(find.byKey(const Key('scheme_import_create_dialog')), findsNothing);
    expect(find.byKey(const Key('scheme_import_dialog')), findsNothing);
    expect(find.text('14:05 已把 小如改 的标注写成我的，新建舞「测试歌」'), findsOneWidget);
    // 落盘：标注整份写入新建舞的 markers，不落组员方案。
    expect(documents['hash-v1']!.markersSnapshot, _markers);
    expect(schemeStorages, isEmpty);
  });

  testWidgets('本机已有这支舞：先问归属；「写成我的标注」整份写成我的', (tester) async {
    final packageFile = (await tester.runAsync(
      () => writePackage(
        const SusumeManifest(
          videoId: 'hash-v1',
          schemeName: '测试歌',
          schemeId: 'scheme-1',
          memberName: '小如改',
          media: [_sourceVideoEntry],
        ),
      ),
    ))!;
    final indexStore = _seededIndex();
    final harness = _Harness(
      indexStorage: indexStore,
      picked: _pickedFor(packageFile),
      documents: documents,
      importer: importer(indexStore: indexStore),
    );
    await harness.pumpHome(tester);

    await openRestoreBackupFromHomeMenu(tester);
    await _awaitDialog(tester, const Key('scheme_import_ownership_dialog'));

    expect(
      find.byKey(const Key('scheme_import_ownership_dialog')),
      findsOneWidget,
    );
    // 出口集合：两个归属出口加取消。
    expect(find.text('写成我的标注'), findsOneWidget);
    expect(find.text('留成TA的方案'), findsOneWidget);
    expect(
      find.byKey(const Key('scheme_import_ownership_cancel')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('scheme_import_write_as_mine')));
    await tester.pumpAndSettle();

    // 写成我的：不问组员名。
    expect(find.byKey(const Key('scheme_import_dialog')), findsNothing);
    expect(find.text('14:05 已把 小如改 的标注写成我的到「测试歌」'), findsOneWidget);
    // 落盘：markers 文档整份替换，不落组员方案。
    expect(documents['hash-v1']!.markersSnapshot, _markers);
    expect(schemeStorages, isEmpty);
  });

  testWidgets('本机已有这支舞：「留成TA的方案」之后才问组员名，发送方填过则预填', (tester) async {
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
    final indexStore = _seededIndex();
    final harness = _Harness(
      indexStorage: indexStore,
      picked: _pickedFor(packageFile),
      documents: documents,
      importer: importer(indexStore: indexStore),
    );
    await harness.pumpHome(tester);

    await openRestoreBackupFromHomeMenu(tester);
    await _awaitDialog(tester, const Key('scheme_import_ownership_dialog'));
    await tester.tap(find.byKey(const Key('scheme_import_keep_as_member')));
    await tester.pumpAndSettle();

    // 组员名对话框只在组员方案出口之后出现，且按发送方署名预填。
    expect(find.byKey(const Key('scheme_import_dialog')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('scheme_import_member_name_field')),
          )
          .controller!
          .text,
      '小如',
    );

    await tester.enterText(
      find.byKey(const Key('scheme_import_member_name_field')),
      '小如改',
    );
    await tester.tap(find.byKey(const Key('scheme_import_confirm')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('14:05 已导入 小如改 的方案到「测试歌」'), findsOneWidget);
    // 落盘：组员方案存储出现该 schemeId / 成员名的条目。
    final doc = await MemberSchemeStore(schemeStorages['hash-v1']!).read();
    expect(doc.schemes.single.schemeId, 'scheme-1');
    expect(doc.schemes.single.memberName, '小如改');
    expect(doc.schemes.single.schemeName, '测试歌');
    expect(doc.schemes.single.markers, _markers);
  });

  testWidgets('本机已有这支舞：取消即什么都不做，不进导入编排', (tester) async {
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
    final indexStore = _seededIndex();
    documents['hash-v1'] = InMemoryVideoDocumentStorage(
      markers: const {'version': 8},
    );
    final harness = _Harness(
      indexStorage: indexStore,
      picked: _pickedFor(packageFile),
      documents: documents,
      importer: importer(indexStore: indexStore),
    );
    await harness.pumpHome(tester);

    await openRestoreBackupFromHomeMenu(tester);
    await _awaitDialog(tester, const Key('scheme_import_ownership_dialog'));
    await tester.tap(find.byKey(const Key('scheme_import_ownership_cancel')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(schemeStorages, isEmpty);
    expect(documents['hash-v1']!.markersSnapshot, {'version': 8});
  });

  testWidgets('本机没有这支舞、包里带了熟练度：问归属；「建成我的标注方案」写明丢弃熟练度', (tester) async {
    final packageFile = (await tester.runAsync(
      () => writePackage(
        const SusumeManifest(
          videoId: 'sender-new',
          schemeName: '测试歌',
          schemeId: 'scheme-1',
          memberName: '小如',
          mastery: {0: 2},
          media: [_sourceVideoEntry],
        ),
      ),
    ))!;
    final indexStore = _seededIndex();
    final harness = _Harness(
      indexStorage: indexStore,
      picked: _pickedFor(packageFile),
      documents: documents,
      importer: importer(indexStore: indexStore),
    );
    await harness.pumpHome(tester);

    await openRestoreBackupFromHomeMenu(tester);
    await _awaitDialog(tester, const Key('scheme_import_create_dialog'));

    expect(
      find.byKey(const Key('scheme_import_create_dialog')),
      findsOneWidget,
    );
    expect(find.text('建成我的标注方案会丢弃这份熟练度快照。'), findsOneWidget);
    expect(find.text('建成组员方案'), findsOneWidget);

    await tester.tap(find.byKey(const Key('scheme_import_create_as_mine')));
    await tester.runAsync(() async {
      await pollUntil(
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        onTick: () => tester.pump(),
        reason: '建舞写成我的应完成并出声',
      );
    });

    // 建成我的：丢弃熟练度快照，也不问组员名。
    expect(find.byKey(const Key('scheme_import_dialog')), findsNothing);
    expect(documents['hash-v1']!.markersSnapshot, _markers);
    expect(schemeStorages, isEmpty, reason: '熟练度只随组员方案走：丢弃快照');
  });

  testWidgets('本机没有这支舞、包里带了熟练度：「建成组员方案」之后问组员名并新建舞', (tester) async {
    final packageFile = (await tester.runAsync(
      () => writePackage(
        const SusumeManifest(
          videoId: 'sender-new',
          schemeName: '测试歌',
          schemeId: 'scheme-1',
          memberName: '小如',
          mastery: {0: 2},
          media: [_sourceVideoEntry],
        ),
      ),
    ))!;
    final indexStore = _seededIndex();
    final harness = _Harness(
      indexStorage: indexStore,
      picked: _pickedFor(packageFile),
      documents: documents,
      importer: importer(
        indexStore: indexStore,
        titleWriter: (videoId, signature) async {
          await indexStore.update(
            (index) => index.setSignatureCacheByFilePath(
              index.findById(videoId)!.filePath,
              signature,
            ),
          );
          return true;
        },
      ),
    );
    await harness.pumpHome(tester);

    await openRestoreBackupFromHomeMenu(tester);
    await _awaitDialog(tester, const Key('scheme_import_create_dialog'));
    await tester.tap(find.byKey(const Key('scheme_import_create_as_member')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scheme_import_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('scheme_import_confirm')));
    await tester.runAsync(() async {
      await pollUntil(
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        onTick: () => tester.pump(),
        reason: '建成组员方案应完成并出声',
      );
    });

    expect(find.text('14:05 已导入 小如 的方案，新建舞「测试歌」'), findsOneWidget);
    // 落盘：组员方案挂带熟练度快照，成员名为对话框确认值。
    final doc = await MemberSchemeStore(schemeStorages['hash-v1']!).read();
    expect(doc.schemes.single.schemeId, 'scheme-1');
    expect(doc.schemes.single.memberName, '小如');
    expect(doc.schemes.single.mastery, {0: 2});
  });

  testWidgets('包里没带源视频：不弹任何面，明确拒绝并说清下一步', (tester) async {
    final packageFile = (await tester.runAsync(
      () => writePackage(
        const SusumeManifest(
          videoId: 'hash-v1',
          schemeName: '测试歌',
          schemeId: 'scheme-1',
          memberName: '小如',
        ),
      ),
    ))!;
    final indexStore = _seededIndex();
    final harness = _Harness(
      indexStorage: indexStore,
      picked: _pickedFor(packageFile),
      documents: documents,
      importer: importer(indexStore: indexStore),
    );
    await harness.pumpHome(tester);

    await openRestoreBackupFromHomeMenu(tester);
    await tester.runAsync(() async {
      await pollUntil(
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        onTick: () => tester.pump(),
        reason: '拒绝应出声',
      );
    });

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('这支舞的视频不在包里，请先导入视频'), findsOneWidget);
    expect(schemeStorages, isEmpty);
    expect(documents, isEmpty);
  });

  testWidgets('详情页 ⋯ 菜单：不再有选包项，其余项保持不变', (tester) async {
    final indexStore = _seededIndex();
    final harness = _Harness(
      indexStorage: indexStore,
      picked: _pickedFor(File('${tempDir.path}/unused.susume')),
      documents: documents,
      importer: importer(indexStore: indexStore),
    );
    await harness.pumpHome(tester);

    await tester.tap(find.byKey(const Key('dance_card_detail_hash-v1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dance_detail_more')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('dance_detail_import_scheme')),
      findsNothing,
      reason: '选包入口收敛到首页 ⋯，详情页不再有',
    );
    expect(find.text('分享'), findsOneWidget);
    expect(find.text('分享视频（mp4）'), findsOneWidget);
    expect(find.text('改名'), findsOneWidget);
    expect(find.text('换封面'), findsOneWidget);
    expect(find.text('删除这支舞'), findsOneWidget);
  });
}

class _Harness {
  _Harness({
    required this.indexStorage,
    required this.importer,
    required this.picked,
    required this.documents,
  });

  final InMemoryVideoIndexStorage indexStorage;
  final SchemeImporter importer;
  final PickedVideo picked;
  final Map<String, InMemoryVideoDocumentStorage> documents;

  final statsStorage = InMemoryPracticeStatsStorage();
  late final statsStore = PracticeStatsStore(statsStorage);
  final engine = FakePlaybackEngine();

  Future<void> pumpHome(WidgetTester tester) async {
    useNamedViewport(tester, ViewportTier.compact);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoIndexStoreProvider.overrideWithValue(indexStorage),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => documents[videoId] ?? InMemoryVideoDocumentStorage(),
          ),
          coverCacheProvider.overrideWith((ref) => InMemoryCoverCache()),
          practicePlanStorageProvider.overrideWithValue(
            InMemoryPracticePlanStorage(),
          ),
          practiceStatsStoreProvider.overrideWithValue(statsStore),
          fourBeatBucketStoreProvider.overrideWithValue(
            FourBeatBucketStore(InMemoryFourBeatBucketStorage()),
          ),
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
        ],
        child: const DanceLearningApp(),
      ),
    );
    await tester.pumpAndSettle();
  }
}
