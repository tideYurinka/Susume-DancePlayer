/// 竖屏编辑面骨架分配（画面落位的**唯一来源**）：一条规则、实测分支。
///
/// 竖屏编辑面自上而下七段：标题栏、画面区、视频播放工具栏两行、轨道设置条、
/// 轨道行、标注工具行、播放控制工具行。固定段只有名义高：顶栏 [kEditorTopBarHeight]、
/// 底栏两行 [kEditorPortraitToolbarRowsHeight]、视频播放工具栏两行
/// [kEditorVideoToolbarHeight]、设置条 [kEditorSettingsClusterHeight]；画面区
/// （余数）与轨道带（行高表之和）分剩余高。
///
/// **画面落位两分支**：满宽 contain 高 ≤ 画面区高 → **贴底**（画面满宽、
/// 底边贴住画面区下缘，黑区留在画面上方）；放不进 → **观看态背景位**
/// （整屏 contain 居中、位置不改，各工具带以半透明黑压在其上）。
///
/// **判定输入是量出来的高度，不是源画面的方向**——故本库没有按源方向手写的
/// 判断，只有 [PicturePlacement] 两值；横屏源与竖向源走同一式子，结果不同
/// 只是各自的实测高不同。横屏编辑面的骨架与今天逐位相同，本库对横屏屏
/// （[editorIsPortrait] 为假）不给任何几何——消费方走既有布局。
///
/// **方向判定是一条具名纯件**：[editorIsPortrait] 是全仓读「编辑面此刻是不是
/// 竖屏」的唯一函数——调用侧不得再手写 `size.height > size.width`。
/// **档位判定同样是一条具名纯件**：[editorIsCompact] 是全仓读「编辑面此刻
/// 是不是紧凑档」的唯一函数（阈值 600dp，取视口最短边）。
///
/// **宽高比未知**：按观看态背景位处理（先出画），首帧就绪后调用侧带真实宽高
/// 比重算重排——打开瞬间不闪一次错误布局。
///
/// **零框架依赖**：不引 Flutter 框架、不引 Riverpod；只 import `dart:math` 与
/// `dart:ui` 的 [Offset]/[Rect]/[Size]，可在不启动 widget 环境的情况下直测。
///
/// **提示卡落位**：两张左下角提示卡
/// （循环提示、续播提示）的落位也是本库的一条具名纯件
/// [cornerPromptAnchor]——返回卡的左下角屏幕坐标，`null` = 本次放不下。
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'visual_tokens.dart'
    show kHitTargetMinSize, kCornerPromptCardPaddingV;

/// 编辑面顶栏名义行高（dp）：返回钮 + 工具槽行 + 上下内边距的既有实测值。
/// 只进骨架分配，不改顶栏本身的布局。
const double kEditorTopBarHeight = 52;

/// 编辑面底部工具条名义行高（dp）：进度控件 + 标注工具行的既有实测值。
const double kEditorToolbarHeight = 52;

/// 竖屏底栏名义高（dp）：底栏为**标注工具行 + 播放控制工具行**
/// 两行，每行 [kEditorToolbarHeight]，只进竖屏骨架分配。
const double kEditorPortraitToolbarRowsHeight = kEditorToolbarHeight * 2;

/// 竖屏视频播放工具栏名义高（dp）：横屏时住在顶栏的
/// 十枚看片工具里，撤销/重做/查看引导落竖屏标题栏后，其余七枚在
/// 画面正下方的**两行**——第一行两枚（全局镜像、局部镜像，靠右）、第二行
/// 五枚（音画同步、取景调整、节拍提示、倍速设置、对比练习，五等分列），
/// 每行 [kEditorToolbarHeight]，只进竖屏骨架分配。放不下时该行等比缩小
/// （渲染层兜底），名义高不随之变化。
const double kEditorVideoToolbarHeight = kEditorToolbarHeight * 2;

/// 轨道设置条名义行高（dp）：该行的行盒即命中
/// 盒、统一撑到命中下限（[kHitTargetMinSize]，视觉件居中其内不变）——
/// 名义高表随真实渲染重算（排版容量，不是视觉尺寸）。
const double kEditorSettingsClusterHeight = kHitTargetMinSize;

