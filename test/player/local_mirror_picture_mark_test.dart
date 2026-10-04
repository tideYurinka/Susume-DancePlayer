import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart'
    show VideoDocumentCoordinator;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationEditorProvider,
        localMirrorEnabledProvider,
        localMirrorFragmentsProvider;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/control_layer.dart';
import 'package:dance_learning_app/player/editor_skeleton.dart';
import 'package:dance_learning_app/player/local_mirror_picture_mark.dart';
import 'package:dance_learning_app/player/metronome_overlay.dart'
    show MetronomeOverlay;
import 'package:dance_learning_app/player/note_sticker_layout.dart'
    show videoContentRectInBox;
import 'package:dance_learning_app/player/note_sticker_overlay.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/settings_persistence.dart'
    show videoDocumentCoordinatorProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kLocalMirrorEnabledColor;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/android_camera_platform.dart';
import '../helpers/beat_test_seam.dart'
    show hangingBeatPipeline, turnBeatAnimationOn;
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/stack_paint_order.dart';

/// 局部镜像画面标识：局部镜像生效那
/// 一刻画面内容矩形上的琥珀细边框 + 「局部镜像」角标。
///
/// 本文件钉**用户可见面**：出现/消失条件（位置即真值、总开关、与全局镜像
/// 无关）、边框与角标的矩形（非对比态贴画面内容矩形、对比态贴源视频半区）、
/// 层序（视频画面之上、备注贴纸之下）与「整件不吃触摸」。取值口径（画面翻转
/// 与标识同源）由 `surface_direction_test.dart` 的覆盖取值组直测。
void main() {
  /// 视口布景：逻辑尺寸 = physicalSize ÷ devicePixelRatio。
  void setViewport(
    WidgetTester tester, {
    required Size logical,
    double devicePixelRatio = 1.0,
  }) {
    tester.view.devicePixelRatio = devicePixelRatio;
    tester.view.physicalSize = logical * devicePixelRatio;
    addTearDown(tester.view.reset);
  }

  Future<ProviderContainer> pumpPlayer(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
    Map<String, dynamic> markers = const {},
  }) async {
    final source = Uri.file('/videos/a.mp4');
    final docStorage = InMemoryVideoDocumentStorage(markers: markers);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          beatAnalysisPipelineProvider.overrideWithValue(hangingBeatPipeline),
          cameraCaptureProvider.overrideWithValue(FakeCameraCaptureService()),
          androidCameraPlatform(),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          contentHasherProvider.overrideWithValue(const FixedHasher('vid-a')),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => docStorage,
          ),
          videoDocumentCoordinatorProvider.overrideWith(
            (ref, videoId) => VideoDocumentCoordinator(docStorage),
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

  /// 会话内放一条启用局部镜像片段（模块唯一提交入口），返回它的半开区间。
  Future<LocalMirrorFragment> seedFragment(
    WidgetTester tester,
    ProviderContainer container, {
    Duration at = const Duration(seconds: 2),
  }) async {
    final outcome = container
        .read(annotationEditorProvider)
        .submit(AddLocalMirrorFragment(at: at));
    expect(outcome.applied, isTrue);
    await tester.pumpAndSettle();
    return container.read(localMirrorFragmentsProvider).single;
  }

  /// 位置即真值：seek 到 [ms]（暂停定格）并落定界面。
  Future<void> seekTo(
    WidgetTester tester,
    FakePlaybackEngine engine,
    int ms,
  ) async {
    await engine.pause();
    await engine.seek(Duration(milliseconds: ms));
    await tester.pumpAndSettle();
  }

  Finder mark() => find.byKey(kLocalMirrorPictureMarkKey);

  group('出现与消失（位置即真值）', () {
    testWidgets('生效于区间内出现；离开区间（含终点）立刻消失', (tester) async {
      setViewport(tester, logical: const Size(800, 600));
      final engine = FakePlaybackEngine(videoAspectRatio: 1);
      final container = await pumpPlayer(tester, engine: engine);
      final fragment = await seedFragment(tester, container);

      await seekTo(tester, engine, fragment.startMs + 10);
      expect(mark(), findsOneWidget, reason: '落在片段区间内：标识出现');

      await seekTo(tester, engine, fragment.startMs - 10);
      expect(mark(), findsNothing, reason: '区间起点之前：标识消失');

      await seekTo(tester, engine, fragment.endMs);
      expect(mark(), findsNothing, reason: '半开区间终点当刻不属于片段');
    });

    testWidgets('暂停定格 / 步进式 seek 同样跟随位置判定', (tester) async {
      setViewport(tester, logical: const Size(800, 600));
      final engine = FakePlaybackEngine(videoAspectRatio: 1);
      final container = await pumpPlayer(tester, engine: engine);
      final fragment = await seedFragment(tester, container);

      // 播放态下进入区间：标识出现。
      await seekTo(tester, engine, fragment.startMs + 10);
      expect(mark(), findsOneWidget);

      // 暂停定格在区间内仍出现（位置即真值，不看播放态）。
      await engine.pause();
      await tester.pumpAndSettle();
      expect(mark(), findsOneWidget, reason: '暂停定格不改变位置判定');

      // 步进到空隙：消失。
      await seekTo(tester, engine, fragment.endMs + 10);
      expect(mark(), findsNothing);
    });

    testWidgets('拖动定格（scrub）时标识跟随位置判定', (tester) async {
      setViewport(tester, logical: const Size(800, 600));
      final engine = FakePlaybackEngine(
        duration: const Duration(seconds: 60),
        videoAspectRatio: 1,
      );
      final container = await pumpPlayer(tester, engine: engine);
      final fragment = await seedFragment(tester, container);
      await seekTo(tester, engine, fragment.endMs + 1000);
      expect(mark(), findsNothing, reason: '起点在片段之后');

      // 单指水平拖动（每像素 50ms）：左拖若干步即把定格目标带进片段区间，
      // 手指未抬起时标识已跟随位置出现。
      final gesture = await tester.startGesture(const Offset(600, 300));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump();
      }
      expect(mark(), findsOneWidget, reason: '拖动定格进区间：手指未抬起即出现标识');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(mark(), findsOneWidget, reason: '松手后落点仍在区间内');
    });

    testWidgets('关掉总开关：区间内也不出现', (tester) async {
      setViewport(tester, logical: const Size(800, 600));
      final engine = FakePlaybackEngine(videoAspectRatio: 1);
      final container = await pumpPlayer(tester, engine: engine);
      final fragment = await seedFragment(tester, container);
      await seekTo(tester, engine, fragment.startMs + 10);
      expect(mark(), findsOneWidget);

      container.read(localMirrorEnabledProvider.notifier).replace(false);
      await tester.pumpAndSettle();
      expect(mark(), findsNothing, reason: '总开关关：标识不画');
    });

    testWidgets('没有任何局部镜像片段：整件不挂载（画面一位不变）', (tester) async {
      setViewport(tester, logical: const Size(800, 600));
      final engine = FakePlaybackEngine(videoAspectRatio: 1);
      final container = await pumpPlayer(tester, engine: engine);

      expect(container.read(localMirrorFragmentsProvider), isEmpty);
      expect(mark(), findsNothing);
    });

    testWidgets('全局镜像开着时照旧出现（标识说的是局部镜像在生效）', (tester) async {
      setViewport(tester, logical: const Size(800, 600));
      final engine = FakePlaybackEngine(videoAspectRatio: 1);
      final container = await pumpPlayer(
        tester,
        engine: engine,
        markers: const {
          'meta': {'mirrored': true, 'localMirrorEnabled': true},
        },
      );
      final fragment = await seedFragment(tester, container);
      await seekTo(tester, engine, fragment.startMs + 10);

      expect(mark(), findsOneWidget, reason: '全局镜像开不影响局部镜像标识');
    });
  });

  group('矩形与外观', () {
    testWidgets('边框贴画面内容矩形（信箱黑边除外）、向内 2dp 直角；角标内缩 8dp', (tester) async {
      // 方画面 800×600 → contain 内容矩形 (100,0,600,600)：左右各 100dp 信箱。
      setViewport(tester, logical: const Size(800, 600));
      final engine = FakePlaybackEngine(videoAspectRatio: 1);
      final container = await pumpPlayer(tester, engine: engine);
      final fragment = await seedFragment(tester, container);
      await seekTo(tester, engine, fragment.startMs + 10);

      final rect = tester.getRect(mark());
      expect(rect.left, closeTo(100, 0.001), reason: '左边信箱黑边之外不画');
      expect(rect.top, closeTo(0, 0.001));
      expect(rect.width, closeTo(600, 0.001));
      expect(rect.height, closeTo(600, 0.001));

      final border =
          (tester
                          .widget<DecoratedBox>(
                            find.byKey(kLocalMirrorPictureMarkBorderKey),
                          )
                          .decoration
                      as BoxDecoration)
                  .border!
              as Border;
      expect(border.top.width, kLocalMirrorPictureMarkBorderWidth);
      expect(border.top.color, kLocalMirrorEnabledColor);
      expect(
        (tester
                    .widget<DecoratedBox>(
                      find.byKey(kLocalMirrorPictureMarkBorderKey),
                    )
                    .decoration
                as BoxDecoration)
            .borderRadius,
        isNull,
        reason: '直角边框',
      );

      final badge = tester.getRect(find.byKey(kLocalMirrorPictureMarkBadgeKey));
      expect(
        badge.right,
        closeTo(rect.right - kLocalMirrorPictureMarkBadgeInset, 0.001),
      );
      expect(
        badge.bottom,
        closeTo(rect.bottom - kLocalMirrorPictureMarkBadgeInset, 0.001),
      );
    });

    testWidgets('角标带「局部镜像」文案与顶栏槽同款图标、同色', (tester) async {
      setViewport(tester, logical: const Size(800, 600));
      final engine = FakePlaybackEngine(videoAspectRatio: 1);
      final container = await pumpPlayer(tester, engine: engine);
      final fragment = await seedFragment(tester, container);
      await seekTo(tester, engine, fragment.startMs + 10);

      expect(find.text('局部镜像'), findsOneWidget);
      expect(find.byIcon(kLocalMirrorPictureMarkIcon), findsOneWidget);
      final text = tester.widget<Text>(find.text('局部镜像'));
      expect(text.style!.color, kLocalMirrorEnabledColor);
    });

    testWidgets('竖屏编辑态（贴底分支）：边框仍贴画面内容矩形', (tester) async {
      const screen = Size(360, 780);
      setViewport(tester, logical: screen);
      final engine = FakePlaybackEngine(videoAspectRatio: 16 / 9);
      final container = await pumpPlayer(tester, engine: engine);
      final fragment = await seedFragment(tester, container);
      await seekTo(tester, engine, fragment.startMs + 10);

      // 单击展开控制层（编辑态）。
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      expect(find.byType(ControlLayer), findsOneWidget);
      expect(mark(), findsOneWidget);

      final skeleton = editorSkeletonFor(
        screen: screen,
        trackBandHeight: TrackRowTable.normal.totalHeight,
        videoAspectRatio: engine.videoAspectRatio,
      );
      expect(skeleton.sticksToBottom, isTrue, reason: '本布景走画面带上移分支');
      final expected = videoContentRectInBox(
        box: Size(screen.width, skeleton.pictureBandHeight),
        aspectRatio: engine.videoAspectRatio,
      ).shift(Offset(0, skeleton.bandTopIn(systemTopInset: 0)));
      final rect = tester.getRect(mark());
      expect(rect.left, closeTo(expected.left, 0.001));
      expect(rect.top, closeTo(expected.top, 0.001));
      expect(rect.width, closeTo(expected.width, 0.001));
      expect(rect.height, closeTo(expected.height, 0.001));
    });
  });

  group('对比态：标识落在源视频半区', () {
    Future<ProviderContainer> enterCompare(
      WidgetTester tester,
      FakePlaybackEngine engine,
      ProviderContainer container,
    ) async {
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareWatching);
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('横屏：贴源视频半区的画面矩形（信箱黑边除外）；练习半区不出现', (tester) async {
      setViewport(tester, logical: const Size(800, 600));
      final engine = FakePlaybackEngine(videoAspectRatio: 16 / 9);
      final container = await pumpPlayer(tester, engine: engine);
      final fragment = await seedFragment(tester, container);
      await enterCompare(tester, engine, container);
      await seekTo(tester, engine, fragment.startMs + 10);
      expect(mark(), findsOneWidget);

      // 源半区 399×600 里 16:9 画面 contain：399×224.44，垂直居中。
      final rect = tester.getRect(mark());
      expect(rect.left, closeTo(0, 0.001));
      expect(rect.top, closeTo((600 - 399 * 9 / 16) / 2, 0.001));
      expect(rect.width, closeTo((800 - 2) / 2, 0.001), reason: '横屏左半区满宽');
      expect(
        rect.height,
        closeTo(399 * 9 / 16, 0.001),
        reason: '贴画面内容矩形、信箱黑边除外',
      );
      expect(rect.right, lessThanOrEqualTo(400), reason: '不越入练习半区');
    });

    testWidgets('竖屏：贴源视频上半区的画面矩形（信箱黑边除外）', (tester) async {
      setViewport(tester, logical: const Size(600, 800));
      final engine = FakePlaybackEngine(videoAspectRatio: 16 / 9);
      final container = await pumpPlayer(tester, engine: engine);
      final fragment = await seedFragment(tester, container);
      await enterCompare(tester, engine, container);
      await seekTo(tester, engine, fragment.startMs + 10);
      expect(mark(), findsOneWidget);

      // 源半区 600×399 里 16:9 画面 contain：600×337.5，垂直居中。
      final rect = tester.getRect(mark());
      expect(rect.left, closeTo(0, 0.001));
      expect(rect.top, closeTo((399 - 600 * 9 / 16) / 2, 0.001));
      expect(rect.width, closeTo(600, 0.001), reason: '竖屏上半区满宽');
      expect(rect.height, closeTo(600 * 9 / 16, 0.001));
      expect(rect.bottom, lessThanOrEqualTo(400), reason: '不越入练习半区');
    });
  });

  group('层序与触摸', () {
    testWidgets('在共享 Stack 里位于视频画面之后、节拍浮层与备注贴纸之前', (tester) async {
      setViewport(tester, logical: const Size(800, 600));
      final engine = FakePlaybackEngine(videoAspectRatio: 1);
      final container = await pumpPlayer(tester, engine: engine);
      final fragment = await seedFragment(tester, container);
      await seekTo(tester, engine, fragment.startMs + 10);
      expect(mark(), findsOneWidget);

      final surface = find.byKey(const Key('player_surface'));
      final sticker = find.byType(NoteStickerOverlay);

      final belowStack = sharedStackOf(tester, mark(), surface);
      expect(
        paintIndexOf(belowStack, tester.element(mark())),
        greaterThan(paintIndexOf(belowStack, tester.element(surface))),
        reason: '标识绘制在视频画面之后',
      );

      final aboveStack = sharedStackOf(tester, mark(), sticker);
      expect(
        paintIndexOf(aboveStack, tester.element(mark())),
        lessThan(paintIndexOf(aboveStack, tester.element(sticker))),
        reason: '标识绘制在备注贴纸之前（用户浮层压在它之上）',
      );

      // 节拍动画浮层（数拍跟练）同样压在标识之上。
      turnBeatAnimationOn(tester);
      await tester.pump();
      expect(find.byType(MetronomeOverlay), findsOneWidget);
      final beatStack = sharedStackOf(
        tester,
        mark(),
        find.byType(MetronomeOverlay),
      );
      expect(
        paintIndexOf(beatStack, tester.element(mark())),
        lessThan(
          paintIndexOf(
            beatStack,
            tester.element(find.byType(MetronomeOverlay)),
          ),
        ),
        reason: '标识绘制在节拍动画浮层之前',
      );
    });

    testWidgets('整件不吃触摸：点在角标上仍穿透到播放手势层', (tester) async {
      setViewport(tester, logical: const Size(800, 600));
      final engine = FakePlaybackEngine(videoAspectRatio: 1);
      final container = await pumpPlayer(tester, engine: engine);
      final fragment = await seedFragment(tester, container);
      await seekTo(tester, engine, fragment.startMs + 10);

      expect(
        tester.widget<IgnorePointer>(mark()).ignoring,
        isTrue,
        reason: '标识不进命中测试',
      );

      final badgeCenter = tester
          .getRect(find.byKey(kLocalMirrorPictureMarkBadgeKey))
          .center;
      await tester.tapAt(badgeCenter);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      expect(find.byType(ControlLayer), findsOneWidget, reason: '点角标穿透到播放手势层');
    });
  });
}
