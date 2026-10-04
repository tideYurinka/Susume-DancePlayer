import 'dart:io';

import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/persistence/material_manifest.dart'
    show materialRecordingFileResolverProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/help/guide_anchor.dart'
    show GuideAnchor, GuideBadgeTrigger;
import 'package:dance_learning_app/help/guide_state.dart'
    show guideSessionProvider;
import 'package:dance_learning_app/player/annotation_edit.dart'
    show AddLocalMirrorFragment;
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player/av_sync.dart'
    show
        AudioOutputDeviceController,
        AvSyncDeviceInfo,
        audioOutputDeviceControllerProvider;
import 'package:dance_learning_app/player/av_sync_session.dart'
    show avSyncCalibrationSessionProvider;
import 'package:dance_learning_app/player/beat_animation.dart'
    show BeatAnimationStyle, beatAnimationStyleProvider;
import 'package:dance_learning_app/player/compare_recording.dart'
    show CompareRecordingPhase, compareRecordingPhaseProvider;
import 'package:dance_learning_app/player/metronome_overlay.dart'
    show MetronomeOverlay, overlayPlacementProvider;
import 'package:dance_learning_app/player/overlay.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationEditorProvider, localMirrorFragmentsProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;

import '../helpers/video_surface.dart' show videoSurfacePlaceholderKey;

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';

import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/device_viewport.dart';

class _FakeAudioOutputDeviceController implements AudioOutputDeviceController {
  @override
  Future<AvSyncDeviceInfo?> get() async => null;

  @override
  Stream<AvSyncDeviceInfo?> get deviceStream =>
      const Stream<AvSyncDeviceInfo?>.empty();
}

