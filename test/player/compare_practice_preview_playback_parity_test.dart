import 'dart:io';

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/practice_clip_playback.dart';
import 'package:dance_learning_app/player/practice_mirror.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show practiceClipsProvider;
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show SurfaceFace;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
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
import '../helpers/practice_mirror_surface.dart';
import '../helpers/video_index_fixtures.dart';
import '../helpers/device_viewport.dart';

/// 练习侧「预览件 ↔ 回放件」的画面方向一致性（由画面方向库归一）。
///
/// ## 用户可见判据
///
/// 同一个练习镜像取值下，**相机预览面与片段回放面的方向相等**——录制时看到的
/// 与退出录制后回看同一素材时看到的是同一个方向。方向由画面方向库给出（两张
/// 面在库内是同一个表达式），本文件在部件层量两路画面件实际呈现的方向：判据
/// 收在 `test/helpers/practice_mirror_surface.dart` 的 [practicePaneDirection]，
/// 各面基准方向由模块提供，调用点不再硬写符号。
///
/// 两路画面件的**渲染落点**（显示层施加的缩放）相差**平台预览基准那一次**：
/// 每面各带自己的自身原始朝向（`F = R ⊕ D`），这是该式的结果、不是例外；同一
/// 开关取值下方向相等才是用户要的「同向」。
///
/// ## 真机读数（同帧同裁切 + 无偏归一化互相关）
///
/// 本机 DNP AN00 / Android 前置，练习镜像**关**（与设备上该支舞的文档取值一致）：
///
/// - **相机实时预览件 vs 同场录像文件抽帧**（同帧、同一把尺子）：同向
///   `ncc = +0.65` / 镜像版 `+0.98`（自检 `ncc(A,A) = 1.0000`）⇒ 预览件相对录像
///   文件是**水平镜像**。两次独立截图读数一致（`+0.9797` / `+0.9851`），通路
///   源码同判：引擎的 `ImageReaderSurfaceProducer.handlesCropAndRotation() =
///   false`，`camera` 插件因此走 `ImageReaderRotatedPreview.frontFacingCamera`，
///   该分支对前置相机做自拍镜像。
/// - **在屏练习片段回放 vs 同一录像抽帧**：显示层反相在位时是录像的镜像、
///   撤掉后与录像**同向**（`+0.9938`）⇒ 回放件就是录像文件的原相。
///
/// 于是「同一个开关取值下多出来的那一次翻转」归**预览面**（该面的自身原始朝向
/// = 平台预览基准 = 镜像），片段回放面的自身原始朝向 = 原相。两面的**用户可见
/// 方向**仍恒等（本文件的同向判据），而**渲染落点**因平台那一次而相差一次；
/// 平台若不镜像预览，两路落点相同。
///
/// 相对**录像文件原相**的用户可见方向表面取值：两路都锚定**平台
/// 保存基准**（本机 = 原相）⇒ 练习镜像**开**时两面呈**镜像（照镜子）**、
/// **关**时呈**原相**。渲染落点（显示层施加的缩放）逐路等于画面方向库给出的
/// 该面施加缩放——本文件「渲染落点」组钉它。
///
/// ## 先红后绿记录
///
/// 改动**之前**（显示层只包住相机预览件、片段回放件裸挂）「开镜像：两路同向」
/// 一例为红；把显示层包住当前显示的那一路之后转绿。起两路方向都读画面
/// 方向库，纯值层的同向不变量另有
/// `test/surface_direction/surface_direction_test.dart` 直测。
void main() {
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

  late FakePlaybackEngine engine;
  late FakePlaybackEngine practiceEngine;
  late FakeSystemUi systemUi;
  late FakeCameraCaptureService camera;
  late MemoryManifestStorage manifestStorage;

  void setWideView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<ProviderContainer> pumpPlayer(
    WidgetTester tester, {
    Map<String, dynamic> privateInitial = const {},
  }) async {
    final source = Uri.file('/videos/a.mp4');
    manifestStorage = MemoryManifestStorage();
    await MaterialManifestStore(manifestStorage).append(material);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          practiceClipEngineProvider.overrideWithValue(practiceEngine),
          cameraCaptureProvider.overrideWithValue(camera),
          androidCameraPlatform(),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(initial: privateInitial),
          ),
          systemUiControllerProvider.overrideWithValue(systemUi),
          materialManifestStoreProvider.overrideWithValue(
            MaterialManifestStore(manifestStorage),
          ),
          materialsBaseDirectoryProvider.overrideWithValue(
            () async => Directory('/tmp/materials'),
          ),
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

  Future<void> enterCompareEditing(WidgetTester tester) async {
    await singleTapShow(tester);
    await tester.tap(find.byKey(const Key('tool_compare')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
  }

  void givenClipOnTrack(ProviderContainer container) {
    container.read(practiceClipsProvider.notifier).restore([clip]);
  }

  Future<void> tapPracticeMirrorSlot(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('control_practice_mirror')));
    await tester.pumpAndSettle();
  }

  /// 切到片段回放态（预览件离树、回放件上树）。
  Future<void> activateClip(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
    await tester.pumpAndSettle();
  }

  const previewKey = Key('fake_camera_preview');
  const playbackKey = Key('practice_clip_playback');

  setUp(() {
    engine = FakePlaybackEngine(duration: const Duration(seconds: 60));
    practiceEngine = FakePlaybackEngine(duration: const Duration(seconds: 20));
    systemUi = FakeSystemUi();
    camera = FakeCameraCaptureService();
  });

  group('两路练习画面方向相等（判据②③；由画面方向库归一）', () {
    testWidgets('开镜像（设备级默认开）：两路画面同向（按各自基准归一后方向相等）', (tester) async {
      setWideView(tester);
      final container = await pumpPlayer(tester);
      await enterCompareEditing(tester);
      givenClipOnTrack(container);
      await tester.pumpAndSettle();
      expect(
        container.read(effectivePracticeMirrorProvider),
        isTrue,
        reason: '设备级默认开（无随舞覆盖）',
      );
      final faces = practiceFaceDirection(
        practiceMirror: container.read(effectivePracticeMirrorProvider),
      );

      // 实时预览（按下录制看到的画面）：渲染落点读模块的该面取值。
      final previewDirection = checkedPracticePaneDirection(
        tester,
        previewKey,
        face: SurfaceFace.cameraPreview,
        direction: faces,
      );

      // 片段回放（退出录制后看同一素材的画面）。
      await activateClip(tester);
      expect(find.byKey(playbackKey), findsOneWidget);
      expect(
        checkedPracticePaneDirection(
          tester,
          playbackKey,
          face: SurfaceFace.clipPlayback,
          direction: faces,
        ),
        previewDirection,
        reason: '预览件与回放件必须同向（用户原话：两边方向一致、能逐帧对比）',
      );

      // 退出回看：回到实时预览，取值不变（切路径不改真值、不改本路方向）。
      await activateClip(tester);
      expect(
        checkedPracticePaneDirection(
          tester,
          previewKey,
          face: SurfaceFace.cameraPreview,
          direction: faces,
        ),
        previewDirection,
      );

      // 收尾：双引擎暂停后再 settle（回放件的循环定时器不留在树上）。
      engine.pause();
      practiceEngine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('关镜像（随舞覆盖关）：实时预览与片段回放同向（同一开关取值）', (tester) async {
      setWideView(tester);
      final container = await pumpPlayer(
        tester,
        privateInitial: {'practiceMirrorDefault': true},
      );
      await enterCompareEditing(tester);
      givenClipOnTrack(container);
      await tester.pumpAndSettle();

      await tapPracticeMirrorSlot(tester);
      expect(container.read(effectivePracticeMirrorProvider), isFalse);
      final faces = practiceFaceDirection(practiceMirror: false);

      final previewDirection = checkedPracticePaneDirection(
        tester,
        previewKey,
        face: SurfaceFace.cameraPreview,
        direction: faces,
      );
      await activateClip(tester);
      expect(
        checkedPracticePaneDirection(
          tester,
          playbackKey,
          face: SurfaceFace.clipPlayback,
          direction: faces,
        ),
        previewDirection,
        reason: '关着也要同向（按各自基准归一后两路方向相等）',
      );

      // 收尾：双引擎暂停后再 settle（回放件的循环定时器不留在树上）。
      engine.pause();
      practiceEngine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('回放态内点镜像槽：当前显示的片段画面即时反相（随同一个开关）', (
      tester,
    ) async {
      setWideView(tester);
      final container = await pumpPlayer(tester);
      await enterCompareEditing(tester);
      givenClipOnTrack(container);
      await tester.pumpAndSettle();
      await activateClip(tester);
      final opened = checkedPracticePaneDirection(
        tester,
        playbackKey,
        face: SurfaceFace.clipPlayback,
        direction: practiceFaceDirection(
          practiceMirror: container.read(effectivePracticeMirrorProvider),
        ),
      );

      await tapPracticeMirrorSlot(tester);
      expect(container.read(effectivePracticeMirrorProvider), isFalse);
      final closed = checkedPracticePaneDirection(
        tester,
        playbackKey,
        face: SurfaceFace.clipPlayback,
        direction: practiceFaceDirection(
          practiceMirror: container.read(effectivePracticeMirrorProvider),
        ),
      );
      expect(
        closed,
        isNot(opened),
        reason: '正在放的那路画面当场随开关翻（不必先退出回看）',
      );

      await tapPracticeMirrorSlot(tester);
      expect(container.read(effectivePracticeMirrorProvider), isTrue);
      expect(
        checkedPracticePaneDirection(
          tester,
          playbackKey,
          face: SurfaceFace.clipPlayback,
          direction: practiceFaceDirection(
            practiceMirror: container.read(effectivePracticeMirrorProvider),
          ),
        ),
        opened,
      );

      // 收尾：双引擎暂停后再 settle（回放件的循环定时器不留在树上）。
      engine.pause();
      practiceEngine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('切面不换向：同一开关取值下，两条路径按各自基准归一后方向相等', (tester) async {
      setWideView(tester);
      final container = await pumpPlayer(tester);
      await enterCompareEditing(tester);
      givenClipOnTrack(container);
      await tester.pumpAndSettle();

      for (final on in const [true, false]) {
        final current = container.read(effectivePracticeMirrorProvider);
        if (current != on) await tapPracticeMirrorSlot(tester);
        expect(container.read(effectivePracticeMirrorProvider), on);
        final faces = practiceFaceDirection(
          practiceMirror: container.read(effectivePracticeMirrorProvider),
        );
        final previewDirection = practicePaneDirection(
          tester,
          previewKey,
          face: SurfaceFace.cameraPreview,
          direction: faces,
        );
        await activateClip(tester);
        expect(
          practicePaneDirection(
            tester,
            playbackKey,
            face: SurfaceFace.clipPlayback,
            direction: faces,
          ),
          previewDirection,
          reason: '开关=$on 时按各自基准归一后两路方向相等（画面同向）',
        );
        await activateClip(tester);
      }

      // 收尾：双引擎暂停后再 settle（回放件的循环定时器不留在树上）。
      engine.pause();
      practiceEngine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('设备等效视口下同样成立（真机横屏等效 2736×1264 @3.5）', (tester) async {
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
      final container = await pumpPlayer(tester);
      await enterCompareEditing(tester);
      givenClipOnTrack(container);
      await tester.pump(const Duration(milliseconds: 50));

      final faces = practiceFaceDirection(
        practiceMirror: container.read(effectivePracticeMirrorProvider),
      );
      final previewDirection = practicePaneDirection(
        tester,
        previewKey,
        face: SurfaceFace.cameraPreview,
        direction: faces,
      );
      await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(
        practicePaneDirection(
          tester,
          playbackKey,
          face: SurfaceFace.clipPlayback,
          direction: faces,
        ),
        previewDirection,
        reason: '设备等效视口下按各自基准归一后两路方向仍相等（画面同向）',
      );

      // 收尾：先暂停两个引擎（取消各自的 ticker）再落一帧——本视口下
      // pumpAndSettle 会被相机预览的重建节拍拖住，故用定长 pump 收尾。
      engine.pause();
      practiceEngine.pause();
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('渲染落点来自画面方向库（判据③：口径只一处）', () {
    testWidgets('两路画面件的施加缩放恒等于模块给出的该面施加缩放（各面基准不同）', (tester) async {
      setWideView(tester);
      final container = await pumpPlayer(tester);
      await enterCompareEditing(tester);
      givenClipOnTrack(container);
      await tester.pumpAndSettle();

      // 实时预览件（两态）：渲染落点 == 画面方向库给出的该面施加缩放
      // ——该面自身原始朝向 = 本机平台预览基准 = 镜像，故落点 = 平台预览基准
      // ⊕ 练习镜像 ⊕ 平台保存基准（补偿平台对前置实时预览的自拍镜像）。
      expect(container.read(effectivePracticeMirrorProvider), isTrue);
      expect(
        practicePaneScaleX(tester, previewKey),
        practiceFaceScaleX(SurfaceFace.cameraPreview, practiceMirror: true),
      );
      await tapPracticeMirrorSlot(tester);
      expect(container.read(effectivePracticeMirrorProvider), isFalse);
      expect(
        practicePaneScaleX(tester, previewKey),
        practiceFaceScaleX(SurfaceFace.cameraPreview, practiceMirror: false),
      );
      await tapPracticeMirrorSlot(tester);
      await activateClip(tester);

      // 片段回放件：显示层施加的缩放 == 画面方向库给出的该面施加缩放
      // （该面自身原始朝向由库声明，渲染点不自己算符号）。
      expect(container.read(effectivePracticeMirrorProvider), isTrue);
      expect(
        practicePaneScaleX(tester, playbackKey),
        practiceFaceScaleX(SurfaceFace.clipPlayback, practiceMirror: true),
      );
      await tapPracticeMirrorSlot(tester);
      expect(container.read(effectivePracticeMirrorProvider), isFalse);
      expect(
        practicePaneScaleX(tester, playbackKey),
        practiceFaceScaleX(SurfaceFace.clipPlayback, practiceMirror: false),
      );
      await tapPracticeMirrorSlot(tester);
      expect(container.read(effectivePracticeMirrorProvider), isTrue);
      expect(
        practicePaneScaleX(tester, playbackKey),
        practiceFaceScaleX(SurfaceFace.clipPlayback, practiceMirror: true),
      );

      // 收尾：双引擎暂停后再 settle（回放件的循环定时器不留在树上）。
      engine.pause();
      practiceEngine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('镜像真值仍只有一处：切路径前后 effectivePracticeMirrorProvider 不变', (
      tester,
    ) async {
      setWideView(tester);
      final container = await pumpPlayer(tester);
      await enterCompareEditing(tester);
      givenClipOnTrack(container);
      await tester.pumpAndSettle();

      final before = container.read(effectivePracticeMirrorProvider);
      final overrideBefore = container.read(practiceMirrorOverrideProvider);
      await activateClip(tester);
      expect(container.read(effectivePracticeMirrorProvider), before);
      expect(container.read(practiceMirrorOverrideProvider), overrideBefore);
      await activateClip(tester);
      expect(container.read(effectivePracticeMirrorProvider), before);

      // 收尾：双引擎暂停后再 settle（回放件的循环定时器不留在树上）。
      engine.pause();
      practiceEngine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('镜像显示层恒在树上、只有一层，且不因路径切换换结构位', (tester) async {
      setWideView(tester);
      final container = await pumpPlayer(tester);
      await enterCompareEditing(tester);
      givenClipOnTrack(container);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('practice_mirrored_surface')),
        findsOneWidget,
        reason: '关闭镜像时也恒在树上（平台画面件不因开关换结构位）',
      );
      await activateClip(tester);
      expect(find.byKey(const Key('practice_mirrored_surface')), findsOneWidget);

      // 收尾：双引擎暂停后再 settle（回放件的循环定时器不留在树上）。
      engine.pause();
      practiceEngine.pause();
      await tester.pumpAndSettle();
    });
  });

  // 会话态切换后镜像真值不被路径改写（与相邻用例同口径的补钉）。
  testWidgets('回放态内不改写真值：覆盖值保持 null（未随舞覆盖）', (tester) async {
    setWideView(tester);
    final container = await pumpPlayer(tester);
    await enterCompareEditing(tester);
    givenClipOnTrack(container);
    await tester.pumpAndSettle();

    expect(container.read(practiceMirrorOverrideProvider), isNull);
    await activateClip(tester);
    expect(container.read(practiceMirrorOverrideProvider), isNull);
    container
        .read(playerSessionProvider.notifier)
        .enter(PlayerSessionMode.compareWatching);
    await tester.pumpAndSettle();
    expect(container.read(practiceMirrorOverrideProvider), isNull);

    // 收尾：双引擎暂停后再 settle（回放件的循环定时器不留在树上）。
    engine.pause();
    practiceEngine.pause();
    await tester.pumpAndSettle();
  });
}
