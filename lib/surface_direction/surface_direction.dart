/// 画面方向库：回答「每一路画面此刻朝哪一边」。
///
/// 参照系是录像文件的原相，`⊕` 表示水平翻转的合成。每一路画面是一个
/// **面**（[SurfaceFace]），方向由一张五行的表给出，唯一的声明处是逐面穷尽
/// switch（[SurfaceDirection._readingOf]，每个面在其中声明自己的两个事实：
/// 用户可见方向 D 与该面自身原始朝向 R）——加一个面漏声明即编译报错。
///
/// ## 库头契约（不变量清单）
///
/// 1. **纯值库**：零 Flutter、零 Riverpod、零 `dart:ui`。只 import `dart:`
///    与 [`LocalMirrorFragment`]（标注纯域里的区间值类型——另立平行区间类型
///    等于把「半开 + 升序不重叠」这条不变量声明两遍）；该类型自身的依赖闭包
///    同样无 Flutter。可被 widget 层与标注编辑模块 import，反向不可。
/// 2. **两个读法**：[SurfaceDirection.directionOf]（面的方向，用户可见事实，
///    跨面不变量与注解层读它）与 [SurfaceDirection.surfaceScaleX]（该面画面
///    件在屏施加的水平缩放，渲染点读它）。后者 = 该面自身原始朝向 ⊕ 该面
///    方向（`F = R ⊕ D`）。本机三处接线的 R：源视频面的画面就是参照系
///    （原相）；相机预览面的画面由平台按平台预览基准交来（[SurfaceBaselines
///    .platformPreviewBasis]）——**平台对前置实时预览做了自拍镜像，故本机该
///    面的 R = 镜像**；片段回放面的画面由第二播放源交来，实测就是录像文件的
///    原相（[SurfaceFace.clipPlayback] 那一臂），故该面的施加缩放 = 该面方向。
/// 3. **一次求值的快照**：[SurfaceMoment] 是唯一的求值入参，构造器逐项
///    required——装配点显式给出每一项，缺项不静默取默认。
/// 4. **位置即真值**：源视频面的方向按快照里的当前显示位置求值，播放推进、
///    暂停定格、步进、拖动定格同判；其余面与位置无关。
/// 5. **录制期冻结 = 会话持有一份基线项**：[SurfaceBaselines]（两项设备事实
///    与由二者合成的基准键）由录制会话在**武装**落定那一刻取一次、此后只读
///    同一实例；**练习镜像是活输入**，不随录制冻结。
///
/// 面表是**源视频面**（全局镜像 ⊕（局部镜像开关 ∧ 片段覆盖当前位置））、
/// **相机预览面**（练习镜像 ⊕ 平台预览基准 ⊕ 基准键）与**片段回放面**
/// （练习镜像 ⊕ 平台保存基准），照五面表逐字落地；渲染落点 = 各面自身
/// 原始朝向 ⊕ 本表取值（`F = R ⊕ D`），两面因此各带自己的缩放。
/// 录像文件面（素材方向 = 平台保存基准，经 [SurfaceBaselines.materialDirection]
/// 读出）与导出文件面尚未接进面表。
/// **平台基准**（平台预览基准、平台保存基准）由装配点在快照里注入，本库内没有
/// 平台基准的字面量——设备级**基准键**住设备级私密文件（`player/
/// surface_basis_key.dart`，与设备级镜像默认键同文件同形状），读得到就按
/// [SurfaceBaselines.fromBasisKey] 落定；读不到才按平台事实 adapter
/// （`camera_capture/platform_preview_basis.dart`：读相机引擎的 producer 标志，
/// 读不到按机型规则推导）判定；各面的**自身原始朝向**是面表里的声明（相机预览
/// 面取平台预览基准，片段回放面 = 原相）。
/// 「基准键」按定义由两项平台基准合成、且只进**相机预览行**，故相机预览面与
/// 片段回放面的方向恒等——两条练习路径的用户可见方向都锚定在**平台保存基准**。
///
/// ## 归属裁定：多出来的那一次翻转归预览面
///
/// 同一个开关取值下，两条练习路径的**用户可见方向相等**，而**施加的缩放相差
/// 平台预览基准那一次**。那一次翻转的归属由同帧像素钉死：**相机预览件相对
/// 录像文件是水平镜像**（平台对前置实时预览做自拍镜像；同帧同裁切 + 归一化
/// 互相关，镜像版读数逼近 1.0、自检 `ncc(A,A) = 1.0000`），**在屏片段回放件
/// 就是录像文件的原相**（撤掉显示层反相后两者同向）。故多出来的那一次翻转归
/// **预览面**（该面的 R = 平台预览基准），回放面的 R = 原相。
/// 平台若不镜像预览（R = 原相），两条路径的施加缩放**相同**：「多出来那一次」
/// 是平台事实的函数，不是按路径硬编码的常量。
///
/// 相对**录像文件原相**的用户可见方向因此逐面按表取值：两路都锚定在**平台保存
/// 基准**——本机（预览基准 = 镜像、保存基准 = 原相）**练习镜像开 ⇒ 两面呈镜像
/// （照镜子）、关 ⇒ 呈原相**；平台预览基准只在预览面的自身原始朝向里补偿平台的
/// 自拍镜像。
library;