/// 编辑面此刻是不是竖屏（**方向判定的唯一函数**）：屏高大于屏宽即竖屏。
/// 与设备方向锁无关（方向是设备事实），只读这一次布局的屏尺寸。
bool editorIsPortrait(Size screen) => screen.height > screen.width;

/// 紧凑档阈值（dp）：视口**最短边**小于本值即紧凑档（599 紧凑、600 常规）。
/// 现有手机视口最短边 ≤ 480dp、常见平板最短边 ≥ 600dp，分离带很宽；
/// 600dp 同时是 Material 3 compact 的口径。
const double kEditorCompactShortestSideThreshold = 600;

/// 编辑面此刻是不是紧凑档（**档位判定的唯一函数**）：屏宽与屏高中的较小值
/// 小于 [kEditorCompactShortestSideThreshold] 即紧凑档。
///
/// 与编辑面方向判据 [editorIsPortrait] 并列，同样只读这一次布局的屏尺寸——
/// 只看逻辑尺寸、不吃字号档、与设备方向锁无关，故同一台机器竖横两向、
/// 1.0× 与 1.6× 字号下都得到同一档。
///
/// 全仓的阈值算术只有本函数这一处；组合根每帧调它一次，结果经
/// [EditorSkeleton.compact] 递给各消费点——消费方读那一份，不各算一次。
bool editorIsCompact(Size screen) =>
    math.min(screen.width, screen.height) < kEditorCompactShortestSideThreshold;

/// 画面落位两条分支。
enum PicturePlacement {
  /// 贴底：画面满宽、底边贴住画面区下缘，黑区留在画面上方。
  stickToBottom,

  /// 观看态背景位：整屏 contain 居中、位置不改（工具带压在其上）。
  background,
}

/// 一次骨架分配的答案：画面区高、画面落位两分支的几何。
class EditorSkeleton {
  const EditorSkeleton({
    required this.compact,
    required this.portrait,
    required this.pictureAreaHeight,
    required this.picturePlacement,
    required this.pictureBandHeight,
    required this.pictureBandTop,
  });

  /// 本次量测的屏尺寸落哪一档（[editorIsCompact] 的结果，原样透出）。
  /// 紧凑档 = 顶栏走紧凑行集、空轨不占行；消费方一律读它，不按自己的
  /// 屏尺寸重算一遍。
  final bool compact;

  /// 是否走竖屏行（[editorIsPortrait] 的结果，原样透出）。假 = 横屏编辑面，
  /// 以下几何全部为 0、由既有布局接手。
  final bool portrait;

  /// 画面区高（dp，相对**编辑面内容区顶部**即顶栏之下）= 可用高 − 轨道带高。
  /// compact 视口档（该次量测所用视口 → 361.1×781.7dp、设置条名义高 48）
  /// 下为 265.7dp。
  final double pictureAreaHeight;

  /// 画面落位分支（见 [PicturePlacement]）。横屏行取 [PicturePlacement.background]
  /// （无画面带，画面走既有整屏居中）。
  final PicturePlacement picturePlacement;

  /// 贴底分支的画面带高（dp）= 满宽 contain 实测高；背景位为 0（画面走整屏
  /// contain，不落带内）。
  final double pictureBandHeight;

  /// 贴底分支的画面带顶（dp，相对**编辑面内容区顶部**即顶栏之下）
  /// = 画面区高 − 画面带高；背景位为 0。
  final double pictureBandTop;

  /// 是否走贴底分支——画面落位两分支的**唯一谓词**（竖屏且画面放得进）。
  /// 消费方一律读它，不自己重写「portrait + placement」的组合判断。
  bool get sticksToBottom =>
      portrait && picturePlacement == PicturePlacement.stickToBottom;

