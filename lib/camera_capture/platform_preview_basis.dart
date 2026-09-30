/// 平台画面基准 adapter：把画面方向库要的两个
/// **平台事实**的取得收成一处，让装配点不再注入机型校准常量。
///
/// - **平台预览基准**：相机实时预览件相对录像文件是否已被平台镜像。优先直接
///   读相机引擎的 producer 标志（读得到就用读到的）；读不到用**设备级基准键**
///   （已落定的真机判据 / 人工覆盖）；键也读不到按机型规则推导。这些路径都是
///   注入项（[PlatformPreviewBasisAdapter.platform] 与
///   [PlatformPreviewBasisAdapter.readProducerFlag]）或入参，因此都可直测。
/// - **平台保存基准**：平台写出的录像文件相对原相是否带镜像。CameraX 语义下
///   录像文件不携带翻转矩阵 ⇒ 恒为原相（[platformSaveBasis]）。
///
/// 本库是纯值：零 Flutter、零 Riverpod、零 `dart:io`。运行平台这件系统事实与
/// 相机引擎的读取接线住 `platform_preview_basis_providers.dart`。
library;

import '../surface_direction/surface_direction.dart';

/// 相机通路的平台（机型规则的作用域）。
enum CameraPlatform {
  /// Android（本 App 今天的相机通路：`camera` 插件 / CameraX，前置）。
  android,

  /// 其余平台：机型规则表里没有对应行。
  other,
}

/// 相机引擎的 **producer 标志**读法：引擎能直接答「实时预览 producer 是否对
/// 画面做过一次水平镜像」（即平台预览基准这件设备事实）就返回该取值；引擎不
/// 暴露该标志时返回 null（读不到 ⇒ 走机型规则）。
typedef PlatformPreviewBasisFlagReader = FaceDirection? Function();

/// 平台保存基准（设备事实）：平台写出的录像文件相对原相是否带镜像。
///
/// CameraX 语义下录像文件不携带**水平翻转**的显示矩阵（实测侧数据只有旋转，
///  的 `ffprobe` 读数），故今日恒为**原相**—— 的
/// 像素读数同判：在屏片段回放件撤掉显示层那次反相后与录像抽帧同向。
const FaceDirection platformSaveBasis = FaceDirection.original;

/// 判不出时的兜底取值：机型规则表没有该
/// 平台时的显式落点——它是具名的政策，不是散在判定里的默认值。
const FaceDirection platformPreviewBasisFallback = FaceDirection.mirrored;

/// 机型规则表（平台初值）：读不到 producer 标志时，按相机通路平台给出平台预览
/// 基准的**初值**；表里没有该平台 = 无结论（null），由
/// [PlatformPreviewBasisAdapter.resolve] 落到 [platformPreviewBasisFallback]。
///
/// Android 一行 = **镜像**，依据两条：
///
/// - **通路事实**：引擎的 `ImageReaderSurfaceProducer.handlesCropAndRotation()`
///   为 false（`FlutterRenderer.createSurfaceProducer` 在 API ≥ 29 且非
///   「HUAWEI 且 SDK ≤ 29」时用它），`camera` 插件的 `RotatedPreviewDelegate`
///   因此走 `ImageReaderRotatedPreview.frontFacingCamera`——该分支对前置相机做
///   自拍镜像。
/// - **同帧读数**（本机 DNP AN00 / Android 前置）：在屏实时预览件与同场录像
///   抽帧同帧同裁切比对，无偏归一化互相关 `ncc(同向) = +0.65` /
///   `ncc(镜像) = +0.98`（自检 `ncc(A,A) = 1.0000`）⇒ 预览件相对录像文件是
///   **水平镜像**；同场在屏片段回放件与录像抽帧同向 ⇒ 多出来的那一次翻转归
///   **预览面**，回放面是原相（面表见 `surface_direction.dart` 库头）。
///
/// 真机判据优先于推导：本表给的是**新机型初值**，不是设备真相；
/// 设备级基准键（已落定的真机判据 / 人工覆盖）先于本表生效。
FaceDirection? _byPlatformRule(CameraPlatform platform) => switch (platform) {
  CameraPlatform.android => FaceDirection.mirrored,
  CameraPlatform.other => null,
};

/// 平台预览基准的取得。
class PlatformPreviewBasisAdapter {
  const PlatformPreviewBasisAdapter({
    required this.platform,
    required this.readProducerFlag,
  });

  /// 本次判定所在的相机通路平台（机型规则的表键）。
  final CameraPlatform platform;

  /// 相机引擎 producer 标志的读法（注入项）。
  final PlatformPreviewBasisFlagReader readProducerFlag;

  /// 取得平台预览基准，四步：① 直接读相机引擎的 producer 标志；② 读不到就用
  /// **设备级基准键**（已落定的真机判据 / 人工覆盖——真机判据优先于推导）；
  /// ③ 键也读不到（缺失/损坏）按机型规则推导；④ 规则表里没有该平台时取
  /// [platformPreviewBasisFallback]。
  ///
  /// [deviceBasisKey] 是设备级私密文件里的**基准键**（null = 读不到），按
  /// [SurfaceBaselines.fromBasisKey] 落成平台预览基准——键是设备事实的落点，
  /// 与机型规则推导冲突时以它为准。
  ///
  /// **① 先于 ② 是刻意的**：直接读到的标志是当下的平台事实，比任何落定值新
  /// 而键由判定结果落定（「判定一次并
  /// 记住」），若键先于标志生效，引擎一旦可读也会被这份落定值永久遮住。人工
  /// 覆盖因此只在**直接读不可得**时生效——今天每一台真机都是这一态（相机插件
  /// 不暴露该标志），覆盖正是为这一态准备的救回手段。
  FaceDirection resolve({FaceDirection? deviceBasisKey}) {
    final flag = readProducerFlag();
    if (flag != null) return flag;
    if (deviceBasisKey != null) {
      return SurfaceBaselines.fromBasisKey(
        basisKey: deviceBasisKey,
        platformSaveBasis: platformSaveBasis,
      ).platformPreviewBasis;
    }
    return _byPlatformRule(platform) ?? platformPreviewBasisFallback;
  }
}