import '../core/local_mirror_fragment.dart';

/// 面：App 里每一处会出现在屏幕上的画面。
///
/// 加一个面 = 本枚举加一个值 + 逐面穷尽 switch（[SurfaceDirection._readingOf]）
/// 加一臂（编译期兜漏）。
enum SurfaceFace {
  /// 源视频面（正在播放的整支视频）。
  sourceVideo,

  /// 相机预览面（对比练习的练习半区实时预览件）。
  cameraPreview,

  /// 片段回放面（练习素材在屏回放的那一路）。
  clipPlayback,

  /// 录像文件面（素材对象自己的方向，不是文件字节）。
  recordingFile,

  /// 导出文件面（将来用途）。
  exportFile,
}

/// 面的方向：原相 / 镜像。跨面不变量与注解层读它。
enum FaceDirection {
  /// 原相（与录像文件同向）。
  original(1),

  /// 镜像（相对录像文件水平翻转）。
  mirrored(-1);

  const FaceDirection(this.scaleX);

  /// 本方向对应的显示层水平缩放因子（喂 `Matrix4.diagonal3Values`）。
  final double scaleX;

  /// 是否为「镜像」这一取值（判据读它，不读符号）。
  bool get isMirrored => this == FaceDirection.mirrored;
}

/// 水平翻转的合成（`⊕`）：两侧取值相同即原相、相异即镜像。
FaceDirection _compose(FaceDirection a, FaceDirection b) =>
    a.isMirrored ^ b.isMirrored ? FaceDirection.mirrored : FaceDirection.original;

/// 布尔开关作为 `⊕` 的一项：开 = 镜像、关 = 原相。
FaceDirection _flipOf(bool on) =>
    on ? FaceDirection.mirrored : FaceDirection.original;

/// **基线项**：两项设备事实（平台预览基准、平台保存基准）与由二者派生的
/// **基准键**——录制**武装**那一刻冻结的单位。
///
/// 录制会话在武装落定那一刻取一次、此后只读同一实例，于是**素材方向**
/// （[materialDirection]）在整段素材上同值（前言与正片同向）。**练习镜像不在
/// 本值内**——它是活输入，录制中拨开关当场生效。加一个平台事实 = 本类型加一个
/// `required` 字段。
class SurfaceBaselines {
  const SurfaceBaselines({
    required this.platformPreviewBasis,
    required this.platformSaveBasis,
  });

  /// 从**已落定的设备级基准键**反解两项设备事实：基准键 := 平台预览基准
  /// ⊕ 平台保存基准 ⇒ 平台预览基准 = 基准键 ⊕ 平台保存基准（保存基准仍由
  /// 平台事实给出）；派生出的 [basisKey] 即落定的那一份。
  ///
  /// 只做这步反解——键读不到（缺失/损坏）时的判定与兜底镜像是取得侧的取值链
  /// （`camera_capture/platform_preview_basis.dart`），不归本构造器。
  factory SurfaceBaselines.fromBasisKey({
    required FaceDirection basisKey,
    required FaceDirection platformSaveBasis,
  }) => SurfaceBaselines(
    platformPreviewBasis: _compose(basisKey, platformSaveBasis),
    platformSaveBasis: platformSaveBasis,
  );

  /// 平台预览基准（设备事实）：平台在实时预览面上是否额外做了一次镜像。
  ///
  /// 它同时是相机预览面的两个事实来源——用户可见方向里的 `⊕ 平台预览基准`
  /// 这一项，以及**该面的自身原始朝向**（平台镜像了预览，交到应用手里的画面
  /// 就是镜像的）。取值由平台事实 adapter 给出（读相机引擎的 producer 标志，
  /// 读不到按机型规则推导）；换来源不改本库的取值口径。
  final FaceDirection platformPreviewBasis;

