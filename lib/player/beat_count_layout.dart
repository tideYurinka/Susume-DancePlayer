/// **数拍数字在浮层内容区里的布局算术**（纯件：不建 widget、不碰 IO、不读
/// 构建上下文；`#30`）。
///
/// ## 为什么要有这一件
///
/// 手机上「数字落在哪」不是随手定的，而是
/// `Center → 底衬（内边距 16/10）→ Column[数字行, 间距 6, 节拍动画]` 这套
/// 布局算出来的。投屏副本里**不画节拍动画**（规格：呈现类只烤逐拍静态数字），
/// 但动画在 Column 里**占的那一格高度仍然要留着**——不留，数字就会比手机上
/// 低一截（半个动画条 + 间距），「电视上的位置与手机同一时刻一致」当场失效。
///
/// 所以本件把这条算术抽出来：上屏 widget（`BeatCountContent`）与投屏副本的
/// 光栅化（`cast_beat_sheet.dart`）**同读同一份常量与同一个式子**，不是照着
/// 上屏再写一遍。
///
/// ## 两形态
///
/// - **矩形**：内容区 = 浮层框（`宽 × 高·字号容量倍率`），数字按量测尺寸原样
///   落在里面；
/// - **摆锤**：内容区被 `FittedBox` 等比铺满基准盒（220 × 120·字号容量倍率），
///   故数字与底衬都随系数 [beatNumbersScaleInContent] 放大。
library;

import 'dart:ui' show Offset, Size;

import 'beat_animation.dart'
    show
        BeatAnimationStyle,
        kBeatBarAnimationHeight,
        kBeatPendulumAnimationHeight;
import 'overlay.dart' show kPendulumBaseContentSize, overlayContentHeightScale;

/// 数拍底衬的内边距（上屏 `BeatCountContent` 与投屏副本同读）。
const double kBeatPillPaddingH = 16;
const double kBeatPillPaddingV = 10;

/// 数字行与节拍动画之间的间距（上屏 `BeatCountContent` 与本节同读）。
const double kBeatNumbersGap = 6;

/// 数拍底衬的圆角（上屏 `BeatCountContent` 与投屏副本同读）。
const double kBeatPillRadius = 12;

/// 摆锤形态的等比系数：内容区宽 ÷ 摆锤基准宽（`FittedBox` 的等比铺满）。
/// 矩形形态恒 1（它只按宽系数改框宽，数字本身不缩放）。
double beatNumbersScaleInContent({
  required Size contentSize,
  required BeatAnimationStyle style,
}) {
  if (style != BeatAnimationStyle.pendulum) return 1;
  final base = kPendulumBaseContentSize.width;
  if (base <= 0) return 1;
  final scale = contentSize.width / base;
  return scale.isFinite && scale > 0 ? scale : 1;
}

/// 数字那一行在**内容区**里的中心（内容区坐标，逻辑单位）。
///
/// 同一条算术：底衬与它里面的 Column 一起被 `Center` 居中，
/// Column = 数字行 + 间距 + 动画位；数字行的中心因此是
/// `(内容区高 − 底衬高)/2 + 内边距 + 数字行高/2`。
///
/// [contentSize] 是**内容区**（`overlayContentSize` 的产出）；
/// [numbersSize] 是量出来的数字行逻辑尺寸（摆锤形态下按基准盒量、未乘系数）。
Offset beatNumbersCenterInContent({
  required Size contentSize,
  required Size numbersSize,
  required BeatAnimationStyle style,
  double textScale = 1,
}) {
  final scale = beatNumbersScaleInContent(
    contentSize: contentSize,
    style: style,
  );
  // 摆锤：先在基准盒（未缩放）里算，再乘系数；矩形：系数恒 1、就是内容区。
  final areaWidth = style == BeatAnimationStyle.pendulum
      ? kPendulumBaseContentSize.width
      : contentSize.width;
  final areaHeight = style == BeatAnimationStyle.pendulum
      ? kPendulumBaseContentSize.height * overlayContentHeightScale(textScale)
      : contentSize.height;
  final animationHeight = style == BeatAnimationStyle.pendulum
      ? kBeatPendulumAnimationHeight
      : kBeatBarAnimationHeight;
  final columnHeight = numbersSize.height + kBeatNumbersGap + animationHeight;
  final pillHeight = columnHeight + kBeatPillPaddingV * 2;
  final centerY =
      (areaHeight - pillHeight) / 2 +
      kBeatPillPaddingV +
      numbersSize.height / 2;
  return Offset(areaWidth / 2 * scale, centerY * scale);
}

/// 数字那一行的底衬尺寸（**绘制坐标**：已乘形态系数）——投屏副本里那格画布的
/// 大小就是它（各格的数字宽窄不同，取全部行里最大的那一份当固定画布，
/// 图像序列才是单条流）。
Size beatNumbersCanvasSize({
  required Size contentSize,
  required Size numbersSize,
  required BeatAnimationStyle style,
  double textScale = 1,
}) {
  final scale = beatNumbersScaleInContent(
    contentSize: contentSize,
    style: style,
  );
  return Size(
    (numbersSize.width + kBeatPillPaddingH * 2) * scale,
    (numbersSize.height + kBeatPillPaddingV * 2) * scale,
  );
}
