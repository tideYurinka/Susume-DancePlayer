import 'dart:io';

import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    show BeatGrid, BeatPoint;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/compare_recording.dart'
    show recordingResolutionProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationSelectionDomainProvider, annotationEditorProvider;
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/video_index_fixtures.dart';
import '../helpers/fixed_hasher.dart';

/// 起录连贯：**预览与录制共用同一个相机实例**——
/// 进入对比态开流时按当前录制分辨率档建预览控制器，起录只在这同一个实例上
/// 挂录像用例，预览流全程不断；停录后才换一次实例并重开流。
///
/// 测试用 fake 模拟「换 controller 实例」的可见效应（实例序号子件），断言落在
/// 练习半区的可见行为上，不钉内部实现。
void main() {
  group('录制起录连贯：预览实例全程不换、无占位件（相机 seam 回归）', () {
    late FakePlaybackEngine engine;
    late FakeSystemUi systemUi;
    late FakeCameraCaptureService camera;
    late MemoryManifestStorage manifestStorage;
    late File materialOutputFile;
    late InMemoryPrivateJsonStorage privateStorage;

    void setWideView(WidgetTester tester) {
      tester.view.physicalSize = const Size(1920, 1080); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    Future<void> pumpPlayer(WidgetTester tester) async {
      final source = Uri.file('/videos/a.mp4');
      privateStorage = InMemoryPrivateJsonStorage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            cameraCaptureProvider.overrideWithValue(camera),
            privateJsonStorageProvider.overrideWithValue(privateStorage),
            materialManifestStorageProvider.overrideWithValue(manifestStorage),
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => InMemoryVideoDocumentStorage(),
            ),
            materialRecordingFileResolverProvider.overrideWithValue(
              (videoId) async => materialOutputFile,
            ),
            systemUiControllerProvider.overrideWithValue(systemUi),
            contentHasherProvider.overrideWithValue(
              const FixedHasher('seeded'),
            ),
            videoIndexStoreProvider.overrideWithValue(
              InMemoryVideoIndexStorage(
                initial: VideoIndex(
                  entries: [
                    historyEntry(
                      filePath: source.toFilePath(),
                      mirrored: false,
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
    }

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(PlayerPage)),
          listen: false,
        );

    Future<MaterialManifestDocument> readManifest() =>
        MaterialManifestStore(manifestStorage).read();

    Future<void> singleTapShow(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
    }

    /// 建 3 个学习段并激活第 2 段（10s–20s，与录制测试同款布景）。
    void givenActiveSegment(WidgetTester tester) {
      final editor = containerOf(tester).read(annotationEditorProvider);
      containerOf(tester).read(beatTrackStateProvider.notifier).replace(
            BeatTrackState.ready(
              BeatGrid(
                model: 'madmom_downbeat_rnn_full.onnx',
                fps: 100,
                generatedAt: DateTime.utc(2026, 9, 6),
                shift: 0,
                beats: [
                  for (var i = 0; i < 60; i++)
                    BeatPoint(t: 0.5 + i * 0.5, down: (0.5 + i * 0.5) % 4 == 2),
                ],
              ),
            ),
          );
      editor.submit(AddSegmentLine(at: const Duration(seconds: 10)));
      editor.submit(AddSegmentLine(at: const Duration(seconds: 20)));
      containerOf(tester)
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(1);
    }

    Future<void> enterCompare(WidgetTester tester) async {
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
    }

    Future<void> pressRecord(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('compare_record_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      systemUi = FakeSystemUi();
      camera = FakeCameraCaptureService();
      manifestStorage = MemoryManifestStorage();
      materialOutputFile = File('/tmp/unused_preview_rebuild.mp4');
    });

    testWidgets('起录那一刻预览实例号不变：预览不中断、不出现占位件', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      givenActiveSegment(tester);
      await enterCompare(tester);

      // 开流实例 1：练习半区显示实例 1 的实时预览。
      expect(camera.previewInstance, 1);
      expect(
        find.byKey(const Key('fake_camera_preview_instance_1')),
        findsOneWidget,
      );

      // 按录 → 前导 4s → 起录：起录只在**同一个实例**上挂录像用例。
      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();

      expect(camera.startRecordingCalls, hasLength(1));
      expect(camera.isRecording, isTrue);
      // 实例号不变 = 起录没有销毁/重建 controller（换实例即预览件重挂、黑屏根因）。
      expect(
        camera.previewInstance,
        1,
        reason: '起录不得换 controller 实例（销毁重建即练习侧黑一下）',
      );
      expect(find.byKey(const Key('fake_camera_preview')), findsOneWidget);
      expect(
        find.byKey(const Key('fake_camera_preview_instance_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('fake_camera_preview_placeholder')),
        findsNothing,
        reason: '起录那一刻不得出现占位底色',
      );
    });

    testWidgets('停录后才换一次实例并重开流：回到实时预览（非占位件）', (tester) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_prev').path}/rec_1.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(tester);
      givenActiveSegment(tester);
      await enterCompare(tester);

      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 4)); // 前导 → 起录（实例仍是 1）。
      await tester.pump(const Duration(seconds: 10)); // 录制至段尾自动停。
      await tester.pumpAndSettle();

      expect(camera.stopRecordingCount, 1);
      expect(camera.isRecording, isFalse);
      // 停录后才换一次实例（1 → 2）并重开流：预览件仍在练习半区、内容为
      // 重开后的新实例，不是未开流占位件。
      expect(camera.previewInstance, 2);
      expect(find.byKey(const Key('fake_camera_preview')), findsOneWidget);
      expect(
        find.byKey(const Key('fake_camera_preview_instance_1')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('fake_camera_preview_instance_2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('fake_camera_preview_placeholder')),
        findsNothing,
      );
    });

    testWidgets('起录失败：预览实例仍在（非占位件）、不落素材、回待录态并恢复原倍速', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await enterCompare(tester);
      expect(camera.previewInstance, 1);
      // 先离开 1.0×：起录失败要按准备收尾路径恢复原倍速。
      await engine.setRate(1.5);

      // 起录失败（设备异常）：失败路径不得留下黑屏——预览实例必须还在。
      camera.startRecordingFails = true;
      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(camera.startRecordingCalls, isEmpty);
      expect(camera.stopRecordingCount, 0);
      expect(camera.isRecording, isFalse);
      expect(
        camera.previewInstance,
        1,
        reason: '起录失败后预览实例仍在（不再有「好的控制器已被销毁、重建失败无人重开流」）',
      );
      expect(find.byKey(const Key('fake_camera_preview')), findsOneWidget);
      expect(
        find.byKey(const Key('fake_camera_preview_instance_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('fake_camera_preview_placeholder')),
        findsNothing,
        reason: '起录失败后练习侧仍是实时预览，不是黑底',
      );
      // 回到待录态、不落素材、引擎停下且恢复原倍速（既有准备收尾路径）。
      expect(
        find.byKey(const Key('compare_recording_indicator')),
        findsNothing,
      );
      expect(find.byKey(const Key('compare_record_button')), findsOneWidget);
      expect(engine.isPlaying, isFalse);
      expect(engine.rate, 1.5);
      expect((await readManifest()).materials, isEmpty);
    });

    testWidgets('分辨率档只在开流时生效：中途改档不换实例、下次进对比态才带新档开流', (
      tester,
    ) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await enterCompare(tester);
      // 开流带当前档（设备级默认 1080p）。
      expect(camera.openResolutions, [RecordingResolution.fhd1080p]);
      expect(camera.previewInstance, 1);

      // 会话中途改档 → 720p：实例一位不动、流不断（当场什么也不发生）。
      await containerOf(tester)
          .read(recordingResolutionProvider.notifier)
          .select(RecordingResolution.hd720p, privateStorage);
      await tester.pumpAndSettle();
      expect(camera.previewInstance, 1);
      expect(
        find.byKey(const Key('fake_camera_preview_instance_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('fake_camera_preview_placeholder')),
        findsNothing,
      );
      expect(camera.openResolutions, [RecordingResolution.fhd1080p]);

      // 本会话余下的录制仍按**开流档**出参（中途改的档不生效）。
      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(
        camera.startRecordingCalls.single.resolution,
        RecordingResolution.fhd1080p,
      );
      await pressRecord(tester);
      await tester.pumpAndSettle();

      // 离开对比态（关流）→ 重新进入：开流才带上新档。
      final session = containerOf(tester).read(playerSessionProvider.notifier);
      session.enter(PlayerSessionMode.editing);
      await tester.pumpAndSettle();
      expect(camera.previewInstance, 0); // 离开对比态即关流。
      session.enter(PlayerSessionMode.compareWatching);
      await tester.pumpAndSettle();

      // 开流两次：进对比态那次 1080p（旧档）、重进这次 720p（新档）。
      expect(camera.startCount, 2);
      expect(camera.openResolutions, [
        RecordingResolution.fhd1080p,
        RecordingResolution.hd720p,
      ]);
      // 实例 1（开流）→ 2（停录重开）→ 0（离开对比态关流）→ 3（重进开流）。
      expect(camera.previewInstance, 3);
    });
  });
}
