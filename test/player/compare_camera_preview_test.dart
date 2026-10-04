import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/practice_mirror.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/settings_persistence.dart'
    show videoDocumentCoordinatorProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart'
    show VideoDocumentCoordinator;
import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show FaceDirection, SurfaceFace;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/android_camera_platform.dart';
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/practice_mirror_surface.dart';
import '../helpers/video_index_fixtures.dart';

void main() {
  group('相机采集与实时预览', () {
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

    Future<void> pumpPlayer(WidgetTester tester) async {
      final source = Uri.file('/videos/a.mp4');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            cameraCaptureProvider.overrideWithValue(camera),
            androidCameraPlatform(),
            privateJsonStorageProvider.overrideWithValue(
              InMemoryPrivateJsonStorage(),
            ),
            systemUiControllerProvider.overrideWithValue(systemUi),
            contentHasherProvider.overrideWithValue(
              const FixedHasher('seeded'),
            ),
            // 打开会话读两份文档走内存实现（真实实现走 path_provider，在
            // flutter_test 的 fake async 时钟下不完成）。
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => InMemoryVideoDocumentStorage(),
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

    PlayerSessionMode modeOf(WidgetTester tester) =>
        containerOf(tester).read(playerSessionProvider).mode;

    Future<void> singleTapShow(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
    }

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      systemUi = FakeSystemUi();
      camera = FakeCameraCaptureService();
    });

    testWidgets('进入对比态：相机授权（已授）→ 预览件挂练习半区、开一次流', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);

      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      expect(modeOf(tester), PlayerSessionMode.compareWatching);
      expect(find.byKey(const Key('fake_camera_preview')), findsOneWidget);
      expect(camera.requestPermissionCount, 1);
      expect(camera.startCount, 1);
      expect(camera.stopCount, 0);
    });

    testWidgets('离开对比态：预览关闭（关一次流）；练习半区预览件随分屏退场', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      containerOf(tester).read(playerSessionProvider.notifier).exitCompare();
      await tester.pumpAndSettle();

      expect(modeOf(tester), PlayerSessionMode.watching);
      expect(find.byKey(const Key('fake_camera_preview')), findsNothing);
      expect(camera.startCount, 1);
      expect(camera.stopCount, 1);
    });

    testWidgets('权限拒绝：不进入对比态（模式一位不动、待办清空、零开流），可重试路径', (tester) async {
      setWideView(tester);
      camera.permissionResult = CameraPermissionStatus.denied;
      await pumpPlayer(tester);
      await singleTapShow(tester);

      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      // 拒绝 = 不进入对比态、零副作用；重试弹窗未决期间待办在槽（用户
      // 可重试），模式值不动、零开流。
      expect(modeOf(tester), PlayerSessionMode.editing);
      expect(
        containerOf(tester).read(playerSessionProvider).pendingEntry,
        isNotNull,
      );
      expect(camera.startCount, 0);
      expect(find.byKey(const Key('camera_permission_dialog')), findsOneWidget);

      // 重试：再次询问被系统拒为永久拒绝 → 提示换「去系统设置」路径。
      await tester.tap(find.byKey(const Key('camera_permission_retry')));
      await tester.pumpAndSettle();
      expect(camera.requestPermissionCount, 2);
      expect(
        find.byKey(const Key('camera_permission_open_settings')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('camera_permission_retry')), findsNothing);

      // 去系统设置：跳设置页即结束本次进入编排（不在返回瞬间重问），
      // 待办取消、模式值不动；授权后再次发起进入按已授权放行。
      await tester.tap(
        find.byKey(const Key('camera_permission_open_settings')),
      );
      await tester.pumpAndSettle();
      expect(camera.openSettingsCount, 1);
      expect(find.byKey(const Key('camera_permission_dialog')), findsNothing);

      expect(modeOf(tester), PlayerSessionMode.editing);
      expect(
        containerOf(tester).read(playerSessionProvider).pendingEntry,
        isNull,
      );
      expect(camera.startCount, 0);
    });

    testWidgets('控制层展开时预览照常实时：展开跃迁不关流、不重开流、不重问权限', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      await singleTapShow(tester);
      await tester.pumpAndSettle();

      expect(modeOf(tester), PlayerSessionMode.compareEditing);
      expect(find.byKey(const Key('control_layer')), findsOneWidget);
      // 预览件仍在练习半区；相机生命周期未动。
      expect(find.byKey(const Key('fake_camera_preview')), findsOneWidget);
      expect(camera.startCount, 1);
      expect(camera.stopCount, 0);
      expect(camera.requestPermissionCount, 1);
    });

    testWidgets('退后台即关相机；回前台仍处对比态则恢复预览', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      expect(camera.startCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(camera.stopCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(modeOf(tester), PlayerSessionMode.compareWatching);
      expect(camera.startCount, 2);
      expect(find.byKey(const Key('fake_camera_preview')), findsOneWidget);
    });

    testWidgets('旁路不开未授权的流：未经相机门直落对比取值 → 零开流', (tester) async {
      setWideView(tester);
      camera.permissionResult = CameraPermissionStatus.denied;
      await pumpPlayer(tester);
      // 绕过入口编排直落对比取值（旁路路径）：对比边沿开流以已授权为
      // 前提，未授权零启动。
      containerOf(tester)
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareWatching);
      await tester.pumpAndSettle();

      expect(modeOf(tester), PlayerSessionMode.compareWatching);
      expect(camera.startCount, 0);
      expect(camera.requestPermissionCount, 0);
    });
  });

  group('练习侧镜像', () {
    late FakePlaybackEngine engine;
    late FakeSystemUi systemUi;
    late FakeCameraCaptureService camera;

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      systemUi = FakeSystemUi();
      camera = FakeCameraCaptureService();
    });

    void setWideView(WidgetTester tester) {
      tester.view.physicalSize = const Size(
        1920,
        1080,
      ); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    Future<void> singleTapShow(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
    }

    /// 同上，但可预置设备级全局私密文件内容（设备级镜像默认关）。
    Future<ProviderContainer> pumpCompareEditingWithPrivate(
      WidgetTester tester, {
      InMemoryVideoDocumentStorage? docs,
      Map<String, dynamic> privateInitial = const {},
    }) async {
      final source = Uri.file('/videos/a.mp4');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            cameraCaptureProvider.overrideWithValue(camera),
            androidCameraPlatform(),
            privateJsonStorageProvider.overrideWithValue(
              InMemoryPrivateJsonStorage(initial: privateInitial),
            ),
            systemUiControllerProvider.overrideWithValue(systemUi),
            contentHasherProvider.overrideWithValue(
              const FixedHasher('seeded'),
            ),
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => docs ?? InMemoryVideoDocumentStorage(),
            ),
            if (docs != null)
              videoDocumentCoordinatorProvider.overrideWith(
                (ref, videoId) => VideoDocumentCoordinator(docs),
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
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await tester.pumpAndSettle();
      return container;
    }

    /// 点按一次「练习侧镜像」槽（开关入口 =
    /// 标注工具区对比槽集的 `control_practice_mirror` 槽）。
    Future<void> tapPracticeMirrorSlot(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('control_practice_mirror')));
      await tester.pumpAndSettle();
    }

    /// 切镜像槽后练习半区预览件仍在原处（显示层翻转不换画面件结构位）。
    void expectPreviewPresent(WidgetTester tester) {
      expect(
        find.byKey(const Key('fake_camera_preview')),
        findsOneWidget,
        reason: '翻转只换包裹层，预览件本身仍在练习半区',
      );
    }

    /// 练习半区预览件的**用户可见方向**：生效练习镜像从容器读，渲染落点由
    /// 画面方向库归一——断言「槽点按 → 生效值 → 在屏方向」这条端到端连线
    /// （显示层缩放读库、面选相机预览面的渲染语义本身在
    /// `test/player/camera_stage_test.dart` 直接 pump 该模块钉死）。
    FaceDirection? checkedPreviewDirection(
      WidgetTester tester,
      ProviderContainer container,
    ) => checkedPracticePaneDirection(
      tester,
      const Key('fake_camera_preview'),
      face: SurfaceFace.cameraPreview,
      direction: practiceFaceDirection(
        practiceMirror: container.read(effectivePracticeMirrorProvider),
      ),
    );

    testWidgets('设备级默认开：进入对比态练习侧预览件挂在练习半区', (tester) async {
      setWideView(tester);
      final container = await pumpCompareEditingWithPrivate(tester);
      expect(
        container.read(effectivePracticeMirrorProvider),
        isTrue,
        reason: '设备级默认开（无随舞覆盖）',
      );

      expectPreviewPresent(tester);
      expect(checkedPreviewDirection(tester, container), isNotNull);
    });

    testWidgets('槽点按切镜像即时生效：在屏方向当场翻、预览件不换结构位', (tester) async {
      setWideView(tester);
      final container = await pumpCompareEditingWithPrivate(tester);

      final opened = checkedPreviewDirection(tester, container);

      await tapPracticeMirrorSlot(tester);
      expect(container.read(effectivePracticeMirrorProvider), isFalse);
      final closed = checkedPreviewDirection(tester, container);
      expect(closed, isNot(opened), reason: '拨动练习镜像 ⇒ 在屏那路画面当场翻');
      expectPreviewPresent(tester);

      await tapPracticeMirrorSlot(tester);
      expect(container.read(effectivePracticeMirrorProvider), isTrue);
      expect(checkedPreviewDirection(tester, container), opened);
    });

    testWidgets('随舞覆盖记忆：关掉重开这支舞仍是切换后的状态（local prefs 段）', (tester) async {
      setWideView(tester);
      final docs = InMemoryVideoDocumentStorage();
      final container = await pumpCompareEditingWithPrivate(tester, docs: docs);

      await tapPracticeMirrorSlot(tester);
      expect(container.read(effectivePracticeMirrorProvider), isFalse);
      expectPreviewPresent(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        (docs.localSnapshot['prefs']
            as Map<String, dynamic>?)?['practiceMirror'],
        false,
      );

      // 重开这支舞：新页同 docs，覆盖值恢复。
      final reopened = await pumpCompareEditingWithPrivate(tester, docs: docs);
      expect(reopened.read(effectivePracticeMirrorProvider), isFalse);
      expectPreviewPresent(tester);
    });

    testWidgets('槽覆盖设备默认：设备级默认关 + 槽点按开 → 落盘 true，重开恢复开', (tester) async {
      setWideView(tester);
      final docs = InMemoryVideoDocumentStorage();
      // 设备级默认关（global_private.json 扩键）。
      final container = await pumpCompareEditingWithPrivate(
        tester,
        docs: docs,
        privateInitial: {'practiceMirrorDefault': false},
      );
      expect(
        container.read(effectivePracticeMirrorProvider),
        isFalse,
        reason: '无覆盖时生效值回落设备级默认',
      );
      expectPreviewPresent(tester);

      // 槽点按 → 覆盖设备默认（开）→ 预览即时按新取值呈现。
      await tapPracticeMirrorSlot(tester);
      expect(container.read(effectivePracticeMirrorProvider), isTrue);
      expectPreviewPresent(tester);

      // 落盘随舞 prefs；重开这支舞覆盖恢复 → 仍是开（非设备默认）。
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        (docs.localSnapshot['prefs']
            as Map<String, dynamic>?)?['practiceMirror'],
        true,
      );
      final reopened = await pumpCompareEditingWithPrivate(
        tester,
        docs: docs,
        privateInitial: {'practiceMirrorDefault': false},
      );
      expect(reopened.read(effectivePracticeMirrorProvider), isTrue);
      expectPreviewPresent(tester);
    });
  });
}
