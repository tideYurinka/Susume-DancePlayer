/// 单画面取景几何：普通编辑面／观看面的容器
/// 几何纯件。取值是那份**取景选区**（`framing_selection.dart`，按源画面原相
/// 归一化），渲染与手势共用本文件的两条几何：
///
/// - **竖屏编辑态贴底分支**：可用区 = 整个画面区，纵向把选区下缘对到画面区
///   下缘（未调过时画面仍贴底、与既有落位逐像素一致；圈小之后内容往上长、
///   把上方黑区吃掉）；
/// - **其余单画面（观看态、横屏编辑面、背景位）**：可用区 = 整屏，未调过 =
///   整屏 contain 居中。
///
/// [singlePicturePictureRectOnScreen] 同时是「点画面外」判定、黑边起手判定与
/// 拖动落点换算的分母——渲染层与手势域不各算一次。
library;

import 'package:flutter/material.dart';

import '../annotation/framing_selection.dart'
    show FramingSelection, FramingSelectionGeometry, framingSelectionTransform;
import 'editor_skeleton.dart' show EditorSkeleton, kEditorTopBarHeight;
import 'note_sticker_layout.dart' show videoContentRectInBox;

/// 单画面路径未调过的**画面矩形**（**屏幕坐标**）：点画面外退出的判定矩形
/// 与拖动落点换算的分母。退化分支（宽高比未知）返回 `null`——无「画面外」
/// 可达，退出走完成/返回。
Rect? singlePicturePictureRectOnScreen({
  required Size screen,
  required double systemTopInset,
  required EditorSkeleton? skeleton,
  required double? aspectRatio,
}) {
  final ratio = aspectRatio;
  if (ratio == null || ratio <= 0) return null;
  final sticks = skeleton != null && skeleton.sticksToBottom;
  if (sticks) {
    // 带盒满宽 contain（宽限高）：带顶 = 顶栏之下 + 骨架带顶（屏幕坐标）。
    final stageTop = systemTopInset + kEditorTopBarHeight;
    return Rect.fromLTWH(
      0,
      stageTop + skeleton.pictureBandTop,
      screen.width,
      skeleton.pictureBandHeight,
    );
  }
  final fittedHeight = screen.width / ratio;
  if (fittedHeight <= screen.height) {
    return Rect.fromLTWH(
      0,
      (screen.height - fittedHeight) / 2,
      screen.width,
      fittedHeight,
    );
  }
  final fittedWidth = screen.height * ratio;
  return Rect.fromLTWH(
    (screen.width - fittedWidth) / 2,
    0,
    fittedWidth,
    screen.height,
  );
}

/// **选区内容在本态可用区里显示的画面矩形**（[stage] 所在坐标系）：
/// 下游读数（备注贴纸、局部镜像标识、取消区、循环／续播提示卡）唯一共用的
/// 取景后几何。等于把「选区 + 可用区 → 显示变换」套到源画面 contain 基座上
/// 再取出选区内容那一块——与画面件渲染的是同一份数学。
///
/// `selection` 为 `null` = 未调过 → 返回源画面 contain 基座本身（未取景
/// 口径）。画面宽高比未知（画面即容器）时返回可用区本身、不套窗口。
Rect framedContentRectInStage({
  required Rect stage,
  required double? aspectRatio,
  required bool sticksToBottom,
  required FramingSelection? selection,
}) {
  final picture = videoContentRectInBox(
    box: stage.size,
    aspectRatio: aspectRatio,
  ).shift(stage.topLeft);
  final geometry = FramingSelectionGeometry(
    availableWidth: stage.width,
    availableHeight: stage.height,
    aspectRatio: aspectRatio,
    sticksToBottom: sticksToBottom,
  );
  if (!geometry.aspectKnown || stage.isEmpty) return picture;
  final resolved = selection ?? const FramingSelection.fullFrame();
  final transform = framingSelectionTransform(
    selection: selection,
    geometry: geometry,
  );
  final content = Rect.fromLTRB(
    picture.left + resolved.left * picture.width,
    picture.top + resolved.top * picture.height,
    picture.left + resolved.right * picture.width,
    picture.top + resolved.bottom * picture.height,
  );
  // 显示变换 = 绕可用区中心等比缩放 + 平移（与 [FramingSelectionView] 同形，
  // 但此处把选区那一块单独取出来）。
  final pivot = stage.center;
  final scaled = Rect.fromLTRB(
    pivot.dx + (content.left - pivot.dx) * transform.scale,
    pivot.dy + (content.top - pivot.dy) * transform.scale,
    pivot.dx + (content.right - pivot.dx) * transform.scale,
    pivot.dy + (content.bottom - pivot.dy) * transform.scale,
  );
  return scaled.shift(Offset(transform.translateX, transform.translateY));
}

/// 单画面路径**取景后的画面矩形**（**屏幕坐标**）：观看态 / 横屏
/// 编辑面 / 背景位 = 整屏可用区；竖屏编辑贴底分支 = 骨架给的画面带（带高
/// 已由 [editorSkeletonFor] 按选区内容比封顶在未取景画面矩形高）。未调过时
/// 与 [singlePicturePictureRectOnScreen] 同一条未取景画面矩形；宽高比未知返回 `null`。
Rect? singlePictureFramedPictureRectOnScreen({
  required Size screen,
  required double systemTopInset,
  required EditorSkeleton? skeleton,
  required double? aspectRatio,
  required FramingSelection? selection,
}) {
  final ratio = aspectRatio;
  if (ratio == null || ratio <= 0) return null;
  final sticks = skeleton != null && skeleton.sticksToBottom;
  if (sticks) {
    final stage = Rect.fromLTWH(
      0,
      systemTopInset + kEditorTopBarHeight + skeleton.pictureBandTop,
      screen.width,
      skeleton.pictureBandHeight,
    );
    return framedContentRectInStage(
      stage: stage,
      aspectRatio: ratio,
      sticksToBottom: true,
      selection: selection,
    );
  }
  return framedContentRectInStage(
    stage: Rect.fromLTWH(0, 0, screen.width, screen.height),
    aspectRatio: ratio,
    sticksToBottom: false,
    selection: selection,
  );
}
