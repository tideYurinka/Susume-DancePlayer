import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dance_learning_app/core/current_beat.dart'
    show BeatCountDisplay, LeadingBeatCount, PracticeBeatCount;
import 'package:dance_learning_app/player/beat_animation.dart'
    show BeatAnimationStyle;
import 'package:dance_learning_app/player/beat_count_layout.dart'
    show
        beatNumbersCanvasSize,
        beatNumbersScaleInContent,
        kBeatPillPaddingH,
        kBeatPillPaddingV;
import 'package:dance_learning_app/player/cast_beat_sheet.dart';
import 'package:dance_learning_app/player/metronome_overlay.dart'
    show BeatCountNumbers, kBeatGroupLeftInset;
import 'package:dance_learning_app/cast/cast_beat_count.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 数拍层光栅化直测：判定只看**产物自己的像素事实**（尺寸、alpha、墨迹位置）
/// 与**上屏那一份布局**（量测尺寸、基线关系）——不反算被测代码的算式。
///
/// 「与手机一致」在这里是**同源**（同一份样式、间距与内边距常量），因此这些
/// 用例钉的是「同一份材料真的进了画布、且动画一像素都没进」；逐帧观感仍归
/// 真机验收（见 `lib/cast/docs/real-device-acceptance.md` 路径 L）。
void main() {
  CastBeatCountText text({
    String eightCount = '3',
    String beatCount = '5',
    String? group,
  }) => CastBeatCountText(
    eightCount: eightCount,
    beatCount: beatCount,
    group: group,
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

  /// 非黑墨迹（白 / 青数字本身）的包围盒：底衬是纯黑，故按「有 alpha 且
  /// 不是纯黑」取。
  ({int left, int top, int right, int bottom})? inkBox(
    ({int width, int height, Uint8List rgba}) image,
  ) {
    int? left, top, right, bottom;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final offset = (y * image.width + x) * 4;
        final alpha = image.rgba[offset + 3];
        if (alpha == 0) continue;
        final r = image.rgba[offset];
        final g = image.rgba[offset + 1];
        final b = image.rgba[offset + 2];
        if (r == 0 && g == 0 && b == 0) continue; // 底衬
        left = left == null || x < left ? x : left;
        right = right == null || x > right ? x : right;
        top = top == null || y < top ? y : top;
        bottom = bottom == null || y > bottom ? y : bottom;
      }
    }
    if (left == null || top == null || right == null || bottom == null) {
      return null;
    }
    return (left: left, top: top, right: right, bottom: bottom);
  }

  group('与上屏同源：一行的量测尺寸与基线关系', () {
    testWidgets('量出来的行尺寸 = 上屏那一行（含组上标让位与两数间距）', (tester) async {
      for (final (case_, display, expected)
          in <(String, BeatCountDisplay, CastBeatCountText)>[
        ('练习区无组上标', const PracticeBeatCount(eightCount: 3, beatCount: 5), text()),
        (
          '练习区带组上标',
          const PracticeBeatCount(eightCount: 9, beatCount: 2),
          // 相对八拍 9 → 显示号 (9−1)%4+1 = 1、组 = ⌈9/4⌉ = 3。
          text(eightCount: '1', beatCount: '2', group: '3'),
        ),
        ('前导区（0｜x）', const LeadingBeatCount(beatCount: 7), text(eightCount: '0', beatCount: '7')),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 400,
                height: 300,
                child: Center(child: BeatCountNumbers(display: display)),
              ),
            ),
          ),
        );
        final rowSize = tester.getSize(
          find.byKey(
            display is LeadingBeatCount
                ? const Key('beat_count_leading')
                : const Key('beat_count_practice'),
          ),
        );
        final geometry = measureCastBeatRow(text: expected)!;

        expect(
          rowSize.width,
          closeTo(geometry.size.width, 0.01),
          reason: '$case_：行宽（含上标让位与两数间距）应与量测一致',
        );
        expect(
          rowSize.height,
          closeTo(geometry.size.height, 0.01),
          reason: '$case_：行高（共同基线 + 最大下沉）应与量测一致',
        );
      }
    });

    testWidgets('八拍号与拍号按共同基线对齐、组上标悬在行左上角', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: BeatCountNumbers(
              display: PracticeBeatCount(eightCount: 9, beatCount: 2),
            ),
          ),
        ),
      );
      final eight = tester.getRect(find.byKey(const Key('beat_count_eight')));
      final beat = tester.getRect(find.byKey(const Key('beat_count_beat')));
      final group = tester.getRect(find.byKey(const Key('beat_count_group')));
      final geometry = measureCastBeatRow(
        text: text(eightCount: '1', beatCount: '2', group: '3'),
      )!;

      // 上标占位：八拍号相对上标右移 [kBeatGroupLeftInset]。
      expect(eight.left - group.left, closeTo(kBeatGroupLeftInset, 0.01));
      // 两数间距：与量测里的横向差一致。
      expect(
        beat.left - eight.left,
        closeTo(geometry.beatTopLeft.dx - geometry.eightTopLeft.dx, 0.01),
      );
      // 共同基线：两数的顶部差 = 各自基线差（大字在上、小字下沉）。
      expect(
        beat.top - eight.top,
        closeTo(geometry.beatTopLeft.dy - geometry.eightTopLeft.dy, 0.01),
      );
      expect(geometry.groupTopLeft, Offset.zero);
    });
  });

  group('画布 = 数字行的底衬（动画一像素都不进副本）', () {
    test('画布尺寸只含底衬内边距，不含动画位', () {
      const content = Size(320, 120);
      const numbers = Size(100, 56);

      final canvas = beatNumbersCanvasSize(
        contentSize: content,
        numbersSize: numbers,
        style: BeatAnimationStyle.bar,
      );

      expect(canvas.width, 100 + kBeatPillPaddingH * 2);
      expect(canvas.height, 56 + kBeatPillPaddingV * 2);
      // 动画条高 28 + 间距 6 若进了画布，高会是 110——这一条正是「不做动画」的
      // 在场断言（摆锤 32 同理）。
      expect(canvas.height, isNot(56 + 6 + 28 + kBeatPillPaddingV * 2));
      expect(canvas.height, lessThan(56 + 6 + 28 + kBeatPillPaddingV * 2));
    });

    test('产物：画布就是那一行数字的底衬，四角透明、底衬之内为黑', () async {
      final geometry = measureCastBeatRow(text: text())!;
      // 装配处就是这么定画布的：全部行里最大的那一份数字行 → 底衬尺寸。
      final canvas = beatNumbersCanvasSize(
        contentSize: const Size(320, 120),
        numbersSize: geometry.size,
        style: BeatAnimationStyle.bar,
      );
      final image = await decode(
        await renderCastBeatSheet(
          text: text(),
          canvasLogicalSize: canvas,
          scale: 1,
        ),
      );

      expect(image.width, (canvas.width * 4).round());
      expect(image.height, (canvas.height * 4).round());
      // 圆角外 = 透明。
      expect(alphaAt(image, 0, 0), 0);
      expect(alphaAt(image, image.width - 1, image.height - 1), 0);
      // 底衬之内、墨迹之外（左缘中点）：黑，alpha 115 = 0.45 × 255。
      final probe = (image.height ~/ 2) * image.width * 4 + 4 * 4;
      expect(image.rgba[probe + 3], 115, reason: '底衬 = 黑 45%');
      expect(
        (image.rgba[probe], image.rgba[probe + 1], image.rgba[probe + 2]),
        (0, 0, 0),
      );
      // 数字墨迹在场，且落在底衬之内。
      final ink = inkBox(image)!;
      expect(ink.left, greaterThan(0));
      expect(ink.right, lessThan(image.width - 1));
      expect(ink.top, greaterThan(0));
      expect(ink.bottom, lessThan(image.height - 1));
    });

    test('空窗那一格是全透明画布（序列要连续覆盖整片）', () async {
      const canvas = Size(200, 90);
      final bytes = await renderCastBeatSheet(
        text: null,
        canvasLogicalSize: canvas,
        scale: 1,
      );
      final image = await decode(bytes);

      expect(image.width, 800);
      var opaque = 0;
      for (var i = 3; i < image.rgba.length; i += 4) {
        if (image.rgba[i] != 0) opaque++;
      }
      expect(opaque, 0, reason: '不显示的段不能留任何像素');
      expect(inkBox(image), isNull);
    });
  });

  group('各格同尺寸（图像序列是一条流的前提）', () {
    test('不同文字、不同宽度渲染进同一块画布 → 像素尺寸逐一相同', () async {
      const canvas = Size(200, 90);
      final narrow = await decode(
        await renderCastBeatSheet(
          text: text(eightCount: '1', beatCount: '1'),
          canvasLogicalSize: canvas,
          scale: 1,
        ),
      );
      final wide = await decode(
        await renderCastBeatSheet(
          text: text(eightCount: '4', beatCount: '8', group: '12'),
          canvasLogicalSize: canvas,
          scale: 1,
        ),
      );

      expect((narrow.width, narrow.height), (wide.width, wide.height));
    });

    test('摆锤等比：同一相对画布下墨迹按系数放大（比例不变）', () async {
      const numbers = Size(100, 56);
      const content = Size(400, 218.1818181818); // 摆锤系数 = 400/220
      final scale = beatNumbersScaleInContent(
        contentSize: content,
        style: BeatAnimationStyle.pendulum,
      );
      final canvas = beatNumbersCanvasSize(
        contentSize: content,
        numbersSize: numbers,
        style: BeatAnimationStyle.pendulum,
      );

      final single = await decode(
        await renderCastBeatSheet(
          text: text(),
          canvasLogicalSize: const Size(132, 76),
          scale: 1,
        ),
      );
      final scaled = await decode(
        await renderCastBeatSheet(
          text: text(),
          canvasLogicalSize: canvas,
          scale: scale,
        ),
      );

      final singleInk = inkBox(single)!;
      final scaledInk = inkBox(scaled)!;
      final singleRatio =
          (singleInk.right - singleInk.left + 1) / single.width;
      final scaledRatio =
          (scaledInk.right - scaledInk.left + 1) / scaled.width;
      expect(
        scaledRatio,
        closeTo(singleRatio, 0.05),
        reason: '同一相对画布下墨迹占比不变（等比放大，不是另画一份）',
      );
      expect(canvas.width, closeTo(132 * scale, 0.01));
    });
  });

  test('量不出墨迹的输入不装内容（画成全透明，而不是抛）', () async {
    const canvas = Size(64, 40);

    final image = await decode(
      await renderCastBeatSheet(
        text: text(eightCount: '', beatCount: ''),
        canvasLogicalSize: canvas,
        scale: 1,
      ),
    );

    expect(inkBox(image), isNull);
    expect(alphaAt(image, image.width ~/ 2, image.height ~/ 2), 0);
  });
}
