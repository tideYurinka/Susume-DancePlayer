import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/document_beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;

import '../helpers/beat_test_seam.dart';
import '../helpers/document_grid_of.dart';

/// 八拍锚点相位：派生相位值对象 [BeatPhase]
/// 由「网格 + 锚点集合」求值——锚点自身即八拍点、其后每隔一个强拍一个
/// 八拍点、管到下一个锚点之前；锚点之前保持自动相位。

Duration ms(int v) => Duration(milliseconds: v);

/// 真实网格样例：拍点每 0.5s 一拍、强拍每 4 拍（4/4 均匀）——强拍拍序号
/// 0/4/8…、时刻 0/2/4…s（[beats] 控制拍数，默认 72 拍 = 36s）。网格构造
/// 复用共享助手（`test/helpers/beat_test_seam.dart`），只在此包一层 seam
/// 实现的 DocumentBeatGrid 适配。
DocumentBeatGrid uniformGrid({int beats = 72}) =>
    documentGridOf(uniformDownbeatGridDoc(seconds: (beats - 1) / 2));

/// 拍序号 → 时刻（0.5s 一拍）。
Duration at(int beat) => ms(beat * 500);

/// 窗口内八拍点的拍序号集合（时刻 → 序号反查）。
List<int> pointBeats(BeatPhase phase, int from, int to) => [
  for (final t in phase.pointsInWindow(at(from), at(to)))
    (t.inMilliseconds / 500).round(),
];

/// 弱起真实网格：拍点每 0.5s 一拍、首个强拍在拍序号 3（其后每 4 拍一个），
/// 有界（末拍 39）。
DocumentBeatGrid pickupGrid() => documentGridOf(
  marker_doc.BeatGrid(
    model: 'm',
    fps: 100,
    generatedAt: DateTime.utc(2024),
    beats: [
      for (var i = 0; i < 40; i++)
        marker_doc.BeatPoint(t: i * 0.5, down: i >= 3 && (i - 3) % 4 == 0),
    ],
  ),
);

