import 'dart:async';

import 'package:dance_learning_app/annotation/compare_materials.dart'
    show MaterialRecord, PracticeClip;
import 'package:dance_learning_app/annotation/interval_fragment_row.dart'
    show IntervalEdge;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_edit.dart'
    show RemovePracticeClip;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationEditor,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        practiceClipsProvider;
import 'package:dance_learning_app/player/settings_persistence.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/video_index_fixtures.dart';

/// 撤销/重做按 id 作用域：外部写（录制入轨、
/// 素材连带删除）不进撤销史、也不被撤销/重做影响；断言模块公开面（截取
/// 提交 / 撤销 / 重做 / 具名入口）与最终表、落盘结果。
void main() {
  const total = Duration(minutes: 1);
  const pathA = '/videos/a.mp4';
  const idA = 'vid-a';

  // 片段源区间 8s–20s：素材源起点 8000，截取范围素材内 0–12000，素材全长
  // 20000（与 practice_clip_trim_test 同一口径，吸附落点可预期）。
  const c1 = PracticeClip(
    id: 'c1',
    materialId: 'm1',
    materialSourceStartMs: 8000,
    inMs: 0,
    outMs: 12000,
    materialDurationMs: 20000,
  );
  const c2 = PracticeClip(
    id: 'c2',
    materialId: 'm2',
    materialSourceStartMs: 40000,
    inMs: 0,
    outMs: 12000,
    materialDurationMs: 20000,
  );

  // 录制产出素材：源起点 60000（与既有片段零重叠——入轨清理不波及 c1），
  // 全长 20000 → 入轨片段 clip_mX 源区间 60000–80000。
  MaterialRecord material(String id) => MaterialRecord(
    id: id,
    videoId: idA,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    durationMs: 20000,
    sourceStartMs: 60000,
    fileName: '$id.mp4',
    sizeBytes: 100,
  );

  late ProviderContainer container;
  late FakePlaybackEngine engine;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    final index = InMemoryVideoIndexStorage(
      initial: VideoIndex(
        entries: [historyEntry(filePath: pathA, mirrored: false, videoId: idA)],
      ),
    );
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        videoIndexStoreProvider.overrideWithValue(index),
        videoDocumentStorageProvider(idA)
            .overrideWithValue(InMemoryVideoDocumentStorage(local: const {})),
        materialManifestStorageProvider.overrideWithValue(
          MemoryManifestStorage(),
        ),
      ],
    );
    // 就绪均匀网格：八拍点 = 0/4/8…s（截取吸附口径）。
    container
        .read(beatTrackStateProvider.notifier)
        .replace(uniformReadyBeatState(seconds: 60));
  });

  tearDown(() => container.dispose());

  AnnotationEditor editor() => container.read(annotationEditorProvider);
  List<PracticeClip> clips() => container.read(practiceClipsProvider);
  int historyLength() => container.read(annotationEditHistoryProvider).length;

  /// 一次截取拖动：c1 尾端点拖到请求 25s → 吸 24s → 素材内 out = 16000。
  void trimC1Tail() {
    final session = editor().beginPracticeClipTrimDrag(0, IntervalEdge.end);
    expect(session.moveTo(const Duration(seconds: 25)), Duration(seconds: 24));
    session.end();
    expect(clips()[0].id, 'c1');
    expect(clips()[0].outMs, 16000);
    expect(historyLength(), 1);
  }

  group('外部写不进史、撤销不抢外部写（红灯对）', () {
    test('录制入轨后撤销更早的截取：新录片段仍在、表长不变、盘上一致', () async {
      final persistence = VideoSettingsPersistence(container);
      unawaited(persistence.startForVideo(idA));
      await persistence.started;
      container.read(practiceClipsProvider.notifier).restore(const [c1]);

      trimC1Tail();
      container
          .read(practiceClipsProvider.notifier)
          .addFromMaterial(material('m2'));
      // 外部写不产生历史条目。
      expect(historyLength(), 1);
      expect(clips(), hasLength(2));

      container.read(annotationEditorProvider).undo();

      // 新录片段仍在、表长不变；被截的那条回到截取前范围。
      expect(clips(), hasLength(2));
      expect(clips()[0].id, 'c1');
      expect(clips()[0].outMs, 12000);
      expect(clips()[1].id, 'clip_m2');

      // 落盘与会话表一致。
      await persistence.flush;
      final doc = await container
          .read(videoDocumentCoordinatorProvider(idA))
          .readLocal();
      expect(
        [for (final clip in doc.practiceClips) clip.id],
        ['c1', 'clip_m2'],
      );
    });

    test('片段被素材连带删除后撤销更早的截取：被删片段不复活', () {
      container.read(practiceClipsProvider.notifier).restore(const [c1, c2]);

      trimC1Tail();
      container.read(practiceClipsProvider.notifier).removeByMaterial('m2');
      // 外部写不产生历史条目。
      expect(historyLength(), 1);
      expect(clips(), hasLength(1));
      expect(clips().single.id, 'c1');
      expect(clips().single.outMs, 16000);

      editor().undo();

      // 被删片段不复活；只有被截的那条回退。
      expect(clips().single.id, 'c1');
      expect(clips().single.outMs, 12000);
      expect(historyLength(), 0);
    });
  });

  group('重做方向同样按 id 作用域（对称）', () {
    test('重做正常路径：被截的那条回到截取后范围', () {
      container.read(practiceClipsProvider.notifier).restore(const [c1]);

      trimC1Tail();
      editor().undo();
      expect(clips().single.outMs, 12000);

      editor().redo();

      expect(clips().single.id, 'c1');
      expect(clips().single.outMs, 16000);
    });

    test('截取后被外部删除，撤销同样不复活（与重做对称）', () {
      container.read(practiceClipsProvider.notifier).restore(const [c1]);

      trimC1Tail();
      container.read(practiceClipsProvider.notifier).removeByMaterial('m1');
      expect(clips(), isEmpty);

      editor().undo();

      expect(clips(), isEmpty, reason: '被删片段不复活');
    });

    test('截取后被外部删除，重做不复活', () {
      container.read(practiceClipsProvider.notifier).restore(const [c1]);

      trimC1Tail();
      editor().undo();
      container.read(practiceClipsProvider.notifier).removeByMaterial('m1');
      expect(
        container.read(annotationEditHistoryProvider).canRedo,
        isTrue,
        reason: '外部写不产生历史条目（可重做条目仍是那一次截取）',
      );

      editor().redo();

      expect(clips(), isEmpty, reason: '被删片段不复活');
      expect(
        container.read(annotationEditHistoryProvider).canRedo,
        isFalse,
        reason: '游标照走',
      );
    });
  });

  group('回放写后表恒升序', () {
    // c0 比 c1 更早（源起点 0–8s）：删除撤销的复活分支把它追加在表尾，
    // 回放写把它排回升序。
    const c0 = PracticeClip(
      id: 'c0',
      materialId: 'm0',
      materialSourceStartMs: 0,
      inMs: 0,
      outMs: 8000,
      materialDurationMs: 8000,
    );

    test('删除撤销（复活）：表按源起点升序', () {
      container.read(practiceClipsProvider.notifier).restore(const [c0, c1]);
      editor().submit(RemovePracticeClip(clipId: 'c0'));
      expect(clips().map((c) => c.id), ['c1']);

      editor().undo();

      expect(clips().map((c) => c.id), ['c0', 'c1']);
    });
  });
}
