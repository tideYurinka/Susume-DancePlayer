import 'dart:io';

import 'package:dance_learning_app/annotation/compare_materials.dart'
    show MaterialRecord, PracticeClip;
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/annotation_edit.dart'
    show EditApplied, RemovePracticeClip;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationEditor,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        practiceClipActivationProvider,
        practiceClipsProvider,
        practiceOnscreenFaceProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/practice_clip_playback.dart'
    show practiceClipEngineProvider;
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show SurfaceFace;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/android_camera_platform.dart';
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/video_index_fixtures.dart';

/// 删除即退出回看：三条删除路径（verb 删除 /
/// 素材连带删除 / 回放移除）在同一次写里清激活——表里没有的片段不能还在
/// 回看（写后不变量，悬空激活不可表达）；练习半区回落实时预览；素材被删
/// 后练习侧引擎停播，不再循环已删文件。
void main() {
  // 片段源区间 8s–20s（与 practice_clip_trim_test 同一口径）。
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

  group('三条删除路径清激活 + 练习半区回落（模块公开面 + 容器）', () {
    late ProviderContainer container;
    late FakePlaybackEngine engine;
    late RecordingSaveSink sink;

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      sink = RecordingSaveSink();
      container = ProviderContainer(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          annotationSaveSinkProvider.overrideWithValue(sink),
        ],
      );
      container
          .read(practiceClipsProvider.notifier)
          .restore(const [c1, c2]);
      container.read(practiceClipActivationProvider.notifier).toggle(c1);
    });

    tearDown(() => container.dispose());

    AnnotationEditor editorOf() => container.read(annotationEditorProvider);
    List<PracticeClip> clips() => container.read(practiceClipsProvider);
    expectFallbackToPreview() {
      expect(container.read(practiceClipActivationProvider), isNull);
      expect(
        container.read(practiceOnscreenFaceProvider),
        SurfaceFace.cameraPreview,
        reason: '练习半区回落实时预览',
      );
    }

    test('verb 删除激活中的片段：激活被清、回落实时预览', () {
      final outcome = editorOf().submit(RemovePracticeClip(clipId: 'c1'));
      expect(outcome, isA<EditApplied>());
      expect(clips().map((c) => c.id), ['c2']);
      expectFallbackToPreview();
    });

    test('素材连带删除激活中的片段：激活被清、回落实时预览', () {
      container.read(practiceClipsProvider.notifier).removeByMaterial('m1');
      expect(clips().map((c) => c.id), ['c2']);
      expectFallbackToPreview();
    });

    test('回放移除（撤销/重做回放删掉激活中的片段）：激活被清、回落实时预览', () {
      // 历史里记一次删除 → 撤销放回 c1 → 重新激活 c1 → 重做经回放移除 c1。
      editorOf().submit(RemovePracticeClip(clipId: 'c1'));
      editorOf().undo();
      expect(clips().map((c) => c.id), ['c1', 'c2']);
      container.read(practiceClipActivationProvider.notifier).toggle(c1);
      expect(container.read(practiceClipActivationProvider), isNotNull);

      editorOf().redo();

      expect(clips().map((c) => c.id), ['c2']);
      expectFallbackToPreview();
    });
  });

  group('素材被删后练习侧引擎停播（练习侧引擎替身）', () {
    late FakePlaybackEngine engine;
    late FakePlaybackEngine practiceEngine;
    late FakeCameraCaptureService camera;
    late FakeSystemUi systemUi;
    late MemoryManifestStorage manifestStorage;

    final clip = PracticeClip(
      id: 'clip_m1',
      materialId: 'm1',
      materialSourceStartMs: 0,
      inMs: 10000,
      outMs: 20000,
    );
    final material = MaterialRecord(
      id: 'm1',
      videoId: 'vid-a',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      durationMs: 20000,
      sourceStartMs: 10000,
      fileName: 'rec_m1.mp4',
      sizeBytes: 1,
    );

    Future<ProviderContainer> pumpPlayer(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final source = Uri.file('/videos/a.mp4');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            practiceClipEngineProvider.overrideWithValue(practiceEngine),
            cameraCaptureProvider.overrideWithValue(camera),
            androidCameraPlatform(),
            privateJsonStorageProvider.overrideWithValue(
              InMemoryPrivateJsonStorage(),
            ),
            materialManifestStoreProvider.overrideWithValue(
              MaterialManifestStore(manifestStorage),
            ),
            materialsBaseDirectoryProvider.overrideWithValue(
              () async => Directory('/tmp/materials'),
            ),
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => InMemoryVideoDocumentStorage(),
            ),
            systemUiControllerProvider.overrideWithValue(systemUi),
            videoIndexStoreProvider.overrideWithValue(
              InMemoryVideoIndexStorage(
                initial: VideoIndex(
                  entries: [
                    historyEntry(
                      filePath: source.toFilePath(),
                      mirrored: false,
                      videoId: 'vid-a',
                    ),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(home: PlayerPage(source: source)),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
    }

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(seconds: 60));
      practiceEngine = FakePlaybackEngine(
        duration: const Duration(seconds: 20),
      );
      camera = FakeCameraCaptureService();
      systemUi = FakeSystemUi();
      manifestStorage = MemoryManifestStorage();
    });

    testWidgets('删素材：练习侧当场停播，不再循环已删文件', (tester) async {
      await MaterialManifestStore(manifestStorage).append(material);
      final container = await pumpPlayer(tester);
      container.read(practiceClipsProvider.notifier).restore([clip]);

      container.read(practiceClipActivationProvider.notifier).toggle(clip);
      await tester.pumpAndSettle();

      expect(practiceEngine.source, isNotNull, reason: '前置：回看已就位');
      expect(practiceEngine.isPlaying, isTrue, reason: '前置：回看播放中');

      container.read(practiceClipsProvider.notifier).removeByMaterial('m1');
      await tester.pumpAndSettle();

      expect(container.read(practiceClipActivationProvider), isNull);
      expect(
        container.read(practiceOnscreenFaceProvider),
        SurfaceFace.cameraPreview,
        reason: '练习半区回落实时预览',
      );
      expect(practiceEngine.isPlaying, isFalse, reason: '练习侧引擎停播');

      final frozen = practiceEngine.position;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(
        practiceEngine.position,
        frozen,
        reason: '不再循环已删文件：停播后位置不推进',
      );
    });

    testWidgets('播放源解析不到（清单无此素材）：退出回看、回落实时预览', (tester) async {
      // 清单为空 = 解析不出素材文件：回看不得静默挂在回放件上。
      final container = await pumpPlayer(tester);
      container.read(practiceClipsProvider.notifier).restore([clip]);

      container.read(practiceClipActivationProvider.notifier).toggle(clip);
      await tester.pumpAndSettle();

      expect(container.read(practiceClipActivationProvider), isNull);
      expect(
        container.read(practiceOnscreenFaceProvider),
        SurfaceFace.cameraPreview,
      );
      expect(practiceEngine.isPlaying, isFalse);
    });
  });
}

/// 记录型保存 sink（与 annotation_editor_commit_seam_test 同款）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}
