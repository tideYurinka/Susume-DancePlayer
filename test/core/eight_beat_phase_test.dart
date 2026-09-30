import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';

Duration ms(int v) => Duration(milliseconds: v);

/// 测试用真实网格：拍点每 500ms 一拍、强拍（downbeat）按 [downbeats]
/// 给定（弱起变体把首强拍挪到序号 3）。
class FakeRealTestGrid implements BeatGrid {
  // 性质表态：本 fake 模拟就绪真实网格。
  @override
  BeatGridNature get nature => BeatGridNature.ready;

  FakeRealTestGrid(this.times, this.downbeats);

  final List<Duration> times;
  final Set<int> downbeats;

  @override
  int get beatsPerBar => 4;

  @override
  Duration beatTime(int index) => times[index];

  @override
  int beatIndexAt(Duration time) {
    var index = -1;
    for (var i = 0; i < times.length; i++) {
      if (times[i] <= time) index = i;
    }
    return index;
  }

  @override
  bool isDownbeat(int index) => downbeats.contains(index);

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      times[from + count] - times[from];

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) => [
    for (final t in times)
      if (t >= start && t <= end) t,
  ];

  @override
  int get firstDownbeatIndex =>
      downbeats.isEmpty ? 0 : downbeats.reduce((a, b) => a < b ? a : b);

  @override
  int? get lastBeatIndex => times.length - 1;
}

/// 弱起网格：首拍 0.1s 非强拍，强拍序号 3/7/11/15（1.6s/3.6s/5.6s/7.6s）
/// → 默认原点（序号 3）下八拍点 = 序数奇数的强拍 1.6s 与 5.6s。
FakeRealTestGrid pickupGrid() => FakeRealTestGrid(
  [for (var i = 0; i < 16; i++) ms(100 + i * 500)],
  {3, 7, 11, 15},
);

