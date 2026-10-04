/// 贴纸布局纯件：窗内显隐谓词 + 归一化几何 → 内容矩形像素换算。
///
/// - 显隐只看「播放头 ∈ 时间窗」（半开 `[startMs, endMs)`），与播放 /
///   暂停无关；对乱序 / 重叠的异常输入优雅降级（取命中
///   的一条、不崩）。
/// - 像素换算：位置取中心归一化（内容矩形坐标系），尺寸按等比系数放大
///   后钳进内容矩形（钳制退化 = 贴纸大于内容矩形时居中放置）。
/// - **随面换算**：画面方向生效时，贴纸按该面方向做水平坐标换算
///   （[noteStickerCenterOnFace]）——几何仍以视频原相归一化坐标存储，换算
///   只发生在「归一化 → 屏幕」这一处；文字与图标不套翻转变换，故保持正向。
library;

import 'dart:ui' show Offset, Rect, Size;

import '../annotation/framing_selection.dart' show FramingSelection;
import '../annotation/note_sticker.dart';
import '../surface_direction/surface_direction.dart' show FaceDirection;

/// 贴纸基准字号（缩放系数 1.0 时；字号由贴纸整体缩放承担）。
const double kNoteStickerBaseFontSize = 24;

/// 播放头 [positionMs] 所在时间窗内的备注；窗外 / 无备注返回 null。
/// 列表按起点升序是编辑侧不变量；对乱序 / 重叠输入取扫描中首条命中的。
NoteSticker? noteStickerAt(List<NoteSticker> notes, int positionMs) {
  final index = noteStickerIndexAt(notes, positionMs);
  return index == null ? null : notes[index];
}

/// 播放头 [positionMs] 所在时间窗内的备注索引（贴纸几何命令的
/// 定位依据）；窗外 / 无备注返回 null。命中口径与 [noteStickerAt] 同源。
int? noteStickerIndexAt(List<NoteSticker> notes, int positionMs) {
  for (var i = 0; i < notes.length; i++) {
    final note = notes[i];
    if (positionMs >= note.startMs && positionMs < note.endMs) return i;
  }
  return null;
}

/// 贴纸手势换算（**像素 ↔ 归一化几何的全仓单点**）：以手势
/// 起手的几何 [start] 为基，单指平移增量 [panDelta]（**屏幕**空间像素）按
/// [contentRect] 尺寸换算为中心归一化增量，双指捏合倍率 [pinchRatio]
/// 乘到等比系数（字号随整体缩放承担）。内容矩形为空 = 无参考系可换算，
/// 原样返回（不崩）。钳制不在此处——按模块纪律钳制在模块内单点收口
///（[clampNoteGeometry]）。
///
/// [faceDirection] 是这一层换算是**渲染换算的逆**：屏幕位置 =
/// [noteStickerCenterOnFace]（归一化几何），故屏幕上向右的位移在镜像下
/// 对应归一化 `x` **减小**——不按面方向反相一次，贴纸就会反着手指走。
///
/// [selection]：渲染先把源点按**选区窗口**换算再映射到取景后的
/// 画面矩形，故归一化增量的逆要多乘一次窗口尺寸（屏幕位移 → 窗口归一化
/// 位移 → 源归一化位移），贴纸才始终跟手。未调过（null）= 窗口即整帧。
NoteGeometry noteGeometryFromGesture({
  required NoteGeometry start,
  required Rect contentRect,
  required Offset panDelta,
  required double pinchRatio,
  required FaceDirection faceDirection,
  FramingSelection? selection,
}) {
  if (contentRect.isEmpty) return start;
  final windowWidth = selection?.width ?? 1.0;
  final windowHeight = selection?.height ?? 1.0;
  return NoteGeometry(
    centerX:
        start.centerX +
        panDelta.dx * faceDirection.scaleX * windowWidth / contentRect.width,
    centerY: start.centerY + panDelta.dy * windowHeight / contentRect.height,
    scale: start.scale * pinchRatio,
  );
}

