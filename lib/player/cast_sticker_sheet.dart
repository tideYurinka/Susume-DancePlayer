/// **贴纸图光栅化**（播放页侧）：把一条备注贴纸按**上屏同一份 span 与样式**
/// 画进一张带 alpha 的**单帧 PNG**——投屏渲染的第二路输入就是它。
///
/// ## 为什么在播放页侧画、而不是让 ffmpeg 画字
///
/// 贴纸的观感全在 Flutter 那套文本排版里：正文恒白、点名段取名册代表色、描边
/// 按底色派生、纯白点名段还要在白边之外再包一层更细的黑边（见
/// `note_sticker_overlay.dart`）。`drawtext` 拿不到这些（字体度量与 Flutter 不同
/// 源、点名分段要再拼一条口径），于是：「样式与手机一致」这句话的落实方式就是
/// **复用上屏那三层 span 与同一个样式构造器**——不是照着它再写一遍。
///
/// 具体复用面：
/// - 分段装配：[NoteMentionSpans]（点名语法解析 + 填充 span，与上屏同一入口）；
/// - 描边层：[noteStickerStrokeSpans] / [noteStickerOuterStrokeSpans]；
/// - 基础样式：[noteStickerTextStyle]（`inherit: false`，不与环境默认样式合并）；
/// - 字号：`kNoteStickerBaseFontSize × geometry.scale`（上屏那一式）；
/// - 量测：[measureTextSpanExtent]（上屏量贴纸盒用的同一件）。
///
/// 三层各自建一个 [TextPainter] 画在**同一个原点**上（与上屏那三层
/// `Text.rich` 的层序一致：外黑边 → 描边 → 填充），画布透明，因此 PNG 的 alpha
/// 就是文字墨迹本身——含抗锯齿的半透明边沿（**乘**出来的，不是设出来的）。
///
/// ## 尺寸
///
/// 画布逻辑尺寸 = 量测盒 + 每边一个描边线宽的余量（描边以字形轮廓为中心向内外
/// 各溢半个线宽，上屏那三层是 `Clip.none`、墨迹本来就溢出盒外）。这个**逻辑
/// 尺寸**就是归一化落位的分子：装配处按它除以**上屏画面矩形**得到
/// `CastSticker` 的宽高分数（见 `cast_render_wiring.dart`），于是电视上的贴纸
/// 与手机上的贴纸占同一块画面的同一个比例。
///
/// 像素尺寸 = 逻辑尺寸 × [kCastStickerSheetDensity]：投屏副本的帧宽通常是手机
/// 画面区宽的好几倍，密度留出富余——链上 `scale2ref` 是**下采样**到帧的比例，
/// 下采样不掉清晰度，往小里画才是糊的。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../annotation/note_sticker.dart';
import '../core/text_extent.dart' show measureTextSpanExtent;
import 'note_sticker_layout.dart' show kNoteStickerBaseFontSize;
import 'note_sticker_overlay.dart'
    show
        NoteMentionSpans,
        kNoteStickerOutlineWidth,
        noteStickerOuterStrokeSpans,
        noteStickerStrokeSpans,
        noteStickerTextStyle;

/// 贴纸图的像素密度（每逻辑像素几个像素）：见库头「尺寸」。
const double kCastStickerSheetDensity = 4;

/// 一条贴纸的光栅化结果。
class CastStickerRaster {
  const CastStickerRaster({
    required this.bytes,
    required this.widthPx,
    required this.heightPx,
    required this.logicalSize,
  });

  /// 带 alpha 的单帧 PNG 字节。
  final Uint8List bytes;

  /// PNG 像素宽。
  final int widthPx;

  /// PNG 像素高。
  final int heightPx;

  /// 逻辑尺寸（量测盒 + 描边余量）——归一化落位的分子。
  final Size logicalSize;

  @override
  String toString() =>
      'CastStickerRaster($widthPx×$heightPx, logical $logicalSize)';
}

/// 贴纸盒的量测与画布逻辑尺寸（**量测与渲染同源的那一处**）：上屏贴纸盒按
/// [measureTextSpanExtent] 量出可视分段，这里再多给每边一个描边线宽的余量。
///
/// 空文本（量测不出宽或高）给 `null`：没有可画的墨迹，宁可不装这一条第二路输入。
Size? castStickerSheetLogicalSize({
  required NoteSticker note,
  required Map<String, int> rosterColors,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final spans = NoteMentionSpans(note, rosterColors);
  final measured = measureTextSpanExtent(
    TextSpan(
      style: noteStickerTextStyle(
        kNoteStickerBaseFontSize * note.geometry.scale,
      ),
      children: spans.fillSpans,
    ),
    scaler: textScaler,
    maxLines: 1,
  );
  if (!measured.width.isFinite ||
      !measured.height.isFinite ||
      measured.width <= 0 ||
      measured.height <= 0) {
    return null;
  }
  return Size(
    measured.width + kNoteStickerOutlineWidth * 2,
    measured.height + kNoteStickerOutlineWidth * 2,
  );
}

/// 把一条备注贴纸画成一张带 alpha 的单帧 PNG。
Future<CastStickerRaster?> renderCastStickerSheet({
  required NoteSticker note,
  required Map<String, int> rosterColors,
  TextScaler textScaler = TextScaler.noScaling,
  double density = kCastStickerSheetDensity,
}) async {
  final logical = castStickerSheetLogicalSize(
    note: note,
    rosterColors: rosterColors,
    textScaler: textScaler,
  );
  if (logical == null || !density.isFinite || density <= 0) return null;
  final pixelWidth = (logical.width * density).round();
  final pixelHeight = (logical.height * density).round();
  if (pixelWidth <= 0 || pixelHeight <= 0) return null;

  final spans = NoteMentionSpans(note, rosterColors);
  final style = noteStickerTextStyle(
    kNoteStickerBaseFontSize * note.geometry.scale,
  );
  final outerStroke = _painter(
    noteStickerOuterStrokeSpans(
      segments: spans.mention.segments,
      rosterColors: rosterColors,
    ),
    style,
    textScaler,
  );
  final painters = <TextPainter>[
    // 层序与上屏一致：外层黑边（纯白点名段才有）→ 描边 → 填充。
    ?outerStroke,
    _painter(
      TextSpan(
        children: noteStickerStrokeSpans(
          segments: spans.mention.segments,
          rosterColors: rosterColors,
        ),
      ),
      style.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = kNoteStickerOutlineWidth
          ..color = const Color(kNoteStrokeBlackColor),
      ),
      textScaler,
    )!,
    _painter(
      TextSpan(children: spans.fillSpans),
      style.copyWith(color: const Color(kNoteBodyColor)),
      textScaler,
    )!,
  ];

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(density);
  // 每边让出一个描边线宽：描边墨迹不被画布裁掉（上屏那三层是 Clip.none）。
  canvas.translate(kNoteStickerOutlineWidth, kNoteStickerOutlineWidth);
  for (final painter in painters) {
    painter.paint(canvas, Offset.zero);
    painter.dispose();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(pixelWidth, pixelHeight);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) return null;
  return CastStickerRaster(
    bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    widthPx: pixelWidth,
    heightPx: pixelHeight,
    logicalSize: logical,
  );
}

/// 只在这一层有内容时建 painter（层为空 = 不画、不多一次排版）。
TextPainter? _painter(TextSpan? span, TextStyle style, TextScaler textScaler) {
  if (span == null) return null;
  return TextPainter(
    text: span,
    textScaler: textScaler,
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
}
