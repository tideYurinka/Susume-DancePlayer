import 'package:dance_learning_app/camera_capture/platform_preview_basis.dart'
    show CameraPlatform, PlatformPreviewBasisAdapter, platformSaveBasis;
import 'package:dance_learning_app/surface_direction/surface_direction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 练习侧画面方向的判据（「有效方向」由画面方向库归一）。
///
/// 镜像显示层是包住练习半区**当前显示的那一路画面**的那层水平翻转件
/// （`practice_mirrored_surface`，X 轴缩放因子），且该层**恒在树上**（不做
/// 显示层翻转时 `scaleX = 1`）——于是「画面件在不在包裹层里」不再是判据，
/// 「画面件头顶那层显示层的水平缩放因子」才是。相机预览件与片段回放件用同一
/// 口径读取，才能直接比较三处（录制态 / 回放态 / 退出后）。
///
/// **显示层读数不是用户可见方向**：渲染点施加的缩放 F 是该面自身原始朝向 R
/// 与用户可见方向 D 的合成（`F = R ⊕ D`，见 `surface_direction.dart` 的面表），
/// 每面各带自己的 R。所以判据分两层：[practicePaneScaleX] 读**渲染落点**
/// （应用侧施加的缩放），[practicePaneDirection] 按画面方向库给出的该面基准
/// 把落点归一成**用户可见方向**。要比较「用户看到两路画面是否同向」，用后者
/// 直接比：同一开关取值下两路方向相等就是用户要的「同向」。
///
/// **本机两面的 R 相差一次**（画面方向库的归属裁定，见该库库头）：相机预览面的
/// R = 平台预览基准 = **镜像**，片段回放面的 R = **原相**。故两路**落点**天然
/// 相差一次、而**方向**相等；相对录像文件原相的方向在练习镜像**开**时为镜像
/// （照镜子）、**关**时为原相。判据要用户可见方向就必须走
/// [practicePaneDirection]（或当场断言的 [checkedPracticePaneDirection]），
/// [practicePaneScaleX] 只回答「显示层落点是多少」。
///
/// 说明：本件读取的是 `tester.widget` 上的显示层取值（不变换像素、不做
/// golden 比对），与仓内既有镜像断言同款。渲染层的真实像素方向属真机行为，
/// 部件测试只能钉住「渲染点施加的缩放来自画面方向库，且两路方向相等」，真机
/// 那一层由真机取证读数记录。

/// 练习侧两面方向的求值（部件夹具用）：与播放页装配点在**键未落定**那一态同一条
/// 判定路径——平台事实 adapter（Android 通路；producer 标志读不到，与真实相机
/// 引擎同态）与 CameraX 语义的平台保存基准——于是夹具取的「各面基准方向」与
/// 运行时同一来源，调用点不再硬写符号。
///
/// 通路平台按 Android 取而不读测试宿主的平台事实：受审行为是 Android 真机
/// 行为（部件夹具布景也把相机通路平台按 Android 注入），测试宿主不是 Android。
///
/// 本 helper 只消费练习侧两面（相机预览 / 片段回放），源视频面那三项不被练习
/// 两面消费，按练习面快照的零位读入（[SurfaceMoment.practiceOnly]）。
SurfaceDirection practiceFaceDirection({required bool practiceMirror}) =>
    SurfaceDirection(
      moment: SurfaceMoment.practiceOnly(
        practiceMirror: practiceMirror,
        baselines: practiceFaceBaselines(),
      ),
    );

/// 设备事实的**当前取值**（部件夹具用）：取**设备级基准键读不到**那一支——
/// 夹具的内存私密文件里没有该键（与全新设备同态），故走平台事实判定：真实相机
/// 引擎读不到 producer 标志 ⇒ 机型规则（Android ⇒ 镜像）。要审「键落定后」的
/// 取值，用例自己注入键（见 `platform_basis_wiring_test.dart`）。
SurfaceBaselines practiceFaceBaselines() => SurfaceBaselines(
  platformPreviewBasis: const PlatformPreviewBasisAdapter(
    platform: CameraPlatform.android,
    // 真实相机引擎读不到 producer 标志（见 camera_capture.dart 的
    // platformPreviewBasisFlag），夹具按同一状态走机型规则。
    readProducerFlag: _noProducerFlag,
  ).resolve(),
  platformSaveBasis: platformSaveBasis,
);