  /// 贴底分支的画面带顶（屏幕坐标）= 系统栏顶内缩 + 顶栏名义高 + 骨架给的
  /// 黑区高。画面件与注解层基准共用这一处换算，两处不各算一次。
  double bandTopIn({required double systemTopInset}) =>
      systemTopInset + kEditorTopBarHeight + pictureBandTop;

  /// 值对象判等（按内容）：画面层输入按它判定「骨架未变」，从而不重建子树。
  @override
  bool operator ==(Object other) =>
      other is EditorSkeleton &&
      other.compact == compact &&
      other.portrait == portrait &&
      other.pictureAreaHeight == pictureAreaHeight &&
      other.picturePlacement == picturePlacement &&
      other.pictureBandHeight == pictureBandHeight &&
      other.pictureBandTop == pictureBandTop;

  @override
  int get hashCode => Object.hash(
    compact,
    portrait,
    pictureAreaHeight,
    picturePlacement,
    pictureBandHeight,
    pictureBandTop,
  );
}

/// 骨架分配纯函数（[EditorSkeleton] 的唯一出口；零 widget 环境直测）。
///
/// - [screen]：编辑面可用屏尺寸（已扣系统栏；调用方传 SafeArea 内的尺寸）。
/// - [compact]：本次屏尺寸落哪一档（[editorIsCompact] 的结果；缺省 = 常规
///   档）。本库不自己再算一次——顶栏行集、气泡锚点与轨道带剪裁都读
///   [EditorSkeleton.compact] 这一个结果，同一屏上三者不会分裂成两档。
/// - [trackBandHeight]：本态轨道带整带高（行高表之和，不随屏高压缩）。
/// - [videoAspectRatio]：**源画面**宽高比（宽/高）；null 或非正 = 未知。
/// - [framingAspectRatio]：**取景选区内容**宽高比（宽/高）；
///   null = 未调过（落位与盒高都按源画面）。
///
/// 固定段（顶栏/底栏两行/视频播放工具栏两行/设置条）的名义高是本库常量——
/// 它们是**编辑面骨架的一部分**，不做成入参（调用侧没有第二组取值）。
///
/// 规则：**满宽 contain 高 ≤ 画面区高 → 贴底，否则 → 观看态背景位**；
/// 宽高比未知时直接按背景位处理（先出画）。边界取「等于即放得进」（`<=`）。
/// 贴底分支的带高**封顶在未取景时的画面矩形高**（屏宽 ÷ 源画面宽高比）：
/// 选区比源画面更「高」时左右留黑、画面顶边不上移。
EditorSkeleton editorSkeletonFor({
  required Size screen,
  bool compact = false,
  required double trackBandHeight,
  required double? videoAspectRatio,
  double? framingAspectRatio,
}) {
  if (!editorIsPortrait(screen)) {
    // 横屏编辑面不分配骨架：画面仍居中于剩余空间（既有形态）。
    return EditorSkeleton(
      compact: compact,
      portrait: false,
      pictureAreaHeight: 0,
      picturePlacement: PicturePlacement.background,
      pictureBandHeight: 0,
      pictureBandTop: 0,
    );
  }
  final above = math.max(
    0.0,
    screen.height -
        kEditorTopBarHeight -
        // 竖屏底栏两行（标注工具行 + 播放控制工具行）计入名义高表。
        kEditorPortraitToolbarRowsHeight -
        // 竖屏视频播放工具栏两行（两枚 + 五枚看片
        // 工具）计入名义高表。
        kEditorVideoToolbarHeight -
        kEditorSettingsClusterHeight,
  );
  final pictureAreaHeight = math.max(0.0, above - trackBandHeight);
  final sourceRatio = videoAspectRatio;
  final sourceKnown = sourceRatio != null && sourceRatio > 0;
  final framingRatio = framingAspectRatio;
  final framingKnown = framingRatio != null && framingRatio > 0;
  // 落位判定读选区内容宽高比（未调过 = 源画面宽高比）。
  final ratio = framingKnown ? framingRatio : sourceRatio;
  final known = ratio != null && ratio > 0;
  final containHeight = known ? screen.width / ratio : 0.0;
  // 盒高封顶在未取景时的画面矩形高（源画面满宽 contain 高）。
  final unframedHeight = sourceKnown ? screen.width / sourceRatio : containHeight;
  final stick = known && containHeight <= pictureAreaHeight;
  final bandHeight = stick ? math.min(containHeight, unframedHeight) : 0.0;
  return EditorSkeleton(
    compact: compact,
    portrait: true,
    pictureAreaHeight: pictureAreaHeight,
    picturePlacement: stick
        ? PicturePlacement.stickToBottom
        : PicturePlacement.background,
    pictureBandHeight: bandHeight,
    pictureBandTop: stick ? pictureAreaHeight - bandHeight : 0,
  );
}

