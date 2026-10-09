/// **数拍层的光栅化**（播放页侧；`#30`）：把「八拍号 + 组上标 + 拍号」这一行按
/// **上屏同一份样式**画进一张带 alpha 的 PNG——投屏副本里数拍那一层的每一格
/// 就是它。
///
/// ## 为什么在播放页侧画
///
/// `drawtext` 这条路在**已链接的 ffmpeg 变体里不存在**：`ffmpeg_kit_flutter_new_min`
/// 零外部库（没有 `libfreetype`），`libavfilter` 里根本没有 `drawtext` 滤镜
/// ——这一点在 `lib/cast/docs/real-device-acceptance.md` 的实测留档里写明。于是
/// 与备注贴纸（`#29`）同款：字由 Flutter 侧按**上屏同一份样式**光栅化，投屏域
/// 只把它当一路输入叠上去。
///
/// 具体复用面：样式 [beatEightCountTextStyle] / [beatCountTextStyle] /
/// [beatGroupTextStyle]、字号与间距常量、底衬内边距与圆角、以及
/// [beatCountTextOf]（文字取值）——不是照着上屏再写一遍。
///
/// ## 只画数字：节拍动画一像素都不进副本
///
/// 规格把呈现类定成「只烤逐拍静态数字，不做摆锤动画」。因此本件画的只有数字行
/// 与它的底衬：动画条、摆锤、游标、拖尾一个都不画（`cast_beat_sheet_test.dart`
/// 用「画布=数字行的底衬尺寸」与「动画位那一圈没有像素」两条在场断言钉住）。
///
/// ## 画布尺寸固定：图像序列是**一条流**
///
/// 逐拍 PNG 走 `-f concat` 当**一路输入**（见 `cast_beat_gate.dart` 库头），
/// 因此每一格的像素尺寸必须一致。各格数字宽窄不同，故取全部行里**最大**的那一份
/// 底衬当固定画布（[beatNumbersCanvasSize]），逐格把底衬居中画进去——而每格的
/// 底衬中心，正是手机上那一行数字的中心（[beatNumbersCenterInContent]），
/// 于是「哪一格」不影响落位。
library;

import 'dart:math' show max;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../cast/cast_beat_count.dart';
import 'beat_count_layout.dart'
    show
        kBeatNumbersGap,
        kBeatPillPaddingH,
        kBeatPillPaddingV,
        kBeatPillRadius;
import 'metronome_overlay.dart'
    show
        beatCountTextStyle,
        beatEightCountTextStyle,
        beatGroupTextStyle,
        kBeatGroupLeftInset;

/// 数拍层 PNG 的像素密度（每逻辑像素几个像素）：副本帧宽通常是手机画面区宽的
/// 好几倍，留出富余——`scale2ref` 是下采样到帧的比例，往小里画才是糊的。
const double kCastBeatSheetDensity = 4;

/// 一行数拍数字的逻辑几何（**与上屏同一份样式与基线排版**）。
///
/// 三个位置都在这一行的左上角坐标系里：八拍号与拍号按**共同基线**对齐
/// （上屏那一行 `Row(crossAxisAlignment: baseline)` 的口径），组上标悬在行左上角
/// （上屏是 `Stack` 里 `Positioned(left: 0, top: 0)`），八拍号因此右移
/// [kBeatGroupLeftInset] 给上标让位。
class CastBeatRowGeometry {
  const CastBeatRowGeometry({
    required this.size,
    required this.eightTopLeft,
    required this.beatTopLeft,
    this.groupTopLeft,
  });

  /// 这一行的量测尺寸（宽含上标让位与两数间距）。
  final Size size;

  /// 八拍号（青·大）在这一行里的左上角。
  final Offset eightTopLeft;

  /// 拍号（白·小）在这一行里的左上角。
  final Offset beatTopLeft;

  /// 组上标在这一行里的左上角（无组上标时为 null）。
  final Offset? groupTopLeft;
}

