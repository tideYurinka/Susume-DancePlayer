import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/core/beat_grid.dart';

Duration ms(int v) => Duration(milliseconds: v);

/// 测试用真实网格：显式拍时刻 + downbeat 标记（有界；弱起由 downbeat 布局
/// 表达）。与 `snap_test.dart` 同构的最小 fake。
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

/// 弱起真实网格：首拍 0.1s 非强拍，首个强拍序号 3（1.6s）；拍点
/// 0.1s/0.6s/…/4.1s（共 9 拍）。
FakeRealTestGrid pickupGrid() => FakeRealTestGrid(
      [for (var i = 0; i < 9; i++) ms(100 + i * 500)],
      {3, 7},
    );

void main() {
  group('半拍吸附位置解析（占位网格，120bpm：一拍 500ms）', () {
    test('落点就近吸附到最近的半拍格点（相邻拍点中点）', () {
      // 0.3s 距 0.25s 中点 50ms、距 0.75s 中点 450ms → 吸附 0.25s。
      expect(resolveHalfBeatSnap(ms(300), grid: placeholderBeatGrid), ms(250));
    });

    test('落点更近拍点时仍吸附到相邻中点（吸附候选不含拍点本身）', () {
      // 0.47s 距拍点 0.5s 30ms，但拍点不是候选；最近中点 = 0.25s（220ms）
      // 与 0.75s（280ms）取前者。
      expect(resolveHalfBeatSnap(ms(470), grid: placeholderBeatGrid), ms(250));
    });

    test('恰在拍点上时落到前一中点与后一中点等距取靠后', () {
      // 0.5s 拍点：前中点 0.25s、后中点 0.75s 等距 → 靠后 0.75s。
      expect(resolveHalfBeatSnap(ms(500), grid: placeholderBeatGrid), ms(750));
    });

    test('更近一侧中点就近取（拍点不是候选不参与并列）', () {
      expect(resolveHalfBeatSnap(ms(375), grid: placeholderBeatGrid), ms(250));
    });

    test('已落在半拍格点上则原样返回', () {
      expect(resolveHalfBeatSnap(ms(1250), grid: placeholderBeatGrid), ms(1250));
    });
  });

  group('半拍吸附位置解析（真实有界网格）', () {
    test('弱起区间内贴到首强拍后的第一个中点（不外推弱起半拍）', () {
      // 首个强拍 = 序号 3（1.6s）；首个候选中点 = 1.6s–2.1s 之间 1.85s。
      final grid = pickupGrid();
      expect(resolveHalfBeatSnap(ms(1000), grid: grid), ms(1850));
    });

    test('强拍之间的落点吸附到最近中点', () {
      final grid = pickupGrid();
      // 强拍 1.6s 与次拍 2.1s 之间：1.9s 距中点 1.85s 50ms。
      expect(resolveHalfBeatSnap(ms(1900), grid: grid), ms(1850));
    });

    test('末拍之前贴到最后一个中点（中点只存在于相邻拍点之间）', () {
      final grid = pickupGrid();
      // 4.0s 落在末拍 4.1s 前：最后中点 = 3.6s–4.1s 的 3.85s。
      expect(resolveHalfBeatSnap(ms(4000), grid: grid), ms(3850));
    });
  });

  group('帧步进相邻半拍格点（仅相邻拍点中点）', () {
    test('下一帧跳步：严格越过当前位置的下一个中点', () {
      expect(nextHalfBeatPoint(ms(250), grid: placeholderBeatGrid), ms(750));
      expect(nextHalfBeatPoint(ms(251), grid: placeholderBeatGrid), ms(750));
      // 拍点上步进 = 后一中点。
      expect(nextHalfBeatPoint(ms(500), grid: placeholderBeatGrid), ms(750));
    });

    test('上一帧跳步：严格越过当前位置的前一个中点', () {
      expect(previousHalfBeatPoint(ms(750), grid: placeholderBeatGrid), ms(250));
      expect(previousHalfBeatPoint(ms(749), grid: placeholderBeatGrid), ms(250));
      expect(previousHalfBeatPoint(ms(500), grid: placeholderBeatGrid), ms(250));
    });

    test('有界网格边界外无相邻中点返回 null', () {
      final grid = pickupGrid();
      // 最后中点 = 3.85s；其后无候选。
      expect(nextHalfBeatPoint(ms(3850), grid: grid), isNull);
      // 首强拍 1.6s 之前无候选（弱起区间不派生半拍）。
      expect(previousHalfBeatPoint(ms(1850), grid: grid), isNull);
    });

    test('真实网格的相邻中点跳步', () {
      final grid = pickupGrid();
      expect(nextHalfBeatPoint(ms(1850), grid: grid), ms(2350));
      expect(previousHalfBeatPoint(ms(2100), grid: grid), ms(1850));
      expect(nextHalfBeatPoint(ms(2100), grid: grid), ms(2350));
    });
  });
}
