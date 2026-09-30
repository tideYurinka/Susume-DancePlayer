// 局部镜像片段点按命中解析纯函数测试。
//
// seam 入参 = 片段表 + 点按时刻（ms）+ 最小命中宽（ms，时间量——像素→
// 时间换算在 widget 层，接线）；返回被点中的片段下标或 null（轨道
// 空白）。命中规则与 `resolveLearningTrackHit` 的学习段体分支同构：区间
// 对称扩展至 ≥ 最小命中宽（宽段不收缩）、多候选取距点按最近的片段中心。
import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 片段助手（毫秒）。
  LocalMirrorFragment frag(int startMs, int endMs) =>
      LocalMirrorFragment(startMs: startMs, endMs: endMs);

  /// 统一调用助手。
  int? hitAt(
    List<LocalMirrorFragment> fragments,
    int timeMs, {
    int minHitWidthMs = 0,
  }) => resolveLocalMirrorTapHit(
    fragments: fragments,
    timeMs: timeMs,
    minHitWidthMs: minHitWidthMs,
  );

  group('窄片段对称扩展命中', () {
    test('点在窄片段几何外、但落最小命中宽扩展域内 → 命中', () {
      // 片段 [1000, 1200) 宽 200ms，最小命中宽 500ms → 左右各扩 150ms，
      // 扩展域 [850, 1350)；点 900ms 在几何外、扩展域内。
      expect(
        hitAt([frag(1000, 1200)], 900, minHitWidthMs: 500),
        0,
        reason: '窄片段点其附近（最小命中宽内）即命中',
      );
    });

    test('窄片段命中域对称：起点前/终点后各扩同样的量', () {
      final fragments = [frag(1000, 1200)];
      const minHit = 400;
      // 扩 100ms：命中域 [900, 1300)。
      expect(hitAt(fragments, 899, minHitWidthMs: minHit), isNull);
      expect(hitAt(fragments, 900, minHitWidthMs: minHit), 0);
      expect(hitAt(fragments, 1299, minHitWidthMs: minHit), 0);
      expect(hitAt(fragments, 1300, minHitWidthMs: minHit), isNull);
    });

    test('宽片段不收缩：命中域恰为其几何区间（半开）', () {
      final fragments = [frag(1000, 5000)];
      const minHit = 500;
      expect(hitAt(fragments, 1000, minHitWidthMs: minHit), 0);
      expect(hitAt(fragments, 4999, minHitWidthMs: minHit), 0);
      expect(hitAt(fragments, 5000, minHitWidthMs: minHit), isNull);
      // 几何外即使只差 1ms 也不命中（不扩展）。
      expect(hitAt(fragments, 999, minHitWidthMs: minHit), isNull);
    });
  });

  group('多候选取距点按最近的片段中心', () {
    test('相邻小片段间隙处点按 → 更近中心者胜', () {
      // 两段各宽 200ms、最小命中宽 800ms → 各扩 300ms：
      // 段 0 域 [700, 1700)、段 1 域 [1700, 2700) 不重叠时各自命中；
      // 构造重叠：段 0 [1000,1200)、段 1 [1400,1600)，各扩 300ms →
      // 段 0 域 [700,1500)、段 1 域 [1100,1900) 重叠 [1100,1500)。
      final fragments = [frag(1000, 1200), frag(1400, 1600)];
      const minHit = 800;
      // 点 1300ms：距段 0 中心 200ms < 距段 1 中心 200ms？相等——取先扫到
      // 的下标不符合「最近」意图，改点 1350ms：距段 0 中心 250、距段 1 150。
      expect(hitAt(fragments, 1350, minHitWidthMs: minHit), 1);
      expect(hitAt(fragments, 1150, minHitWidthMs: minHit), 0);
    });

    test('点落宽片段与窄片段扩展域重叠处 → 更近中心者胜', () {
      // 宽段 [0, 4000)（中心 2000），窄段 [4000, 4200) 扩展后域
      // [3900, 4300)。点 4050ms 同时落两者：距窄段中心 50 < 距宽段 2050。
      final fragments = [frag(0, 4000), frag(4000, 4200)];
      expect(hitAt(fragments, 4050, minHitWidthMs: 500), 1);
    });

    test('三点以上候选取最近中心；点恰落几何间隙正中（真平票）取靠前片段', () {
      // 三段各宽 100ms：[1000,1100) [1200,1300) [1400,1500)，最小命中宽
      // 1000ms → 各扩 450ms，扩展域连片 [550,1950)。点 1300ms 距段 1
      // 中心 0 最近。
      final fragments = [
        frag(1000, 1100),
        frag(1200, 1300),
        frag(1400, 1500),
      ];
      const minHit = 1000;
      expect(hitAt(fragments, 1300, minHitWidthMs: minHit), 1);
      // 真平票：点 1150ms 距段 0 中心 150 == 距段 1 中心 150 → 取靠前者。
      expect(hitAt(fragments, 1150, minHitWidthMs: minHit), 0);
    });
  });

  group('空命中', () {
    test('空片段表 → null', () {
      expect(hitAt(const [], 1234, minHitWidthMs: 500), isNull);
    });

    test('所有片段扩展域外（轨道空白）→ null', () {
      expect(
        hitAt([frag(1000, 2000), frag(3000, 4000)], 2500, minHitWidthMs: 400),
        isNull,
        reason: '点 2500ms 距两段扩展域皆外（段 0 域 [800,2200)、段 1 [2800,4200)）',
      );
    });
  });

  group('命中与参数口径', () {
    test('最小命中宽非正 → 不扩展，命中域 = 几何区间', () {
      final fragments = [frag(1000, 2000)];
      expect(hitAt(fragments, 999, minHitWidthMs: 0), isNull);
      expect(hitAt(fragments, 999, minHitWidthMs: -100), isNull);
      expect(hitAt(fragments, 1000, minHitWidthMs: 0), 0);
    });
  });

  group('最小命中宽常量', () {
    test('行级点按最小命中宽 = 40dp（与分段线/首尾线抓取宽同档）', () {
      expect(kLocalMirrorTapHitWidth, 40);
    });
  });
}
