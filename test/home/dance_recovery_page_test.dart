import 'dart:io';

import 'package:dance_learning_app/core/video_identity.dart';
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:dance_learning_app/dance/dance_library.dart';
import 'package:dance_learning_app/dance/video_copy_presence.dart';
import 'package:dance_learning_app/home/dance_open.dart';
import 'package:dance_learning_app/import/import_providers.dart'
    show
        contentHasherProvider,
        importVideosDirectoryProvider,
        videoIndexStoreProvider,
        videoPickerProvider;
import 'package:dance_learning_app/import/picked_video.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_providers.dart'
    show fourBeatBucketStoreProvider;
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart'
    show practicePlanStorageProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/dance_snapshot_fixture.dart';
import '../helpers/fake_video_copy_presence.dart';
import '../helpers/fake_video_picker.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_member_scheme_storage.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/poll.dart';
import '../helpers/recording_hasher.dart';

/// 找回面部件测试：副本丢失的舞点开进的是找回面（不是播放页），面上给
/// 「选择视频文件」「删除这支舞」「暂不找回」三条出路；「选择视频文件」核对
/// **视频标识**——相符把副本放回条目记录的原路径，不符明确告知并给
/// 「按新视频另建一支」/「取消」，失败出声、状态不变。
void main() {
  testWidgets('打开一支副本丢失的舞：进的是找回面，不是播放页', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);
    await tester.tap(find.byKey(const Key('host_open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dance_recovery_page')), findsOneWidget);
    // 标题与卡片同读一处（未署名回退文件名回落名）。
    expect(find.widgetWithText(AppBar, 'v1'), findsOneWidget);
    expect(find.text('视频副本丢失'), findsOneWidget);
    // 三条出路都在场。
    expect(find.byKey(const Key('dance_recovery_pick')), findsOneWidget);
    expect(find.text('选择视频文件'), findsOneWidget);
    expect(find.byKey(const Key('dance_recovery_delete')), findsOneWidget);
    expect(find.byKey(const Key('dance_recovery_later')), findsOneWidget);
  });

  testWidgets('「暂不找回」：原样离开，索引与文档一个字节不动', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);
    await tester.tap(find.byKey(const Key('host_open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dance_recovery_later')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dance_recovery_page')), findsNothing);
    expect(harness.indexStorage.updateCount, 0);
    expect(harness.indexStorage.current.entries, hasLength(1));
    expect(await harness.documents['v1']!.loadMarkersOrNull(), isNotNull);
  });

  testWidgets('「删除这支舞」：二次确认后照常成立——条目与文档删净，页面退掉', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);
    await tester.tap(find.byKey(const Key('host_open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dance_recovery_delete')));
    await tester.pumpAndSettle();
    // 与详情页同一处二次确认：默认不删。
    expect(find.byKey(const Key('dance_delete_dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dance_delete_confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dance_recovery_page')), findsNothing);
    // 副本本来就不在：删除照常成立（索引条目与两份文档都清掉）。
    expect(harness.indexStorage.current.entries, isEmpty);
    expect(await harness.documents['v1']!.loadMarkersOrNull(), isNull);
  });

  testWidgets('「选择视频文件」+ 标识相符：副本放回原路径，退出找回面，标注原地可读', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);
    await tester.tap(find.byKey(const Key('host_open')));
    await tester.pumpAndSettle();

    // 复制是真实文件 IO：在真实事件循环里完成。
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('dance_recovery_pick')));
      await pollUntil(
        () => File(harness.entryFilePath).existsSync(),
        onTick: () => tester.pump(),
        reason: '找回应把副本复制回条目记录的原路径',
      );
    });
    await tester.pumpAndSettle();

    expect(File(harness.entryFilePath).readAsBytesSync(), [1, 2, 3]);
    expect(
      find.byKey(const Key('dance_recovery_page')),
      findsNothing,
      reason: '修好即退出找回面（卡片随读面作废不再标丢失）',
    );

    final entry = harness.indexStorage.current.entries.single;
    expect(entry.videoId, 'v1', reason: '身份不动');
    expect(entry.filePath, harness.entryFilePath, reason: '路径不动');
    expect(entry.sizeBytes, 3, reason: '大小不动');
    expect(entry.displayName, 'v1-new-name.mp4', reason: '显示名随这次选中的文件名刷新');
    expect(entry.fastKey, fastKeyFor(name: 'v1-new-name.mp4', sizeBytes: 3));
    // 标注按同一 videoId 原地生效（文档键随身份，不随文件名）；封面缓存
    // 不动——标识相符即内容相同，按身份命名的缓存仍然正确。
    expect(await harness.documents['v1']!.loadMarkersOrNull(), isNotNull);
    expect(harness.coverCache.ready, contains('v1'));
    expect(harness.recording.hashedPaths, [harness.selectedFile.path]);
  });

  testWidgets('「选择视频文件」+ 标识不符：告知「这不是这支视频」，取消即留在原处且零副作用', (tester) async {
    final harness = _Harness(hasherValue: 'another-dance');
    await harness.pump(tester);
    await tester.tap(find.byKey(const Key('host_open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dance_recovery_pick')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('dance_recovery_mismatch_dialog')),
      findsOneWidget,
    );
    expect(find.text('这不是这支视频'), findsOneWidget);
    expect(find.byKey(const Key('dance_recovery_create_new')), findsOneWidget);
    expect(
      find.byKey(const Key('dance_recovery_mismatch_cancel')),
      findsOneWidget,
    );
    expect(File(harness.entryFilePath).existsSync(), isFalse, reason: '不符不接上');
    expect(harness.indexStorage.updateCount, 0, reason: '不符不落索引');

    await tester.tap(find.byKey(const Key('dance_recovery_mismatch_cancel')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('dance_recovery_mismatch_dialog')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('dance_recovery_page')),
      findsOneWidget,
      reason: '取消：留在找回面，这支舞保持丢失',
    );
    expect(harness.indexStorage.current.entries.single.displayName, 'v1.mp4');
  });

  testWidgets('「按新视频另建一支」：复用导入管道另建条目与副本，旧舞保持丢失', (tester) async {
    final harness = _Harness(hasherValue: 'another-dance');
    await harness.pump(tester);
    await tester.tap(find.byKey(const Key('host_open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dance_recovery_pick')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('dance_recovery_mismatch_dialog')),
      findsOneWidget,
    );

    // 建舞分支要走真实的复制与哈希：在真实事件循环里完成。
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('dance_recovery_create_new')));
      await pollUntil(
        () => harness.indexStorage.current.entries.length == 2,
        onTick: () => tester.pump(),
        reason: '按新视频另建一支：另落一条条目',
      );
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dance_recovery_page')), findsNothing);
    final entries = harness.indexStorage.current.entries;
    final old = entries.firstWhere((e) => e.videoId == 'v1');
    expect(old.filePath, harness.entryFilePath, reason: '旧舞路径不动');
    expect(
      File(old.filePath).existsSync(),
      isFalse,
      reason: '旧舞保持丢失（另建一支不接上它）',
    );
    final created = entries.firstWhere((e) => e.videoId == 'another-dance');
    expect(created.displayName, 'v1-new-name.mp4');
    expect(
      File(created.filePath).existsSync(),
      isTrue,
      reason: '新条目自己的副本已复制进私有目录',
    );
    // 总读取次数不增加：核对选中文件时已算出标识，另建一支直接拿它落条目
    // （[VideoIsNotThisDance.videoId] 一路带到建舞分支），刚复制的副本不再
    // 整读第二遍。
    expect(harness.recording.hashedPaths, [
      harness.selectedFile.path,
    ], reason: '核对读一遍源文件；另建一支不重读副本');
    expect(
      harness.recording.hashedPaths,
      isNot(contains(created.filePath)),
      reason: '新副本路径从未被摘要读过',
    );
  });

  testWidgets('「选择视频文件」+ 选择器取消：零副作用，留在找回面', (tester) async {
    final harness = _Harness(cancelled: true);
    await harness.pump(tester);
    await tester.tap(find.byKey(const Key('host_open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dance_recovery_pick')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dance_recovery_page')), findsOneWidget);
    expect(
      find.byKey(const Key('dance_recovery_mismatch_dialog')),
      findsNothing,
    );
    expect(harness.indexStorage.updateCount, 0);
    expect(File(harness.entryFilePath).existsSync(), isFalse);
  });

  testWidgets('核对失败：出声「找回失败」，状态不变并留在找回面', (tester) async {
    final harness = _Harness(hasherThrows: true);
    await harness.pump(tester);
    await tester.tap(find.byKey(const Key('host_open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dance_recovery_pick')));
    await tester.pumpAndSettle();

    expect(find.text('找回失败'), findsOneWidget);
    expect(find.byKey(const Key('dance_recovery_page')), findsOneWidget);
    expect(harness.indexStorage.updateCount, 0);
    expect(harness.indexStorage.current.entries.single.displayName, 'v1.mp4');
    expect(File(harness.entryFilePath).existsSync(), isFalse);
  });
}

/// 宿主：一枚按钮走打开一支舞的唯一入口（[openDance]），找回面从它压栈，
/// 退出即回到这里。
class _Host extends StatelessWidget {
  const _Host({required this.dance});

  final DanceSnapshot dance;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Builder(
        builder: (context) => TextButton(
          key: const Key('host_open'),
          onPressed: () => openDance(context, dance),
          child: const Text('打开这支舞'),
        ),
      ),
    ),
  );
}

