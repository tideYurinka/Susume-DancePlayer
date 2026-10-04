import 'dart:io';

import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:dance_learning_app/dance/dance_library.dart';
import 'package:dance_learning_app/dance/video_copy_presence.dart';
import 'package:dance_learning_app/home/dance_open.dart';
import 'package:dance_learning_app/import/import_providers.dart'
    show videoIndexStoreProvider;
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

import '../helpers/dance_snapshot_fixture.dart';
import '../helpers/fake_video_copy_presence.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_member_scheme_storage.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';

/// 找回面部件测试：副本丢失的舞点开进的是找回面（不是播放页），面上给
/// 「删除这支舞」「暂不找回」两条出路；删除照常成立（副本已不在是空操作）。
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
    // 两条出路都在场。
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

class _Harness {
  _Harness() {
    // 临时目录用同步创建：用例体内的真实异步文件 IO 在
    // flutter_test 的 fake async 时钟下不可完成（与 `dance_delete_flow_test`
    // 同款先例）。
    materialsDir = Directory.systemTemp.createTempSync('recovery_page');
    indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [_entry('v1')]),
    );
    documents = {
      'v1': InMemoryVideoDocumentStorage(
        markers: const MarkersDocument(rangeEndMs: 120000).toJson(),
      ),
    };
    coverCache = InMemoryCoverCache();
    bucketStore = FourBeatBucketStore(InMemoryFourBeatBucketStorage());
    planStorage = InMemoryPracticePlanStorage();
    manifestStorage = MemoryManifestStorage();
    dance = danceSnapshotFixture(
      videoId: 'v1',
      displayName: 'v1.mp4',
      lastOpenedAt: DateTime(2026, 9, 1),
      copyMissing: true,
    );
  }

  late final InMemoryVideoIndexStorage indexStorage;
  late final Map<String, InMemoryVideoDocumentStorage> documents;
  late final InMemoryCoverCache coverCache;
  late final FourBeatBucketStore bucketStore;
  late final InMemoryPracticePlanStorage planStorage;
  late final MemoryManifestStorage manifestStorage;
  late final Directory materialsDir;
  late final DanceSnapshot dance;

  Future<void> pump(WidgetTester tester) async {
    addTearDown(() => materialsDir.deleteSync(recursive: true));
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
          videoCopyPresenceProvider.overrideWithValue(
            FakeVideoCopyPresence(missingPaths: const {'/videos/v1.mp4'}),
          ),
        ],
        child: MaterialApp(home: _Host(dance: dance)),
      ),
    );
    await tester.pumpAndSettle();
  }
}

VideoIndexEntry _entry(String videoId) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);
