import 'package:dance_learning_app/help/guide_bubble_placement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 贴框布点的纯函数直测（接缝二）：直喂高亮框矩形 / 屏幕尺寸 / 件宽上限，
/// 覆盖四个边界——框中心在屏幕上半、框中心在屏幕下半、水平钳位、箭头钳位——
/// 并断言四类输入下条子矩形与高亮框矩形都不相交。
///
/// 期望值取自明写的规则（边距 16、间距 12 + 箭头 10、件宽上限 320），
/// 不是拿实现的中间量再算一遍。
void main() {
  const screen = Size(360, 780); // 合成档 360×780dp（竖屏量级），非设备档。

  GuideBubblePlacement place(Rect anchor, {Size size = screen}) =>
      placeGuideBubble(
        anchorRect: anchor,
        screen: size,
        maxWidth: guideBubbleMaxWidth,
      );

  /// 条子矩形：高取一档代表性值，够覆盖「框偏上放下方 / 框偏下放上方」两形态。
  Rect bubbleRect(GuideBubblePlacement p, Size size) => p.below
      ? Rect.fromLTWH(p.left, p.top!, p.width, 64)
      : Rect.fromLTWH(p.left, size.height - p.bottom! - 64, p.width, 64);

  test('框中心在屏幕上半：条子放框下方，间距 = 12 + 10 箭头', () {
    const anchor = Rect.fromLTWH(150, 100, 48, 48);
    final p = place(anchor);

    expect(p.below, isTrue);
    expect(p.top, 148 + 12 + 10);
    expect(p.bottom, isNull);
    expect(p.left, 16);
    expect(p.width, 320);
    expect(p.arrowLeft, 148);
    expect(bubbleRect(p, screen).overlaps(anchor), isFalse);
  });

  test('框中心在屏幕下半：条子放框上方，间距 = 12 + 10 箭头', () {
    const anchor = Rect.fromLTWH(150, 600, 48, 48);
    final p = place(anchor);

    expect(p.below, isFalse);
    expect(p.top, isNull);
    expect(p.bottom, 780 - 600 + 12 + 10);
    expect(p.left, 16);
    expect(p.width, 320);
    expect(p.arrowLeft, 148);
    expect(bubbleRect(p, screen).overlaps(anchor), isFalse);
  });

  test('水平钳位：框贴屏幕左/右缘时条子被钳回 [16, 屏宽 − 16 − 条宽]', () {
    // 框中心 100：不钳位时条子会伸到屏外，钳到左缘 16。
    final leftClamped = place(const Rect.fromLTWH(90, 100, 20, 20));
    expect(leftClamped.left, 16);
    expect(leftClamped.arrowLeft, 74);

    // 框中心 250：钳到右缘 24（= 360 − 16 − 320）。
    final rightClamped = place(const Rect.fromLTWH(240, 100, 20, 20));
    expect(rightClamped.left, 24);
    expect(rightClamped.arrowLeft, 216);

    expect(
      bubbleRect(
        leftClamped,
        screen,
      ).overlaps(const Rect.fromLTWH(90, 100, 20, 20)),
      isFalse,
    );
    expect(
      bubbleRect(
        rightClamped,
        screen,
      ).overlaps(const Rect.fromLTWH(240, 100, 20, 20)),
      isFalse,
    );
  });

  test('箭头钳位：框中心落在条宽之外时箭头钳在条宽内', () {
    // 框中心 10 在条子左边之外：箭头钳到最左 0。
    final leftOut = place(const Rect.fromLTWH(0, 100, 20, 20));
    expect(leftOut.left, 16);
    expect(leftOut.arrowLeft, 0);

    // 框中心 350 在条子右边之外：箭头钳到最右 320 − 20 = 300。
    final rightOut = place(const Rect.fromLTWH(340, 100, 20, 20));
    expect(rightOut.left, 24);
    expect(rightOut.arrowLeft, 300);

    expect(
      bubbleRect(leftOut, screen).overlaps(const Rect.fromLTWH(0, 100, 20, 20)),
      isFalse,
    );
    expect(
      bubbleRect(
        rightOut,
        screen,
      ).overlaps(const Rect.fromLTWH(340, 100, 20, 20)),
      isFalse,
    );
  });

  test('件宽上限：宽屏上条子宽取上限 320、不近满宽', () {
    const wide = Size(800, 600);
    final p = place(const Rect.fromLTWH(390, 100, 20, 20), size: wide);

    expect(p.width, 320);
    expect(p.left, 240);
    expect(p.arrowLeft, 150);
    expect(
      bubbleRect(p, wide).overlaps(const Rect.fromLTWH(390, 100, 20, 20)),
      isFalse,
    );
  });
}