void main() {
  group('八拍相位纯派生（core 单一相位源）', () {
    test('单点判定：自原点起 downbeat 序数（1 起）奇数 = 八拍点', () {
      final grid = pickupGrid();
      final phase = BeatPhase(grid: grid);
      // 默认原点 = 首个强拍（序号 3）：序数 1（1.6s）、3（5.6s）为八拍点。
      expect(phase.isEightBeatPoint(3), isTrue);
      expect(phase.isEightBeatPoint(7), isFalse);
      expect(phase.isEightBeatPoint(11), isTrue);
      expect(phase.isEightBeatPoint(15), isFalse);
      // 非强拍、原点之前均非八拍点。
      expect(phase.isEightBeatPoint(4), isFalse);
      expect(phase.isEightBeatPoint(0), isFalse);
    });

    test('显式原点：相位自指定 downbeat 重数（八拍锚点）', () {
      final grid = pickupGrid();
      // 锚点 = 默认原点（首个强拍序号 3）→ 与默认逐位一致。
      final atFirst = BeatPhase(grid: grid, anchors: const [3]);
      expect(atFirst.isEightBeatPoint(3), isTrue);
      expect(atFirst.isEightBeatPoint(11), isTrue);
      // 锚点改到序号 7：锚点自身即八拍点（序数 1），其后序号 15（序数 3）
      // 仍是八拍点。
      final atSeven = BeatPhase(grid: grid, anchors: const [7]);
      expect(atSeven.isEightBeatPoint(7), isTrue);
      expect(atSeven.isEightBeatPoint(15), isTrue);
    });

    test('最近八拍点解析：弱起、等距并列取靠后者、原点之前贴首点', () {
      final grid = pickupGrid();
      final phase = BeatPhase(grid: grid);
      expect(phase.nearest(ms(2000)), ms(1600));
      expect(phase.nearest(ms(4600)), ms(5600));
      // 弱起区间落在首强拍之前 → 贴首个八拍点。
      expect(phase.nearest(ms(500)), ms(1600));
    });

    test('窗口八拍点序列：有界网格窗口切断只出窗内点', () {
      final grid = pickupGrid();
      final phase = BeatPhase(grid: grid);
      // 整窗：两个八拍点 1.6s / 5.6s。
      expect(phase.pointsInWindow(ms(0), ms(8000)), [ms(1600), ms(5600)]);
      // 窗口切断：只含 5.6s。
      expect(phase.pointsInWindow(ms(3000), ms(7000)), [ms(5600)]);
      // 空窗：无点。
      expect(phase.pointsInWindow(ms(2000), ms(3000)), isEmpty);
    });

    test('无界占位网格：按 beatsPerBar × 2 周期算术求值', () {
      const grid = placeholderBeatGrid;
      final phase = BeatPhase(grid: grid);
      // 首个强拍 0 起每 8 拍（4s）一个八拍点。
      expect(phase.nearest(ms(1000)), ms(0));
      expect(phase.nearest(ms(9000)), ms(8000));
      // 窗口算术求值。
      expect(phase.pointsInWindow(ms(1000), ms(13000)), [
        ms(4000),
        ms(8000),
        ms(12000),
      ]);
      // 单点判定按同周期。
      expect(phase.isEightBeatPoint(16), isTrue);
      expect(phase.isEightBeatPoint(20), isFalse);
    });

    test('锚点 = 首个强拍时与无锚点逐位一致（显式默认原点等价回归）', () {
      final grid = pickupGrid();
      final anchored = BeatPhase(
        grid: grid,
        anchors: [grid.firstDownbeatIndex],
      );
      final plain = BeatPhase(grid: grid);
      for (var t = 0; t <= 8000; t += 100) {
        expect(anchored.nearest(ms(t)), plain.nearest(ms(t)));
      }
    });
  });

  group('键盘微调的相邻点求值', () {
    // 占位 120bpm 无界：拍点 0/0.5/1.0…，八拍点 0/4/8…s。
    test('相邻八拍点：取严格前后最近者，方向 0 无目标', () {
      const grid = placeholderBeatGrid;
      final phase = BeatPhase(grid: grid);
      expect(adjacentEightBeatPoint(phase, grid, ms(5000), 1), ms(8000));
      expect(adjacentEightBeatPoint(phase, grid, ms(5000), -1), ms(4000));
      expect(adjacentEightBeatPoint(phase, grid, ms(4000), 1), ms(8000));
      expect(adjacentEightBeatPoint(phase, grid, ms(4000), -1), ms(0));
      expect(adjacentEightBeatPoint(phase, grid, ms(5000), 0), isNull);
    });

    test('相邻八拍点：网格首点之前无目标（不越界）', () {
      const grid = placeholderBeatGrid;
      final phase = BeatPhase(grid: grid);
      expect(adjacentEightBeatPoint(phase, grid, ms(0), -1), isNull);
      expect(adjacentEightBeatPoint(phase, grid, ms(1000), -1), ms(0));
    });

    test('相邻八拍点：有界真实网格（弱起锚点相位）同源求值', () {
      final grid = pickupGrid(); // 八拍点 1.6s / 5.6s
      final phase = BeatPhase(grid: grid);
      expect(adjacentEightBeatPoint(phase, grid, ms(2000), 1), ms(5600));
      expect(adjacentEightBeatPoint(phase, grid, ms(2000), -1), ms(1600));
      expect(adjacentEightBeatPoint(phase, grid, ms(1600), -1), isNull);
      expect(adjacentEightBeatPoint(phase, grid, ms(5600), 1), isNull);
    });

    test('相邻拍点：沿网格挪一拍', () {
      const grid = placeholderBeatGrid; // 0.5s 一拍
      expect(adjacentBeatPoint(grid, ms(1100), 1), ms(1500));
      expect(adjacentBeatPoint(grid, ms(1100), -1), ms(500));
    });

    test('相邻拍点：越出可及拍序（首拍之前 / 末拍之后）返回空', () {
      const unbounded = placeholderBeatGrid;
      expect(adjacentBeatPoint(unbounded, ms(0), -1), isNull);
      final bounded = pickupGrid(); // 末拍序号 15（7.6s）
      expect(adjacentBeatPoint(bounded, ms(7600), 1), isNull);
      expect(adjacentBeatPoint(bounded, ms(7600), -1), ms(7100));
    });
  });
}
