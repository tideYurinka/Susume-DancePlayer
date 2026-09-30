import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/core/beat_grid.dart';

Duration ms(int v) => Duration(milliseconds: v);

/// 测试用真实网格：显式拍时刻 + downbeat 标记（有界；弱起由 downbeat 布局表达）。
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
  int get lastBeatIndex => times.length - 1;
}

/// 弱起真实网格：首拍 0.1s 非强拍，首个强拍在序号 3（1.6s）；此后每 4 拍一强拍。
/// 拍点 0.1s/0.6s/…/4.1s（共 9 拍，末拍 4.1s）。
FakeRealTestGrid pickupGrid() => FakeRealTestGrid(
      [for (var i = 0; i < 9; i++) ms(100 + i * 500)],
      {3, 7},
    );

/// 非弱起真实网格：首拍 0s 即强拍，每 4 拍一强拍（0s/2s/4s）。
FakeRealTestGrid groundedGrid() => FakeRealTestGrid(
      [for (var i = 0; i < 9; i++) ms(i * 500)],
      {0, 4, 8},
    );

void main() {
  group('首尾线强制对齐 snapRangeBoundary（无条件吸最近真实拍点）', () {
    test('网格覆盖区内：吸最近真实拍点（逐拍，含弱起拍）', () {
      final grid = groundedGrid(); // 拍点 0/0.5/…/4s。
      expect(snapRangeBoundary(ms(1900), grid: grid), ms(2000));
      expect(snapRangeBoundary(ms(2100), grid: grid), ms(2000));
      expect(snapRangeBoundary(ms(100), grid: grid), ms(0));
      // 等距并列取时间靠后拍点。
      expect(snapRangeBoundary(ms(250), grid: grid), ms(500));
    });

    test('弱起真实网格：弱起拍同属真实拍点，覆盖内就近吸附', () {
      final grid = pickupGrid(); // 拍点 0.1s..4.1s。
      expect(snapRangeBoundary(ms(300), grid: grid), ms(100));
      expect(snapRangeBoundary(ms(2000), grid: grid), ms(2100));
      expect(snapRangeBoundary(ms(1950), grid: grid), ms(2100));
      expect(snapRangeBoundary(ms(1850), grid: grid), ms(2100)); // 并列取靠后。
    });

    test('网格覆盖区外：自由落点（解除不可超过节拍生成区域的吸附回拉）', () {
      final grid = groundedGrid(); // 覆盖区 = 0..4s（首拍..末拍）。
      expect(snapRangeBoundary(ms(4100), grid: grid), ms(4100));
      expect(snapRangeBoundary(ms(5000), grid: grid), ms(5000));
    });

    test('无网格（占位均匀实现无界）：自由落点、吸附不生效', () {
      expect(snapRangeBoundary(ms(2100), grid: placeholderBeatGrid), ms(2100));
      expect(snapRangeBoundary(ms(9999), grid: placeholderBeatGrid), ms(9999));
    });

    test('异常态秒制兜底网格（无界）：自由落点', () {
      const grid = UnavailableBeatGrid();
      expect(snapRangeBoundary(ms(2100), grid: grid), ms(2100));
    });
  });

  group('首尾线步进相邻真实拍点（严格越过当前位置）', () {
    test('弱起真实网格：相邻真实拍点逐拍步进；弱起区间向后无拍点返回 null', () {
      final grid = pickupGrid();
      expect(nextBeatPoint(ms(400), grid: grid), ms(600));
      expect(previousBeatPoint(ms(400), grid: grid), ms(100));
      expect(nextBeatPoint(ms(2000), grid: grid), ms(2100));
      expect(previousBeatPoint(ms(2000), grid: grid), ms(1600));
      // 弱起之前：向前落首拍、向后无拍点。
      expect(nextBeatPoint(ms(50), grid: grid), ms(100));
      expect(previousBeatPoint(ms(50), grid: grid), isNull);
    });

    test('非弱起真实网格：恰在拍点上取真邻', () {
      final grid = groundedGrid();
      expect(nextBeatPoint(ms(500), grid: grid), ms(1000));
      expect(previousBeatPoint(ms(500), grid: grid), Duration.zero);
    });

    test('有界真实网格越过末拍/首拍方向返回 null；覆盖区外自由（null）', () {
      final grid = pickupGrid();
      expect(nextBeatPoint(ms(4100), grid: grid), isNull);
      expect(nextBeatPoint(ms(4200), grid: grid), isNull);
      expect(previousBeatPoint(ms(4200), grid: grid), ms(4100));
      expect(nextBeatPoint(Duration.zero, grid: grid), ms(100));
      expect(previousBeatPoint(Duration.zero, grid: grid), isNull);
    });

    test('占位/异常态无界网格：无真实拍点网格语义，步进返回 null', () {
      expect(nextBeatPoint(ms(2100), grid: placeholderBeatGrid), isNull);
      expect(previousBeatPoint(ms(2100), grid: placeholderBeatGrid), isNull);
      const grid = UnavailableBeatGrid();
      expect(nextBeatPoint(ms(2100), grid: grid), isNull);
      expect(previousBeatPoint(ms(2100), grid: grid), isNull);
    });
  });
}