/// 量一行数拍数字；量不出墨迹（空文本 / 尺寸退化）时给 null——没有可画的字
/// 就不装这一格的内容（画一张全透明画布）。
CastBeatRowGeometry? measureCastBeatRow({
  required CastBeatCountText text,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final eight = _measure(text.eightCount, beatEightCountTextStyle(), textScaler);
  final beat = _measure(text.beatCount, beatCountTextStyle(), textScaler);
  final groupText = text.group;
  final group = groupText == null
      ? null
      : _measure(groupText, beatGroupTextStyle(), textScaler);
  if (eight == null || beat == null) return null;
  if (groupText != null && group == null) return null;

  // 共同基线（与 RenderFlex 的 baseline 对齐同一算式）：行高 = 最大基线
  // + 最大基线以下的下沉。
  final eightBaseline = eight.baseline;
  final beatBaseline = beat.baseline;
  final baseline = max(eightBaseline, beatBaseline);
  final descent = max(
    eight.size.height - eightBaseline,
    beat.size.height - beatBaseline,
  );
  final leftInset = group == null ? 0.0 : kBeatGroupLeftInset;
  return CastBeatRowGeometry(
    size: Size(
      leftInset + eight.size.width + kBeatNumbersGap + beat.size.width,
      baseline + descent,
    ),
    eightTopLeft: Offset(leftInset, baseline - eightBaseline),
    beatTopLeft: Offset(
      leftInset + eight.size.width + kBeatNumbersGap,
      baseline - beatBaseline,
    ),
    groupTopLeft: group == null ? null : Offset.zero,
  );
}

/// 全部行里**最大**的那一份数字行尺寸（固定画布的分子）：一行都量不出来时给
/// null——那就不装这一层。
Size? castBeatNumbersSizeOf({
  required List<CastBeatCountRow> rows,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  var width = 0.0;
  var height = 0.0;
  for (final row in rows) {
    final text = row.text;
    if (text == null) continue;
    final geometry = measureCastBeatRow(text: text, textScaler: textScaler);
    if (geometry == null) continue;
    if (geometry.size.width > width) width = geometry.size.width;
    if (geometry.size.height > height) height = geometry.size.height;
  }
  if (width <= 0 || height <= 0) return null;
  return Size(width, height);
}

/// 一格画布的渲染：[text] 为 null（这一段不显示数拍）时画一张**全透明**画布
/// ——序列要连续覆盖整片，漏一格整条时间轴就错位。
///
/// [canvasLogicalSize] 是固定画布的逻辑尺寸（各格同一份，
/// [beatNumbersCanvasSize] 的产出）；[scale] 是形态缩放（摆锤等比，矩形 = 1）。
Future<Uint8List> renderCastBeatSheet({
  required CastBeatCountText? text,
  required Size canvasLogicalSize,
  required double scale,
  TextScaler textScaler = TextScaler.noScaling,
  double density = kCastBeatSheetDensity,
}) async {
  final pixelWidth = (canvasLogicalSize.width * density).round();
  final pixelHeight = (canvasLogicalSize.height * density).round();
  if (pixelWidth <= 0 || pixelHeight <= 0) {
    throw StateError('数拍层画布尺寸不成立：$canvasLogicalSize × $density');
  }
  final geometry = text == null
      ? null
      : measureCastBeatRow(text: text, textScaler: textScaler);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(density);
  if (geometry != null) {
    // 底衬：与上屏同一个内边距与圆角，随形态缩放一起放大。
    final pill = Rect.fromCenter(
      center: Offset(canvasLogicalSize.width / 2, canvasLogicalSize.height / 2),
      width: (geometry.size.width + kBeatPillPaddingH * 2) * scale,
      height: (geometry.size.height + kBeatPillPaddingV * 2) * scale,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        pill,
        Radius.circular(kBeatPillRadius * scale),
      ),
      Paint()..color = kBeatPillColor,
    );
    canvas.save();
    canvas.translate(pill.center.dx, pill.center.dy);
    canvas.scale(scale);
    canvas.translate(-geometry.size.width / 2, -geometry.size.height / 2);
    for (final layer in _rowLayers(geometry, text!, textScaler)) {
      layer.painter.paint(canvas, layer.topLeft);
      layer.painter.dispose();
    }
    canvas.restore();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(pixelWidth, pixelHeight);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('数拍层画布编码不出 PNG');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// 数拍层底衬的颜色（与上屏 `BeatCountContent` 的 `Colors.black
/// withValues(alpha: 0.45)` 同一个值：0.45 × 255 四舍五入 = 115 = 0x73）。
const Color kBeatPillColor = Color(0x73000000);

/// 一行里的三层（次序 = 上屏的绘制次序：组上标、八拍号、拍号）。
List<({TextPainter painter, Offset topLeft})> _rowLayers(
  CastBeatRowGeometry geometry,
  CastBeatCountText text,
  TextScaler textScaler,
) => <({TextPainter painter, Offset topLeft})>[
  if (text.group != null && geometry.groupTopLeft != null)
    (
      painter: _layout(text.group!, beatGroupTextStyle(), textScaler),
      topLeft: geometry.groupTopLeft!,
    ),
  (
    painter: _layout(text.eightCount, beatEightCountTextStyle(), textScaler),
    topLeft: geometry.eightTopLeft,
  ),
  (
    painter: _layout(text.beatCount, beatCountTextStyle(), textScaler),
    topLeft: geometry.beatTopLeft,
  ),
];

({Size size, double baseline})? _measure(
  String value,
  TextStyle style,
  TextScaler scaler,
) {
  if (value.isEmpty) return null;
  final painter = _layout(value, style, scaler);
  final size = Size(painter.width, painter.height);
  final baseline = painter.computeDistanceToActualBaseline(
    TextBaseline.alphabetic,
  );
  painter.dispose();
  if (!size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0 ||
      !baseline.isFinite) {
    return null;
  }
  return (size: size, baseline: baseline);
}

TextPainter _layout(String value, TextStyle style, TextScaler scaler) =>
    TextPainter(
      text: TextSpan(text: value, style: style),
      textScaler: scaler,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
