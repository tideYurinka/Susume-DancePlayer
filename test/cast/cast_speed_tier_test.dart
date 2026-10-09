import 'package:dance_learning_app/cast/cast_render_request.dart'
    show CastSpeedTier;
import 'package:dance_learning_app/cast/cast_speed_tier.dart';
import 'package:flutter_test/flutter_test.dart';

/// 投屏倍速档纯件直测：候选三档、默认勾选（含手动倍率不在三档内时的就近
/// 取值）、跨档坐标换算（三档两两互换）与边界钳制、学习段随档换算。
///
/// 纯件——零 Flutter、零 IO、零网络：不启动 widget、不跑进程。
void main() {
  group('候选三档与档位文案', () {
    test('候选只有 0.5 / 0.75 / 1 三档，次序从慢到快', () {
      expect(kCastSpeedTierCandidates, [
        CastSpeedTier.half,
        CastSpeedTier.threeQuarter,
        CastSpeedTier.full,
      ]);
      expect(
        [for (final t in kCastSpeedTierCandidates) t.rate],
        [0.5, 0.75, 1],
      );
    });

    test('档位文案逐档唯一', () {
      expect(castSpeedTierLabel(CastSpeedTier.half), '0.5×');
      expect(castSpeedTierLabel(CastSpeedTier.threeQuarter), '0.75×');
      expect(castSpeedTierLabel(CastSpeedTier.full), '1×');
    });
  });

  group('默认勾选：与当前手动倍率最接近的一档', () {
    test('手动倍率就在三档上：勾那一档', () {
      expect(nearestCastSpeedTier(0.5), CastSpeedTier.half);
      expect(nearestCastSpeedTier(0.75), CastSpeedTier.threeQuarter);
      expect(nearestCastSpeedTier(1), CastSpeedTier.full);
      expect(defaultCastSpeedTiersFor(0.75), {CastSpeedTier.threeQuarter});
    });

    test('手动倍率不在三档内：就近取值（1.3 → 1×、1.6 → 1×、0.3 → 0.5×）', () {
      expect(nearestCastSpeedTier(1.3), CastSpeedTier.full);
      expect(nearestCastSpeedTier(1.6), CastSpeedTier.full);
      expect(nearestCastSpeedTier(0.3), CastSpeedTier.half);
      expect(nearestCastSpeedTier(0.7), CastSpeedTier.threeQuarter);
    });

    test('手动倍率超出三档两端：钳到最近的那一端（0.1 → 0.5×、2.0 → 1×）', () {
      expect(nearestCastSpeedTier(0.1), CastSpeedTier.half);
      expect(nearestCastSpeedTier(2), CastSpeedTier.full);
    });

    test('平局（正好落在两档中点）：取较慢那一档', () {
      expect(nearestCastSpeedTier(0.625), CastSpeedTier.half);
      expect(nearestCastSpeedTier(0.875), CastSpeedTier.threeQuarter);
    });

    test('非有限取值兜到 1×（读数坏掉时不至于勾出一个奇怪的档）', () {
      expect(nearestCastSpeedTier(double.nan), CastSpeedTier.full);
      expect(nearestCastSpeedTier(double.infinity), CastSpeedTier.full);
    });
  });

  group('这一次投屏的档计划', () {
    test('渲染档：选中的档按声明次序排列，起投档 = 选中里最接近手动倍率的那一档', () {
      final plan = castSpeedTierPlanFor(
        renders: true,
        manualRate: 1,
        selected: const {
          CastSpeedTier.half,
          CastSpeedTier.full,
          CastSpeedTier.threeQuarter,
        },
      );
      expect(plan.tiers, [
        CastSpeedTier.half,
        CastSpeedTier.threeQuarter,
        CastSpeedTier.full,
      ]);
      expect(plan.startTier, CastSpeedTier.full);
    });

    test('起投档只在选中的档里挑：手动倍率 1× 但只勾了 0.5×，起投档就是 0.5×', () {
      final plan = castSpeedTierPlanFor(
        renders: true,
        manualRate: 1,
        selected: const {CastSpeedTier.half},
      );
      expect(plan.tiers, [CastSpeedTier.half]);
      expect(plan.startTier, CastSpeedTier.half);
    });

    test('没勾任何档：退回默认那一档（至少一档，投屏总有一份可播）', () {
      final plan = castSpeedTierPlanFor(
        renders: true,
        manualRate: 0.8,
        selected: const {},
      );
      expect(plan.tiers, [CastSpeedTier.threeQuarter]);
      expect(plan.startTier, CastSpeedTier.threeQuarter);
    });

    test('都不勾渲染档：只有原片这一档（1×），勾了什么一律不算', () {
      final plan = castSpeedTierPlanFor(
        renders: false,
        manualRate: 0.5,
        selected: const {CastSpeedTier.half, CastSpeedTier.threeQuarter},
      );
      expect(plan.tiers, [CastSpeedTier.full]);
      expect(plan.startTier, CastSpeedTier.full);
    });

    test('单档计划（原片那条路的取值形状）', () {
      final plan = CastSpeedTierPlan.single(CastSpeedTier.half);
      expect(plan.tiers, [CastSpeedTier.half]);
      expect(plan.startTier, CastSpeedTier.half);
      expect(plan.pending, isEmpty, reason: '单档没有后台要渲的档');
    });

    test('起投档之外的都是后台待渲档（声明次序）', () {
      final plan = castSpeedTierPlanFor(
        renders: true,
        manualRate: 0.75,
        selected: const {
          CastSpeedTier.half,
          CastSpeedTier.threeQuarter,
          CastSpeedTier.full,
        },
      );
      expect(plan.startTier, CastSpeedTier.threeQuarter);
      expect(plan.pending, [CastSpeedTier.half, CastSpeedTier.full]);
    });
  });

  group('档位副本时长：setpts=PTS/rate 的直接后果', () {
    test('0.5× 档时长翻倍、0.75× 档 4/3、1× 档不变', () {
      const source = Duration(seconds: 12);
      expect(
        castCopyDuration(source, CastSpeedTier.half),
        const Duration(seconds: 24),
      );
      expect(
        castCopyDuration(source, CastSpeedTier.threeQuarter),
        const Duration(seconds: 16),
      );
      expect(castCopyDuration(source, CastSpeedTier.full), source);
    });

    test('零时长与负值都给零（坏输入不造出负数位置）', () {
      expect(
        castCopyDuration(Duration.zero, CastSpeedTier.half),
        Duration.zero,
      );
      expect(
        castCopyDuration(const Duration(seconds: -3), CastSpeedTier.half),
        Duration.zero,
      );
    });
  });

  group('位置换算：三档两两互换', () {
    const source = Duration(seconds: 10);
    // 源 10 秒在各档副本里的位置：0.5× → 20 秒、0.75× → 13.333 秒、1× → 10 秒。
    const inHalf = Duration(microseconds: 20000000);
    const inThreeQuarter = Duration(microseconds: 13333333);

    test('源坐标 → 各档副本坐标', () {
      expect(castCopyPosition(source, CastSpeedTier.half), inHalf);
      expect(
        castCopyPosition(source, CastSpeedTier.threeQuarter),
        inThreeQuarter,
      );
      expect(castCopyPosition(source, CastSpeedTier.full), source);
    });

    test('各档副本坐标 → 源坐标（与上一组互为逆运算）', () {
      expect(castSourcePosition(inHalf, CastSpeedTier.half), source);
      expect(
        castSourcePosition(inThreeQuarter, CastSpeedTier.threeQuarter),
        source,
      );
      expect(castSourcePosition(source, CastSpeedTier.full), source);
    });

    test('档间换算：新位置 = 旧位置 × 旧率 ÷ 新率（九组两两互换逐条钉）', () {
      // 三档之间互换九组；给出的是同一时刻（源 6 秒）在各档里的读数。
      const moment = Duration(seconds: 6);
      final inTier = {
        for (final tier in CastSpeedTier.values)
          tier: castCopyPosition(moment, tier),
      };
      expect(inTier[CastSpeedTier.half], const Duration(seconds: 12));
      expect(inTier[CastSpeedTier.threeQuarter], const Duration(seconds: 8));
      expect(inTier[CastSpeedTier.full], const Duration(seconds: 6));

      for (final from in CastSpeedTier.values) {
        for (final to in CastSpeedTier.values) {
          expect(
            castSwitchedPosition(position: inTier[from]!, from: from, to: to),
            inTier[to],
            reason: '${from.name} → ${to.name}',
          );
        }
      }
    });

    test('同档换档是恒等（点当前那一档不该把位置挪走）', () {
      for (final tier in CastSpeedTier.values) {
        expect(
          castSwitchedPosition(
            position: const Duration(seconds: 7),
            from: tier,
            to: tier,
          ),
          const Duration(seconds: 7),
          reason: tier.name,
        );
      }
    });

    test('负位置钳到零', () {
      expect(
        castSwitchedPosition(
          position: const Duration(seconds: -5),
          from: CastSpeedTier.full,
          to: CastSpeedTier.half,
        ),
        Duration.zero,
      );
    });

    test('越过新档时长：钳到新档末尾', () {
      // 1× 上 20 秒 → 0.5× 上是 40 秒，但这一档只有 30 秒。
      expect(
        castSwitchedPosition(
          position: const Duration(seconds: 20),
          from: CastSpeedTier.full,
          to: CastSpeedTier.half,
          newCopyDuration: const Duration(seconds: 30),
        ),
        const Duration(seconds: 30),
      );
      // 恰好落在末尾：不动。
      expect(
        castSwitchedPosition(
          position: const Duration(seconds: 15),
          from: CastSpeedTier.full,
          to: CastSpeedTier.half,
          newCopyDuration: const Duration(seconds: 30),
        ),
        const Duration(seconds: 30),
      );
    });
  });

  group('学习段随档换算（两端各算一次、起点不越终点）', () {
    test('段两端按同一比例换算，次序不翻转', () {
      final span = castSwitchedSpan(
        start: const Duration(seconds: 4),
        end: const Duration(seconds: 6),
        from: CastSpeedTier.full,
        to: CastSpeedTier.half,
      );
      expect(span.start, const Duration(seconds: 8));
      expect(span.end, const Duration(seconds: 12));
    });

    test('段尾越出新档时长：两端各自钳，起点不越终点', () {
      final span = castSwitchedSpan(
        start: const Duration(seconds: 14),
        end: const Duration(seconds: 20),
        from: CastSpeedTier.full,
        to: CastSpeedTier.half,
        newCopyDuration: const Duration(seconds: 30),
      );
      expect(span.start, const Duration(seconds: 28));
      expect(span.end, const Duration(seconds: 30));
      expect(span.start <= span.end, isTrue);
    });

    test('两端都被钳到同一点时退化成一个点（不造出反向区间）', () {
      final span = castSwitchedSpan(
        start: const Duration(seconds: 20),
        end: const Duration(seconds: 30),
        from: CastSpeedTier.full,
        to: CastSpeedTier.half,
        newCopyDuration: const Duration(seconds: 30),
      );
      expect(span.start, const Duration(seconds: 30));
      expect(span.end, const Duration(seconds: 30));
    });

    test('零长段与逆序输入：退化成一个点，不抛', () {
      final at = castSwitchedSpan(
        start: const Duration(seconds: 5),
        end: const Duration(seconds: 5),
        from: CastSpeedTier.threeQuarter,
        to: CastSpeedTier.full,
      );
      expect(at.start, at.end);
    });
  });
}