/// scrub 取消区尺寸上限（逻辑像素）：≈1.8× 常规 48dp 触控目标。
/// 判定与标记经 [cancelZoneRadius] 共用同一值，集中可调。
const double kScrubCancelZoneSize = 88.0;

/// 画面矩形求解（唯一一处 contain 算术）：给定屏
/// 尺寸、系统栏顶内缩、视频宽高比与可空骨架，返回**未经取景变换**的画面矩形
/// （屏幕坐标）。组合根调用一次，手势仲裁域（取消区圆心）与浮层标记消费同一
/// 份答案，两处不各算一次。
///
/// - 观看态（[skeleton] 为空）：整屏 contain 居中——竖屏 16:9 源时画面上方
///   留黑边，取消区圆心落在画面上角而不是屏幕上角；
/// - 编辑态贴底分支（[skeleton] 非空且落带内）：矩形 = 满宽画面带
///   （带顶按 [EditorSkeleton.bandTopIn] 换算到屏幕坐标）；
/// - 骨架非贴底（横屏编辑面 / 背景位）：同观看态整屏 contain 居中；
/// - 宽高比未知（null / 非正）：退化为系统栏内的屏幕可用区，取消照旧可用。
Rect videoPictureRect({
  required Size screen,
  required double systemTopInset,
  required double? videoAspectRatio,
  EditorSkeleton? skeleton,
}) {
  if (skeleton != null && skeleton.sticksToBottom) {
    return Rect.fromLTWH(
      0,
      skeleton.bandTopIn(systemTopInset: systemTopInset),
      screen.width,
      skeleton.pictureBandHeight,
    );
  }
  final ratio = videoAspectRatio;
  if (ratio == null || ratio <= 0) {
    return Rect.fromLTWH(
      0,
      systemTopInset,
      screen.width,
      math.max(0.0, screen.height - systemTopInset),
    );
  }
  final height = math.min(screen.height, screen.width / ratio);
  final width = height * ratio;
  return Rect.fromLTWH(
    (screen.width - width) / 2,
    (screen.height - height) / 2,
    width,
    height,
  );
}

/// 竖屏编辑面**画面区**矩形（屏幕坐标）：满宽，纵向自顶栏之下
/// 到视频播放工具栏两行上缘。
///
/// 转屏钮的锚只看**画面区**、不看画面显示朝向——16:9 横画面与 9:16 竖画面
/// 因此落在同一处（[videoPictureRect] 的「背景位」分支会随显示朝向落到整屏
/// 居中，不能作此钮的锚）。这是「画面区右下角」的唯一式子：转屏钮落位与
/// 测试断言共用它，不各算一次。
Rect portraitPictureAreaRect({
  required Size screen,
  required double systemTopInset,
  required EditorSkeleton skeleton,
}) => Rect.fromLTWH(
  0,
  systemTopInset + kEditorTopBarHeight,
  screen.width,
  skeleton.pictureAreaHeight,
);

/// 转屏钮**视觉圆底**尺寸（dp）：字形 24dp、圆底 36dp、半透明深色圆底。
/// 命中盒不在本文件定值：命中下限只有 visual_tokens 一处声明，渲染侧把视觉
/// 圆底透明外扩到下限——36dp 是视觉尺寸，低于仓库 44dp 触控指引，触控下限
/// 由外扩补齐。
const double kRotateButtonVisualSize = 36;

/// 转屏钮相对画面区右下角的内缩（dp）。
const double kRotateButtonInset = 8;

