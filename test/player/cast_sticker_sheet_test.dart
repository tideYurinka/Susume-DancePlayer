import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/core/text_extent.dart'
    show measureTextSpanExtent;
import 'package:dance_learning_app/player/cast_sticker_sheet.dart';
import 'package:dance_learning_app/player/note_sticker_layout.dart'
    show kNoteStickerBaseFontSize;
import 'package:dance_learning_app/player/note_sticker_overlay.dart'
    show NoteMentionSpans, kNoteStickerOutlineWidth, noteStickerTextStyle;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// 贴纸图光栅化直测：产物是**带 alpha 的单帧 PNG**，判定只看 PNG 自己的像素
/// 事实（尺寸、alpha、点名取色）——不反算被测代码的算式。
///
/// 「与手机一致」在这里是**同源**而不是逐像素复刻：三层 span、基础样式、字号与
/// 量测都复用上屏那一套（见库头），因此这些用例钉的是「同一份材料真的进了
/// 画布」，逐帧观感仍归真机验收。
void main() {
  NoteSticker note({
    String text = '走位',
    double scale = 1,
    double centerX = 0.5,
    double centerY = 0.12,
  }) => NoteSticker(
    startMs: 0,
    endMs: 1000,
    text: text,
    geometry: NoteGeometry(centerX: centerX, centerY: centerY, scale: scale),
  );

  /// 解开 PNG 读像素（rgba 顺序）：产物事实的独立读数。
  Future<({int width, int height, Uint8List rgba})> decode(
    Uint8List bytes,
  ) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final reading = (
      width: image.width,
      height: image.height,
      rgba: data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    image.dispose();
    codec.dispose();
    return reading;
  }

  int alphaAt(({int width, int height, Uint8List rgba}) image, int x, int y) =>
      image.rgba[(y * image.width + x) * 4 + 3];

  (int, int, int) colorAt(
    ({int width, int height, Uint8List rgba}) image,
    int x,
    int y,
  ) {
    final offset = (y * image.width + x) * 4;
    return (image.rgba[offset], image.rgba[offset + 1], image.rgba[offset + 2]);
  }

  group('产物是一张带 alpha 的单帧 PNG', () {
    test('PNG 签名 + 像素尺寸 = 逻辑尺寸 × 密度', () async {
      final raster = (await renderCastStickerSheet(
        note: note(),
        rosterColors: const {},
      ))!;

      expect(raster.bytes.sublist(0, 8), <int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);
      expect(raster.widthPx, (raster.logicalSize.width * 4).round());
      expect(raster.heightPx, (raster.logicalSize.height * 4).round());
      final image = await decode(raster.bytes);
      expect(image.width, raster.widthPx);
      expect(image.height, raster.heightPx);
    });

    test('逻辑尺寸 = 量测盒 + 每边一个描边线宽的余量（描边墨迹不被裁）', () async {
      final raster = (await renderCastStickerSheet(
        note: note(),
        rosterColors: const {},
      ))!;
      // 独立量一遍上屏那个盒（上屏量测与渲染同源的唯一样式）。
      final measured = measureTextSpanExtent(
        TextSpan(
          style: noteStickerTextStyle(kNoteStickerBaseFontSize),
          children: NoteMentionSpans(note(), const {}).fillSpans,
        ),
        maxLines: 1,
      );

      expect(
        raster.logicalSize.width,
        closeTo(measured.width + kNoteStickerOutlineWidth * 2, 1e-9),
        reason: '每边让出一个描边线宽：描边墨迹（半个线宽）不被画布裁掉',
      );
      expect(
        raster.widthPx,
        greaterThan((measured.width * 4).round()),
        reason: 'PNG 也把这一圈余量画进去',
      );
    });

    test('四角透明：底色是透明的，不是黑底或白底', () async {
      final raster = (await renderCastStickerSheet(
        note: note(),
        rosterColors: const {},
      ))!;
      final image = await decode(raster.bytes);

      expect(alphaAt(image, 0, 0), 0);
      expect(alphaAt(image, image.width - 1, 0), 0);
      expect(alphaAt(image, 0, image.height - 1), 0);
      expect(alphaAt(image, image.width - 1, image.height - 1), 0);
    });

    test('alpha 通道真的留在 PNG 里：墨迹不透明、余量透明（不压在不透明底上）', () async {
      final raster = (await renderCastStickerSheet(
        note: note(text: '走位八拍'),
        rosterColors: const {},
      ))!;
      final image = await decode(raster.bytes);
      final alphas = <int>{
        for (var i = 3; i < image.rgba.length; i += 4) image.rgba[i],
      };

      expect(alphas, contains(255), reason: '字形内部是全不透明的白字');
      expect(alphas, contains(0), reason: '余量那一圈是透明——没有底色被烤进来');
      // 半透明边沿（抗锯齿）在 `flutter test` 的测试字体下是二值的：逐像素的
      // 混合验收归宿主对照（`tool/cast_sticker_check_host.dart`）与真机。
    });

    test('正文恒白：字形内部的填充色就是白', () async {
      final raster = (await renderCastStickerSheet(
        note: note(text: '走位'),
        rosterColors: const {},
      ))!;
      final image = await decode(raster.bytes);
      final whites = <({int x, int y})>[];
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (alphaAt(image, x, y) == 255) {
            final (r, g, b) = colorAt(image, x, y);
            if (r > 240 && g > 240 && b > 240) whites.add((x: x, y: y));
          }
        }
      }

      expect(whites, isNotEmpty, reason: '正文恒白（kNoteBodyColor）');
    });

    test('点名段用名册代表色（与上屏同一份取色）', () async {
      const green = 0xFF00FF00;
      final raster = (await renderCastStickerSheet(
        note: note(text: '@小蓝 走位'),
        rosterColors: const {'小蓝': green},
      ))!;
      final image = await decode(raster.bytes);
      var greenish = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (alphaAt(image, x, y) < 200) continue;
          final (r, g, b) = colorAt(image, x, y);
          if (g > 200 && r < 80 && b < 80) greenish++;
        }
      }

      expect(greenish, greaterThan(0), reason: '点名段取代表色，正文段不是这个色');
    });

    test('字号随等比系数放大：尺寸系数真的进了画布', () async {
      final small = (await renderCastStickerSheet(
        note: note(scale: 1),
        rosterColors: const {},
      ))!;
      final large = (await renderCastStickerSheet(
        note: note(scale: 2),
        rosterColors: const {},
      ))!;

      expect(
        large.logicalSize.height,
        greaterThan(small.logicalSize.height),
        reason: '字号 = 基准字号 × 等比系数（上屏那一式）',
      );
    });

    test('随系统字号缩放：量测与渲染吃同一个 textScaler', () async {
      final plain = (await renderCastStickerSheet(
        note: note(),
        rosterColors: const {},
      ))!;
      final scaled = (await renderCastStickerSheet(
        note: note(),
        rosterColors: const {},
        textScaler: const TextScaler.linear(2),
      ))!;

      expect(scaled.logicalSize.width, greaterThan(plain.logicalSize.width));
    });

    test('空文本量不出墨迹：不产出第二路输入', () async {
      expect(
        await renderCastStickerSheet(
          note: note(text: ''),
          rosterColors: const {},
        ),
        isNull,
      );
    });
  });
}
