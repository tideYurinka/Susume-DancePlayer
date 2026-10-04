import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/camera_capture/platform_preview_basis.dart'
    show CameraPlatform;
import 'package:dance_learning_app/camera_capture/platform_preview_basis_providers.dart'
    show cameraPlatformProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonFileProvider;
import 'package:dance_learning_app/player/surface_basis_key.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_camera_capture_service.dart';

/// 基准键的**人工覆盖路径**：覆盖 = 按操作说明
/// （`docs/basis-key-manual-override.md`）直接改设备级私密文件
/// `global_private.json` 的顶层布尔键 `surfaceBasisKey`，**重启应用**后按新键
/// 取值。本期没有设置界面。
///
/// 全程走**真实文件**（生产的 `privateJsonFileProvider` →
/// `AtomicJsonFile` → 原子读写）与 provider 缝：不经任何应用内写入入口、
/// 不 pump 任何部件——「人工改动」就是文件系统上的一次重写，重启就是新容器。
void main() {
  late Directory tempDir;
  late File keyFile;
  late FakeCameraCaptureService camera;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('basis_key_override');
    keyFile = File(p.join(tempDir.path, 'global_private.json'));
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  /// 启动一次应用（新容器 = 重启等价）：设备级私密文件按生产装配落在
  /// `global_private.json` 这个真实文件上。
  ProviderContainer launch() {
    camera = FakeCameraCaptureService();
    return ProviderContainer(
      overrides: [
        privateJsonFileProvider.overrideWithValue(keyFile),
        cameraCaptureProvider.overrideWithValue(camera),
        // 机型规则推导为镜像 ⇒ 任何原相取值都只能来自人工改动的键。
        cameraPlatformProvider.overrideWithValue(CameraPlatform.android),
      ],
    );
  }

  /// 人工改键：直接重写设备级文件（操作说明里 adb 改文件那一步），不经任何
  /// 应用入口。
  Future<void> editByHand(Map<String, dynamic> json) =>
      keyFile.writeAsString(jsonEncode(json));

  /// 以设备事实的当前取值求画面方向（练习镜像 / 源侧输入取中性值——本文件受审
  /// 的是基线项那一项）。
  SurfaceDirection tableOf(SurfaceBaselines baselines) => SurfaceDirection(
    moment: SurfaceMoment(
      globalMirrored: false,
      localMirrorEnabled: false,
      fragments: const [],
      positionMs: 0,
      practiceMirror: false,
      baselines: baselines,
    ),
  );

  Future<SurfaceBaselines> startAndSettle() async {
    await container.read(surfaceBasisKeyProvider.notifier).restoreDone;
    return container.read(liveSurfaceBaselinesProvider);
  }

  test('人工改键后重启：取值按新键生效（镜像 → 原相）', () async {
    // 已启动过的设备：设备级文件里已有键 true（镜像）。
    await editByHand({'surfaceBasisKey': true});
    container = launch();
    final before = await startAndSettle();
    expect(before.basisKey, FaceDirection.mirrored, reason: '前提：改键前取值 = 镜像');
    expect(
      tableOf(before).surfaceScaleX(SurfaceFace.cameraPreview),
      -1,
      reason: '按键认定平台预览基准 = 镜像 ⇒ 预览面补偿那一次（施加缩放 = -1）',
    );
    expect(
      tableOf(before).surfaceScaleX(SurfaceFace.clipPlayback),
      1,
      reason: '回放面的施加缩放 = 练习镜像 ⊕ 平台保存基准（键不进本面）',
    );
    container.dispose();

    // 人工改键：把设备级文件里的这一个键改成 false（原相）。
    await editByHand({'surfaceBasisKey': false});

    // 重启应用。
    container = launch();
    addTearDown(container.dispose);
    final baselines = await startAndSettle();

    expect(
      baselines.basisKey,
      FaceDirection.original,
      reason: 'Android 机型规则推导为镜像 ⇒ 原相只能来自人工改动的键',
    );
    final table = tableOf(baselines);
    expect(
      table.directionOf(SurfaceFace.cameraPreview),
      FaceDirection.original,
      reason: '相机预览面方向锚定平台保存基准（原相），不随认定的预览基准动',
    );
    expect(
      table.directionOf(SurfaceFace.clipPlayback),
      FaceDirection.original,
      reason: '片段回放面方向同样锚定平台保存基准（两路恒等不被破坏）',
    );
    expect(
      table.surfaceScaleX(SurfaceFace.cameraPreview),
      1,
      reason: '预览面的施加缩放随人工键翻（−1 → 1：不再补偿一次镜像）',
    );
    expect(
      table.surfaceScaleX(SurfaceFace.clipPlayback),
      1,
      reason: '回放面的施加缩放不随键翻（只读练习镜像 ⊕ 平台保存基准）',
    );
    expect(
      baselines.materialDirection,
      FaceDirection.original,
      reason: '素材方向 = 平台保存基准 ⇒ 不随人工键走',
    );
    expect(jsonDecode(await keyFile.readAsString()), {
      'surfaceBasisKey': false,
    }, reason: '人工覆盖的键读回后原样留在设备级文件里（不被判定链改写）');
  });

  // 反向（原相 → 镜像）：本机机型规则推导也是镜像，故这一条钉的是「人工改动后
  // 重启」这条流程，不是「键先于规则」——键先于规则由上一条（键 = 原相）钉住。
  test('人工改键后重启：原相 → 镜像同样生效', () async {
    await editByHand({'surfaceBasisKey': false});
    container = launch();
    expect((await startAndSettle()).basisKey, FaceDirection.original);
    container.dispose();

    await editByHand({'surfaceBasisKey': true});
    container = launch();
    addTearDown(container.dispose);
    final baselines = await startAndSettle();

    expect(baselines.basisKey, FaceDirection.mirrored);
    final table = tableOf(baselines);
    expect(
      table.directionOf(SurfaceFace.cameraPreview),
      FaceDirection.original,
    );
    expect(table.directionOf(SurfaceFace.clipPlayback), FaceDirection.original);
    expect(table.surfaceScaleX(SurfaceFace.cameraPreview), -1);
    expect(table.surfaceScaleX(SurfaceFace.clipPlayback), 1);
    expect(baselines.materialDirection, FaceDirection.original);
  });

  test('人工改键不动同文件其它设备级键', () async {
    await editByHand({'practiceMirrorDefault': true, 'surfaceBasisKey': true});
    container = launch();
    expect((await startAndSettle()).basisKey, FaceDirection.mirrored);
    container.dispose();

    // 人工只改 surfaceBasisKey 这一个键，其余键按原样写回。
    await editByHand({'practiceMirrorDefault': true, 'surfaceBasisKey': false});
    container = launch();
    addTearDown(container.dispose);
    await startAndSettle();

    expect(jsonDecode(await keyFile.readAsString()), {
      'practiceMirrorDefault': true,
      'surfaceBasisKey': false,
    }, reason: '同文件并列键共存，应用不与人工改动争写');
  });

  test('人工写入损坏值时：不阻塞启动，按键读不到走判定链', () async {
    await editByHand({'surfaceBasisKey': 'mirrored'});
    container = launch();
    addTearDown(container.dispose);

    expect(
      (await startAndSettle()).basisKey,
      FaceDirection.mirrored,
      reason: '类型损坏 = 读不到 ⇒ 判定链（Android 规则 = 镜像）',
    );
    expect(jsonDecode(await keyFile.readAsString()), {
      'surfaceBasisKey': true,
    }, reason: '人工写的非法值被判定结果就地替换为合法键');
  });
}