/// 贴纸中心在**面**上的位置（随面换算单点）：把视频原相归一化坐标
/// [center] 换算成该面此刻的归一化坐标——[FaceDirection.mirrored] 时水平
/// 分量按「到框边的距离」取反（`x → 1 - x`，贴纸仍贴它标的那个舞者），
/// 纵向与文字 / 图标朝向都不参与。
///
/// 渲染（[noteStickerRect]）与手势（[noteGeometryFromGesture] 的逆）都以本
/// 换算为准：一处取反、另一处取反回来，屏幕上贴纸始终跟手。
Offset noteStickerCenterOnFace({
  required Offset center,
  required FaceDirection faceDirection,
}) => faceDirection.isMirrored ? Offset(1 - center.dx, center.dy) : center;

/// 备注贴纸在播放页坐标系里的像素矩形：[geometry]（内容矩形归一化）经
/// **选区窗口**换算（`(源点 − 选区原点) ÷ 选区尺寸`）、[faceDirection]
/// 换算后映射到 [contentRect]（取景后的画面矩形），贴纸实际尺寸 [stickerSize]
/// 按等比系数放大，中心钳进内容矩形（贴纸完整落在画面内；放大后仍超框
/// 则居中）。
///
/// [selection] 为 `null` = 未调过 → 窗口即整帧（整帧口径）。
/// 屏幕尺寸只吃 [NoteGeometry.scale]，**不随取景缩放**。
///
/// 换算与钳制都在本函数里：渲染矩形即命中矩形（注册表消费同一返回值），
/// 不存在「画在一处、点在另一处」。
Rect noteStickerRect({
  required NoteGeometry geometry,
  required Rect contentRect,
  required Size stickerSize,
  required FaceDirection faceDirection,
  FramingSelection? selection,
}) {
  final scaled = stickerSize * geometry.scale;
  final center = noteStickerCenterOnFace(
    center: _noteCenterInWindow(
      center: Offset(geometry.centerX, geometry.centerY),
      selection: selection,
    ),
    faceDirection: faceDirection,
  );
  final mapped =
      contentRect.topLeft +
      Offset(center.dx * contentRect.width, center.dy * contentRect.height);
  // 逐轴钳制：轴上装得下 → 中心钳进框（矩形完整留在框内）；装不下
  // （贴纸大于内容矩形）→ 该轴居中（钳制退化）。
  final dx = scaled.width >= contentRect.width
      ? contentRect.center.dx
      : mapped.dx.clamp(
          contentRect.left + scaled.width / 2,
          contentRect.right - scaled.width / 2,
        );
  final dy = scaled.height >= contentRect.height
      ? contentRect.center.dy
      : mapped.dy.clamp(
          contentRect.top + scaled.height / 2,
          contentRect.bottom - scaled.height / 2,
        );
  return Rect.fromCenter(
    center: Offset(dx, dy),
    width: scaled.width,
    height: scaled.height,
  );
}

/// 源画面归一化点 → **选区窗口**归一化点：`(源点 − 选区原点) ÷
/// 选区尺寸`。未调过（null）= 整帧、恒等。窗口外的点保留越界量（渲染侧
/// 再按取景后的画面矩形钳到边缘）。
Offset _noteCenterInWindow({
  required Offset center,
  required FramingSelection? selection,
}) {
  if (selection == null) return center;
  return Offset(
    (center.dx - selection.left) / selection.width,
    (center.dy - selection.top) / selection.height,
  );
}

/// 宿主框（全屏播放页 Stack）内按引擎宽高比 contain 居中推导**视频内容
/// 矩形**（宿主接线；信箱内的画面区）。[aspectRatio] 未知（null /
/// 非法）时按宿主框整体兜底（优雅降级，与画面渲染层回落口径一致）；
/// 宿主框为空返回零矩形。
Rect videoContentRectInBox({required Size box, required double? aspectRatio}) {
  if (box.isEmpty) return Rect.zero;
  final ratio = aspectRatio;
  if (ratio == null || ratio <= 0 || ratio.isNaN) {
    return Rect.fromLTWH(0, 0, box.width, box.height);
  }
  final fittedWidth = box.height * ratio;
  if (fittedWidth <= box.width) {
    return Rect.fromLTWH(
      (box.width - fittedWidth) / 2,
      0,
      fittedWidth,
      box.height,
    );
  }
  final fittedHeight = box.width / ratio;
  return Rect.fromLTWH(
    0,
    (box.height - fittedHeight) / 2,
    box.width,
    fittedHeight,
  );
}