void main() {
  group('BeatPhase：无锚点相位基线', () {
    test('有界真实网格：八拍点序号 / 窗口序列 / 最近点均为字面期望', () {
      final grid = uniformGrid(); // 72 拍 × 0.5s、强拍每 4 拍
      final phase = BeatPhase(grid: grid);

      // 强拍序号 0/4/8…、其中序数奇数者为八拍点：0/8/16…/64；68 是强拍
      // 但序数 18（偶），71 是末拍且非强拍。
      for (final index in [0, 8, 16, 24, 32, 40, 48, 56, 64]) {
        expect(phase.isEightBeatPoint(index), isTrue, reason: '拍序号 $index');
      }
      for (final index in [4, 20, 68, 71]) {
        expect(phase.isEightBeatPoint(index), isFalse, reason: '拍序号 $index');
      }

      // 八拍点时刻 = 拍序号 × 0.5s：整片窗口九个点。
      expect(phase.pointsInWindow(Duration.zero, ms(36000)), [
        Duration.zero,
        ms(4000),
        ms(8000),
        ms(12000),
        ms(16000),
        ms(20000),
        ms(24000),
        ms(28000),
        ms(32000),
      ]);
      // 窗口 [3000, 13000] 只含 4s/8s/12s 三点。
      expect(phase.pointsInWindow(ms(3000), ms(13000)), [
        ms(4000),
        ms(8000),
        ms(12000),
      ]);
      // 点之间的空窗与末点之后的窗口：无点。
      expect(phase.pointsInWindow(ms(12500), ms(12500)), isEmpty);
      expect(phase.pointsInWindow(ms(35000), ms(36000)), isEmpty);

      // 最近点：1s 距 0s 更近；2s 与 0s/4s 等距取靠后的 4s；末点之后
      // 回落 32s。
      expect(phase.nearest(ms(1000)), Duration.zero);
      expect(phase.nearest(ms(2000)), ms(4000));
      expect(phase.nearest(ms(3000)), ms(4000));
      expect(phase.nearest(ms(36000)), ms(32000));
    });

    test('无界占位网格：周期算术路径', () {
      const grid = placeholderBeatGrid; // 拍 0.5s、强拍每 4 拍、无界
      final phase = BeatPhase(grid: grid);

      for (final index in [0, 8, 24, 40]) {
        expect(phase.isEightBeatPoint(index), isTrue, reason: '拍序号 $index');
      }
      for (final index in [4, 20, 33]) {
        expect(phase.isEightBeatPoint(index), isFalse, reason: '拍序号 $index');
      }
      // 八拍点 0/4/8…s；[1s, 13s] 内为 4s/8s/12s。
      expect(phase.pointsInWindow(ms(1000), ms(13000)), [
        ms(4000),
        ms(8000),
        ms(12000),
      ]);
      expect(phase.nearest(ms(2000)), ms(4000), reason: '等距取靠后');
      expect(phase.nearest(ms(9000)), ms(8000));
    });
  });

  group('BeatPhase：分段奇偶重定相（八拍锚点）', () {
    test('单锚点：第 8 个强拍落锚后 = 8/10/12…，且 7→8 只隔 4 拍（半八拍基线）', () {
      final grid = uniformGrid();
      // 无锚点自动相位：强拍序数 1/3/5/7 = 拍序号 0/8/16/24。
      final auto = BeatPhase(grid: grid);
      expect(pointBeats(auto, 0, 71), [0, 8, 16, 24, 32, 40, 48, 56, 64]);
      // 第 8 个强拍 = 拍序号 28（原本是偶数序数、非八拍点）。
      final phase = BeatPhase(grid: grid, anchors: const [28]);

      expect(phase.isEightBeatPoint(28), isTrue, reason: '锚点自身即八拍点');
      expect(pointBeats(phase, 0, 71), [0, 8, 16, 24, 28, 36, 44, 52, 60, 68]);
      // 半八拍：第 7 个与第 8 个强拍（序数 7→8）之间只隔 4 拍。
      expect(at(28) - at(24), ms(2000), reason: '4 拍 × 0.5s');
      expect(phase.isEightBeatPoint(30), isFalse, reason: '非强拍无八拍点');
    });

    test('锚点之前的相位逐位不变', () {
      final grid = uniformGrid();
      final auto = BeatPhase(grid: grid);
      final phase = BeatPhase(grid: grid, anchors: const [28]);

      for (var i = 0; i < 28; i++) {
        expect(
          phase.isEightBeatPoint(i),
          auto.isEightBeatPoint(i),
          reason: '锚点之前拍序号 $i 相位不变',
        );
      }
    });

    test('多锚点分段：第三段按最近锚点计、锚点处截断上一段', () {
      final grid = uniformGrid();
      // 第二锚点 40 在纯 28 相位下不是八拍点（序数 4）——落锚后它成为
      // 新段原点，其后 40/48/56/64 为八拍点，而 44（旧段序数 5）被截断。
      final phase = BeatPhase(grid: grid, anchors: const [28, 40]);

      expect(pointBeats(phase, 0, 71), [0, 8, 16, 24, 28, 36, 40, 48, 56, 64]);
      expect(phase.isEightBeatPoint(44), isFalse, reason: '下一锚点处截断');
      expect(phase.isEightBeatPoint(40), isTrue);
    });

    test('窗口序列：窗口切断不重置相位、只出窗内点', () {
      final grid = uniformGrid();
      final phase = BeatPhase(grid: grid, anchors: const [28]);

      expect(pointBeats(phase, 26, 46), [28, 36, 44]);
      expect(pointBeats(phase, 29, 35), isEmpty);
    });

    test('最近点解析：等距并列取时间靠后者、锚点段内亦然', () {
      final grid = uniformGrid();
      final phase = BeatPhase(grid: grid, anchors: const [28]);

      // 12s（序号 24）与 14s（序号 28）等距 → 取靠后的 14s。
      expect(phase.nearest(ms(13000)), at(28));
      expect(phase.nearest(ms(12999)), at(24));
      // 锚点段内：17s（序号 34）距 18s（序号 36）更近。
      expect(phase.nearest(ms(17000)), at(36));
    });

    test('网格无八拍点返回 null；非强拍锚点被忽略（不改相位）', () {
      final grid = documentGridOf(
        marker_doc.BeatGrid(
          model: 'm',
          fps: 100,
          generatedAt: DateTime.utc(2024),
          beats: [
            for (var i = 0; i < 16; i++)
              marker_doc.BeatPoint(t: i * 0.5, down: false),
          ],
        ),
      );
      expect(BeatPhase(grid: grid).nearest(ms(1000)), isNull);
      expect(
        BeatPhase(grid: grid, anchors: const [4]).nearest(ms(1000)),
        isNull,
      );

      final uniform = uniformGrid();
      final ignored = BeatPhase(grid: uniform, anchors: const [30]);
      expect(ignored.anchors, isEmpty, reason: '非强拍锚点不成立');
      expect(
        pointBeats(ignored, 0, 71),
        pointBeats(BeatPhase(grid: uniform), 0, 71),
      );
    });

    test('锚点集合语义等价于升序去重（乱序/重复输入同结果）', () {
      final grid = uniformGrid();
      final canonical = BeatPhase(grid: grid, anchors: const [28, 40]);
      final messy = BeatPhase(grid: grid, anchors: const [40, 28, 28]);

      expect(messy.anchors, [28, 40]);
      expect(pointBeats(messy, 0, 71), pointBeats(canonical, 0, 71));
    });

    test('无界占位网格：锚点按周期算术分段求值', () {
      const grid = placeholderBeatGrid; // 拍 0.5s、强拍每 4 拍、无界
      final phase = BeatPhase(grid: grid, anchors: const [16]);

      // 自动相位 0s/4s；锚点（拍序号 16 = 8s）后 8s/12s/16s。
      expect(phase.nearest(ms(1500)), ms(0));
      expect(phase.pointsInWindow(ms(0), ms(18000)), [
        ms(0),
        ms(4000),
        ms(8000),
        ms(12000),
        ms(16000),
      ]);
      expect(phase.nearest(ms(10000)), ms(12000), reason: '等距取靠后');
      expect(phase.isEightBeatPoint(24), isTrue);
      expect(phase.isEightBeatPoint(20), isFalse);
    });
  });

  group('BeatPhase：八拍点索引回溯（动画八拍窗口首拍）', () {
    test('有界网格：不晚于给定拍的最近八拍点', () {
      final grid = uniformGrid(); // 八拍点 = 拍序号 0/8/16/24…
      final phase = BeatPhase(grid: grid);

      expect(phase.eightBeatPointIndexAtOrBefore(0), 0);
      expect(phase.eightBeatPointIndexAtOrBefore(7), 0);
      expect(phase.eightBeatPointIndexAtOrBefore(8), 8);
      expect(phase.eightBeatPointIndexAtOrBefore(9), 8);
      expect(phase.eightBeatPointIndexAtOrBefore(71), 64);
    });

    test('锚点段内：锚点自身即最近点、其前仍是自动相位点', () {
      final grid = uniformGrid();
      final phase = BeatPhase(grid: grid, anchors: const [28]);

      expect(phase.eightBeatPointIndexAtOrBefore(24), 24);
      expect(phase.eightBeatPointIndexAtOrBefore(27), 24);
      expect(phase.eightBeatPointIndexAtOrBefore(28), 28, reason: '锚点自身即八拍点');
      expect(phase.eightBeatPointIndexAtOrBefore(35), 28);
      expect(phase.eightBeatPointIndexAtOrBefore(36), 36);
    });

    test('无界占位网格：周期算术最近点', () {
      const grid = placeholderBeatGrid; // 无界、强拍每 4 拍
      final phase = BeatPhase(grid: grid);

      for (final probe in [(0, 0), (6, 0), (7, 0), (8, 8), (9, 8), (100, 96)]) {
        expect(
          phase.eightBeatPointIndexAtOrBefore(probe.$1),
          probe.$2,
          reason: '拍序号 ${probe.$1}',
        );
      }
    });

    test('弱起网格：首个八拍点之前返回 null（无窗口可回溯）', () {
      final grid = pickupGrid(); // 首个强拍 = 拍序号 3
      final phase = BeatPhase(grid: grid);

      expect(phase.eightBeatPointIndexAtOrBefore(0), isNull);
      expect(phase.eightBeatPointIndexAtOrBefore(2), isNull);
      expect(phase.eightBeatPointIndexAtOrBefore(3), 3);
      expect(phase.eightBeatPointIndexAtOrBefore(10), 3);
      expect(phase.eightBeatPointIndexAtOrBefore(11), 11);
    });

    test('网格无强拍：恒 null（无八拍点可回溯）', () {
      final grid = documentGridOf(
        marker_doc.BeatGrid(
          model: 'm',
          fps: 100,
          generatedAt: DateTime.utc(2024),
          beats: [
            for (var i = 0; i < 16; i++)
              marker_doc.BeatPoint(t: i * 0.5, down: false),
          ],
        ),
      );
      expect(BeatPhase(grid: grid).eightBeatPointIndexAtOrBefore(15), isNull);
    });

    test('与单点判定同源：回溯结果恒为八拍点', () {
      final grid = uniformGrid();
      final phase = BeatPhase(grid: grid, anchors: const [28]);

      for (var i = 0; i <= 71; i++) {
        final found = phase.eightBeatPointIndexAtOrBefore(i);
        if (found == null) continue;
        expect(found, lessThanOrEqualTo(i), reason: '拍 $i');
        expect(
          phase.isEightBeatPoint(found),
          isTrue,
          reason: '拍 $i 回溯到的 $found 须是八拍点',
        );
      }
    });

    test('索引域区间：闭区间内的八拍点序号（数拍八拍号顺数用）', () {
      final grid = uniformGrid();
      final anchored = BeatPhase(grid: grid, anchors: const [28]);

      expect(BeatPhase(grid: grid).eightBeatPointIndicesInRange(0, 20), [
        0,
        8,
        16,
      ]);
      expect(anchored.eightBeatPointIndicesInRange(1, 27), [8, 16, 24]);
      expect(anchored.eightBeatPointIndicesInRange(25, 28), [
        28,
      ], reason: '半八拍：锚点 28 落在区间内');
      expect(anchored.eightBeatPointIndicesInRange(29, 35), isEmpty);
      expect(anchored.eightBeatPointIndicesInRange(25, 36), [28, 36]);
    });

    test('强拍判定 = 八拍点或 downbeat（大线/中线同一条判定）', () {
      final grid = uniformGrid(); // downbeat 每 4 拍、八拍点每 8 拍
      final anchored = BeatPhase(grid: grid, anchors: const [28]);

      // 4/20/40 是四拍中线（downbeat、非八拍点）→ 强拍；5 两者都不是 → 弱拍。
      expect(anchored.isStrongBeat(4), isTrue, reason: '四拍中线 = 强拍');
      expect(anchored.isStrongBeat(20), isTrue, reason: '四拍中线 = 强拍');
      expect(anchored.isStrongBeat(40), isTrue, reason: '四拍中线 = 强拍');
      expect(anchored.isStrongBeat(5), isFalse, reason: '弱拍非强拍');
      expect(anchored.isStrongBeat(28), isTrue, reason: '锚点自身即八拍点');
      expect(
        anchored.isStrongBeat(28) && !anchored.isEightBeatPoint(20),
        isTrue,
        reason: '锚点段：28 强拍且为八拍点、20 已非八拍点',
      );
    });
  });
}
