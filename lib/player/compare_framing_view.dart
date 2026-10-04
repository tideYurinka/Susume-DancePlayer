import 'package:flutter/material.dart';

import '../annotation/framing_selection.dart' show FramingSelection;
import 'compare_split.dart' show kCompareSplitGap;
import 'framing_stage.dart' show framedContentRectInStage;

/// 侧别半区尺寸（分屏几何的单一声明：横屏左右等分、竖屏上下等分，
/// 扣除细缝）。取景手势的归一化与「点画面外」判定共用。
Size compareFramingPaneSize({required Size screen, required bool landscape}) =>
    landscape
    ? Size((screen.width - kCompareSplitGap) / 2, screen.height)
    : Size(screen.width, (screen.height - kCompareSplitGap) / 2);

/// 源侧半区**取景后的画面矩形**（半区原点 + 选区内容 contain 居中画面，
/// 全局坐标）：取景手势的「点画面外」退出判定、落点换算与 scrub
/// 取消区几何共用同一口径。`selection` 为 `null` = 未调过 → 即源半区
/// contain 画面矩形。
Rect compareFramingPictureRect({
  required Size screen,
  required bool landscape,
  required double? aspectRatio,
  FramingSelection? selection,
}) {
  final pane = compareFramingPaneSize(screen: screen, landscape: landscape);
  return framedContentRectInStage(
    stage: Rect.fromLTWH(0, 0, pane.width, pane.height),
    aspectRatio: aspectRatio,
    sticksToBottom: false,
    selection: selection,
  );
}