/// 竖屏转屏钮矩形（屏幕坐标）：触控底贴 [portraitPictureAreaRect]
/// 的右下角、向内缩 [kRotateButtonInset]。渲染点与测试断言共用它，不各算一次。
Rect portraitRotateButtonRect({required Rect pictureArea}) => Rect.fromLTRB(
  pictureArea.right - kRotateButtonInset - kRotateButtonVisualSize,
  pictureArea.bottom - kRotateButtonInset - kRotateButtonVisualSize,
  pictureArea.right - kRotateButtonInset,
  pictureArea.bottom - kRotateButtonInset,
);

/// 横屏「转为竖屏」钮**视觉**尺寸（dp）：62 × 32，12sp 字号下
/// 文本上限 4 字。命中盒由渲染侧外扩，本值只描述
/// 可见底衬。
const double kLandscapeToPortraitButtonWidth = 62;
const double kLandscapeToPortraitButtonHeight = 32;

/// 横屏「转为竖屏」钮相对系统栏内缩的间隙（dp，4）。
const double _kLandscapeToPortraitButtonGap = 4;

/// 横屏「转为竖屏」钮矩形（**屏幕坐标**）：锚由
/// **系统栏内缩**推出，不取中带容器内的固定 4dp。
///
/// - 左 = 左系统栏内缩 + 间隙——与返回键、顶栏同一条内缩线；
/// - 上 = 顶系统栏内缩 + 顶栏名义高 + 间隙（返回键正下方），底边不越过
///   [trackBandTop]（短屏上移，最多贴到顶系统栏内缩）。
///
/// **「不压画面」不是这枚钮的约束**：单画面与对比练习态都允许压在画面上
/// （半透明底衬保证可读）；唯一必须避开的是数拍数字的默认位置（真机基准下
/// 数字在 x ≈ 130–190，本钮右缘 105.4 在其左侧）与轨道带。
///
/// 返回的是**屏幕坐标**：消费方须在 SafeArea 之外按此矩形摆放，否则会被内缩
/// 挪位、与顶栏那条线错开。渲染父级必须是足够高的 Stack（横屏中带那个
/// `Expanded` Stack 只剩二十余 dp，会把这枚 32dp 的钮裁掉下半截）。
Rect landscapeToPortraitButtonRect({
  required double systemTopInset,
  required double systemLeftInset,
  required double trackBandTop,
}) {
  final left = systemLeftInset + _kLandscapeToPortraitButtonGap;
  final preferredTop =
      systemTopInset + kEditorTopBarHeight + _kLandscapeToPortraitButtonGap;
  final latestTop =
      trackBandTop -
      _kLandscapeToPortraitButtonGap -
      kLandscapeToPortraitButtonHeight;
  return Rect.fromLTWH(
    left,
    math.max(systemTopInset, math.min(preferredTop, latestTop)),
    kLandscapeToPortraitButtonWidth,
    kLandscapeToPortraitButtonHeight,
  );
}

/// 左下角提示卡的**名义高**（dp）：命中下限 48 + 胶囊垂直内边距 ×2（卡片
/// 紧凑档的垂直内边距为 0，故 = 48，与卡的渲染高一致）。只用于
/// [cornerPromptAnchor] 的「放不下」容量判定，不参与卡的渲染尺寸——真实高
/// 随系统字号变。
const double kCornerPromptCardNominalHeight =
    kHitTargetMinSize + kCornerPromptCardPaddingV * 2;

/// 提示卡相对**画面矩形**左下角的内缩（dp）。
const double kCornerPromptInset = 24;

/// 控制层展开时卡底边与控制层占用区上缘之间的间隙（dp）。
const double kCornerPromptOccupancyGap = 24;

