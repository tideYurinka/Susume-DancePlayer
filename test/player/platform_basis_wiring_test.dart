import 'dart:io';

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show practiceClipsProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/practice_clip_playback.dart';
import 'package:dance_learning_app/player/practice_mirror.dart';
import 'package:dance_learning_app/player/surface_basis_key.dart'
    show liveSurfaceBaselinesProvider, surfaceBasisKeyProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show FaceDirection, SurfaceDirection, SurfaceFace, SurfaceMoment;
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

/// 装配点以**真实来源**取平台预览基准：画面方向
/// 快照里的平台事实不再由装配点注入机型校准常量，而是经平台事实 adapter 判定
/// ——优先读相机引擎的 producer 标志，读不到按机型规则推导。
///
/// 本文件在**部件缝**上钉这条接线：改相机引擎的 producer 标志，练习侧画面件
/// 施加的缩放随之按模块口径变化；清掉标志则回到机型规则（Android ⇒ 镜像，
/// 取证订正后的取值）。判据读**相机预览面**——该面补偿平台自拍镜像的
/// 那一次施加缩放随平台预览基准变化（片段回放面只读平台保存基准，不随它变）。
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

  setUp(() {
    engine = FakePlaybackEngine(duration: const Duration(seconds: 60));
    practiceEngine = FakePlaybackEngine(duration: const Duration(seconds: 20));
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

  /// 设备等效视口下的布景（与 compare_practice_mirror_consistency_test 同款）：
  /// 受审行为是 Android 真机行为，故相机通路平台按 Android 注入（测试宿主不是
  /// Android，读宿主平台事实会落到机型规则表之外）。
  Future<ProviderContainer> pumpPlayer(
    WidgetTester tester, {
    Map<String, dynamic> privateInitial = const {},
  }) async {
    final source = Uri.file('/videos/a.mp4');
    final manifestStorage = MemoryManifestStorage();
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

  testWidgets('引擎读得到 producer 标志：练习两面按读到的基准取值（机型规则不参与）', (tester) async {
    // 读到的引擎事实 = 预览面未被平台镜像（与 Android 机型规则的镜像相反）。
    camera.scriptedProducerFlag = FaceDirection.original;
    setWideView(tester);
    final container = await pumpPlayer(tester);
    await enterCompareEditing(tester);
    container.read(practiceClipsProvider.notifier).restore([clip]);
    await tester.pumpAndSettle();
    expect(
      container.read(effectivePracticeMirrorProvider),
      isTrue,
      reason: '设备级默认开（无随舞覆盖）',
    );

    // 相机预览面：施加的缩放 = 平台预览基准 ⊕ 练习镜像 ⊕ 平台保存基准
    // （该面的 R = 平台预览基准，D = 练习镜像 ⊕ 平台保存基准）。
    expect(
      practicePaneScaleX(tester, const Key('fake_camera_preview')),
      -1,
      reason: '读到的基准 = 原相 + 开镜像 ⇒ 预览面施加一次显示层翻转',
    );

    // 片段回放面：施加的缩放 = 练习镜像 ⊕ 平台保存基准——只读保存基准，
    // 平台预览基准不进这一路。
    await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
    await tester.pumpAndSettle();
    expect(
      practicePaneScaleX(tester, const Key('practice_clip_playback')),
      -1,
      reason: '开镜像 ⇒ 回放面翻一次（与读到的平台预览基准无关）',
    );

    engine.pause();
    practiceEngine.pause();
    await tester.pumpAndSettle();
  });

  testWidgets('引擎读不到 producer 标志：按机型规则推导（Android ⇒ 镜像）', (tester) async {
    // 读不到（真实相机引擎今天不暴露该标志）⇒ Android 机型规则 ⇒ 镜像
    // （同帧取证：相机通路对前置实时预览做自拍镜像）。
    camera.scriptedProducerFlag = null;
    setWideView(tester);
    final container = await pumpPlayer(tester);
    await enterCompareEditing(tester);
    container.read(practiceClipsProvider.notifier).restore([clip]);
    await tester.pumpAndSettle();

    expect(
      practicePaneScaleX(tester, const Key('fake_camera_preview')),
      1,
      reason: '预览基准 = 镜像 ⇒ 平台已把预览镜像，应用侧不再多翻一次（补偿那一次）',
    );

    await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
    await tester.pumpAndSettle();
    expect(
      practicePaneScaleX(tester, const Key('practice_clip_playback')),
      -1,
      reason: '回放面的施加缩放 = 练习镜像 ⊕ 平台保存基准，不随平台预览基准变',
    );

    engine.pause();
    practiceEngine.pause();
    await tester.pumpAndSettle();
  });

  testWidgets('设备级基准键先于机型规则：键 = 原相时回放面按落定的键取值', (tester) async {
    // 引擎读不到（真实相机引擎今天不暴露该标志）、Android 规则为镜像，但设备级
    // 基准键已落定为**原相**——真机判据优先于推导，
    // 故平台预览基准 = 原相，预览面按认定的事实补偿那一次。
    camera.scriptedProducerFlag = null;
    setWideView(tester);
    final container = await pumpPlayer(
      tester,
      privateInitial: {'surfaceBasisKey': false},
    );
    await enterCompareEditing(tester);
    container.read(practiceClipsProvider.notifier).restore([clip]);
    await tester.pumpAndSettle();

    expect(
      container.read(surfaceBasisKeyProvider),
      FaceDirection.original,
      reason: '启动恢复把设备级键读进会话',
    );
    expect(
      container.read(liveSurfaceBaselinesProvider).basisKey,
      FaceDirection.original,
      reason: '装配点按键落定基线项（机型规则推导被键覆盖）',
    );
    expect(
      practicePaneScaleX(tester, const Key('fake_camera_preview')),
      -1,
      reason: '键 = 原相 ⇒ 认定平台没镜像预览 ⇒ 应用侧补上那一次翻转',
    );
    final direction = SurfaceDirection(
      moment: SurfaceMoment(
        globalMirrored: false,
        localMirrorEnabled: false,
        fragments: const [],
        positionMs: 0,
        practiceMirror: true,
        baselines: container.read(liveSurfaceBaselinesProvider),
      ),
    );
    final previewDirection = practicePaneDirection(
      tester,
      const Key('fake_camera_preview'),
      face: SurfaceFace.cameraPreview,
      direction: direction,
    );
    expect(previewDirection, isNotNull, reason: '该态下相机预览件在树上');

    await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
    await tester.pumpAndSettle();
    expect(
      practicePaneScaleX(tester, const Key('practice_clip_playback')),
      -1,
      reason: '回放面只读练习镜像 ⊕ 平台保存基准：键不进这一路',
    );
    expect(
      practicePaneDirection(
        tester,
        const Key('practice_clip_playback'),
        face: SurfaceFace.clipPlayback,
        direction: direction,
      ),
      previewDirection,
      reason: '键改的是基线项，不改「录制所见 == 回看所见」：两路用户可见方向仍相等',
    );

    engine.pause();
    practiceEngine.pause();
    await tester.pumpAndSettle();
  });
}
