import 'dart:io';
import 'dart:ui' as ui;

import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/annotation/compare_materials.dart'
    show MaterialRecord, PracticeClip;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart'
    show
        MaterialManifestStore,
        materialManifestStorageProvider,
        materialRecordingFileResolverProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationTimelineProvider,
        practiceClipActivationProvider,
        practiceClipsProvider,
        practiceOnscreenFaceProvider,
        selectedPracticeClipIdProvider;
import 'package:dance_learning_app/player/compare_recording.dart'
    show CompareRecordingPhase, compareRecordingPhaseProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/practice_clip_playback.dart'
    show practiceClipEngineProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show SurfaceFace;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/android_camera_platform.dart';
import '../helpers/beat_test_seam.dart';
import '../helpers/compare_framing_harness.dart' show tapFramingEntry;
import '../helpers/track_band_session_harness.dart';
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/semantics_assertions.dart';
import '../helpers/video_index_fixtures.dart';
import '../helpers/device_viewport.dart';

/// 练习片段回看的**出口**：回看中要看得见、且有一个明示的退出。
///
/// - 编辑态（对比-控制层）：回看中的块上方展开「回看中 · 区间 + 退出回看」
///   浮条，形式与备注单击气泡同款；**跟随激活而非选中**——只选中未回看时
///   不出现。
/// - 播放态 / 取景态：画面常驻出口件，点一下退出回看并回到相机实时预览。
/// - 两处动作走同一个退出写入口（清激活 + 清选中）；录制期不出现。
/// 全流程走真实 UI 路径（点块激活），只断言用户可见外部行为。
void main() {
  const total = Duration(minutes: 3);
  // 片段源区间 5s–15s：三分钟视频（轨道带组）与一分钟视频（整页组）都在片内。
  const clip = PracticeClip(
    id: 'c1',
    materialId: 'm1',
    materialSourceStartMs: 5000,
    inMs: 0,
    outMs: 10000,
    materialDurationMs: 30000,
  );

  /// 编辑态回看浮条（对比行集的轨道带）。
  group('编辑态回看浮条', () {
    late FakePlaybackEngine engine;

    Future<ProviderContainer> pumpBand(WidgetTester tester) async {
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            beatTrackStateProvider.overrideWithBuild(
              (ref, _) => uniformReadyBeatState(seconds: 180),
            ),
            annotationTimelineProvider.overrideWithBuild(
              (ref, _) => AnnotationTimeline.wholeVideo(total),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.compare,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      container.read(practiceClipsProvider.notifier).restore(const [clip]);
      await tester.pumpAndSettle();
      return container;
    }

    BoxDecoration blockDecoration(WidgetTester tester) =>
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byKey(const Key('practice_clip_c1')),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;

    setUp(() {
      engine = FakePlaybackEngine(duration: total);
    });

    testWidgets('回看中：块上方出现「回看中 · 区间 + 退出回看」浮条', (tester) async {
      final container = await pumpBand(tester);
      container.read(practiceClipActivationProvider.notifier).toggle(clip);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('clip_review_bubble')), findsOneWidget);
      expect(find.textContaining('回看中'), findsOneWidget);
      expect(
        find.byKey(const Key('clip_review_bubble_exit')),
        findsOneWidget,
        reason: '浮条上有一枚明示的退出入口',
      );
    });

    testWidgets('回看中的块视觉与常态可区分（填充换色 + 加粗白描边）', (tester) async {
      final container = await pumpBand(tester);
      expect(
        blockDecoration(tester).color,
        kPracticeClipBlockColor,
        reason: '未回看 = 常态填充',
      );

      container.read(practiceClipActivationProvider.notifier).toggle(clip);
      await tester.pumpAndSettle();

      final active = blockDecoration(tester);
      expect(active.color, kPracticeClipActiveBlockColor);
      final border = active.border as Border?;
      expect(border?.top.color, Colors.white);
      expect(border?.top.width, kPracticeClipActiveBorderWidth);
    });

    testWidgets('只选中未回看：不出现回看浮条', (tester) async {
      final container = await pumpBand(tester);
      container.read(selectedPracticeClipIdProvider.notifier).select('c1');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('clip_review_bubble')),
        findsNothing,
        reason: '浮条跟随激活而非选中',
      );
    });

    testWidgets('点浮条「退出回看」：两槽一起清、浮条消失', (tester) async {
      final container = await pumpBand(tester);
      container.read(practiceClipActivationProvider.notifier).toggle(clip);
      container.read(selectedPracticeClipIdProvider.notifier).select('c1');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('clip_review_bubble_exit')));
      await tester.pumpAndSettle();

      expect(container.read(practiceClipActivationProvider), isNull);
      expect(container.read(selectedPracticeClipIdProvider), isNull);
      expect(find.byKey(const Key('clip_review_bubble')), findsNothing);
      expect(blockDecoration(tester).color, kPracticeClipBlockColor);
    });
  });

  /// 播放态 / 取景态的画面常驻出口件（整页，真实手势路径）。
  group('画面常驻出口件', () {
    late FakePlaybackEngine engine;
    late FakePlaybackEngine practiceEngine;
    late FakeCameraCaptureService camera;
    late FakeSystemUi systemUi;
    late MemoryManifestStorage manifestStorage;
    late File materialOutputFile;

    Future<ProviderContainer> pumpPlayer(WidgetTester tester) async {
      tester.view.physicalSize = const Size(
        1920,
        1080,
      ); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
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
            materialManifestStorageProvider.overrideWithValue(manifestStorage),
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => InMemoryVideoDocumentStorage(),
            ),
            materialRecordingFileResolverProvider.overrideWithValue(
              (videoId) async => materialOutputFile,
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

    Future<void> singleTapShow(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
    }

    /// 进对比-控制层：唤出控制层 → 点顶栏「对比练习」槽（进对比-播放态）
    /// → 再唤出控制层 = 对比-控制层（练习片段轨在屏）。
    Future<void> enterCompareEditing(WidgetTester tester) async {
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      await singleTapShow(tester);
      await tester.pumpAndSettle();
    }

    /// 收起控制层 = 回对比-播放态。
    Future<void> collapseToCompareWatching(WidgetTester tester) async {
      await singleTapShow(tester);
      await tester.pumpAndSettle();
    }

    /// 点练习片段块激活回看（真实 UI 路径；编辑态）。
    Future<void> activateClipByTap(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('practice_clip_c1')));
      await tester.pumpAndSettle();
    }

    setUp(() async {
      engine = FakePlaybackEngine(duration: const Duration(seconds: 60));
      practiceEngine = FakePlaybackEngine(
        duration: const Duration(seconds: 20),
      );
      camera = FakeCameraCaptureService();
      systemUi = FakeSystemUi();
      manifestStorage = MemoryManifestStorage();
      // 片段回看需解析得到播放源（解析不到即退出
      // 回看）——种入清单条目让回放件真实就位。
      await MaterialManifestStore(manifestStorage).append(
        MaterialRecord(
          id: 'm1',
          videoId: 'vid-a',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          durationMs: 30000,
          sourceStartMs: 5000,
          fileName: 'rec_m1.mp4',
          sizeBytes: 1,
        ),
      );
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('clip_exit').path}/rec.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
    });

    testWidgets('回看中：出口件在；点它清两槽并回到相机实时预览', (tester) async {
      final container = await pumpPlayer(tester);
      container.read(practiceClipsProvider.notifier).restore(const [clip]);
      await enterCompareEditing(tester);
      await collapseToCompareWatching(tester);
      expect(
        find.byKey(const Key('clip_review_exit_chip')),
        findsNothing,
        reason: '未回看 = 无出口件',
      );

      await singleTapShow(tester);
      await activateClipByTap(tester);
      expect(
        find.byKey(const Key('clip_review_bubble')),
        findsOneWidget,
        reason: '编辑态由回看浮条承载',
      );

      await collapseToCompareWatching(tester);
      expect(find.byKey(const Key('clip_review_exit_chip')), findsOneWidget);

      await tester.tap(find.byKey(const Key('clip_review_exit_chip')));
      await tester.pumpAndSettle();

      expect(container.read(practiceClipActivationProvider), isNull);
      expect(container.read(selectedPracticeClipIdProvider), isNull);
      expect(
        container.read(practiceOnscreenFaceProvider),
        SurfaceFace.cameraPreview,
        reason: '退出回看 = 回到相机实时预览',
      );
      expect(find.byKey(const Key('clip_review_exit_chip')), findsNothing);
    });

    testWidgets('录制期（准备态）：出口件不出现', (tester) async {
      final container = await pumpPlayer(tester);
      container.read(practiceClipsProvider.notifier).restore(const [clip]);
      await enterCompareEditing(tester);
      await activateClipByTap(tester);
      await collapseToCompareWatching(tester);
      expect(
        find.byKey(const Key('clip_review_exit_chip')),
        findsOneWidget,
        reason: '前置：回看中',
      );

      await tester.tap(find.byKey(const Key('compare_record_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        container.read(compareRecordingPhaseProvider),
        isNot(CompareRecordingPhase.idle),
        reason: '前置：已进入录制准备期',
      );
      expect(find.byKey(const Key('clip_review_exit_chip')), findsNothing);

      // 收尾：取消准备期（会话的周期计时器不留到测试结束）。
      await tester.tap(find.byKey(const Key('compare_record_button')));
      await tester.pumpAndSettle();
    });

    testWidgets('取景调节态：出口件仍在，点它退出回看', (tester) async {
      final container = await pumpPlayer(tester);
      container.read(practiceClipsProvider.notifier).restore(const [clip]);
      await enterCompareEditing(tester);
      await activateClipByTap(tester);
      await collapseToCompareWatching(tester);

      await singleTapShow(tester);
      // 「取景」槽已退役：进取景调节态经生效顶栏
      // 「取景调整」入口（对比-控制层分派到分屏路径）；本视口是紧凑档
      // 横屏，这枚入口由「更多」钮的向上弹出菜单承载。
      await tapFramingEntry(tester);
      await tester.pumpAndSettle();
      expect(
        container.read(playerSessionProvider).mode,
        PlayerSessionMode.compareFraming,
        reason: '前置：已进取景调节态',
      );
      expect(find.byKey(const Key('clip_review_exit_chip')), findsOneWidget);

      await tester.tap(find.byKey(const Key('clip_review_exit_chip')));
      await tester.pumpAndSettle();

      expect(container.read(practiceClipActivationProvider), isNull);
      expect(container.read(selectedPracticeClipIdProvider), isNull);
    });

    testWidgets('出口件：报按钮角色与名字；读屏激活确实退出回看', (tester) async {
      final handle = tester.ensureSemantics();
      final container = await pumpPlayer(tester);
      container.read(practiceClipsProvider.notifier).restore(const [clip]);
      await enterCompareEditing(tester);
      await activateClipByTap(tester);
      await collapseToCompareWatching(tester);
      expect(
        find.byKey(const Key('clip_review_exit_chip')),
        findsOneWidget,
        reason: '前置：回看中',
      );

      expectButtonSemantics(
        tester,
        const Key('clip_review_exit_chip'),
        label: '退出回看',
      );
      activateBySemantics(tester, const Key('clip_review_exit_chip'));
      await tester.pumpAndSettle();

      expect(
        container.read(practiceClipActivationProvider),
        isNull,
        reason: '读屏双击出口应真的退出回看',
      );
      expect(find.byKey(const Key('clip_review_exit_chip')), findsNothing);
      handle.dispose();
    });

    testWidgets('出口件的触控目标不小于手指尺寸（设备等效视口）', (tester) async {
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
      tester.view.gestureSettings = const ui.GestureSettings(
        physicalTouchSlop: 8 * 3.5,
      );
      addTearDown(tester.view.reset);

      final container = await pumpPlayer(tester);
      container.read(practiceClipsProvider.notifier).restore(const [clip]);
      await enterCompareEditing(tester);
      await activateClipByTap(tester);
      await collapseToCompareWatching(tester);

      final size = tester.getSize(
        find.byKey(const Key('clip_review_exit_chip')),
      );
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(64));
    });
  });
}