/// 算标识即失败的假哈希（界面上「找回失败」那一声的来源）。
class _ThrowingHasher implements ContentHasher {
  @override
  Future<String> hashFile(File file) async =>
      throw const FileSystemException('读取失败');
}

class _Harness {
  _Harness({
    this.hasherValue = 'v1',
    this.cancelled = false,
    this.hasherThrows = false,
  }) {
    // 临时目录用同步创建：用例体内的真实异步文件 IO 在
    // flutter_test 的 fake async 时钟下不可完成（与 `dance_delete_flow_test`
    // 同款先例）。
    root = Directory.systemTemp.createTempSync('recovery_page');
    materialsDir = Directory(p.join(root.path, 'materials'));
    videosDir = Directory(p.join(root.path, 'videos'));
    // 条目记录的原路径（父目录起初不存在 = 副本丢失）。
    entryFilePath = p.join(root.path, 'original', 'v1.mp4');
    selectedFile = File(p.join(root.path, 'picked', 'v1-new-name.mp4'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(
        entries: [_entry('v1', filePath: entryFilePath, sizeBytes: 3)],
      ),
    );
    picker = FakeVideoPicker(
      cancelled
          ? null
          : PickedVideo(
              name: 'v1-new-name.mp4',
              sourceUri: selectedFile.uri,
              sizeBytes: 3,
            ),
    );
    recording = RecordingHasher(hasherValue);
    hasher = hasherThrows ? _ThrowingHasher() : recording;
    documents = {
      'v1': InMemoryVideoDocumentStorage(
        markers: const MarkersDocument(rangeEndMs: 120000).toJson(),
      ),
    };
    // 封面缓存按身份命名：这一版先把它喂成「已就绪」，找回后照旧。
    coverCache = InMemoryCoverCache(ready: {'v1'});
    bucketStore = FourBeatBucketStore(InMemoryFourBeatBucketStorage());
    planStorage = InMemoryPracticePlanStorage();
    manifestStorage = MemoryManifestStorage();
    dance = danceSnapshotFixture(
      videoId: 'v1',
      displayName: 'v1.mp4',
      lastOpenedAt: DateTime(2026, 9, 1),
      copyMissing: true,
      filePath: entryFilePath,
      sizeBytes: 3,
    );
  }

  final String hasherValue;
  final bool cancelled;
  final bool hasherThrows;

  late final InMemoryVideoIndexStorage indexStorage;
  late final Map<String, InMemoryVideoDocumentStorage> documents;
  late final InMemoryCoverCache coverCache;
  late final FourBeatBucketStore bucketStore;
  late final InMemoryPracticePlanStorage planStorage;
  late final MemoryManifestStorage manifestStorage;
  late final Directory root;
  late final Directory materialsDir;
  late final Directory videosDir;
  late final String entryFilePath;
  late final File selectedFile;
  late final FakeVideoPicker picker;
  late final RecordingHasher recording;
  late final ContentHasher hasher;
  late final DanceSnapshot dance;

  Future<void> pump(WidgetTester tester) async {
    addTearDown(() => root.deleteSync(recursive: true));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoIndexStoreProvider.overrideWithValue(indexStorage),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => documents[videoId] ?? InMemoryVideoDocumentStorage(),
          ),
          coverCacheProvider.overrideWith((ref) => coverCache),
          fourBeatBucketStoreProvider.overrideWithValue(bucketStore),
          materialsBaseDirectoryProvider.overrideWithValue(
            () async => materialsDir,
          ),
          materialManifestStorageProvider.overrideWithValue(manifestStorage),
          memberSchemeStorageProvider.overrideWith(
            (ref, videoId) => InMemoryMemberSchemeStorage(),
          ),
          practicePlanStorageProvider.overrideWithValue(planStorage),
          videoPickerProvider.overrideWithValue(picker),
          contentHasherProvider.overrideWithValue(hasher),
          importVideosDirectoryProvider.overrideWith((ref) async => videosDir),
          videoCopyPresenceProvider.overrideWithValue(
            FakeVideoCopyPresence(missingPaths: {entryFilePath}),
          ),
        ],
        child: MaterialApp(home: _Host(dance: dance)),
      ),
    );
    await tester.pumpAndSettle();
  }
}

VideoIndexEntry _entry(
  String videoId, {
  String? filePath,
  int sizeBytes = 1,
  String displayName = 'v1.mp4',
}) => VideoIndexEntry(
  videoId: videoId,
  displayName: displayName,
  filePath: filePath ?? '/videos/$videoId.mp4',
  sizeBytes: sizeBytes,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);
