/// 单画面取景几何 + **上屏画面矩形**的唯一求解点。
///
/// [pictureRectOnScreen] 是「视频画面在屏幕上实际所占矩形」（见
/// `CONTEXT.md` 词条**画面矩形**）：贴纸尺寸分数与数拍落位的参考矩形、进度
/// 取消区、角落提示卡、局部镜像标识与画面手势分母都读这一份，全仓不再各解
/// 一次。它按三条规则取值：
///
/// - **取景后取值**：选区内容按 contain 装进可用区（选区自己的宽高比就是
///   它的宽高比）；
/// - **竖屏编辑贴底骨架**：可用区取骨架给的**画面带**（带顶按系统栏顶内缩
///   换算到屏幕坐标）；
/// - **其余单画面**（观看态、横屏编辑面、背景位骨架）= 可用区取整屏。
///
/// **取景态内按整帧**不入参：取景态的画面按未调过的整帧显示，故调用侧一律传
/// `selection: null`（与画面件 `FramingSelectionView` 的 `framingActive` 同口径）。
///
/// **宽高比未知只有一条兜底**：画面即容器——返回可用区本身，不另按系统栏内缩
/// 截一刀。
///
/// [framedContentRectInStage] 与 [videoContentRectInBox] 是本文件取值的两块
/// 基座：前者是「选区窗口 + 可用区 → 显示变换」那一份数学（与画面件渲染的是
/// 同一份），后者是宿主机箱内按宽高比 contain 的纯几何。
library;

import 'package:flutter/material.dart';

import '../annotation/framing_selection.dart'
    show FramingSelection, FramingSelectionGeometry, framingSelectionTransform;
import 'editor_skeleton.dart' show EditorSkeleton;
import 'note_sticker_layout.dart' show videoContentRectInBox;

/// **上屏画面矩形**（屏幕坐标）的唯一求解点。
///
/// [skeleton] 非空且贴底 = 竖屏编辑面的画面带；其余（含 `null`）= 整屏。
/// [selection] 非空 = 取景生效，取选区内容那一块；`null` = 未调过 / 取景态内
/// 的整帧。
Rect pictureRectOnScreen({
  required Size screen,
  required double systemTopInset,
  required EditorSkeleton? skeleton,
  required double? aspectRatio,
  required FramingSelection? selection,
}) {
  final sticksToBottom = skeleton != null && skeleton.sticksToBottom;
  final stage = sticksToBottom
      ? Rect.fromLTWH(
          0,
          skeleton.bandTopIn(systemTopInset: systemTopInset),
          screen.width,
          skeleton.pictureBandHeight,
        )
      : Rect.fromLTWH(0, 0, screen.width, screen.height);
  return framedContentRectInStage(
    stage: stage,
    aspectRatio: aspectRatio,
    sticksToBottom: sticksToBottom,
    selection: selection,
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
