import 'dart:io';

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/dance/dance_library.dart';
import 'package:dance_learning_app/dance/dance_library_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/player/material_library.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show practiceClipsProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/memory_manifest_storage.dart';

void main() {
  group('练习素材库删除：持久化侧连带清空', () {
    late Directory tempDir;
    late MemoryManifestStorage manifestStorage;
    late MaterialRecord record;
    late File materialFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('material_library_test');
      manifestStorage = MemoryManifestStorage();
      record = MaterialRecord(
        id: 'mat_a',
        videoId: 'vid1',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        durationMs: 8000,
        sourceStartMs: 10000,
        fileName: 'rec_1.mp4',
        sizeBytes: 42,
      );
      // 素材文件真实存在（断言删除后消失）。
      materialFile = File(p.join(tempDir.path, record.videoId, record.fileName))
        ..createSync(recursive: true);
      materialFile.writeAsStringSync('video-bytes');
    });

    tearDown(() async => tempDir.delete(recursive: true));

    test('remove：素材文件删除 + 清单条目删除 + 轨道引用连带删除（两边都空）', () async {
      final container = ProviderContainer(
        overrides: [
          materialsBaseDirectoryProvider.overrideWithValue(() async => tempDir),
          materialManifestStorageProvider.overrideWithValue(manifestStorage),
        ],
      );
      addTearDown(container.dispose);

      await container.read(materialManifestStoreProvider).append(record);
      container.read(practiceClipsProvider.notifier).state = [
        const PracticeClip(
          id: 'clip_a',
          materialId: 'mat_a',
          materialSourceStartMs: 10000,
          inMs: 0,
          outMs: 8000,
        ),
        const PracticeClip(
          id: 'clip_b',
          materialId: 'mat_b',
          materialSourceStartMs: 0,
          inMs: 0,
          outMs: 4000,
        ),
      ];
      container.read(materialLibraryProvider.notifier).state = [record];

      await container.read(materialLibraryProvider.notifier).remove(record);

      // 文件没了。
      expect(materialFile.existsSync(), isFalse);
      // 清单条目没了。
      final manifest = await MaterialManifestStore(manifestStorage).read();
      expect(manifest.materials, isEmpty);
      // 会话库列表空了。
      expect(container.read(materialLibraryProvider), isEmpty);
      // 轨道上引用该素材的片段连带删除，其余片段保留。
      final clips = container.read(practiceClipsProvider);
      expect(clips.map((c) => c.id), ['clip_b']);
    });

    test('openFor：先清上一舞残留——videoId 为 null 呈空态、非空才装载', () async {
      final container = ProviderContainer(
        overrides: [
          materialsBaseDirectoryProvider.overrideWithValue(() async => tempDir),
          materialManifestStorageProvider.overrideWithValue(manifestStorage),
        ],
      );
      addTearDown(container.dispose);

      final library = container.read(materialLibraryProvider.notifier);
      library.state = [record];

      // videoId 未解析：残留列表清空，呈现空态。
      await library.openFor(null);
      expect(container.read(materialLibraryProvider), isEmpty);

      // 清单有该舞素材：装载进会话列表。
      await MaterialManifestStore(manifestStorage).append(record);
      await library.openFor(record.videoId);
      expect(container.read(materialLibraryProvider), [record]);
    });
  });

  group('素材库「发给小组」入口', () {
    late Directory tempDir;
    late MemoryManifestStorage manifestStorage;
    late MaterialRecord record;
    late File materialFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('material_send_test');
      manifestStorage = MemoryManifestStorage();
      record = MaterialRecord(
        id: 'mat_a',
        videoId: 'vid1',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        durationMs: 8000,
        sourceStartMs: 10000,
        fileName: 'rec_1.mp4',
        sizeBytes: 42,
      );
      materialFile = File(p.join(tempDir.path, record.videoId, record.fileName))
        ..createSync(recursive: true);
      materialFile.writeAsStringSync('video-bytes');
    });

    tearDown(() async => tempDir.delete(recursive: true));

    DanceSnapshot snapshot() => composeDanceSnapshot(
      entry: VideoIndexEntry(
        videoId: 'vid1',
        displayName: 'dance_vid1.mp4',
        filePath: '${tempDir.path}/source.mp4',
        sizeBytes: 64,
        fastKey: 'k',
        mirrored: false,
        lastOpenedAt: DateTime(2026, 9, 1),
      ),
      importOrder: 0,
      markers: MarkersDocument(
        rangeEndMs: 24000,
        segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
        signature: const SongSignature(song: '海草舞'),
      ),
      local: const LocalDocument(mastery: {0: LearningMastery.mastered}),
      practice: const DancePracticeTotals(),
    );

    Checkbox checkboxOf(WidgetTester tester, String key) =>
        tester.widget<Checkbox>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(Checkbox),
          ),
        );

    testWidgets('每行「发给小组」可达；点开分享面初始勾选：熟练度与该条录像勾、源视频不勾', (tester) async {
      await MaterialManifestStore(manifestStorage).append(record);
      // 第二条素材：验证「每一行」都有入口且可达，而非只有首行。
      final record2 = MaterialRecord(
        id: 'mat_b',
        videoId: 'vid1',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000001000),
        durationMs: 4000,
        sourceStartMs: 20000,
        fileName: 'rec_2.mp4',
        sizeBytes: 21,
      );
      await MaterialManifestStore(manifestStorage).append(record2);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            materialsBaseDirectoryProvider.overrideWithValue(
              () async => tempDir,
            ),
            materialManifestStorageProvider.overrideWithValue(manifestStorage),
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (_) => InMemoryVideoDocumentStorage(
                markers: MarkersDocument(
                  rangeEndMs: 24000,
                  segmentLines: const [
                    SegmentLine(position: Duration(seconds: 8)),
                  ],
                ).toJson(),
              ),
            ),
            danceSnapshotProvider.overrideWith((ref, videoId) => snapshot()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: _SetCurrentVideoId(
                videoId: record.videoId,
                child: const MaterialLibraryPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 入口可达：每一行操作区里「发给小组」在删除钮旁。
      expect(find.byKey(const Key('material_library_send_0')), findsOneWidget);
      expect(find.byKey(const Key('material_library_send_1')), findsOneWidget);

      // 第二行的入口也点得到，且初始勾选针对那一行的录像。
      await tester.tap(find.byKey(const Key('material_library_send_1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('share_sheet')), findsOneWidget);
      expect(checkboxOf(tester, 'share_sheet_source_video').value, isFalse);
      expect(checkboxOf(tester, 'share_sheet_mastery').value, isTrue);
      expect(checkboxOf(tester, 'share_sheet_clips_mat_b').value, isTrue);
      expect(checkboxOf(tester, 'share_sheet_clips_mat_a').value, isFalse);
    });
  });
}

/// 先写当前舞 videoId 再构建素材库子页：子页首帧后的装载回调读到该值。
class _SetCurrentVideoId extends ConsumerStatefulWidget {
  const _SetCurrentVideoId({required this.videoId, required this.child});

  final String videoId;
  final Widget child;

  @override
  ConsumerState<_SetCurrentVideoId> createState() => _SetCurrentVideoIdState();
}

class _SetCurrentVideoIdState extends ConsumerState<_SetCurrentVideoId> {
  @override
  void initState() {
    super.initState();
    // 首帧后写入：不在 widget 生命周期内改 provider；本回调注册早于素材
    // 库子页的装载回调，子页读到的已是该值。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(currentVideoIdProvider.notifier).set(widget.videoId);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