  /// 平台保存基准（设备事实）：平台在保存的录像文件上是否额外做了一次镜像。
  /// 录像文件不携带翻转矩阵 ⇒ 今日恒为原相（CameraX 语义，取值由平台事实
  /// adapter 给出）。
  ///
  /// 它是**练习侧两路用户可见方向的共同锚点**：片段回放面直接消费它，相机
  /// 预览面经「平台预览基准 ⊕ 基准键」相消后也落到它；**素材方向**
  /// （[materialDirection]）同样直接读它。
  final FaceDirection platformSaveBasis;

  /// 基准键 := 平台预览基准 ⊕ 平台保存基准（派生量，不是第二处输入）——于是
  /// 「相机预览」与「片段回放」成为同一个表达式。它进表的位置在**相机预览行**：
  /// 平台预览基准作为该面的自身原始朝向进入施加缩放，补偿平台对前置实时预览的
  /// 自拍镜像。
  FaceDirection get basisKey =>
      _compose(platformPreviewBasis, platformSaveBasis);

  /// **素材方向**（录像文件面 = 平台保存基准）：素材对象自己的方向事实，
  /// 不是文件字节。它只读本值——练习镜像、位置与源侧开关都不参与，故武装
  /// 冻结一次即覆盖整段素材。参照系就是录像文件原相，故素材方向即平台保存
  /// 基准；基准键是「预览基准相对保存基准」的落点，不参与本值。
  FaceDirection get materialDirection => platformSaveBasis;

  @override
  bool operator ==(Object other) =>
      other is SurfaceBaselines &&
      other.platformPreviewBasis == platformPreviewBasis &&
      other.platformSaveBasis == platformSaveBasis;

  @override
  int get hashCode => Object.hash(platformPreviewBasis, platformSaveBasis);
}

/// 一次求值的全部入参（不可变快照）。
///
/// 逐项 required：装配点必须显式给出每一项，没有「漏传就走默认」的坑。录制期
/// 冻结的只是其中的**基线项**（[baselines]）——练习镜像是活输入。
class SurfaceMoment {
  const SurfaceMoment({
    required this.globalMirrored,
    required this.localMirrorEnabled,
    required this.fragments,
    required this.positionMs,
    required this.practiceMirror,
    required this.baselines,
  });

  /// 只读练习两面的求值入参：相机预览面与片段回放面只消费练习镜像与基线项，
  /// 源视频面的三项输入（全局镜像、局部镜像开关与片段表、显示位置）不参与
  /// 它们的取值，按「不镜像、无片段、零位置」读入。
  const SurfaceMoment.practiceOnly({
    required this.practiceMirror,
    required this.baselines,
  }) : globalMirrored = false,
       localMirrorEnabled = false,
       fragments = const [],
       positionMs = 0;

  /// 全局镜像：整支视频的镜像开关。
  final bool globalMirrored;

  /// 局部镜像总开关（视频级视图开关）：关时片段整组不参与。
  final bool localMirrorEnabled;

  /// 会话内启用片段集合（升序、两两不重叠、半开区间）。
  final List<LocalMirrorFragment> fragments;

  /// 当前显示位置（毫秒；位置即真值——播放推进、暂停定格、步进、拖动定格
  /// 同一真值来源）。
  final int positionMs;

  /// 练习镜像：练习侧唯一的用户自由选择（照镜子 / 原相），作用于练习侧
  /// 各面。**活的**——录制中拨开关当场生效（不随录制冻结）。
  final bool practiceMirror;

  /// 本次求值读的**基线项**（两项设备事实与由二者合成的基准键）：非录制期是
  /// 设备事实的当前取值；录制期是会话在**武装**落定那一刻取的那一份
  /// （[SurfaceBaselines]），此后只读同一实例、不再重读设备事实。
  final SurfaceBaselines baselines;
}

/// 面方向的唯一答案源：拿一份快照，回答每个面此刻朝哪一边、该施加什么缩放。
class SurfaceDirection {
  const SurfaceDirection({required this.moment});

  /// 本次求值的入参（快照是唯一入参；录制期冻结的是其中的基线项
  /// [SurfaceMoment.baselines]，练习镜像是活输入）。
  final SurfaceMoment moment;

