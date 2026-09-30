import 'dart:io';
import 'dart:ui' as ui;

import 'package:dance_learning_app/annotation/compare_materials.dart';
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
    show armedSurfaceBaselinesProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/practice_clip_playback.dart';
import 'package:dance_learning_app/player/practice_mirror.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        annotationEditorProvider,
        localMirrorFragmentsProvider,
        practiceClipsProvider;
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
import '../helpers/fixed_hasher.dart';
import '../helpers/device_viewport.dart';

/// 练习侧镜像在「录制态 / 预览（回放）态 / 退出后」三处一致。
///
/// 用户回报：「录制和预览时的练习侧镜像状态和退出录制后显示相反」，
/// 预期「录制画面和回放画面相同」。侦察结论：三处镜像真值
/// 同源（[effectivePracticeMirrorProvider]），错位出在**录制期渲染路径**——
/// 练习半区的镜像显示层翻转只包了相机预览件（`practice_mirrored_surface`），
/// 片段回放件（`practice_clip_playback`）裸挂：用户按下录制时看到镜像画面、
/// 退出录制后看同一素材的回放却是原相，「录制画面」与「回放画面」因此相反。
///
/// 本文件钉的是**用户可见面**：练习半区当前显示的那一路画面呈原相还是镜像
/// ——判据收在 `test/helpers/practice_mirror_surface.dart`（与
/// `compare_camera_preview_test.dart` 共用一处），且按画面方向库给出的该面
/// **基准方向**归一（模块提供基线，调用点不再硬写符号），以及切换/离开
/// 各态时这个取值是否一直是同一个（不新增第二处真值）。
///
/// **极性口径**：两路用户可见方向锚定**平台保存基准**，本机（预览基准 = 镜像、
/// 保存基准 = 原相）练习镜像**开**时为**镜像（照镜子）**、**关**时为**原相**；
/// 平台预览基准只在预览面的自身原始朝向里补偿平台自拍镜像。读数与归属见画面
/// 方向库库头与 `compare_practice_preview_playback_parity_test.dart` 文件头。
///
/// 先红后绿记录：改动**之前**
/// 本文件的「开启镜像：录制态与回放态同向」「回放态内点镜像槽」
/// 「设备等效视口下同样成立」三例失败于同一处——片段回放件没有镜像显示层
/// 祖先（`Found 0 widgets with key [<'practice_mirrored_surface'>]`）；
/// 包住练习半区那一路画面之后三例转绿。
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
  late File materialOutputFile;

  void setWideView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  /// 设备等效视口 + 真机手指容差（受审面走真手势时的布景纪律）。
  void setDeviceView(WidgetTester tester) {
    useNamedViewport(tester, ViewportTier.compact, landscape: true);
    tester.view.gestureSettings = const ui.GestureSettings(
      physicalTouchSlop: 8 * 3.5,
    );
    addTearDown(tester.view.reset);
  }

  Future<ProviderContainer> pumpPlayer(
    WidgetTester tester, {
    Map<String, dynamic> privateInitial = const {},
    bool sourceMirrored = false,
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
          // 按视频文档走内存实现（markers 缺失 → 镜像按索引历史应用；
          // 生产实现走 path_provider，在测试的 fake 时钟下不完成）。
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => InMemoryVideoDocumentStorage(),
          ),
          contentHasherProvider.overrideWithValue(
            const FixedHasher('vid-a'),
          ),
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(
              initial: VideoIndex(
                entries: [
                  historyEntry(
                    filePath: source.toFilePath(),
                    mirrored: sourceMirrored,
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

  /// 录制相位的布景（与 compare_recording_test 同款：素材文件解析缝 +
  /// 内存文档存储 + 录制准备拍数可读）。
  Future<void> pumpPlayerForRecording(WidgetTester tester) async {
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
          materialManifestStorageProvider.overrideWithValue(manifestStorage),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => InMemoryVideoDocumentStorage(),
          ),
          materialRecordingFileResolverProvider.overrideWithValue(
            (videoId) async => materialOutputFile,
          ),
          systemUiControllerProvider.overrideWithValue(systemUi),
          contentHasherProvider.overrideWithValue(
            const FixedHasher('vid-a'),
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

  void givenClipOnTrack(WidgetTester tester, ProviderContainer container) {
    container.read(practiceClipsProvider.notifier).restore([clip]);
  }

  Future<void> tapPracticeMirrorSlot(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('control_practice_mirror')));
    await tester.pumpAndSettle();
  }


  setUp(() {
    engine = FakePlaybackEngine(duration: const Duration(seconds: 60));
    practiceEngine = FakePlaybackEngine(duration: const Duration(seconds: 20));
    systemUi = FakeSystemUi();
    camera = FakeCameraCaptureService();
    materialOutputFile = File('/tmp/unused_mirror_37.mp4');
  });

  group('练习侧镜像三处一致（判据①②）', () {
    testWidgets('开启镜像：录制态（相机实时预览）与回放态（片段回放件）按模块方向一致呈现', (tester) async {
      setWideView(tester);
      final container = await pumpPlayer(tester);
      await enterCompareEditing(tester);
      givenClipOnTrack(tester, container);
      await tester.pumpAndSettle();
      expect(
        container.read(effectivePracticeMirrorProvider),
        isTrue,
        reason: '设备级默认开（无随舞覆盖）',
      );

      final faces = practiceFaceDirection(
        practiceMirror: container.read(effectivePracticeMirrorProvider),
      );
      // 录制态 = 相机实时预览（按下录制看到的画面）：渲染落点读模块的该面取值。
      final previewDirection = checkedPracticePaneDirection(
        tester,
        const Key('fake_camera_preview'),
        face: SurfaceFace.cameraPreview,
        direction: faces,
      );

      // 回放态 = 点选片段激活后练习侧回放该素材（看录制产物的画面）。
      await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('practice_clip_playback')), findsOneWidget);
      expect(
        checkedPracticePaneDirection(
          tester,
          const Key('practice_clip_playback'),
          face: SurfaceFace.clipPlayback,
          direction: faces,
        ),
        previewDirection,
        reason: '按各自基准归一后两路方向相等（录制画面与回放画面同向）',
      );

      // 退出回看（再点同片段）：回到实时预览，取值与按下录制那一刻一致。
      await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
      await tester.pumpAndSettle();
      expect(
        practicePaneDirection(
          tester,
          const Key('fake_camera_preview'),
          face: SurfaceFace.cameraPreview,
          direction: faces,
        ),
        previewDirection,
      );

      engine.pause();
      practiceEngine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('关闭镜像（随舞覆盖关）：录制态与回放态同向（同一开关、同一次求值）', (tester) async {
      setWideView(tester);
      final container = await pumpPlayer(
        tester,
        privateInitial: {'practiceMirrorDefault': true},
      );
      await enterCompareEditing(tester);
      givenClipOnTrack(tester, container);
      await tester.pumpAndSettle();

      await tapPracticeMirrorSlot(tester);
      expect(container.read(effectivePracticeMirrorProvider), isFalse);
      final faces = practiceFaceDirection(practiceMirror: false);

      final previewDirection = checkedPracticePaneDirection(
        tester,
        const Key('fake_camera_preview'),
        face: SurfaceFace.cameraPreview,
        direction: faces,
      );
      await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
      await tester.pumpAndSettle();
      expect(
        checkedPracticePaneDirection(
          tester,
          const Key('practice_clip_playback'),
          face: SurfaceFace.clipPlayback,
          direction: faces,
        ),
        previewDirection,
        reason: '关着也要同向（按各自基准归一后两路方向相等）',
      );

      engine.pause();
      practiceEngine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('回放态内点镜像槽：当前显示的片段画面即时反相（回放也跟随同一个开关）', (
      tester,
    ) async {
      setWideView(tester);
      final container = await pumpPlayer(tester);
      await enterCompareEditing(tester);
      givenClipOnTrack(tester, container);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
      await tester.pumpAndSettle();
      final opened = checkedPracticePaneDirection(
        tester,
        const Key('practice_clip_playback'),
        face: SurfaceFace.clipPlayback,
        direction: practiceFaceDirection(
          practiceMirror: container.read(effectivePracticeMirrorProvider),
        ),
      );

      // 回放中途经对比槽集关掉镜像：正在放的那路画面当场随开关翻（不必先退出
      // 回看再看实时预览）。
      await tapPracticeMirrorSlot(tester);
      expect(container.read(effectivePracticeMirrorProvider), isFalse);
      final closed = checkedPracticePaneDirection(
        tester,
        const Key('practice_clip_playback'),
        face: SurfaceFace.clipPlayback,
        direction: practiceFaceDirection(practiceMirror: false),
      );
      expect(closed, isNot(opened), reason: '拨动开关 ⇒ 在屏那路画面当场反相');

      // 再点开：同样即时回到同一个呈现。
      await tapPracticeMirrorSlot(tester);
      expect(container.read(effectivePracticeMirrorProvider), isTrue);
      expect(
        checkedPracticePaneDirection(
          tester,
          const Key('practice_clip_playback'),
          face: SurfaceFace.clipPlayback,
          direction: practiceFaceDirection(practiceMirror: true),
        ),
        opened,
      );

      engine.pause();
      practiceEngine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('三态共用一个真值：录制态/回放态/退出后读到的生效镜像同一个值', (tester) async {
      setWideView(tester);
      final container = await pumpPlayer(tester);
      await enterCompareEditing(tester);
      givenClipOnTrack(tester, container);
      await tester.pumpAndSettle();

      final inRecordingLike = container.read(effectivePracticeMirrorProvider);
      final overrideBefore = container.read(practiceMirrorOverrideProvider);

      await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
      await tester.pumpAndSettle();
      expect(
        container.read(effectivePracticeMirrorProvider),
        inRecordingLike,
        reason: '回放态不得另立第二处镜像真值',
      );

      await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
      await tester.pumpAndSettle();
      expect(container.read(effectivePracticeMirrorProvider), inRecordingLike);
      expect(container.read(practiceMirrorOverrideProvider), overrideBefore);

      engine.pause();
      practiceEngine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('设备等效视口下同样成立：片段回放件处在镜像显示层内', (tester) async {
      setDeviceView(tester);
      final container = await pumpPlayer(tester);
      await enterCompareEditing(tester);
      givenClipOnTrack(tester, container);
      await tester.pump(const Duration(milliseconds: 50));

      final faces = practiceFaceDirection(
        practiceMirror: container.read(effectivePracticeMirrorProvider),
      );
      final previewDirection = practicePaneDirection(
        tester,
        const Key('fake_camera_preview'),
        face: SurfaceFace.cameraPreview,
        direction: faces,
      );
      await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(
        practicePaneDirection(
          tester,
          const Key('practice_clip_playback'),
          face: SurfaceFace.clipPlayback,
          direction: faces,
        ),
        previewDirection,
        reason: '设备等效视口下按各自基准归一后两路方向仍相等（画面同向）',
      );

      engine.pause();
      practiceEngine.pause();
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('练习侧镜像局部语义不回归（判据③）', () {
    testWidgets('片段回放件仍替代实时预览：镜像只做显示层翻转，回放件本身仍在练习半区', (
      tester,
    ) async {
      setWideView(tester);
      final container = await pumpPlayer(tester);
      await enterCompareEditing(tester);
      givenClipOnTrack(tester, container);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('practice_clip_playback')), findsOneWidget);
      expect(
        find.byKey(const Key('fake_camera_preview')),
        findsNothing,
        reason: '回看期间练习侧显示片段回放，不是实时预览',
      );
      expect(camera.stopCount, 1, reason: '回看期间摄像头停止（既有语义）');

      engine.pause();
      practiceEngine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('源侧局部镜像片段照常反相，练习侧镜像不被它改写（判据③）', (tester) async {
      setWideView(tester);
      final container = await pumpPlayer(tester);
      givenClipOnTrack(tester, container);
      // 会话内放一条启用局部镜像片段（模块唯一提交入口）。
      final outcome = container
          .read(annotationEditorProvider)
          .submit(const AddLocalMirrorFragment(at: Duration(seconds: 2)));
      expect(outcome.applied, isTrue);
      final fragment = container.read(localMirrorFragmentsProvider).single;

      // 进入对比-控制层并激活片段（练习侧显示片段回放），再回对比-播放态。
      await enterCompareEditing(tester);
      await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
      await tester.pumpAndSettle();
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareWatching);
      await tester.pumpAndSettle();
      final faces = practiceFaceDirection(
        practiceMirror: container.read(effectivePracticeMirrorProvider),
      );
      final playbackDirection = practicePaneDirection(
        tester,
        const Key('practice_clip_playback'),
        face: SurfaceFace.clipPlayback,
        direction: faces,
      );
      expect(
        playbackDirection,
        faces.directionOf(SurfaceFace.clipPlayback),
        reason: '回放件的渲染落点读模块的该面取值（判据从模块基线推出）',
      );

      // 定格在片段内：源侧照常反相（行藏、效果不藏），练习侧一位不动。
      await engine.pause();
      await engine.seek(Duration(milliseconds: fragment.startMs + 100));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('mirrored_surface')),
        findsOneWidget,
        reason: '源侧局部镜像片段的反相在对比态照常生效',
      );
      expect(
        practicePaneDirection(
          tester,
          const Key('practice_clip_playback'),
          face: SurfaceFace.clipPlayback,
          direction: faces,
        ),
        playbackDirection,
        reason: '源侧的局部镜像门不代管练习侧（两侧各读自己那一份）',
      );

      // 定格在片段外：源侧恢复原相，练习侧仍不动。
      await engine.seek(Duration(milliseconds: fragment.endMs + 1000));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mirrored_surface')), findsNothing);
      expect(
        practicePaneDirection(
          tester,
          const Key('practice_clip_playback'),
          face: SurfaceFace.clipPlayback,
          direction: faces,
        ),
        playbackDirection,
      );

      engine.pause();
      practiceEngine.pause();
      await tester.pumpAndSettle();
    });
  });

  group('录制相位的练习侧镜像（判据①：录制态 = 按下录制那一刻看到的画面）', () {
    /// 建 3 个学习段并激活第 2 段（10s–20s，与录制测试同款布景）。
    void givenActiveSegment(WidgetTester tester) {
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container.read(beatTrackStateProvider.notifier).replace(
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
      final editor = container.read(annotationEditorProvider);
      editor.submit(AddSegmentLine(at: const Duration(seconds: 10)));
      editor.submit(AddSegmentLine(at: const Duration(seconds: 20)));
      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(1);
    }

    Future<void> pressRecord(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('compare_record_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }

    /// 练习侧镜像显示层的水平缩放因子（恒在树上）。
    double practiceMirrorScaleX(WidgetTester tester) {
      final transform =
          tester
                  .widget<Transform>(
                    find.byKey(const Key('practice_mirrored_surface')),
                  )
                  .transform;
      return transform.entry(0, 0);
    }

    testWidgets('按下录制 → 录制中 → 停录：练习侧画面同向、镜像显示层不换结构位', (tester) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_mirror37').path}/rec.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayerForRecording(tester);
      givenActiveSegment(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      // 录制前（实时预览）：渲染落点 == 画面方向库给出的该面施加缩放。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      final expectedScale = practiceFaceScaleX(
        SurfaceFace.cameraPreview,
        practiceMirror: container.read(effectivePracticeMirrorProvider),
      );
      final before = practiceMirrorScaleX(tester);
      expect(before, expectedScale, reason: '预览件的施加缩放读模块的该面取值');

      // 录制准备期与录制中：同一路实时预览、同一个镜像显示层（不换结构位
      // ⇒ 平台画面件不重建）。
      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('fake_camera_preview')), findsOneWidget);
      expect(practiceMirrorScaleX(tester), before);
      await tester.pump(const Duration(seconds: 2)); // 越过起录点。
      expect(camera.isRecording, isTrue);
      expect(find.byKey(const Key('fake_camera_preview')), findsOneWidget);
      expect(practiceMirrorScaleX(tester), before);

      // 停录（段尾自动停）→ 回到实时预览：仍是同一个显示层、同一取值。
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(camera.isRecording, isFalse);
      expect(
        practiceMirrorScaleX(tester),
        before,
        reason: '镜像显示层全程同一位（开关不变即取值不变，武装冻结不改练习镜像）',
      );
    });

    testWidgets('录制中关镜像槽：画面当场反相（录制态也跟随同一个开关）', (tester) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_mirror37b').path}/rec.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayerForRecording(tester);
      givenActiveSegment(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      // 进入对比-控制层，经槽集关掉练习侧镜像，再回对比-播放态起录。
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await tester.tap(find.byKey(const Key('control_practice_mirror')));
      await tester.pumpAndSettle();
      expect(container.read(effectivePracticeMirrorProvider), isFalse);
      // 收起控制层回对比-播放态（录制钮只在对比-播放态露出）。
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareWatching);
      await tester.pumpAndSettle();
      final offScale = practiceFaceScaleX(
        SurfaceFace.cameraPreview,
        practiceMirror: false,
      );
      final onScale = practiceFaceScaleX(
        SurfaceFace.cameraPreview,
        practiceMirror: true,
      );
      expect(
        practiceMirrorScaleX(tester),
        offScale,
        reason: '关镜像 ⇒ 渲染落点 == 模块给出的该面施加缩放',
      );
      expect(offScale, isNot(onScale), reason: '关与开是两次相反的施加（画面当场反相）');

      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(camera.isRecording, isTrue);
      expect(
        practiceMirrorScaleX(tester),
        offScale,
        reason: '关掉镜像的取值在录制态沿用（武装冻结的是基线项，不是练习镜像）',
      );
      await pressRecord(tester); // 停录并入库。
      await tester.pumpAndSettle();
      expect(practiceMirrorScaleX(tester), offScale);
    });

    testWidgets('录制中拨练习镜像：画面当场翻（练习镜像是活输入，不随录制冻结）', (
      tester,
    ) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_mirror37c').path}/rec.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayerForRecording(tester);
      givenActiveSegment(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      final onScale = practiceFaceScaleX(
        SurfaceFace.cameraPreview,
        practiceMirror: true,
      );
      final offScale = practiceFaceScaleX(
        SurfaceFace.cameraPreview,
        practiceMirror: false,
      );
      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 4)); // 越过起录点：录制中。
      expect(camera.isRecording, isTrue);
      expect(
        practiceMirrorScaleX(tester),
        onScale,
        reason: '起录时练习镜像为开：渲染落点 == 模块给出的该面施加缩放',
      );

      // 录制中拨同一个开关（录制中控制层不可达，故直接写唯一真值的写点）：
      // 画面当场翻——练习镜像是活输入，没有被武装那一刻的冻结带上。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      expect(
        container.read(armedSurfaceBaselinesProvider),
        practiceFaceBaselines(),
        reason: '武装落定那一刻发布的冻结基线项（装配点读它）',
      );
      container.read(practiceMirrorOverrideProvider.notifier).set(false);
      await tester.pump();
      expect(
        practiceMirrorScaleX(tester),
        offScale,
        reason: '录制中拨开关画面当场翻',
      );

      // 再拨回来：同样当场翻（不是只生效一次）。
      container.read(practiceMirrorOverrideProvider.notifier).set(true);
      await tester.pump();
      expect(practiceMirrorScaleX(tester), onScale);

      await pressRecord(tester); // 停录并入库。
      await tester.pumpAndSettle();
      expect(
        container.read(armedSurfaceBaselinesProvider),
        isNull,
        reason: '会话收尾释放冻结值：退出录制即回到设备事实的当前取值',
      );
      expect(practiceMirrorScaleX(tester), onScale);
    });
  });
}
