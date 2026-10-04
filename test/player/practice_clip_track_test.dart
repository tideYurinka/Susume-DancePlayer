import 'dart:io';

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        annotationEditorProvider,
        practiceClipsProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
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

void main() {
  group('练习片段入轨与恢复', () {
    late FakePlaybackEngine engine;
    late FakeSystemUi systemUi;
    late FakeCameraCaptureService camera;
    late MemoryManifestStorage manifestStorage;
    late InMemoryVideoDocumentStorage documentStorage;
    late File materialOutputFile;

    void setWideView(WidgetTester tester) {
      tester.view.physicalSize = const Size(
        1920,
        1080,
      ); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    final source = Uri.file('/videos/a.mp4');

    Future<void> pumpPlayer(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            cameraCaptureProvider.overrideWithValue(camera),
            privateJsonStorageProvider.overrideWithValue(
              InMemoryPrivateJsonStorage(),
            ),
            materialManifestStorageProvider.overrideWithValue(manifestStorage),
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => documentStorage,
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

    Future<void> enterCompareAndRecordSegment(WidgetTester tester) async {
      // 激活学习段 2（10s–18s，建线落点吸附八拍点）：录制 = 段首起、段尾停。
      final editor = containerOf(tester).read(annotationEditorProvider);
      containerOf(tester)
          .read(beatTrackStateProvider.notifier)
          .replace(
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

      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      // 按下录制 → 前导 4s → 起录 → 段尾自动停。
      await tester.tap(find.byKey(const Key('compare_record_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    }

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      systemUi = FakeSystemUi();
      camera = FakeCameraCaptureService();
      manifestStorage = MemoryManifestStorage();
      documentStorage = InMemoryVideoDocumentStorage();
      materialOutputFile = File('/tmp/unused.mp4');
    });

    testWidgets('录制完成即出现片段：入轨 1:1 片段、位置 = 录制源区间', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await enterCompareAndRecordSegment(tester);

      final clips = containerOf(tester).read(practiceClipsProvider);
      expect(clips, hasLength(1));
      // 入点 = 前言长度（录制武装余量）、出点 = 素材全长，故片段的源
      // 区间正好从起录点（10s）开始，到 10s +（素材全长 − 前言）。
      expect(clips.single.inMs, kRecordingArmMarginMs);
      expect(clips.single.outMs, 10000);
      expect(clips.single.sourceStartMs, 10000);
      expect(clips.single.sourceEndMs, 10000 + 10000 - kRecordingArmMarginMs);
      // 素材仍在库。
      final manifest = await MaterialManifestStore(manifestStorage).read();
      expect(manifest.materials, hasLength(1));
    });

    testWidgets('重录重叠：完全覆盖的旧引用删除、部分重叠的裁到不重叠；素材仍在库', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      final container = containerOf(tester);
      // 预置两条旧片段：c_old_full 被新录（10s–20s）完全覆盖；c_old_part
      // 左悬重叠（8s–12s → 裁到 8s–10s）。
      container.read(practiceClipsProvider.notifier).state = [
        const PracticeClip(
          id: 'c_old_full',
          materialId: 'mat_old_full',
          materialSourceStartMs: 0,
          inMs: 12000,
          outMs: 17000,
        ),
        const PracticeClip(
          id: 'c_old_part',
          materialId: 'mat_old_part',
          materialSourceStartMs: 0,
          inMs: 8000,
          outMs: 12000,
        ),
      ];

      await enterCompareAndRecordSegment(tester);

      final clips = containerOf(tester).read(practiceClipsProvider);
      expect(
        clips.map((c) => c.id),
        unorderedEquals(['c_old_part', clips.last.id]),
      );
      // 部分重叠裁到不重叠：8s–10s。
      final kept = clips.firstWhere((c) => c.id == 'c_old_part');
      expect(kept.sourceStartMs, 8000);
      expect(kept.sourceEndMs, 10000);
      // 素材与库内条目不动：预置两素材引用不被清理路径删除，本录新增一条。
      final manifest = await MaterialManifestStore(manifestStorage).read();
      expect(manifest.materials, hasLength(1));
    });

    testWidgets('关掉重开该舞：片段按记忆恢复；不自动播放、不改播放位置', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await enterCompareAndRecordSegment(tester);
      // 片段已落随舞私密 local 文档。
      expect(
        (documentStorage.localSnapshot['prefs']
            as Map<String, dynamic>)['practiceClips'],
        isNotEmpty,
      );

      // 关掉（dispose 页面）重开：全新容器与播放会话、同一份按视频文档
      // 存储——恢复不改播放位置（新会话从 0 起，不自动续跳到片段）。
      engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester);

      final clips = containerOf(tester).read(practiceClipsProvider);
      expect(clips, hasLength(1));
      expect(clips.single.sourceStartMs, 10000);
      expect(clips.single.sourceEndMs, 10000 + 10000 - kRecordingArmMarginMs);
      // 恢复不自动播放、不改播放位置。
      expect(engine.isPlaying, isFalse);
      expect(engine.position, Duration.zero);
    });

    testWidgets('空轨与有片段两形态都常驻显示（练习视频轨行存在）', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      // 进入对比-控制层展开态查看轨道行：先确认模式库对比态进入（行集由
      // 控制层按模式传入）。
      containerOf(tester)
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('track_practice')), findsOneWidget);
      expect(find.byKey(const Key('practice_clip_x')), findsNothing);
    });
  });
}