  /// 面的方向。
  ///
  /// 源视频面 = 全局镜像 ⊕（局部镜像开关 ∧ 任一片段覆盖当前位置）——覆盖
  /// 判定用**当前位置**（[SurfaceMoment.positionMs] 落在某片段的半开区间
  /// `[startMs, endMs)` 内），多片段覆盖为**并集**。相机预览面 = 练习镜像
  /// ⊕ 平台预览基准 ⊕ 基准键。片段回放面 = 练习镜像 ⊕ 平台保存基准——两路
  /// 恒等且锚定**平台保存基准**（基准键只进相机预览行）。录像
  /// 文件面（素材方向）与导出文件面尚未接线：读它们即报未实现，不静默取默认
  /// 值——素材方向今天经基线项的 [SurfaceBaselines.materialDirection] 读出。
  FaceDirection directionOf(SurfaceFace face) => _readingOf(face).direction;

  /// 某面画面件在屏该施加的水平缩放 = 该面自身原始朝向 ⊕ 该面方向
  /// （`F = R ⊕ D`）。同一开关取值下练习侧两路方向相等而缩放可差
  /// 一次，那不是例外而是该式的结果。
  double surfaceScaleX(SurfaceFace face) {
    final reading = _readingOf(face);
    return _compose(reading.direction, reading.ownOrientation).scaleX;
  }

  /// 面表的唯一声明处：每个面在此声明它的**用户可见方向** D 与**自身原始
  /// 朝向** R（该面画面相对录像文件原相的朝向）。两个读法各取其一——加一个
  /// 面漏声明即编译报错。
  ({FaceDirection direction, FaceDirection ownOrientation}) _readingOf(
    SurfaceFace face,
  ) => switch (face) {
    SurfaceFace.sourceVideo => (
      direction: _sourceVideo,
      ownOrientation: FaceDirection.original,
    ),
    // 相机预览面的画面由平台交来，平台怎么镜像预览（平台预览基准）就决定了
    // 该面的自身原始朝向——它是设备事实，不在本库内写死（相机通路对前置实时
    // 预览做自拍镜像，见库头「归属裁定」）。
    SurfaceFace.cameraPreview => (
      direction: _cameraPreview,
      ownOrientation: moment.baselines.platformPreviewBasis,
    ),
    // 片段回放面的画面由第二播放源交来，自身原始朝向 = 录像文件的原相（同帧
    // 读数，见库头「归属裁定」）——多出来的那一次翻转不归本面。
    SurfaceFace.clipPlayback => (
      direction: _clipPlayback,
      ownOrientation: FaceDirection.original,
    ),
    SurfaceFace.recordingFile ||
    SurfaceFace.exportFile => throw UnimplementedError(
      '画面方向：$face 的取值表口径尚未接线',
    ),
  };

  /// 局部镜像此刻是否生效：总开关开 ∧ 当前位置落在某片段的半开区间
  /// `[startMs, endMs)` 内（多片段为并集）。**画面翻转与画面上的标识读同一个
  /// 取值**——本取值是那一式的唯一出处，源视频面方向由它合成，不另立第二条
  /// 镜像口径。
  bool get localMirrorActive =>
      moment.localMirrorEnabled &&
      moment.fragments.any(
        (f) => f.startMs <= moment.positionMs && moment.positionMs < f.endMs,
      );

  /// 全局镜像 ⊕ 局部镜像生效；局部镜像关闭时片段整组不参与。
  FaceDirection get _sourceVideo =>
      _compose(_flipOf(moment.globalMirrored), _flipOf(localMirrorActive));

  /// 练习镜像 ⊕ 平台预览基准 ⊕ 基准键 = 练习镜像 ⊕ 平台保存基准——与片段
  /// 回放面同一表达式，「录制所见 == 回看所见」因此是恒等式而非调用纪律。
  /// 基准键进表的位置在**本行**：平台预览基准作为该面的自身原始朝向进入
  /// 施加缩放（补偿平台对前置实时预览的自拍镜像），在用户可见方向里与基准键
  /// 相消。
  FaceDirection get _cameraPreview => _compose(
    _compose(
      _flipOf(moment.practiceMirror),
      moment.baselines.platformPreviewBasis,
    ),
    moment.baselines.basisKey,
  );

  /// 练习镜像 ⊕ 平台保存基准；练习镜像是练习侧唯一自由选择，平台保存基准
  /// 是设备事实。片段回放面只读这两项——基准键只进相机预览行。
  FaceDirection get _clipPlayback => _compose(
    _flipOf(moment.practiceMirror),
    moment.baselines.platformSaveBasis,
  );
}