/// 真实相机引擎不暴露 producer 标志：夹具按「读不到」这一态取生产取值。
FaceDirection? _noProducerFlag() => null;

/// 练习半区某一路画面件的**渲染落点**：该路画面件头顶显示层的水平缩放因子
/// （`-1` = 施加一次翻转 / `+1` = 不翻；该路画面件此刻不在树上为 `null`）。
double? practicePaneScaleX(WidgetTester tester, Key surfaceKey) {
  final transform = _mirrorLayerTransform(tester, surfaceKey);
  if (transform == null) return null;
  return transform.entry(0, 0) < 0 ? -1 : 1;
}

/// 练习半区某一路画面件的**用户可见画面方向**（`null` = 该路画面件此刻不在
/// 树上）。
///
/// 归一用的**基准方向由画面方向库提供**——R = 该面施加的缩放 F ⊕ 该面方向 D
/// （模块的两个公开读法；`F = R ⊕ D` 的移项，见 `surface_direction.dart` 面表），
/// 不再由调用点硬写 ±1；[face] 是这条画面件对应的面，[direction] 是同一次求值
/// 的方向（练习镜像取当前生效值）。
///
/// 返回的是**实测**落点按模块基准归一后的取值，不是模块取值的复述：渲染点施加
/// 的缩放与模块给的不同，这里就会算出与模块方向不同的用户可见方向。要钉「渲染
/// 落点 == 模块给出的该面施加缩放」，用 [practicePaneScaleX] 直比。
///
/// 判据用法（同向判据）：
/// `practicePaneDirection(previewKey, face: SurfaceFace.cameraPreview, direction: d) ==
///  practicePaneDirection(playbackKey, face: SurfaceFace.clipPlayback, direction: d)`
/// ⇔ 用户看到的两路画面同向。
FaceDirection? practicePaneDirection(
  WidgetTester tester,
  Key surfaceKey, {
  required SurfaceFace face,
  required SurfaceDirection direction,
}) {
  final scaleX = practicePaneScaleX(tester, surfaceKey);
  if (scaleX == null) return null;
  final baseline =
      direction.surfaceScaleX(face) * direction.directionOf(face).scaleX;
  return scaleX * baseline < 0 ? FaceDirection.mirrored : FaceDirection.original;
}

/// 相机预览面某一路画面件此刻的**用户可见方向**：读实测落点并按画面方向库给出
/// 的该面方向当场断言「渲染落点 == 模块的该面施加缩放」。
///
/// 判据从模块基线推出：期望值不硬写符号、也不复写实现里的位表——模块改了
/// 口径，这里跟着走，但渲染点若没读模块就当场红。返回实测的用户可见方向，
/// 供调用点继续做「拨开关当场翻」「两路同向」这类比较（同一读数既断言又复用，
/// 避免读两次）。
FaceDirection? checkedPracticePaneDirection(
  WidgetTester tester,
  Key surfaceKey, {
  required SurfaceFace face,
  required SurfaceDirection direction,
}) {
  final actual = practicePaneDirection(
    tester,
    surfaceKey,
    face: face,
    direction: direction,
  );
  expect(
    actual,
    direction.directionOf(face),
    reason: '$face 的渲染落点必须等于画面方向库给出的该面施加缩放',
  );
  return actual;
}

/// 某面在给定练习镜像取值下的**施加缩放**（部件夹具用）：渲染落点读它。
double practiceFaceScaleX(SurfaceFace face, {required bool practiceMirror}) =>
    practiceFaceDirection(practiceMirror: practiceMirror).surfaceScaleX(face);

/// 画面件头顶那层镜像显示层的水平变换；画面件不在树上返回 null。
Matrix4? _mirrorLayerTransform(WidgetTester tester, Key surfaceKey) {
  if (find.byKey(surfaceKey).evaluate().isEmpty) return null;
  final layers = find
      .ancestor(
        of: find.byKey(surfaceKey),
        matching: find.byKey(const Key('practice_mirrored_surface')),
      )
      .evaluate();
  expect(layers, isNotEmpty, reason: '练习侧镜像显示层是恒在的显示层');
  expect(
    layers.length,
    lessThanOrEqualTo(1),
    reason: '练习侧镜像显示层只有一层（镜像口径只有一处）',
  );
  return (layers.single.widget as Transform).transform;
}
