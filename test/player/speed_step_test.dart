import 'package:dance_learning_app/player/speed_step.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpeedStepParams', () {
    test('默认参数合法', () {
      expect(const SpeedStepParams().isValid, isTrue);
      expect(const SpeedStepParams().startRate, 0.5);
      expect(const SpeedStepParams().maxRate, 1.0);
      expect(const SpeedStepParams().lapsPerRate, 3);
      expect(const SpeedStepParams().rateIncrement, 0.1);
    });

    test('非法组合 isValid 为 false：起步<=0 / 递增量<=0 / 每档遍数<1 / 封顶<起步', () {
      expect(const SpeedStepParams(startRate: 0).isValid, isFalse);
      expect(const SpeedStepParams(startRate: -0.5).isValid, isFalse);
      expect(const SpeedStepParams(rateIncrement: 0).isValid, isFalse);
      expect(const SpeedStepParams(lapsPerRate: 0).isValid, isFalse);
      expect(
        const SpeedStepParams(startRate: 1.0, maxRate: 0.5).isValid,
        isFalse,
      );
    });

    test('copyWith 与相等性', () {
      const p = SpeedStepParams();
      expect(p.copyWith(), p);
      expect(p.copyWith(startRate: 0.6).startRate, 0.6);
      expect(p.copyWith(maxRate: 1.5).maxRate, 1.5);
      expect(p.copyWith(lapsPerRate: 5).lapsPerRate, 5);
      expect(p.copyWith(rateIncrement: 0.2).rateIncrement, 0.2);
      expect(p.copyWith(startRate: 0.6), isNot(p));
    });
  });

  group('speedStepRates（档位序列）', () {
    test('默认参数：0.5 起步、0.1 递增至 1.0（含）', () {
      expect(
        speedStepRates(const SpeedStepParams()),
        [0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
      );
    });

    test('增量不能整除 (b - a) 时末档钳制到 b', () {
      // 0.5 → 0.8 → 1.1 越过 1.0，末档收敛到 1.0。
      expect(
        speedStepRates(
          const SpeedStepParams(
            startRate: 0.5,
            maxRate: 1.0,
            lapsPerRate: 3,
            rateIncrement: 0.3,
          ),
        ),
        [0.5, 0.8, 1.0],
      );
    });

    test('a == b 时只有一档', () {
      expect(
        speedStepRates(
          const SpeedStepParams(
            startRate: 0.8,
            maxRate: 0.8,
            lapsPerRate: 2,
            rateIncrement: 0.1,
          ),
        ),
        [0.8],
      );
    });

    test('结果不可变（unmodifiable）', () {
      final rates = speedStepRates(const SpeedStepParams());
      expect(() => rates.add(2.0), throwsUnsupportedError);
    });

    test('非法参数抛 ArgumentError', () {
      expect(
        () => speedStepRates(const SpeedStepParams(startRate: 0)),
        throwsArgumentError,
      );
      expect(
        () => speedStepRates(const SpeedStepParams(lapsPerRate: 0)),
        throwsArgumentError,
      );
      expect(
        () => speedStepRates(
          const SpeedStepParams(startRate: 0.8, maxRate: 0.5),
        ),
        throwsArgumentError,
      );
    });
  });

  group('rateForStepCycle（档位循环）', () {
    test('默认参数：每档 3 遍，封顶用满后回到起步', () {
      const p = SpeedStepParams();
      expect(rateForStepCycle(p, 0), 0.5);
      expect(rateForStepCycle(p, 2), 0.5);
      expect(rateForStepCycle(p, 3), 0.6);
      expect(rateForStepCycle(p, 5), 0.6);
      expect(rateForStepCycle(p, 6), 0.7);
      expect(rateForStepCycle(p, 15), 1.0);
      expect(rateForStepCycle(p, 17), 1.0);
      // 末档用满后回到起步重新循环。
      expect(rateForStepCycle(p, 18), 0.5);
      expect(rateForStepCycle(p, 19), 0.5);
      expect(rateForStepCycle(p, 20), 0.5);
      expect(rateForStepCycle(p, 21), 0.6);
    });

    test('每档遍数 == 1 时每遍升一档', () {
      const p = SpeedStepParams(
        startRate: 0.5,
        maxRate: 1.0,
        lapsPerRate: 1,
        rateIncrement: 0.5,
      );
      expect(rateForStepCycle(p, 0), 0.5);
      expect(rateForStepCycle(p, 1), 1.0);
      expect(rateForStepCycle(p, 2), 0.5);
    });

    test('负 cycleIndex 抛 ArgumentError', () {
      expect(
        () => rateForStepCycle(const SpeedStepParams(), -1),
        throwsArgumentError,
      );
    });
  });
}
