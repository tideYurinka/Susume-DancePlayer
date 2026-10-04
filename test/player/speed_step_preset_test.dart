import 'package:dance_learning_app/player/speed_step.dart';
import 'package:dance_learning_app/player/speed_step_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('新建预设默认名', () {
    test('无重名时为「自定义 1」', () {
      expect(defaultCustomPresetName(const []), '自定义 1');
      expect(defaultCustomPresetName(const ['初见·大量练习']), '自定义 1');
    });

    test('N 去重递增：避开既有同名，取最小可用正整数', () {
      expect(defaultCustomPresetName(const ['自定义 1']), '自定义 2');
      expect(defaultCustomPresetName(const ['自定义 1', '自定义 2']), '自定义 3');
      // 有空档（1、3 已占）→ 取最小空档 2。
      expect(defaultCustomPresetName(const ['自定义 1', '自定义 3']), '自定义 2');
      // 非默认名样式不算占用。
      expect(defaultCustomPresetName(const ['自定义', '自定义 x']), '自定义 1');
    });
  });

  group('内置预设工厂', () {
    test('「初见·大量练习」= 起步 0.5 → 封顶 1.0、每档 3 遍、递增量 0.1（即原默认）', () {
      final p = builtinSpeedStepPresets[0];
      expect(p.id, 'builtin_first');
      expect(p.name, '初见·大量练习');
      expect(p.builtin, isTrue);
      expect(
        p.params,
        const SpeedStepParams(
          startRate: 0.5,
          maxRate: 1.0,
          lapsPerRate: 3,
          rateIncrement: 0.1,
        ),
      );
    });

    test('「复习」= 起步 0.5 → 封顶 1.0、每档 2 遍、递增量 0.25', () {
      final p = builtinSpeedStepPresets[1];
      expect(p.id, 'builtin_review');
      expect(p.name, '复习');
      expect(p.builtin, isTrue);
      expect(
        p.params,
        const SpeedStepParams(
          startRate: 0.5,
          maxRate: 1.0,
          lapsPerRate: 2,
          rateIncrement: 0.25,
        ),
      );
    });

    test('默认选中为首个内置预设「初见·大量练习」', () {
      expect(defaultSelectedPresetId, builtinSpeedStepPresets[0].id);
    });
  });

  group('预设 JSON 往返', () {
    test('单条预设 toJson/fromJson 往返一致（含内置覆盖标记）', () {
      const preset = SpeedStepPreset(
        id: 'custom_1',
        name: '我的节奏',
        builtin: false,
        params: SpeedStepParams(
          startRate: 0.6,
          maxRate: 1.2,
          lapsPerRate: 2,
          rateIncrement: 0.15,
        ),
      );
      expect(SpeedStepPreset.fromJson(preset.toJson()), preset);
    });

    test('预设文档（列表 + 选中 id）toJson/fromJson 往返一致', () {
      const doc = SpeedStepPresetDoc(
        presets: [
          SpeedStepPreset(
            id: 'builtin_first',
            name: '初见·大量练习',
            builtin: true,
            params: SpeedStepParams(),
          ),
          SpeedStepPreset(
            id: 'custom_1',
            name: '我的节奏',
            builtin: false,
            params: SpeedStepParams(
              startRate: 0.6,
              maxRate: 1.2,
              lapsPerRate: 2,
              rateIncrement: 0.15,
            ),
          ),
        ],
        selectedId: 'custom_1',
      );
      expect(SpeedStepPresetDoc.fromJson(doc.toJson()), doc);
    });
  });
}
