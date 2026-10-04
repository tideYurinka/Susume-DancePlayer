import 'package:dance_learning_app/player/track_edge_pan.dart';

import 'package:flutter_test/flutter_test.dart';

/// 贴边平移纯件（track_edge_pan.dart）的单测面：判定带宽 = 带宽 ÷ 4、侵入
/// 深度、出缘归一 700px/s 的线性速度曲线与时间平滑累积。口径直接锁定纯件，
/// 不经轨道带 widget 泵测。
void main() {
  group('判定带宽、深度与速度曲线', () {
    test('判定带宽 = 轨道带宽 ÷ 4（横屏 781.7 → 195.4；竖屏真机 361.1 → 90.3）', () {
      expect(edgePanZonePx(800), 200);
      // 真机基准：横屏 781.7、竖屏 361.1。
      expect(edgePanZonePx(781.7), closeTo(195.425, 1e-9));
      expect(edgePanZonePx(361.1), closeTo(90.275, 1e-9));
      // 窄带更窄：与带宽成比例。
      expect(edgePanZonePx(400), 100);
      expect(edgePanZonePx(300), 75);
    });

    test('带中部无深度：不平移（800 宽中部为 [200, 600]）', () {
      expect(edgePanDepthPx(x: 400, width: 800), 0);
      expect(edgePanDepthPx(x: 200, width: 800), 0);
      expect(edgePanDepthPx(x: 600, width: 800), 0);
    });

    test('真机竖屏 361.1：带中部 [90.3, 270.8] 不命中，留出微调安全区', () {
      const w = 361.1;
      // 旧口径 200dp 常量下中心（180.55）也有约 20px 深度；新口径为 0。
      expect(edgePanDepthPx(x: 180.55, width: w), 0);
      expect(edgePanDepthPx(x: 90.3, width: w), 0, reason: '带中侧边界内');
      expect(edgePanDepthPx(x: 270.8, width: w), 0, reason: '带中侧边界内');
      // 判定带宽 = 361.1 ÷ 4 = 90.275：越过边界即有深度。
      expect(edgePanDepthPx(x: 90, width: w), closeTo(0.275, 1e-9));
      expect(edgePanDepthPx(x: 271, width: w), closeTo(0.175, 1e-9));
    });

    test('进入边沿区深度递增；贴屏缘 = 满深度 = 判定带宽', () {
      expect(edgePanDepthPx(x: 199, width: 800), closeTo(1, 1e-9));
      expect(edgePanDepthPx(x: 100, width: 800), closeTo(100, 1e-9));
      expect(edgePanDepthPx(x: 0, width: 800), edgePanZonePx(800));
      expect(edgePanDepthPx(x: 799, width: 800), closeTo(199, 1e-9));
      // 横屏 781.7：出缘满深度即 195.425。
      expect(edgePanDepthPx(x: 0, width: 781.7), closeTo(195.425, 1e-9));
      // 竖屏 361.1：出缘满深度即 90.275。
      expect(edgePanDepthPx(x: 0, width: 361.1), closeTo(90.275, 1e-9));
    });

    test('出缘速度恒 700px/s：横屏与竖屏同值，不随带宽变化', () {
      expect(edgePanVelocityPxPerSec(0, width: 800), 0);
      expect(kPlayheadEdgePanMaxVelocityPxPerSec, 700);
      expect(
        edgePanVelocityPxPerSec(edgePanZonePx(800), width: 800),
        closeTo(700, 1e-9),
      );
      expect(
        edgePanVelocityPxPerSec(edgePanZonePx(781.7), width: 781.7),
        closeTo(700, 1e-9),
        reason: '横屏出缘速度',
      );
      expect(
        edgePanVelocityPxPerSec(edgePanZonePx(361.1), width: 361.1),
        closeTo(700, 1e-9),
        reason: '竖屏出缘速度与横屏同值（竖屏也拉得动）',
      );
    });

    test('速度随深度线性递增：半深度半速，与带宽无关', () {
      expect(
        edgePanVelocityPxPerSec(edgePanZonePx(800) * 0.5, width: 800),
        closeTo(350, 1e-9),
      );
      expect(
        edgePanVelocityPxPerSec(edgePanZonePx(800) * 0.2, width: 800),
        closeTo(140, 1e-9),
      );
      expect(
        edgePanVelocityPxPerSec(edgePanZonePx(361.1) * 0.5, width: 361.1),
        closeTo(350, 1e-9),
        reason: '归一化后同一相对深度速度与带宽无关',
      );
    });

    test('平移量随时间平滑累积：与时长成比例、零时长为零', () {
      const usPerPx = 37500.0; // 30s 窗口 / 800px
      const w = 800.0;
      final depth = edgePanZonePx(w); // 出缘最高速 700px/s
      final per100ms = edgePanShiftFor(
        depthPx: depth,
        width: w,
        elapsed: const Duration(milliseconds: 100),
        microsecondsPerPixel: usPerPx,
      );
      final per200ms = edgePanShiftFor(
        depthPx: depth,
        width: w,
        elapsed: const Duration(milliseconds: 200),
        microsecondsPerPixel: usPerPx,
      );
      // 出缘 700px/s × 0.1s = 70px × 37.5ms/px = 2.625s。
      expect(per100ms, const Duration(milliseconds: 2625));
      expect(
        per200ms.inMicroseconds,
        closeTo(per100ms.inMicroseconds * 2, 2),
        reason: '线性段平移量随时间线性累积',
      );
      expect(
        edgePanShiftFor(
          depthPx: depth,
          width: w,
          elapsed: Duration.zero,
          microsecondsPerPixel: usPerPx,
        ),
        Duration.zero,
      );
      // 竖屏真机带宽：同一出缘速度 → 同一时长位移（与带宽无关）。
      final portrait = edgePanShiftFor(
        depthPx: edgePanZonePx(361.1),
        width: 361.1,
        elapsed: const Duration(milliseconds: 100),
        microsecondsPerPixel: usPerPx,
      );
      expect(portrait, per100ms, reason: '出缘速度任何屏宽下同值');
    });
  });
}
