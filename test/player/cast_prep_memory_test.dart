import 'package:dance_learning_app/cast/cast_render_request.dart'
    show CastRenderChoices, CastSpeedTier;
import 'package:dance_learning_app/cast/cast_speed_tier.dart'
    show kCastSpeedTierCandidates;
import 'package:dance_learning_app/persistence/local_document.dart'
    show CastPrepMemoryFields, LocalDocument;
import 'package:dance_learning_app/player/cast_prep_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// **投屏准备记忆**纯件与会话槽（票 #40）：两个渲染勾选档 + 一个**投屏倍速
/// 档**集合按舞记住；缺失 / 非法 / 已不可用一律静默降级回默认。
///
/// 这里只测取值与降级规则（纯件）与槽的三个动作（装载 / 复位 / 回写）；
/// 面板的预置与回写路径在 `cast_prep_panel_test.dart`，落盘与恢复在
/// `settings_persistence_test.dart`。
void main() {
  group('投屏准备记忆纯件', () {
    test('没有记忆就是默认：两个勾选档全选 + 与手动倍率最接近的那一档', () {
      for (final rate in const [0.5, 0.75, 1.0, 1.3, 2.0]) {
        final preset = castPrepMemoryOf(null, manualRate: rate);
        expect(
          preset.choices,
          const CastRenderChoices.all(),
          reason: '$rate×：没有记忆时两个勾选档全选',
        );
        expect(
          preset.tiers,
          {nearestTier(rate)},
          reason: '$rate×：没有记忆时只勾就近那一档',
        );
      }
    });

    test('记忆在场：两个勾选档与多档集合都按记忆预置', () {
      const fields = CastPrepMemoryFields(
        picture: false,
        sound: true,
        tiers: ['0.5', '1'],
      );
      final preset = castPrepMemoryOf(fields, manualRate: 0.75);
      expect(
        preset.choices,
        const CastRenderChoices(picture: false, sound: true),
      );
      expect(preset.tiers, {CastSpeedTier.half, CastSpeedTier.full});
    });

    test('都不勾也是一份合法记忆：原样预置（不因渲染档全空而回默认）', () {
      const fields = CastPrepMemoryFields(
        picture: false,
        sound: false,
        tiers: ['0.75'],
      );
      final preset = castPrepMemoryOf(fields, manualRate: 1);
      expect(preset.choices, const CastRenderChoices.none());
      expect(preset.tiers, {CastSpeedTier.threeQuarter});
    });

    test('逐字段缺席：只该字段回默认，其余字段仍按记忆', () {
      // 只记住画面类勾选：声音类回默认（全选），档回默认。
      final onlyPicture = castPrepMemoryOf(
        const CastPrepMemoryFields(picture: false),
        manualRate: 0.5,
      );
      expect(
        onlyPicture.choices,
        const CastRenderChoices(picture: false, sound: true),
      );
      expect(onlyPicture.tiers, {CastSpeedTier.half});

      // 只记住档：两个勾选档都回默认（全选）。
      final onlyTiers = castPrepMemoryOf(
        const CastPrepMemoryFields(tiers: ['0.5', '0.75']),
        manualRate: 1,
      );
      expect(onlyTiers.choices, const CastRenderChoices.all());
      expect(onlyTiers.tiers, {
        CastSpeedTier.half,
        CastSpeedTier.threeQuarter,
      });
    });

    test('记住的集合为空 → 回默认那一档，绝不预置成空集合', () {
      final preset = castPrepMemoryOf(
        const CastPrepMemoryFields(),
        manualRate: 0.75,
      );
      expect(preset.tiers, {CastSpeedTier.threeQuarter});
      expect(preset.tiers, isNotEmpty, reason: '至少留一档');
    });

    test('写侧对空集合的兜底：落「没有意见」（空表），读回即默认', () {
      final fields = castPrepMemoryFieldsOf(
        const CastPrepMemory(
          choices: CastRenderChoices.all(),
          tiers: <CastSpeedTier>{},
        ),
      );
      expect(fields.tiers, isEmpty, reason: '空表不是一份可用的记忆');
      expect(
        castPrepMemoryOf(fields, manualRate: 1).tiers,
        {CastSpeedTier.full},
        reason: '读回按默认那一档，至少留一档',
      );
    });

    test('认不得的记号在投屏域的值边界拦下：只按可用那几档预置', () {
      // 值类是可以被任何调用方直接构造的公开面（文档层也原样往返记号）：
      // 词表外的记号在这里被处置掉——不是查表硬取（那会当场炸），其余照留。
      final preset = castPrepMemoryOf(
        const CastPrepMemoryFields(tiers: ['0.5', '2', 'double', '1']),
        manualRate: 0.5,
      );
      expect(preset.tiers, {CastSpeedTier.half, CastSpeedTier.full});
    });

    test('记住的档全部不可用 → 整格按「没有意见」，回默认那一档', () {
      final preset = castPrepMemoryOf(
        const CastPrepMemoryFields(tiers: ['2', 'double']),
        manualRate: 1.3,
      );
      expect(preset.tiers, {CastSpeedTier.full});
      expect(preset.choices, const CastRenderChoices.all());
    });

    test('记号的词表只此一份（候选档）：认不得的记号不炸、不清空整份记录', () {
      // 一条认得 + 一条认不得：认得的照留（不是「有一条坏就整格作废」）。
      final mixed = castPrepMemoryOf(
        const CastPrepMemoryFields(picture: false, tiers: ['0.75', '九倍速']),
        manualRate: 1,
      );
      expect(mixed.tiers, {CastSpeedTier.threeQuarter});
      expect(
        mixed.choices,
        const CastRenderChoices(picture: false, sound: true),
      );
    });

    test('写侧：三个字段都给全，档按候选次序规整（与勾选次序无关）', () {
      final fields = castPrepMemoryFieldsOf(
        const CastPrepMemory(
          choices: CastRenderChoices(picture: false, sound: true),
          tiers: {CastSpeedTier.full, CastSpeedTier.half},
        ),
      );
      expect(fields.picture, isFalse);
      expect(fields.sound, isTrue);
      expect(fields.tiers, ['0.5', '1'], reason: '候选次序：从慢到快');
    });

    test('往返：写出去再读回来是同一份取值', () {
      for (final memory in const [
        CastPrepMemory(
          choices: CastRenderChoices.all(),
          tiers: {CastSpeedTier.half},
        ),
        CastPrepMemory(
          choices: CastRenderChoices.none(),
          tiers: {
            CastSpeedTier.half,
            CastSpeedTier.threeQuarter,
            CastSpeedTier.full,
          },
        ),
        CastPrepMemory(
          choices: CastRenderChoices(picture: true, sound: false),
          tiers: {CastSpeedTier.threeQuarter, CastSpeedTier.full},
        ),
      ]) {
        expect(
          castPrepMemoryOf(
            castPrepMemoryFieldsOf(memory),
            manualRate: 0.5,
          ),
          memory,
        );
      }
    });

    test('取值判等：勾选档或档集合不同即不等（集合与次序无关）', () {
      const a = CastPrepMemory(
        choices: CastRenderChoices.all(),
        tiers: {CastSpeedTier.half, CastSpeedTier.full},
      );
      const sameOtherOrder = CastPrepMemory(
        choices: CastRenderChoices.all(),
        tiers: {CastSpeedTier.full, CastSpeedTier.half},
      );
      const otherChoices = CastPrepMemory(
        choices: CastRenderChoices.none(),
        tiers: {CastSpeedTier.half, CastSpeedTier.full},
      );
      const otherTiers = CastPrepMemory(
        choices: CastRenderChoices.all(),
        tiers: {CastSpeedTier.full},
      );
      expect(a, sameOtherOrder);
      expect(a.hashCode, sameOtherOrder.hashCode);
      expect(a == otherChoices, isFalse);
      expect(a == otherTiers, isFalse);
    });

    test('词表锁：档位记号只有候选档这一份声明（脱钩即红）', () {
      // 文档里存的是 `token`（`0.5` / `0.75` / `1`）——与缓存键、按钮文案同一
      // 套记号；投屏域加减档或改记号时这里先红。
      expect(kCastSpeedTierCandidates.map((tier) => tier.token).toList(), [
        '0.5',
        '0.75',
        '1',
      ]);
      expect(kCastSpeedTierCandidates, CastSpeedTier.values);
    });

    test('加一档不靠手抄同步：逐档经文档层往返都认得回来', () {
      // 记号词表的唯一声明处是候选档自己：新增一档只改枚举，文档层与这里都
      // 不必手抄一份（`#21` 整改）。这条断言按候选档展开——加档时它自动跟着
      // 长，谁要在别处另立一份词表（抄漏了新档）就在这里红。
      for (final tier in kCastSpeedTierCandidates) {
        final fields = _memoryFieldsFromFile([tier.token]);
        expect(castPrepMemoryOf(fields, manualRate: 1).tiers, {
          tier,
        }, reason: '${tier.token}：认不认得只由候选档回答');
      }
    });
  });

  group('投屏准备记忆槽（会话 provider）', () {
    test('装载 / 回写 / 复位三个动作：槽里始终是文档字段形状', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final model = container.read(castPrepMemoryProvider.notifier);

      expect(container.read(castPrepMemoryProvider), isNull, reason: '开局无记忆');

      model.restoreFor(
        const CastPrepMemoryFields(picture: true, sound: false, tiers: ['0.5']),
      );
      expect(container.read(castPrepMemoryProvider)!.picture, isTrue);
      expect(container.read(castPrepMemoryProvider)!.sound, isFalse);
      expect(container.read(castPrepMemoryProvider)!.tiers, ['0.5']);

      model.remember(
        const CastPrepMemory(
          choices: CastRenderChoices.all(),
          tiers: {CastSpeedTier.threeQuarter},
        ),
      );
      final written = container.read(castPrepMemoryProvider)!;
      expect(written.picture, isTrue);
      expect(written.sound, isTrue);
      expect(written.tiers, ['0.75']);

      model.clear();
      expect(container.read(castPrepMemoryProvider), isNull);
    });

    test('口（面板的取值来源与回写口）：预设读槽、回写落槽', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final port = CastPrepMemoryPort(
        presetFor: (manualRate) => castPrepMemoryOf(
          container.read(castPrepMemoryProvider),
          manualRate: manualRate,
        ),
        remember: (memory) => container
            .read(castPrepMemoryProvider.notifier)
            .remember(memory),
      );

      // 空槽 → 默认。
      expect(port.presetFor(0.75).tiers, {CastSpeedTier.threeQuarter});

      // 第一次回写建起记忆，第二次预设就按它。
      port.remember(
        const CastPrepMemory(
          choices: CastRenderChoices(picture: false, sound: true),
          tiers: {CastSpeedTier.half, CastSpeedTier.full},
        ),
      );
      final preset = port.presetFor(0.75);
      expect(
        preset.choices,
        const CastRenderChoices(picture: false, sound: true),
      );
      expect(preset.tiers, {CastSpeedTier.half, CastSpeedTier.full});
    });
  });
}

/// 盘上那份记录经**文档层**读回来的字段：测试不手写人工字段，走真实读入
/// 路径——文档层对记号原样往返，认不认得由投屏域的候选档回答。
CastPrepMemoryFields _memoryFieldsFromFile(List<String> tiers) =>
    LocalDocument.fromJson({
      'version': 3,
      'prefs': {
        'castPrep': {'tiers': tiers},
      },
    }).castPrep!;

/// 与 `nearestCastSpeedTier` 同口径的就近档（本测试自己算一遍，避免用被测件
/// 的取值当期望）。
CastSpeedTier nearestTier(double rate) {
  var best = kCastSpeedTierCandidates.first;
  var bestDistance = (best.rate - rate).abs();
  for (final tier in kCastSpeedTierCandidates.skip(1)) {
    final distance = (tier.rate - rate).abs();
    if (distance < bestDistance) {
      best = tier;
      bestDistance = distance;
    }
  }
  return best;
}
