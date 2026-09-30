import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/current_beat.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';
import 'package:dance_learning_app/player/metronome_source_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/uniform_test_grid.dart';

/// 当前拍纯求值直测：`(网格上下文, 位置) → 当前拍`
/// ——期望字面独立书写，不复用实现判定式。
void main() {
  CurrentBeat? eval(
    Duration position, {
    BeatGrid grid = const UniformBeatGrid(),
    List<Duration> segmentLines = const [],
    Duration firstLine = Duration.zero,
    List<Duration> halfBeatLines = const [],
    bool halfBeatEnabled = true,
    List<int> eightBeatAnchors = const [],
    Duration? delayAnchor,
  }) {
    return evaluateCurrentBeat(
      grid: grid,
      phase: BeatPhase(grid: grid, anchors: eightBeatAnchors),
      recordingAnchor: null,
      delayAnchor: delayAnchor,
      activeAnchor: null,
      segmentLines: segmentLines,
      firstLine: firstLine,
      position: position,
      halfBeatLines: halfBeatLines,
      halfBeatEnabled: halfBeatEnabled,
    );
  }

  group('数拍数字与八拍号 / 拍号派生', () {
    test('前导区：锚 6s 前逐拍 0|x（0|8 → 0|1 顺数）', () {
      // 前导 = 位置在锚点之前：延迟锚 6s，位置 5.5s 距锚 1 拍 → 0|8。
      final leading = eval(
        const Duration(milliseconds: 5500),
        firstLine: Duration.zero,
        delayAnchor: const Duration(seconds: 6),
      );
      expect(leading!.eightCount, 0);
      expect(leading.beatCount, 8);
    });

    test('进入锚点：锚点上恒 1｜1', () {
      final practice = eval(
        const Duration(seconds: 6),
        segmentLines: const [Duration(seconds: 6)],
        firstLine: const Duration(seconds: 6),
      );
      expect(practice!.eightCount, 1);
      expect(practice.beatCount, 1);
    });

    test('锚后顺数：6.5s = 1｜2', () {
      final practice = eval(
        const Duration(milliseconds: 6500),
        segmentLines: const [Duration(seconds: 6)],
        firstLine: const Duration(seconds: 6),
      );
      expect(practice!.eightCount, 1);
      expect(practice.beatCount, 2);
    });
  });

  group('稳定与跨分段线', () {
    test('同一位置重复求值结果相等', () {
      const pos = Duration(milliseconds: 7250);
      final a = eval(
        pos,
        segmentLines: const [Duration(seconds: 6)],
        firstLine: const Duration(seconds: 6),
      );
      final b = eval(
        pos,
        segmentLines: const [Duration(seconds: 6)],
        firstLine: const Duration(seconds: 6),
      );
      expect(a, equals(b));
    });

    test('相邻两拍跨分段线各用各自位置的锚：8｜8 → 1｜1', () {
      // 分段线 6s 不落八拍点上（锚 6s = 1|1 起）；线前最后一拍 5.5s 属
      // 前一线（锚 0s：第 12 拍 = 2｜4），线后第一拍 6s 属新线（1｜1）。
      final before = eval(
        const Duration(milliseconds: 5500),
        segmentLines: const [Duration(seconds: 6)],
        firstLine: Duration.zero,
      );
      expect(before!.eightCount, 2);
      expect(before.beatCount, 4);
      final after = eval(
        const Duration(seconds: 6),
        segmentLines: const [Duration(seconds: 6)],
        firstLine: Duration.zero,
      );
      expect(after!.eightCount, 1);
      expect(after.beatCount, 1);
    });
  });

  group('半拍线', () {
    test('前导区内半拍线不排（值为空）', () {
      final leading = eval(
        const Duration(milliseconds: 5500),
        firstLine: Duration.zero,
        delayAnchor: const Duration(seconds: 6),
        halfBeatLines: const [Duration(milliseconds: 5250)],
      );
      expect(leading!.halfBeatLines, isEmpty);
    });

    test('正式区半拍线照排：本拍内的线落在值里', () {
      final practice = eval(
        const Duration(seconds: 6),
        segmentLines: const [Duration(seconds: 6)],
        firstLine: const Duration(seconds: 6),
        halfBeatLines: const [Duration(milliseconds: 6250)],
      );
      expect(
        practice!.halfBeatLines,
        [const Duration(milliseconds: 6250)],
      );
    });

    test('与整拍同毫秒的半拍线不双响（不进值）', () {
      final practice = eval(
        const Duration(seconds: 6),
        segmentLines: const [Duration(seconds: 6)],
        firstLine: const Duration(seconds: 6),
        halfBeatLines: const [
          Duration(seconds: 6), // 本拍起点
          Duration(milliseconds: 6500), // 下一拍起点
        ],
      );
      expect(practice!.halfBeatLines, isEmpty);
    });

    test('半拍开关关闭时值为空', () {
      final practice = eval(
        const Duration(seconds: 6),
        segmentLines: const [Duration(seconds: 6)],
        firstLine: const Duration(seconds: 6),
        halfBeatLines: const [Duration(milliseconds: 6250)],
        halfBeatEnabled: false,
      );
      expect(practice!.halfBeatLines, isEmpty);
    });
  });

  group('网格三态', () {
    test('占位网格照常给出数值', () {
      final value = eval(
        const Duration(milliseconds: 1250),
        firstLine: Duration.zero,
      );
      expect(value!.eightCount, 1);
      expect(value.beatCount, 3);
    });

    test('异常网格给出数值（哨兵 0.5s 拍）', () {
      const fallback = UnavailableBeatGrid();
      final value = eval(
        const Duration(milliseconds: 1250),
        grid: fallback,
        firstLine: Duration.zero,
      );
      expect(value, isNotNull);
      expect(value!.beatCount, 3);
      expect(value.beatStart, const Duration(seconds: 1));
      expect(value.nextBeat, const Duration(milliseconds: 1500));
    });

    test('锚归位仅就绪网格生效（含弱起）：就绪网格锚归首个强拍', () {
      // 弱起就绪网格：首两个非强拍，首个强拍在第 2 拍（1s）。
      final ready = UniformTestGrid(firstDownbeatIndex: 2);
      final value = evaluateCurrentBeat(
        grid: ready,
        phase: BeatPhase(grid: ready),
        recordingAnchor: null,
        delayAnchor: null,
        activeAnchor: null,
        segmentLines: const [Duration.zero],
        firstLine: Duration.zero,
        position: Duration.zero,
      );
      // 锚 0s 归到 1s（首个强拍），位置 0s 在锚之前 2 拍 → 前导 0|7。
      expect(value!.eightCount, 0);
      expect(value.beatCount, 7);

      // 占位网格同锚原样：位置 0s 即锚 → 1｜1，不归位。
      const placeholder = UniformBeatGrid();
      final plain = evaluateCurrentBeat(
        grid: placeholder,
        phase: BeatPhase(grid: placeholder),
        recordingAnchor: null,
        delayAnchor: null,
        activeAnchor: null,
        segmentLines: const [Duration.zero],
        firstLine: Duration.zero,
        position: Duration.zero,
      );
      expect(plain!.eightCount, 1);
      expect(plain.beatCount, 1);
    });

    test('就绪网格弱起归位后 1｜1 落在首个强拍', () {
      final ready = UniformTestGrid(firstDownbeatIndex: 2);
      final value = evaluateCurrentBeat(
        grid: ready,
        phase: BeatPhase(grid: ready),
        recordingAnchor: null,
        delayAnchor: null,
        activeAnchor: null,
        segmentLines: const [Duration.zero],
        firstLine: Duration.zero,
        position: const Duration(seconds: 1),
      );
      expect(value!.eightCount, 1);
      expect(value.beatCount, 1);
      expect(value.isEightBeatPoint, isTrue);
    });
  });

  group('发布值自足', () {
    test('拍起点 / 下一拍 / 拍内进度 / 半拍线都在值内', () {
      final value = eval(
        const Duration(milliseconds: 7250),
        segmentLines: const [Duration(seconds: 6)],
        firstLine: const Duration(seconds: 6),
        halfBeatLines: const [Duration(milliseconds: 6250)],
      );
      expect(value!.beatStart, const Duration(seconds: 7));
      expect(value.nextBeat, const Duration(milliseconds: 7500));
      expect(value.progress, closeTo(0.5, 1e-9));
      expect(value.isEightBeatPoint, isFalse);
      expect(value.isStrongBeat, isFalse);
    });

    test('就绪网格末拍：下一拍为空、进度按名义一拍', () {
      final ready = UniformTestGrid(beatCount: 8);
      final value = evaluateCurrentBeat(
        grid: ready,
        phase: BeatPhase(grid: ready),
        recordingAnchor: null,
        delayAnchor: null,
        activeAnchor: null,
        segmentLines: const [],
        firstLine: Duration.zero,
        position: const Duration(milliseconds: 3500),
      );
      expect(value!.nextBeat, isNull);
      expect(value.progress, closeTo(0.0, 1e-9));
    });

    test('前导区发布值同样自足：拍起点 / 下一拍 / 拍内进度都在值内', () {
      final value = eval(
        const Duration(milliseconds: 5500),
        firstLine: Duration.zero,
        delayAnchor: const Duration(seconds: 6),
      );
      expect(value!.eightCount, 0);
      expect(value.beatCount, 8);
      expect(value.beatStart, const Duration(milliseconds: 5500));
      expect(value.nextBeat, const Duration(seconds: 6));
      expect(value.progress, closeTo(0.0, 1e-9));
    });

    test('前导区的八拍点 / 强拍布尔照网格相位给出（发声归闸门，不在本值）', () {
      // 延迟锚 6s 前的 0|8 落在 5.5s（普通拍）；4s 为网格八拍点（大线）
      // → 两布尔照实。前导区不出声由发声闸门裁决，不在本值。
      final plain = eval(
        const Duration(milliseconds: 5500),
        firstLine: Duration.zero,
        delayAnchor: const Duration(seconds: 6),
      );
      expect(plain!.isStrongBeat, isFalse);
      expect(plain.isEightBeatPoint, isFalse);
      final strong = eval(
        const Duration(seconds: 4),
        firstLine: Duration.zero,
        delayAnchor: const Duration(seconds: 6),
      );
      expect(strong!.beatCount, 5);
      expect(strong.isStrongBeat, isTrue);
      expect(strong.isEightBeatPoint, isTrue);
    });
  });

  group('回卷与同源对表', () {
    test('段循环回跳：段首 1｜1 重新起数；整片回跳：回到首线', () {
      const lines = [Duration(seconds: 6), Duration(seconds: 12)];
      // 段内推进到 2｜3 后段循环回跳到第二段段首 12s → 1｜1。
      final mid = eval(const Duration(milliseconds: 8500), segmentLines: lines);
      expect(mid!.eightCount, 2);
      expect(mid.beatCount, 2);
      final looped = eval(const Duration(seconds: 12), segmentLines: lines);
      expect(looped!.eightCount, 1);
      expect(looped.beatCount, 1);
      // 整片循环回跳到首线 0s → 1｜1。
      final head = eval(Duration.zero, segmentLines: lines);
      expect(head!.eightCount, 1);
      expect(head.beatCount, 1);
    });

    test('同源对表：逐拍求值的八拍号/拍号过选段规则与逐拍择段一致', () {
      final ready = UniformTestGrid(beatCount: 32);
      // 锚素材只留首线：对表锚 = 首线（零）。对表侧槽位独立书写：
      // 数拍派生（deriveBeatCount 直取锚 0）→ 选段规则，不经求值函数。
      for (var ms = 0; ms <= 12000; ms += 250) {
        final position = Duration(milliseconds: ms);
        final value = evaluateCurrentBeat(
          grid: ready,
          phase: BeatPhase(grid: ready),
          recordingAnchor: null,
          delayAnchor: null,
          activeAnchor: null,
          segmentLines: const [],
          firstLine: Duration.zero,
          position: position,
        );
        if (value == null) continue;
        final fromEvaluation = selectMetronomeSlot(
          eightCount: value.eightCount,
          beatCount: value.beatCount,
          mode: MetronomeSlotMode.effect,
        );
        final directCount = deriveBeatCount(
          grid: ready,
          anchor: Duration.zero,
          position: position,
          phase: BeatPhase(grid: ready),
        );
        final fromAnchor = switch (directCount) {
          PracticeBeatCount(:final eightCount, :final beatCount) ||
          LeadingBeatCount(:final eightCount, :final beatCount) =>
            selectMetronomeSlot(
              eightCount: eightCount,
              beatCount: beatCount,
              mode: MetronomeSlotMode.effect,
            ),
        };
        expect(
          fromEvaluation,
          fromAnchor,
          reason: '位置 $ms 处选段同源',
        );
      }
    });
  });

  group('选段四路与选速三态（字面期望）', () {
    test('音效类：恒按拍号（八拍点不换号）', () {
      final slot = selectMetronomeSlot(
        eightCount: 3,
        beatCount: 1,
        mode: MetronomeSlotMode.effect,
      );
      expect(slot, MetronomeSegmentSlot.count1);
    });

    test('按号发音类：小节首按八拍号（八拍号 3 → 号 3）', () {
      final slot = selectMetronomeSlot(
        eightCount: 3,
        beatCount: 1,
        mode: MetronomeSlotMode.numbered,
      );
      expect(slot, MetronomeSegmentSlot.count3);
    });

    test('前导 0｜x：按拍号选段（0|8 → 号 8 槽）', () {
      final slot = selectMetronomeSlot(
        eightCount: 0,
        beatCount: 8,
        mode: MetronomeSlotMode.numbered,
      );
      expect(slot, MetronomeSegmentSlot.count8);
    });

    test('校准会话：每 4 拍重音、无半拍（档 500ms 均匀网格，锚 0）', () {
      // 位置 2s = 第 5 拍 → 1｜5（重音槽）；1.5s = 第 4 拍 → 1｜4（非重音）。
      final accent = eval(const Duration(seconds: 2), firstLine: Duration.zero);
      expect(accent!.beatCount, 5);
      expect(accent.eightCount, 1);
      final plain = eval(
        const Duration(milliseconds: 1500),
        firstLine: Duration.zero,
      );
      expect(plain!.beatCount, 4);
      expect(plain.isStrongBeat, isFalse);
    });

    test('选速三态：有适配取最快 / 全适配取最快 / 无适配取最慢', () {
      final groups = [
        MetronomeSpeedGroup(standardMs: 70, slots: _slots()),
        MetronomeSpeedGroup(standardMs: 100, slots: _slots()),
        MetronomeSpeedGroup(standardMs: 130, slots: _slots()),
      ];
      // 部分适配：间隔 100 → 适配组 {70,100} 里最快 = 70。
      expect(selectMetronomeSpeedGroupIndex(groups, 100), 0);
      // 全适配：间隔 200 → 最快 = 70。
      expect(selectMetronomeSpeedGroupIndex(groups, 200), 0);
      // 无适配：间隔 60 → 全超，取最慢 = 130。
      expect(selectMetronomeSpeedGroupIndex(groups, 60), 2);
    });
  });
}

List<SegmentSpec> _slots() => List.filled(
  kMetronomeSlotCount,
  const SegmentSpec(asset: 'assets/sounds/metronome_beat.wav', markerMs: 0),
);