void main() {
  group('对比态会话与入口', () {
    late FakePlaybackEngine engine;
    late FakeSystemUi systemUi;
    late FakeCameraCaptureService camera;

    void setWideView(WidgetTester tester) {
      tester.view.physicalSize = const Size(
        1920,
        1080,
      ); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    /// 竖屏逻辑尺寸（800 × 1400）：分屏上下断言用。
    void setPortraitView(WidgetTester tester) {
      tester.view.physicalSize = const Size(
        1600,
        2800,
      ); // 合成档 800.0×1400.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    Future<void> pumpPlayer(
      WidgetTester tester, {
      bool avSyncSeam = false,
    }) async {
      final source = Uri.file('/videos/a.mp4');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            cameraCaptureProvider.overrideWithValue(camera),
            privateJsonStorageProvider.overrideWithValue(
              InMemoryPrivateJsonStorage(),
            ),
            systemUiControllerProvider.overrideWithValue(systemUi),
            if (avSyncSeam)
              audioOutputDeviceControllerProvider.overrideWithValue(
                _FakeAudioOutputDeviceController(),
              ),
            // 录制钮命中用例要走到「已离开待录态」：素材输出路径必须可解析
            // （真实现走 path_provider，widget 测试里抛 MissingPluginException
            // 即按起录失败收尾、阶段落回 idle，命中与否就测不出来了）。
            materialRecordingFileResolverProvider.overrideWithValue(
              (videoId) async => File('/tmp/cmp_entry_rec.mp4'),
            ),
            // 素材必须归属舞：videoId 未解析时起录按失败收尾（阶段落回
            // idle），命中与否就测不出来了——故注入可读的按视频文档。
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => InMemoryVideoDocumentStorage(),
            ),
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
      // 节拍动画总开关默认关——本组用例针对数拍浮层机制，先置开。
      turnBeatAnimationOn(tester);
      await tester.pump();
    }

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(PlayerPage)),
          listen: false,
        );

    PlayerSessionMode modeOf(WidgetTester tester) =>
        containerOf(tester).read(playerSessionProvider).mode;

    Future<void> singleTapShow(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
    }

    /// 双击：两次 tap 间隔 < 双击窗口（复用 control_layer_test 语义）。
    Future<void> doubleTap(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 50));
    }

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      systemUi = FakeSystemUi();
      camera = FakeCameraCaptureService();
    });

    testWidgets('顶栏槽改名「对比练习」且可点', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);

      expect(find.text('对比练习'), findsOneWidget);
      expect(find.text('对比播放'), findsNothing);

      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      expect(modeOf(tester), PlayerSessionMode.compareWatching);
    });

    testWidgets('进对比态不产生引导触达：录制钮上没有锚点包装与触达器', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);

      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      expect(modeOf(tester), PlayerSessionMode.compareWatching);

      // 常驻录制钮照常在屏（对比态行为逐位不变），但它不再承载引导：
      // 既没有锚点包装，也没有触达器（对比练习单元整体撤下）。
      final recordButton = find.byKey(const Key('compare_record_button'));
      expect(recordButton, findsOneWidget);
      expect(
        find.ancestor(of: recordButton, matching: find.byType(GuideAnchor)),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: recordButton,
          matching: find.byType(GuideBadgeTrigger),
        ),
        findsNothing,
      );
      expect(
        containerOf(tester).read(guideSessionProvider).triggered,
        isNot(contains('badge_compare')),
      );
    });

    testWidgets('点槽进入对比-播放态：控制层收起、分屏两块、播放中续播、引擎零 seek/暂停', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await engine.play();
      await tester.pump();
      final callsBefore = List<String>.of(engine.callLog);

      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      expect(modeOf(tester), PlayerSessionMode.compareWatching);
      expect(find.byKey(const Key('control_layer')), findsNothing);
      // 续播：进入不暂停、不 seek（时间线与播放位置不动）。
      expect(engine.isPlaying, isTrue);
      expect(
        engine.callLog
            .skip(callsBefore.length)
            .where((c) => c.startsWith('pause') || c.startsWith('seek')),
        isEmpty,
      );
      // 分屏两块：源侧 + 练习侧相机预览（fake）。
      expect(find.byKey(videoSurfacePlaceholderKey), findsOneWidget);
      expect(find.byKey(const Key('fake_camera_preview')), findsOneWidget);
    });

    testWidgets('横屏分屏：源侧左半、练习侧右半、之间留细缝', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      final view = tester.view.physicalSize / tester.view.devicePixelRatio;
      final sourceRect = tester.getRect(find.byKey(videoSurfacePlaceholderKey));
      final practiceRect = tester.getRect(
        find.byKey(const Key('fake_camera_preview')),
      );
      expect(sourceRect.center.dx, lessThan(view.width / 2));
      expect(practiceRect.center.dx, greaterThan(view.width / 2));
      // 细缝：两块之间留缝但不宽。
      final gap = practiceRect.left - sourceRect.right;
      expect(gap, greaterThan(0));
      expect(gap, lessThanOrEqualTo(4));
    });

    testWidgets('竖屏分屏：源侧上半、练习侧下半', (tester) async {
      setPortraitView(tester);
      await pumpPlayer(tester);
      containerOf(tester)
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareWatching);
      await tester.pumpAndSettle();

      final view = tester.view.physicalSize / tester.view.devicePixelRatio;
      final sourceRect = tester.getRect(find.byKey(videoSurfacePlaceholderKey));
      final practiceRect = tester.getRect(
        find.byKey(const Key('fake_camera_preview')),
      );
      expect(sourceRect.center.dy, lessThan(view.height / 2));
      expect(practiceRect.center.dy, greaterThan(view.height / 2));
    });

    testWidgets('对比-播放态单击画面：直接唤出对比-控制层', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      await singleTapShow(tester);
      await tester.pumpAndSettle();

      expect(modeOf(tester), PlayerSessionMode.compareEditing);
      expect(find.byKey(const Key('control_layer')), findsOneWidget);
    });

    testWidgets('对比态内槽高亮；再点退出对比态回单画面（编辑面）', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      // 唤出对比-控制层：槽可见。
      await singleTapShow(tester);
      await tester.pumpAndSettle();

      // 高亮 = 槽内图标琥珀。
      final iconColor = tester
          .widget<Icon>(
            find
                .descendant(
                  of: find.byKey(const Key('tool_compare')),
                  matching: find.byType(Icon),
                )
                .first,
          )
          .color;
      expect(iconColor, kHighlightAmber);

      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      expect(modeOf(tester), PlayerSessionMode.editing);
      expect(
        containerOf(tester).read(playerSessionProvider).isCompare,
        isFalse,
      );
    });

    testWidgets('对比-播放态既有播放手势照常：双击暂停（冒烟）', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      await engine.play();
      await tester.pump();
      expect(engine.isPlaying, isTrue);

      await doubleTap(tester);
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
    });

    testWidgets('对比态内返回箭头先退对比态（回 watching 单画面）、再按才回首页', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      await singleTapShow(tester);
      await tester.pumpAndSettle();

      // 第一次返回：退对比态回单画面（watching，控制层随退出收起），不离
      // 开播放页；再按（系统返回）才回首页——该段为既有行为，不在本用例范围。
      await tester.tap(find.byKey(const Key('control_layer_back')));
      await tester.pumpAndSettle();
      expect(modeOf(tester), PlayerSessionMode.watching);
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(find.byKey(const Key('control_layer')), findsNothing);
    });

    testWidgets('对比-播放态系统返回：先退对比态回单画面，不离开播放页', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(modeOf(tester), PlayerSessionMode.watching);
      expect(find.byType(PlayerPage), findsOneWidget);
    });

    testWidgets('方向锁听模式值：进对比-控制层零锁、收起零方向请求', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      final locksBefore = systemUi.lockLandscapeCount;

      containerOf(tester)
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await tester.pumpAndSettle();
      expect(systemUi.lockLandscapeCount, locksBefore, reason: '进编辑面不锁方向');

      // 收起控制层不再有任何方向副作用：对比-控制层收起退到对比-播放态。
      containerOf(tester).read(playerSessionProvider.notifier).collapse();
      await tester.pumpAndSettle();
      expect(modeOf(tester), PlayerSessionMode.compareWatching);
      expect(systemUi.lockLandscapeCount, locksBefore);
    });

    testWidgets('互斥：校准会话进行中拒绝进入对比态（模式一位不动、会话不退出）', (tester) async {
      // 平板横置（常规档）：三枚仍内联常驻顶栏，「音画同步」按槽键直定位。
      useNamedViewport(tester, ViewportTier.tablet, landscape: true);
      await pumpPlayer(tester, avSyncSeam: true);
      await singleTapShow(tester);
      // 点「音画同步」开气泡（挂载即进入校准会话）：进入是异步链（设备
      // 快照 + 存储读），定步泵推进至活跃（会话时钟常转，不 pumpAndSettle）。
      await tester.tap(find.byKey(const Key('tool_av_sync')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        containerOf(tester).read(avSyncCalibrationSessionProvider).active,
        isTrue,
      );

      // 会话进行中请求进入对比态（经待办槽驱动宿主编排）：拒绝 = 模式
      // 一位不动、待办清空、会话不退出（气泡遮罩覆盖顶栏槽，故不经点击）。
      containerOf(tester)
          .read(playerSessionProvider.notifier)
          .requestEntry(PlayerSessionMode.compareWatching);
      await tester.pump();
      await tester.pump();

      expect(modeOf(tester), PlayerSessionMode.editing);
      expect(
        containerOf(tester).read(playerSessionProvider).pendingEntry,
        isNull,
      );
      expect(
        containerOf(tester).read(avSyncCalibrationSessionProvider).active,
        isTrue,
      );
    });

    testWidgets('互斥反向：对比态内进校准会话先退对比态', (tester) async {
      // 平板横置（常规档）：三枚仍内联常驻顶栏，「音画同步」按槽键直定位。
      useNamedViewport(tester, ViewportTier.tablet, landscape: true);
      await pumpPlayer(tester, avSyncSeam: true);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      expect(modeOf(tester), PlayerSessionMode.compareWatching);

      // 唤出对比-控制层后点「音画同步」工具：互斥接线先退对比态，气泡
      // 挂载即进入校准会话（异步链定步泵推进，会话时钟常转不 pumpAndSettle）。
      await singleTapShow(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tool_av_sync')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(modeOf(tester), PlayerSessionMode.editing);
      expect(
        containerOf(tester).read(avSyncCalibrationSessionProvider).active,
        isTrue,
      );
    });

    // ── 对比态浮层钳制盒放开（= 播放页整屏）───────────────────
    // 断言落在行为面：真拖动 / 真缩放的落点与上限、
    // 进对比态不迁移已保存位、浮层压住录制钮时钮照常可点。
    group('对比态浮层钳制盒 = 播放页整屏', () {
      Size viewOf(WidgetTester tester) =>
          tester.view.physicalSize / tester.view.devicePixelRatio;

      Rect overlayRect(WidgetTester tester) =>
          tester.getRect(find.byKey(const Key('metronome_overlay_selected')));

      /// 内容类声明的钳制盒（宿主注入值；浮层可见时经浮层实例读取）。
      Size injectedClampBoxOf(WidgetTester tester) => tester
          .widget<MetronomeOverlay>(find.byType(MetronomeOverlay))
          .controller
          .clampBox!;

      /// 经进入声明表进对比-播放态（对照：既有入口用例走「点槽」路径）。
      Future<void> enterCompare(WidgetTester tester) async {
        containerOf(tester)
            .read(playerSessionProvider.notifier)
            .enter(PlayerSessionMode.compareWatching);
        await tester.pumpAndSettle();
      }

      /// 设备等效视口竖屏（真机的 2736×1264 @3.5 转竖屏 ⇒ 361.1 × 781.7 dp）：
      /// 页宽 361.1 dp 下矩形/摆锤的尺寸上限都由**页宽**分母顶着
      /// （361.1/320 = 1.13、361.1/220 = 1.64，都低于相对上限 2.5）。
      void setDevicePortraitView(WidgetTester tester) {
        useNamedViewport(tester, ViewportTier.compact);
      }

      /// 点选浮层：[at] 缺省取浮层当前渲染矩形的中心（默认位随视口现算，
      /// 不再是固定的屏左上；起手点须落在浮层命中矩形内）。
      Future<void> selectOverlay(WidgetTester tester, {Offset? at}) async {
        final point =
            at ?? tester.getRect(find.byType(MetronomeOverlay)).center;
        final gesture = await tester.startGesture(point);
        await gesture.up();
        await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
        await tester.pump();
        expect(
          find.byKey(const Key('metronome_overlay_selected')),
          findsOneWidget,
        );
      }

      /// 选中态单指主体拖动：从浮层中心起手，按 [steps] 帧 × [delta] 步进
      /// （每帧一泵），松手收敛。
      Future<void> dragOverlay(
        WidgetTester tester, {
        required Offset delta,
        int steps = 20,
      }) async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('metronome_overlay_selected'))),
        );
        await tester.pump();
        for (var i = 0; i < steps; i++) {
          await gesture.moveBy(delta);
          await tester.pump();
        }
        await gesture.up();
        await tester.pumpAndSettle();
      }

      /// 选中态两指外张到上限（起手一指落浮层上、一指出框 = 混区照样缩放）。
      Future<void> spreadToMax(WidgetTester tester) async {
        final g1 = await tester.startGesture(const Offset(300, 60));
        final g2 = await tester.startGesture(const Offset(340, 60));
        await tester.pump();
        for (var i = 0; i < 12; i++) {
          await g1.moveBy(const Offset(-40, 0));
          await g2.moveBy(const Offset(40, 0));
          await tester.pump();
        }
        await g1.up();
        await g2.up();
        await tester.pumpAndSettle();
      }

      testWidgets('横屏：钳制盒 = 播放页整屏；四格默认位同款（贴左、视口高 12%）', (tester) async {
        setWideView(tester);
        await pumpPlayer(tester);
        final view = viewOf(tester);
        final defaultTopLeft = Offset(0, view.height * 0.12);

        // 单画面态基准：钳制盒 = 整屏、未自定义位 = 贴左 12%。
        expect(injectedClampBoxOf(tester), view);
        await selectOverlay(tester);
        expect(overlayRect(tester).topLeft, defaultTopLeft);

        await enterCompare(tester);
        expect(modeOf(tester), PlayerSessionMode.compareWatching);
        expect(injectedClampBoxOf(tester), view);
        // 对比格未自定义 → 同款默认位。
        expect(overlayRect(tester).topLeft, defaultTopLeft);

        // 对比-控制层展开时不收缩钳制盒（维持现状：此时浮层只读、拖不动，
        // 不会在控制层展开中被拖到看不见的地方）。
        containerOf(tester)
            .read(playerSessionProvider.notifier)
            .enter(PlayerSessionMode.compareEditing);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('control_layer')), findsOneWidget);
        expect(injectedClampBoxOf(tester), view);
      });

      testWidgets('竖屏：钳制盒 = 播放页整屏（分屏方向不改变盒子取值）', (tester) async {
        setPortraitView(tester);
        await pumpPlayer(tester);
        final view = viewOf(tester);

        await enterCompare(tester);
        expect(injectedClampBoxOf(tester), view);
      });

      testWidgets('已保存位按格分离：进对比态取对比格（未自定义 = 默认位）、普通格值不变', (tester) async {
        setWideView(tester);
        await pumpPlayer(tester);
        final view = viewOf(tester);
        // 恢复路径的会话态写入（= 既有已保存位）：落在横屏·普通格。
        containerOf(tester)
            .read(overlayPlacementProvider.notifier)
            .set(
              const OverlayPlacements(
                offsets: {
                  OverlayPlacementCell.landscapeNormal: Offset(500, 300),
                },
              ),
            );
        await tester.pumpAndSettle();

        await selectOverlay(tester);
        expect(overlayRect(tester).topLeft, const Offset(500, 300));

        await enterCompare(tester);
        // 对比态取对比格：未自定义 → 按当前视口现算的默认位；普通格的值
        // 一字不改（切格不回写）。
        expect(overlayRect(tester).topLeft, Offset(0, view.height * 0.12));
        expect(
          containerOf(tester)
              .read(overlayPlacementProvider)!
              .offsetFor(OverlayPlacementCell.landscapeNormal),
          const Offset(500, 300),
        );
      });

      testWidgets('横屏：浮层可拖过中线、右贴边、压在练习侧相机预览上', (tester) async {
        setWideView(tester);
        await pumpPlayer(tester);
        await enterCompare(tester);
        await selectOverlay(tester);

        final view = viewOf(tester);
        await dragOverlay(tester, delta: const Offset(100, 10));

        final rect = overlayRect(tester);
        // 整屏钳制：右缘贴屏幕右缘（源侧半区钳制下右缘止步半宽 480）。
        expect(rect.right, closeTo(view.width, 0.01));
        // 浮层整体进了练习侧半区，并真的压在练习侧相机预览上。
        expect(rect.left, greaterThan(view.width / 2));
        final practiceRect = tester.getRect(
          find.byKey(const Key('fake_camera_preview')),
        );
        expect(practiceRect.center.dx, greaterThan(view.width / 2));
        expect(rect.overlaps(practiceRect), isTrue);
      });

      testWidgets('竖屏：浮层可拖过中线进下半区、压在练习侧相机预览上', (tester) async {
        setPortraitView(tester);
        await pumpPlayer(tester);
        await enterCompare(tester);
        await selectOverlay(tester);

        final view = viewOf(tester);
        await dragOverlay(tester, delta: const Offset(0, 50));

        final rect = overlayRect(tester);
        // 位置原样落地：默认位（贴左、视口高 12%）+ 20 帧 × 50。
        expect(rect.top, closeTo(view.height * 0.12 + 1000, 0.5));
        expect(rect.top, greaterThan(view.height / 2));
        final practiceRect = tester.getRect(
          find.byKey(const Key('fake_camera_preview')),
        );
        expect(practiceRect.center.dy, greaterThan(view.height / 2));
        expect(rect.overlaps(practiceRect), isTrue);
      });

      testWidgets('拖出左上边界（负偏移）→ 钳回屏左上原点', (tester) async {
        setWideView(tester);
        await pumpPlayer(tester);
        await enterCompare(tester);
        await selectOverlay(tester);

        // 先拖进屏幕中间，再反向拖出左上边界。
        await dragOverlay(tester, delta: const Offset(50, 20), steps: 10);
        expect(
          overlayRect(tester).topLeft,
          Offset(500, viewOf(tester).height * 0.12 + 200),
        );
        await dragOverlay(tester, delta: const Offset(-100, -100));
        expect(overlayRect(tester).topLeft, Offset.zero);
      });

      testWidgets('设备等效视口（竖屏 361.1 dp 宽）：尺寸上限吃「页宽」分母', (tester) async {
        setDevicePortraitView(tester);
        await pumpPlayer(tester);
        await enterCompare(tester);
        await selectOverlay(tester);

        final view = viewOf(tester);
        await spreadToMax(tester);
        // 页宽 361.1 < 320 × 2.5 ⇒ 生效上限 = 页宽/320 = 1.13×（相对上限
        // 让位）：实宽恰铺满页宽；分母写错（或仍用半区盒）会溢出页宽。
        expect(overlayRect(tester).width, closeTo(view.width, 0.01));

        final container = containerOf(tester);
        container
            .read(beatAnimationStyleProvider.notifier)
            .set(BeatAnimationStyle.pendulum);
        await tester.pumpAndSettle();
        await spreadToMax(tester);
        final pendulum = overlayRect(tester);
        // 摆锤同样吃页宽分母（页宽/220 = 1.64×），且整体等比：高 = 宽 × 120/220。
        expect(pendulum.width, closeTo(view.width, 0.01));
        expect(pendulum.height / pendulum.width, closeTo(120 / 220, 0.001));
      });

      testWidgets('尺寸上限按整屏推导：矩形钳到 2.5×（800 宽）、摆锤钳到 2.5×（550×300）', (
        tester,
      ) async {
        setWideView(tester);
        await pumpPlayer(tester);
        await enterCompare(tester);
        await selectOverlay(tester);

        await spreadToMax(tester);
        // 矩形：宽系数上限 2.5 ⇒ 实宽 320 × 2.5 = 800、高固定 120
        // （源侧半区钳制下宽上限被压到 480/320 = 1.5 ⇒ 只能 480）。
        // 默认位带小数纵向偏移，getRect 的 size 有 1e-13 量级浮点误差。
        expect(overlayRect(tester).width, closeTo(800, 0.001));
        expect(overlayRect(tester).height, closeTo(120, 0.001));

        final container = containerOf(tester);
        container
            .read(beatAnimationStyleProvider.notifier)
            .set(BeatAnimationStyle.pendulum);
        await tester.pumpAndSettle();
        expect(
          container.read(beatAnimationStyleProvider),
          BeatAnimationStyle.pendulum,
        );
        await spreadToMax(tester);
        // 摆锤：等比上限 2.5 ⇒ 实尺寸 220 × 2.5 = 550、120 × 2.5 = 300
        // （源侧半区钳制下宽维更紧 480/220 = 2.18）。
        expect(overlayRect(tester).width, closeTo(550, 0.001));
        expect(overlayRect(tester).height, closeTo(300, 0.001));
      });

      testWidgets('浮层压到录制钮上时，录制钮仍可点（命中不被浮层吃掉）', (tester) async {
        setWideView(tester);
        await pumpPlayer(tester);
        await enterCompare(tester);
        await selectOverlay(tester);

        // 拖到浮层中心正对录制钮：整屏钳制下浮层可到画面任意处（旧落位在
        // 右下角、新落位在底部居中，命中不被吃掉的判据与钮的位置无关）。
        const steps = 20;
        final recordRect = tester.getRect(
          find.byKey(const Key('compare_record_button')),
        );
        final overlayCenter = tester
            .getRect(find.byKey(const Key('metronome_overlay_selected')))
            .center;
        await dragOverlay(
          tester,
          steps: steps,
          delta: (recordRect.center - overlayCenter) / steps.toDouble(),
        );
        final rect = overlayRect(tester);
        expect(rect.contains(recordRect.center), isTrue, reason: '前置：浮层压住录制钮');

        // 点录制钮：命中真落到钮上（离开待录态），且没被浮层吃掉、也没误开
        // 对比-控制层。
        await tester.tap(find.byKey(const Key('compare_record_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        expect(
          containerOf(tester).read(compareRecordingPhaseProvider),
          isNot(CompareRecordingPhase.idle),
        );
        expect(modeOf(tester), PlayerSessionMode.compareWatching);
      });
    });
  });

  group('对比-控制层轨道行集与源侧效果', () {
    late FakePlaybackEngine engine;
    late FakeSystemUi systemUi;

    void setWideView(WidgetTester tester) {
      tester.view.physicalSize = const Size(
        1920,
        1080,
      ); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    /// 平板视口（820 × 1180 dp，最短边 ≥ 600 → 常规档）：空轨仍常驻、
    /// 按全行集声明断言的用例钉在这一档。
    void setTableView(WidgetTester tester) {
      useNamedViewport(tester, ViewportTier.tablet);
    }

    Future<void> pumpPlayer(WidgetTester tester) async {
      final source = Uri.file('/videos/a.mp4');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            privateJsonStorageProvider.overrideWithValue(
              InMemoryPrivateJsonStorage(),
            ),
            systemUiControllerProvider.overrideWithValue(systemUi),
            // 录制钮命中用例要走到「已离开待录态」：素材输出路径必须可解析
            // （真实现走 path_provider，widget 测试里抛 MissingPluginException
            // 即按起录失败收尾、阶段落回 idle，命中与否就测不出来了）。
            materialRecordingFileResolverProvider.overrideWithValue(
              (videoId) async => File('/tmp/cmp_entry_rec.mp4'),
            ),
            // 素材必须归属舞：videoId 未解析时起录按失败收尾（阶段落回
            // idle），命中与否就测不出来了——故注入可读的按视频文档。
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => InMemoryVideoDocumentStorage(),
            ),
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
      // 节拍动画总开关默认关——本组用例针对数拍浮层机制，先置开。
      turnBeatAnimationOn(tester);
      await tester.pump();
    }

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(PlayerPage)),
          listen: false,
        );

    /// 经进入声明表进对比-播放态、再单击唤出对比-控制层。
    Future<void> enterCompareEditing(WidgetTester tester) async {
      containerOf(tester)
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareWatching);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      expect(
        containerOf(tester).read(playerSessionProvider).mode,
        PlayerSessionMode.compareEditing,
      );
    }

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      systemUi = FakeSystemUi();
    });

    testWidgets('紧凑档对比-控制层：空备注轨不占行，练习视频轨在其下常驻；'
        '无局部镜像轨与手柄带行', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await enterCompareEditing(tester);

      final bandTop = tester.getTopLeft(find.byKey(const Key('track_band'))).dy;
      // 紧凑档下一条备注都没有：备注轨整行（行背景 + 片头标签）不占地方。
      expect(find.byKey(const Key('track_notes')), findsNothing);
      expect(find.byKey(const Key('track_prefix_label_note')), findsNothing);
      // 练习视频轨顶到带顶、48dp 常驻空行。
      final practiceTop = tester
          .getTopLeft(find.byKey(const Key('track_practice')))
          .dy;
      expect(practiceTop, bandTop);
      expect(
        tester.getSize(find.byKey(const Key('track_practice'))).height,
        48,
      );
      expect(
        find.byKey(const ValueKey('track_prefix_label_practiceVideo')),
        findsOneWidget,
      );
      // 无局部镜像轨、无轨道手柄带行。
      expect(find.byKey(const Key('track_mirror')), findsNothing);
      expect(find.byKey(const Key('track_handle_strip_row')), findsNothing);
    });

    testWidgets('常规档（平板）对比-控制层：空备注轨仍常驻在最顶，练习视频轨在其下', (tester) async {
      setTableView(tester);
      await pumpPlayer(tester);
      await enterCompareEditing(tester);

      final bandTop = tester.getTopLeft(find.byKey(const Key('track_band'))).dy;
      final notesTop = tester
          .getTopLeft(find.byKey(const Key('track_notes')))
          .dy;
      final practiceTop = tester
          .getTopLeft(find.byKey(const Key('track_practice')))
          .dy;
      // 常规档空轨常驻：备注轨最顶，练习视频轨在其下、48dp 空行。
      expect(notesTop, bandTop);
      expect(practiceTop, greaterThan(notesTop));
      expect(
        tester.getSize(find.byKey(const Key('track_practice'))).height,
        48,
      );
      // 行集本身的差异与档位无关：无局部镜像轨、无轨道手柄带行。
      expect(find.byKey(const Key('track_mirror')), findsNothing);
      expect(find.byKey(const Key('track_handle_strip_row')), findsNothing);
    });

    testWidgets('跨面一致性：常规档对比-控制层实际渲染的行键 == 对比全行集声明逐位相等', (tester) async {
      setTableView(tester);
      await pumpPlayer(tester);
      await enterCompareEditing(tester);

      // 声明 = 实际渲染：次序即声明次序（构造点映射 compareEditing →
      // compare 全行集；常规档不剪裁，渲染行不可能漏项或乱序）。
      final declared = [for (final row in TrackRowTable.compare.rows) row.key];
      final rendered = find
          .descendant(
            of: find.byKey(const Key('track_band')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  declared.contains((widget.key as ValueKey<String>).value),
            ),
          )
          .evaluate()
          .map((element) => (element.widget.key as ValueKey<String>).value)
          .toList();
      expect(rendered, declared);
    });

    testWidgets('退出对比态回编辑面：轨道带恢复 normal 行集（局部镜像轨回来）', (tester) async {
      setTableView(tester);
      await pumpPlayer(tester);
      await enterCompareEditing(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('track_mirror')), findsOneWidget);
      expect(find.byKey(const Key('track_handle_strip_row')), findsOneWidget);
    });

    testWidgets('行藏、效果不藏：局部镜像片段的画面反相在对比态源侧照常生效', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      final container = containerOf(tester);
      // 会话内放一条启用片段（模块唯一提交入口，占位网格下默认一八拍宽）。
      final outcome = container
          .read(annotationEditorProvider)
          .submit(const AddLocalMirrorFragment(at: Duration(seconds: 2)));
      expect(outcome.applied, isTrue);
      final fragment = container.read(localMirrorFragmentsProvider).single;

      Future<void> pauseAt(Duration position) async {
        await engine.pause();
        await engine.seek(position);
        await tester.pump();
      }

      // 进入对比态（行集里没有局部镜像轨）。
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareWatching);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('track_mirror')), findsNothing);

      // 定格片段内 → 源侧画面反相；定格片段外 → 恢复原相。
      await pauseAt(Duration(milliseconds: fragment.startMs + 100));
      expect(find.byKey(const Key('mirrored_surface')), findsOneWidget);
      await pauseAt(Duration(milliseconds: fragment.endMs + 1000));
      expect(find.byKey(const Key('mirrored_surface')), findsNothing);
    });
  });
}
