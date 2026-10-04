import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/camera_capture/platform_preview_basis.dart'
    show CameraPlatform;
import 'package:dance_learning_app/camera_capture/platform_preview_basis_providers.dart'
    show cameraPlatformProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/player/surface_basis_key.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_camera_capture_service.dart';
import '../helpers/in_memory_private_json_storage.dart';

/// 设备级基准键**供画面方向表读取**：键值变化后
/// 画面方向表按新键落定——直测在 provider 缝上，不 pump 部件。
///
/// 键是设备事实的落点（已落定的真机判据 / 人工覆盖），优先于机型规则推导：
/// 布景取 Android 通路（规则 = 镜像），于是任何**非镜像**取值都只能来自键；
/// 键缺失时取值落回规则（镜像）。
///
/// 键按定义（平台预览基准 ⊕ 平台保存基准）**只进相机预览行**：
/// 键变动改的是「应用认定平台预览基准是什么」⇒ 预览面补偿平台自拍镜像的
/// 那一次施加缩放随之翻；两路练习面的**用户可见方向**锚定平台保存基准，
/// 与素材方向一样不随键动。
void main() {
  late FakeCameraCaptureService camera;
  late InMemoryPrivateJsonStorage privateJson;
  late ProviderContainer container;

  ProviderContainer makeContainer({
    Map<String, dynamic> privateInitial = const {},
  }) {
    camera = FakeCameraCaptureService();
    privateJson = InMemoryPrivateJsonStorage(initial: privateInitial);
    return ProviderContainer(
      overrides: [
        privateJsonStorageProvider.overrideWithValue(privateJson),
        cameraCaptureProvider.overrideWithValue(camera),
        cameraPlatformProvider.overrideWithValue(CameraPlatform.android),
      ],
    );
  }

  /// 以设备事实的当前取值求画面方向（练习镜像 / 源侧输入取中性值——本文件
  /// 受审的是基线项那一项）。
  SurfaceDirection tableOf(
    SurfaceBaselines baselines, {
    bool practiceMirror = false,
  }) => SurfaceDirection(
    moment: SurfaceMoment(
      globalMirrored: false,
      localMirrorEnabled: false,
      fragments: const [],
      positionMs: 0,
      practiceMirror: practiceMirror,
      baselines: baselines,
    ),
  );

  test('键值变化 ⇒ 画面方向表按新键落定（预览面的施加缩放随之翻，'
      '两路可见方向锚定平台保存基准）', () async {
    container = makeContainer(privateInitial: {'surfaceBasisKey': false});
    addTearDown(container.dispose);
    await container.read(surfaceBasisKeyProvider.notifier).restoreDone;

    final before = tableOf(container.read(liveSurfaceBaselinesProvider));
    // 键 = 原相 ⇒ 平台预览基准 = 原相（Android 机型规则为镜像，故这一取值
    // 只能来自键）；保存基准恒为原相 ⇒ 两路方向都是原相。
    expect(
      before.directionOf(SurfaceFace.cameraPreview),
      FaceDirection.original,
      reason: '键 = 原相（Android 机型规则为镜像，故这一取值只能来自键）',
    );
    expect(
      before.directionOf(SurfaceFace.clipPlayback),
      FaceDirection.original,
    );
    expect(
      before.surfaceScaleX(SurfaceFace.cameraPreview),
      1,
      reason: '预览面补偿平台自拍镜像的那一次 = 平台预览基准 = 原相 ⇒ 不翻',
    );
    expect(
      container.read(liveSurfaceBaselinesProvider).materialDirection,
      FaceDirection.original,
      reason: '素材方向 = 平台保存基准（键不进本值）',
    );

    await container
        .read(surfaceBasisKeyProvider.notifier)
        .set(FaceDirection.mirrored);

    final after = tableOf(container.read(liveSurfaceBaselinesProvider));
    expect(
      after.surfaceScaleX(SurfaceFace.cameraPreview),
      -1,
      reason: '键改镜像 ⇒ 认定平台预览基准 = 镜像 ⇒ 预览面的施加缩放随之翻',
    );
    expect(
      after.directionOf(SurfaceFace.cameraPreview),
      FaceDirection.original,
      reason: '方向锚定平台保存基准（原相），不随认定的预览基准动',
    );
    expect(
      after.directionOf(SurfaceFace.clipPlayback),
      FaceDirection.original,
      reason: '回放面只读平台保存基准，键不进它的取值',
    );
    expect(
      after.surfaceScaleX(SurfaceFace.clipPlayback),
      1,
      reason: '回放面自身原始朝向 = 原相且方向 = 原相 ⇒ 施加的缩放 = 原相',
    );
    expect(
      container.read(liveSurfaceBaselinesProvider).materialDirection,
      FaceDirection.original,
      reason: '素材方向 = 平台保存基准 ⇒ 不随键变化',
    );
  });

  test('键先于机型规则：Android 推导为镜像也按键落定', () async {
    container = makeContainer(privateInitial: {'surfaceBasisKey': false});
    addTearDown(container.dispose);
    await container.read(surfaceBasisKeyProvider.notifier).restoreDone;

    expect(
      container.read(liveSurfaceBaselinesProvider).platformPreviewBasis,
      FaceDirection.original,
    );
  });

  test('键缺失 ⇒ 判定一次并记住（Android ⇒ 镜像），取值按判定结果', () async {
    container = makeContainer();
    addTearDown(container.dispose);
    await container.read(surfaceBasisKeyProvider.notifier).restoreDone;

    expect(
      container.read(surfaceBasisKeyProvider),
      FaceDirection.mirrored,
      reason: '读不到键 ⇒ 判定一次（机型规则推导）并记住',
    );
    expect(privateJson.snapshot, {'surfaceBasisKey': true});
    expect(
      container.read(liveSurfaceBaselinesProvider).platformPreviewBasis,
      FaceDirection.mirrored,
    );
  });

  test('键变化不改跨面不变量：两路练习面方向恒等、开关两路一起翻', () async {
    container = makeContainer(privateInitial: {'surfaceBasisKey': false});
    addTearDown(container.dispose);
    await container.read(surfaceBasisKeyProvider.notifier).restoreDone;

    for (final key in [FaceDirection.original, FaceDirection.mirrored]) {
      await container.read(surfaceBasisKeyProvider.notifier).set(key);
      final baselines = container.read(liveSurfaceBaselinesProvider);
      expect(baselines.basisKey, key, reason: '落定后派生出的键回到落定值');
      for (final practiceMirror in [true, false]) {
        final table = tableOf(baselines, practiceMirror: practiceMirror);
        expect(
          table.directionOf(SurfaceFace.cameraPreview),
          table.directionOf(SurfaceFace.clipPlayback),
          reason: '键=$key 练习镜像=$practiceMirror：切路径方向不变',
        );
      }
    }
  });
}
