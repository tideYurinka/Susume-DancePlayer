import 'package:dance_learning_app/player/beat_animation.dart';
import 'package:dance_learning_app/player/overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('矩形宽系数钳制 clampRectWidthFactor（纯函数 seam）', () {
    test('界内原样返回', () {
      expect(clampRectWidthFactor(1.0), 1.0);
      expect(clampRectWidthFactor(1.75), 1.75);
    });

    test('低于下限钳到下限、高于上限钳到上限', () {
      expect(clampRectWidthFactor(0.1), kMinRectWidthFactor);
      expect(clampRectWidthFactor(9.0), kMaxRectWidthFactor);
    });
  });

  group('摆锤等比系数钳制 clampPendulumScale（纯函数 seam）', () {
    test('界内原样返回', () {
      expect(clampPendulumScale(1.0), 1.0);
      expect(clampPendulumScale(2.5), 2.5);
    });

    test('低于下限钳到下限、高于上限钳到上限', () {
      expect(clampPendulumScale(-1.0), kMinPendulumScale);
      expect(clampPendulumScale(100.0), kMaxPendulumScale);
    });
  });

  group('浮层尺寸解析 resolveOverlaySize（纯函数 seam）', () {
    test('矩形：宽 = 默认内容宽 × 宽系数、高固定', () {
      final size = resolveOverlaySize(
        style: BeatAnimationStyle.bar,
        rectWidthFactor: 1.0,
        pendulumScale: 2.0, // 矩形形态不消费摆锤系数。
      );
      expect(size.width, kOverlayBaseContentSize.width * 1.0);
      expect(size.height, kOverlayBaseContentSize.height);
    });

    test('矩形：宽度随宽系数横向伸缩', () {
      final size = resolveOverlaySize(
        style: BeatAnimationStyle.bar,
        rectWidthFactor: 1.5,
        pendulumScale: 1.0,
      );
      expect(size.width, kOverlayBaseContentSize.width * 1.5);
      expect(size.height, kOverlayBaseContentSize.height);
    });

    test('摆锤：整体等比、宽沿用摆锤专属窄基准 220（含数字）', () {
      final size = resolveOverlaySize(
        style: BeatAnimationStyle.pendulum,
        rectWidthFactor: 2.0, // 摆锤形态不消费矩形宽系数。
        pendulumScale: 1.5,
      );
      expect(size.width, kPendulumBaseContentSize.width * 1.5);
      expect(size.height, kPendulumBaseContentSize.height * 1.5);
    });

    test('界外系数解析即钳（缩到最小不触发渲染溢出的前提）', () {
      final rect = resolveOverlaySize(
        style: BeatAnimationStyle.bar,
        rectWidthFactor: 0.01,
        pendulumScale: 1.0,
      );
      expect(rect.width, kOverlayBaseContentSize.width * kMinRectWidthFactor);
      final pendulum = resolveOverlaySize(
        style: BeatAnimationStyle.pendulum,
        rectWidthFactor: 1.0,
        pendulumScale: 42.0,
      );
      expect(
        pendulum.width,
        kPendulumBaseContentSize.width * kMaxPendulumScale,
      );
      expect(
        pendulum.height,
        kPendulumBaseContentSize.height * kMaxPendulumScale,
      );
    });
  });

  group('视口联动生效上限（effective cap = min(相对上限, 视口/基准)）', () {
    test('矩形：视口宽 800 → 生效上限 2.5（＝相对上限，收缩后持平）', () {
      final cap = effectiveMaxRectWidthFactor(const Size(800, 600));
      expect(cap, closeTo(800 / kOverlayBaseContentSize.width, 1e-9));
      expect(cap, lessThanOrEqualTo(kMaxRectWidthFactor));
    });

    test('矩形：宽视口（1280）→ 相对上限 2.5 生效', () {
      expect(effectiveMaxRectWidthFactor(const Size(1280, 600)), 2.5);
    });

    test('矩形：极窄视口 → 视口上限可低于相对下限（铺满视口为准）', () {
      final cap = effectiveMaxRectWidthFactor(const Size(100, 600));
      expect(cap, closeTo(100 / kOverlayBaseContentSize.width, 1e-9));
      expect(cap, lessThan(kMinRectWidthFactor));
    });

    test('摆锤：宽高双维取更紧者、基准用窄宽 220（视口 500×300 → 宽维 2.27 生效）', () {
      final cap = effectiveMaxPendulumScale(const Size(500, 300));
      expect(cap, closeTo(500 / kPendulumBaseContentSize.width, 1e-9));
    });

    test('摆锤：高维更紧时取高维（视口 1280×240 → 2.0 生效）', () {
      final cap = effectiveMaxPendulumScale(const Size(1280, 240));
      expect(cap, closeTo(240 / kPendulumBaseContentSize.height, 1e-9));
    });
  });

  group('视口联动尺寸解析 resolveOverlaySize', () {
    test('矩形：系数 3 + 视口 800 → 实宽钳到铺满视口宽 800', () {
      final size = resolveOverlaySize(
        style: BeatAnimationStyle.bar,
        rectWidthFactor: 3.0,
        pendulumScale: 1.0,
        viewport: const Size(800, 600),
      );
      expect(size, Size(800, kOverlayBaseContentSize.height));
    });

    test('矩形：界内系数不受视口影响', () {
      final size = resolveOverlaySize(
        style: BeatAnimationStyle.bar,
        rectWidthFactor: 1.5,
        pendulumScale: 1.0,
        viewport: const Size(800, 600),
      );
      expect(size, Size(480, kOverlayBaseContentSize.height));
    });

    test('摆锤：系数 3 + 视口 440×300 → 等比钳到 2.0（窄基准宽维更紧）', () {
      final size = resolveOverlaySize(
        style: BeatAnimationStyle.pendulum,
        rectWidthFactor: 1.0,
        pendulumScale: 3.0,
        viewport: const Size(440, 300),
      );
      expect(
        size,
        Size(
          kPendulumBaseContentSize.width * 2.0,
          kPendulumBaseContentSize.height * 2.0,
        ),
      );
    });

    test('不传视口 → 既有相对上限语义（落盘值不在布局期被视口外改写的前提）', () {
      final size = resolveOverlaySize(
        style: BeatAnimationStyle.bar,
        rectWidthFactor: 3.0, // 界外：解析即钳到相对上限 2.5。
        pendulumScale: 1.0,
      );
      expect(size, Size(800, kOverlayBaseContentSize.height));
    });
  });

  group('位置屏内钳制 clampOverlayOffset', () {
    test('越右/下边界 → 钳回视口内右/下贴边', () {
      final offset = clampOverlayOffset(
        offset: const Offset(900, 500),
        contentSize: const Size(320, 120),
        viewport: const Size(800, 600),
      );
      expect(offset, const Offset(480, 480));
    });

    test('越左/上边界（负偏移）→ 钳回 0', () {
      final offset = clampOverlayOffset(
        offset: const Offset(-50, -10),
        contentSize: const Size(320, 120),
        viewport: const Size(800, 600),
      );
      expect(offset, Offset.zero);
    });

    test('内容宽 ≥ 视口 → 左上对齐（dx = 0），高仍钳', () {
      final offset = clampOverlayOffset(
        offset: const Offset(200, 500),
        contentSize: const Size(960, 120),
        viewport: const Size(800, 600),
      );
      expect(offset, const Offset(0, 480));
    });

    test('界内原样返回', () {
      const offset = Offset(40, 60);
      expect(
        clampOverlayOffset(
          offset: offset,
          contentSize: const Size(320, 120),
          viewport: const Size(800, 600),
        ),
        offset,
      );
    });
  });
}