/// 左下角提示卡落位的**唯一纯规则**：
/// 两张卡（循环提示、续播提示）共用，返回卡的**左下角屏幕坐标**——`left`
/// 距屏幕左缘、`bottom` 是卡底边的屏幕 y 坐标（原点在屏幕左上角）；
/// `null` = 本次放不下、不画。渲染侧按
/// `bottom: 屏高 − 锚.bottom` 落到 `Positioned` 语义（换算归调用侧）。
///
/// 落位三步，顺序固定：
/// ① **贴画面**：`left = 画面.left + 24`、`bottom = 画面.bottom − 24`；
/// ② **让路**：卡边落进屏幕边的系统手势让路带就推出带外
///    （`left = max(画面.left + 24, 手势.左)`、
///    `bottom = min(画面.bottom − 24, 屏高 − 手势.底)`）；
/// ③ **占用区**：控制层展开（[editingSkeleton] 非空）时卡底边不越过控制层
///    占用区上缘之上 24dp——占用区上缘 = 竖屏编辑态**画面区下缘**（该角正
///    下方就是看片工具行）、横屏编辑态**轨道带上缘**
///    （`屏高 − 系统栏底内缩 − 工具行名义高 − 整带高`；悬浮设置条不计入）。
///
/// 放不下就不画：卡的顶边不得高于顶栏下缘（`系统栏顶内缩 + 顶栏名义高`），
/// 名义高见 [kCornerPromptCardNominalHeight]（横屏编辑态的中带放不下 48dp 时
/// 本函数给 `null`）。
///
/// 入参即事实：不读状态、不碰容器、不引框架以外的任何东西。画面矩形由调用
/// 侧取既有读面给出（非对比态 = 备注贴纸同一份画面内容矩形，含竖屏编辑态的
/// 贴底画面带；对比态 = 组合根的源半区画面矩形）。
({double left, double bottom})? cornerPromptAnchor({
  required Rect pictureRect,
  required Size screen,
  required double systemTopInset,
  required double systemBottomInset,
  required double gestureLeft,
  required double gestureBottom,
  required EditorSkeleton? editingSkeleton,
  required double trackBandHeight,
}) {
  // ① 贴画面左下角、内缩 24dp。
  var left = pictureRect.left + kCornerPromptInset;
  var bottom = pictureRect.bottom - kCornerPromptInset;
  // ② 让路：只把落进屏幕边让路带的那条边推出带外。
  left = math.max(left, gestureLeft);
  bottom = math.min(bottom, screen.height - gestureBottom);
  // ③ 控制层展开：卡底边抬到占用区上缘之上 24dp。
  if (editingSkeleton != null) {
    final occupancyTop = editingSkeleton.portrait
        ? systemTopInset +
              kEditorTopBarHeight +
              editingSkeleton.pictureAreaHeight
        : screen.height -
              systemBottomInset -
              kEditorToolbarHeight -
              trackBandHeight;
    bottom = math.min(bottom, occupancyTop - kCornerPromptOccupancyGap);
  }
  // 放不下：卡的顶边高于顶栏下缘（大字号下卡的渲染高更大，判定只按名义高）。
  if (bottom - kCornerPromptCardNominalHeight <
      systemTopInset + kEditorTopBarHeight) {
    return null;
  }
  return (left: left, bottom: bottom);
}

/// 取消区半径：`min(88dp, 画面宽, 画面高)`——
/// 判定与标记取同一个值，画出来的圈就是生效的圈；画面很扁时随之收缩。
double cancelZoneRadius(Rect pictureRect) => math.min(
  kScrubCancelZoneSize,
  math.min(pictureRect.width, pictureRect.height),
);

/// 取消区判定（可直测的纯规则）：以画面矩形左上角
/// 为圆心、[cancelZoneRadius] 为半径的四分之一圆扇形——扇内（含半径边界等号
/// 档）待取消；方形角区内但扇形外的角落不待取消；画面外（dx 或 dy 为负）不
/// 待取消。判据用平方距离，不开根。
bool focalInCancelZone({ required Rect pictureRect, required Offset focal }) {
  final dx = focal.dx - pictureRect.left;
  final dy = focal.dy - pictureRect.top;
  if (dx < 0 || dy < 0) return false;
  final r = cancelZoneRadius(pictureRect);
  return dx * dx + dy * dy <= r * r;
}
