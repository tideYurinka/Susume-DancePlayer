import 'package:dance_learning_app/core/current_beat.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_anchor_probe.dart';

/// core 数拍派生直测（不经浮层，期望字面独立书写）。
void main() {
  // 占位均匀网格 120 bpm：一拍 500ms。
  const grid = UniformBeatGrid();

  group('练习区顺数 deriveBeatCount（practice 区）', () {
    test('锚点即 1｜1', () {
      final display = deriveBeatCount(
        grid: grid,
        anchor: const Duration(seconds: 2),
        position: const Duration(seconds: 2),
        phase: BeatPhase(grid: grid),
      );
      expect(display, isA<PracticeBeatCount>());
      final practice = display as PracticeBeatCount;
      expect(practice.eightCount, 1);
      expect(practice.beatCount, 1);
    });

    test('段内推进：1|4（锚 4s 即八拍点，号内无点进位）', () {
      final practice = deriveBeatCount(
        grid: grid,
        anchor: const Duration(seconds: 4),
        position: const Duration(milliseconds: 5500),
        phase: BeatPhase(grid: grid),
      ) as PracticeBeatCount;
      expect(practice.eightCount, 1);
      expect(practice.beatCount, 4);
    });

    test('跨八拍点进位：1|8 → 2|1', () {
      final practice = deriveBeatCount(
        grid: grid,
        anchor: const Duration(seconds: 4),
        position: const Duration(seconds: 8),
        phase: BeatPhase(grid: grid),
      ) as PracticeBeatCount;
      expect(practice.eightCount, 2);
      expect(practice.beatCount, 1);
    });

    test('长段顺数：锚 2s、位置 16.5s = 5｜2', () {
      // 字面期望：段内严格晚于锚 2s 且 ≤ 16.5s 的八拍点为 4/8/12/16s
      // 共 4 个 → 八拍号 = 点数 + 1 = 5；拍号自 16s 顺数 1 拍 = 2。
      final practice = deriveBeatCount(
        grid: grid,
        anchor: const Duration(seconds: 2),
        position: const Duration(milliseconds: 16500),
        phase: BeatPhase(grid: grid),
      ) as PracticeBeatCount;
      expect(practice.eightCount, 5);
      expect(practice.beatCount, 2);
    });
  });

  group('前导区 0|x deriveBeatCount', () {
    test('锚前 8 拍逐拍 0|1…0|8', () {
      const expected = [1, 2, 3, 4, 5, 6, 7, 8];
      for (var i = 0; i < expected.length; i++) {
        final display = deriveBeatCount(
          grid: grid,
          anchor: const Duration(seconds: 6),
          position: Duration(milliseconds: 2000 + 500 * i),
          phase: BeatPhase(grid: grid),
        );
        expect(display, isA<LeadingBeatCount>(), reason: '第 ${i + 1} 拍');
        final leading = display as LeadingBeatCount;
        expect(leading.eightCount, 0);
        expect(leading.beatCount, expected[i]);
      }
    });

    test('锚前超过 8 拍钳 0|1，不外推 0 或负拍号', () {
      final leading = deriveBeatCount(
        grid: grid,
        anchor: const Duration(seconds: 6),
        position: Duration.zero,
        phase: BeatPhase(grid: grid),
      ) as LeadingBeatCount;
      expect(leading.eightCount, 0);
      expect(leading.beatCount, 1);
    });

    test('前导区换算：距锚 1 拍 = 8、9 拍钳 1', () {
      const anchor = Duration(seconds: 6);
      const beat = Duration(milliseconds: 500);
      for (final (before, expected) in [(1, 8), (8, 1), (9, 1)]) {
        final leading = deriveBeatCount(
          grid: grid,
          anchor: anchor,
          position: anchor - beat * before,
          phase: BeatPhase(grid: grid),
        ) as LeadingBeatCount;
        expect(leading.beatCount, expected, reason: '距锚 $before 拍');
      }
    });
  });

  group('锚点链解析（经公开求值口）', () {
    test('优先级：录制锚 > 延迟锚 > 激活锚 > 最近分段线 > 首线', () {
      final lines = [const Duration(seconds: 4), const Duration(seconds: 8)];
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: const Duration(seconds: 4),
          recordingAnchor: const Duration(seconds: 3),
          segmentLines: lines,
          firstLine: lines.first,
          position: const Duration(seconds: 9),
          gridLastBeatTime: const Duration(seconds: 20),
        ),
        const Duration(seconds: 3),
      );
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: const Duration(seconds: 4),
          delayAnchor: const Duration(seconds: 2),
          segmentLines: lines,
          firstLine: lines.first,
          position: const Duration(seconds: 9),
          gridLastBeatTime: const Duration(seconds: 20),
        ),
        const Duration(seconds: 2),
      );
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: null,
          segmentLines: lines,
          firstLine: lines.first,
          position: const Duration(seconds: 5),
          gridLastBeatTime: const Duration(seconds: 20),
        ),
        const Duration(seconds: 4),
      );
    });

    test('位置早于首线或超出末拍 → null', () {
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: null,
          segmentLines: const [Duration(seconds: 4)],
          firstLine: const Duration(seconds: 4),
          position: const Duration(seconds: 1),
          gridLastBeatTime: const Duration(seconds: 20),
        ),
        isNull,
      );
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: null,
          segmentLines: const [Duration(seconds: 4)],
          firstLine: const Duration(seconds: 4),
          position: const Duration(seconds: 21),
          gridLastBeatTime: const Duration(seconds: 20),
        ),
        isNull,
      );
    });
  });
}
