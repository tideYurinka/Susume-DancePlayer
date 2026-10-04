import 'dart:io';

import 'package:dance_learning_app/annotation/compare_materials.dart'
    show MaterialRecord, PracticeClip;
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/beat_grid.dart'
    show BeatGridReads, placeholderBeatGrid;

import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/core/video_identity.dart';
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
    show practiceClipsProvider;
import 'package:dance_learning_app/player/compare_recording.dart'
    show kCompareRecordButtonBottomInset;
import 'package:dance_learning_app/player/gestures.dart'
    show kGestureYieldBottomMinPx;
import 'package:dance_learning_app/player/loop_prompt.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/practice_clip_playback.dart'
    show practiceClipEngineProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
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
import '../helpers/note_editor_harness.dart';
import '../helpers/video_index_fixtures.dart';

/// 固定值哈希（打开恢复的内容哈希校验桩，resume_position_test 同款）。
class _FixedHasher implements ContentHasher {
  const _FixedHasher(this.value);

  final String value;

  @override
  Future<String> hashFile(File file) async => value;
}

/// 「安全区与键盘避让」：演出层常驻入口避开系统手势内缩；键盘收起时
/// 备注输入条底距取键盘内缩与系统手势内缩的较大者。手势内缩为 0 时既有基准
/// 视口落位逐位不变。
///
/// 两张左下角提示卡不再自读系统手势
/// 内缩、不再自写固定内缩：让路断言搬到几何纯件（`editor_skeleton_test.dart`
/// 的八格表、让路与占用区用例），本文件的提示条组只钉 widget 缝（传什么锚
/// 落什么位置、锚为 null 不渲染）。
void main() {
  // 设系统手势内缩（按当前测试面 dpr 换算成物理像素）。
  void setGestureInsets(
    WidgetTester tester, {
    double bottom = 0,
    double left = 0,
    double right = 0,
  }) {
    addTearDown(tester.view.reset);
    final dpr = tester.view.devicePixelRatio;
    tester.view.systemGestureInsets = FakeViewPadding(
      bottom: bottom * dpr,
      left: left * dpr,
      right: right * dpr,
    );
  }

  group('演出层（整页，真实打开路径）', () {
    late FakePlaybackEngine engine;
    late FakePlaybackEngine practiceEngine;
    late FakeCameraCaptureService camera;
    late FakeSystemUi systemUi;
    late MemoryManifestStorage manifestStorage;
    late File materialOutputFile;

    const total = Duration(minutes: 3);
    const clip = PracticeClip(
      id: 'c1',
      materialId: 'm1',
      materialSourceStartMs: 5000,
      inMs: 0,
      outMs: 10000,
      materialDurationMs: 30000,
    );

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
            contentHasherProvider.overrideWithValue(
              const _FixedHasher('vid-a'),
            ),
            videoIndexStoreProvider.overrideWithValue(
              InMemoryVideoIndexStorage(
                initial: VideoIndex(
                  entries: [
                    historyEntry(
                      filePath: source.toFilePath(),
                      mirrored: false,
                      videoId: 'vid-a',
                    ).copyWith(lastPositionMs: 60000),
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

    Future<void> enterCompareEditing(WidgetTester tester) async {
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      await singleTapShow(tester);
      await tester.pumpAndSettle();
    }

    Future<void> collapseToCompareWatching(WidgetTester tester) async {
      await singleTapShow(tester);
      await tester.pumpAndSettle();
    }

    setUp(() async {
      engine = FakePlaybackEngine(duration: total);
      practiceEngine = FakePlaybackEngine(
        duration: const Duration(seconds: 20),
      );
      camera = FakeCameraCaptureService();
      systemUi = FakeSystemUi();
      manifestStorage = MemoryManifestStorage();
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
        '${Directory.systemTemp.createTempSync('safe_area').path}/rec.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
    });

    testWidgets('手势内缩为 0：贴底常驻入口落位与既有基准逐位一致', (tester) async {
      await pumpPlayer(tester);

      // 续播小卡不再自读内缩：底边一律抬出系统手势让路区（底 44 下限），
      // 与上报值无关；左缘 = 画面左缘 + 24。
      final card = tester.getRect(find.byKey(const Key('resume_prompt_card')));
      expect(card.left, 24);
      expect(card.bottom, 540 - kGestureYieldBottomMinPx);
      expect(
        tester.getBottomRight(find.byKey(const Key('speed_entry_button'))),
        const Offset(960 - 12, 540 - 12),
      );
    });

    testWidgets('「从头播放？」小卡：贴画面矩形左下角，卡边落进让路带即推出带外', (tester) async {
      await pumpPlayer(tester);
      setGestureInsets(tester, bottom: 100, left: 40);
      await tester.pump();

      // 本视口宽高比未知 → 画面矩形 = 整屏；上报内缩（底 100 / 左 40）比
      // 固定下限大，取上报值：底边推出底部让路带、左缘推出左右让路带。
      final rect = tester.getRect(find.byKey(const Key('resume_prompt_card')));
      expect(rect.left, 40, reason: '左缘推出左右让路带');
      expect(rect.bottom, 540 - 100, reason: '底边推出底部让路带');
    });

    testWidgets('倍速入口避开系统手势内缩', (tester) async {
      await pumpPlayer(tester);
      setGestureInsets(tester, bottom: 44, right: 16);
      await tester.pump();

      expect(
        tester.getBottomRight(find.byKey(const Key('speed_entry_button'))),
        Offset(960 - 12 - 16, 540 - 12 - 44),
      );
    });

    testWidgets('常驻录制钮底部居中并避开系统手势内缩', (tester) async {
      await pumpPlayer(tester);
      setGestureInsets(tester, bottom: 44, right: 16);
      await tester.pump();
      await enterCompareEditing(tester);
      await collapseToCompareWatching(tester);

      // 底边 = 24 + 系统手势内缩；水平居中在画面（本视口整屏）中线上，
      // 不再靠右、与右下角的倍速入口分列。
      final view = tester.view.physicalSize / tester.view.devicePixelRatio;
      final ring = tester.getRect(
        find.byKey(const Key('compare_record_button')),
      );
      expect(ring.center.dx, closeTo(view.width / 2, 1.0));
      expect(ring.bottom, 540 - kCompareRecordButtonBottomInset - 44);
    });

    testWidgets('回看出口件避开系统手势内缩', (tester) async {
      await pumpPlayer(tester);
      setGestureInsets(tester, bottom: 44, right: 16);
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container.read(practiceClipsProvider.notifier).restore(const [clip]);
      await enterCompareEditing(tester);
      await tester.tap(find.byKey(const Key('practice_clip_c1')));
      await tester.pumpAndSettle();
      await collapseToCompareWatching(tester);

      expect(
        find.byKey(const Key('clip_review_exit_chip')),
        findsOneWidget,
        reason: '前置：回看中',
      );
      expect(
        tester.getBottomRight(find.byKey(const Key('clip_review_exit_chip'))),
        Offset(960 - 12 - 16, 540 - 116 - 44),
      );
    });
  });

  group('「循环练习」提示条（widget 缝：锚入参）', () {
    /// 裸 Stack 直挂卡：脚手架 800×600。锚即卡左下角（`Positioned` 语义）。
    Future<FakePlaybackEngine> pumpCard(
      WidgetTester tester, {
      required ({double left, double bottom})? anchor,
    }) async {
      addTearDown(tester.view.reset);
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 1));
      final controller = LoopPromptController(
        engine,
        gridOf: () => placeholderBeatGrid,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                LoopPromptOverlay(controller: controller, anchor: anchor),
              ],
            ),
          ),
        ),
      );

      // 播放到尾进入 countdown，提示条出现。
      engine.open(Uri.file('/videos/a.mp4'), play: true);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      return engine;
    }

    /// 收尾：走完倒计时（自动循环开跑）后暂停引擎，不留悬挂计时器。
    Future<void> settle(WidgetTester tester, FakePlaybackEngine engine) async {
      await tester.pump(placeholderBeatGrid.eightBeatNominal);
      engine.pause();
      await tester.pump();
    }

    testWidgets('传什么锚落什么位置（卡不再自读系统手势内缩）', (tester) async {
      final engine = await pumpCard(tester, anchor: (left: 40, bottom: 100));
      expect(find.byKey(const Key('loop_prompt')), findsOneWidget);

      final rect = tester.getRect(find.byKey(const Key('loop_prompt')));
      expect(rect.left, 40);
      expect(rect.bottom, 600 - 100);

      await settle(tester, engine);
    });

    testWidgets('锚为 null（本次放不下）：不渲染', (tester) async {
      final engine = await pumpCard(tester, anchor: null);
      expect(find.byKey(const Key('loop_prompt')), findsNothing);

      await settle(tester, engine);
    });
  });

  group('备注输入条（备注编辑器 widget 缝）', () {
    late ProviderContainer container;

    setUp(() {
      container = noteEditorContainer();
      addTearDown(container.dispose);
    });

    Rect editorRect(WidgetTester tester) =>
        tester.getRect(find.byKey(const Key('note_text_editor')));

    testWidgets('键盘收起：底距取系统手势内缩（较大者）', (tester) async {
      addTearDown(tester.view.reset);
      seedAndOpenNoteEditor(container);
      await pumpNoteEditorPanel(tester, container);
      final restRect = editorRect(tester);

      // 手势内缩 44 > 键盘 0：输入条整体上抬 44。
      setGestureInsets(tester, bottom: 44);
      await tester.pump();
      expect(editorRect(tester).bottom, restRect.bottom - 44);

      // 手势内缩缩回 0：回到既有基准落位。
      tester.view.systemGestureInsets = FakeViewPadding.zero;
      await tester.pump();
      expect(editorRect(tester).bottom, restRect.bottom);
    });

    testWidgets('键盘升起时仍取较大者：键盘高于手势内缩则停靠位不变', (tester) async {
      addTearDown(tester.view.reset);
      seedAndOpenNoteEditor(container);
      await pumpNoteEditorPanel(tester, container);

      tester.view.viewInsets = const FakeViewPadding(bottom: 900); // 300 逻辑
      await tester.pump();
      final dockedRect = editorRect(tester);
      expect(dockedRect.bottom, lessThanOrEqualTo(600 - 300));

      // 手势内缩 44 < 键盘 300：停靠位不受影响。
      setGestureInsets(tester, bottom: 44);
      await tester.pump();
      expect(editorRect(tester).bottom, dockedRect.bottom);
    });

    testWidgets('键盘低于手势内缩（收起动画尾帧）：底距不小于手势内缩', (tester) async {
      addTearDown(tester.view.reset);
      seedAndOpenNoteEditor(container);
      await pumpNoteEditorPanel(tester, container);
      final restRect = editorRect(tester);

      tester.view.viewInsets = const FakeViewPadding(bottom: 60); // 20 逻辑
      await tester.pump();
      setGestureInsets(tester, bottom: 44);
      await tester.pump();
      expect(editorRect(tester).bottom, restRect.bottom - 44);
    });
  });
}
