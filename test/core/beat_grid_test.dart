import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/core/beat_grid.dart';

Duration ms(int v) => Duration(milliseconds: v);

/// 判别形状替身（不变式钉住用）：就绪表态但无拍点（末拍为 null）——
/// 潜伏态「就绪且 beat 段空」，映射点产不出、只在此处钉不变式。
class _ReadyEmptyGrid implements BeatGrid {
  const _ReadyEmptyGrid();

  @override
  BeatGridNature get nature => BeatGridNature.ready;

  @override
  int get beatsPerBar => 4;

  @override
  Duration beatTime(int index) => Duration.zero;

  @override
  int beatIndexAt(Duration time) => -1;

  @override
  bool isDownbeat(int index) => false;

  @override
  int get firstDownbeatIndex => 0;

  @override
  int? get lastBeatIndex => null;

  @override
  Duration beatsDuration(int count, {int from = 0}) => Duration.zero;

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) => const [];
}

/// 测试用 fake 真实网格：显式拍时刻 + downbeat 标记（管线产出形状）。
class FakeRealBeatGrid implements BeatGrid {
  // 性质表态：本 fake 模拟就绪真实网格。
  @override
  BeatGridNature get nature => BeatGridNature.ready;

  FakeRealBeatGrid(this.times, this.downbeats, {this.beatsPerBar = 4});

  final List<Duration> times;
  final Set<int> downbeats;

  @override
  final int beatsPerBar;

  @override
  Duration beatTime(int index) => times[index];

  int get beatCount => times.length;

  @override
  bool isDownbeat(int index) => downbeats.contains(index);

  @override
  int get firstDownbeatIndex =>
      downbeats.isEmpty ? 0 : downbeats.reduce((a, b) => a < b ? a : b);

  @override
  int get lastBeatIndex => times.length - 1;

  @override
  int beatIndexAt(Duration time) {
    var index = -1;
    for (var i = 0; i < times.length; i++) {
      if (times[i] <= time) index = i;
    }
    return index;
  }

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      times[from + count] - times[from];

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) => [
    for (final t in times)
      if (t >= start && t <= end) t,
  ];
}

void main() {
  group('占位均匀网格（demoBpm 语义收在 seam 内部）', () {
    const grid = UniformBeatGrid();

    test('一拍 500ms（120 bpm）；拍序号 → 时刻线性外推', () {
      expect(grid.beatTime(0), Duration.zero);
      expect(grid.beatTime(1), ms(500));
      expect(grid.beatTime(8), const Duration(seconds: 4));
    });

    test('时间 → 拍序号：向下取整到不晚于该时刻的最近拍', () {
      expect(grid.beatIndexAt(Duration.zero), 0);
      expect(grid.beatIndexAt(ms(499)), 0);
      expect(grid.beatIndexAt(ms(500)), 1);
      expect(grid.beatIndexAt(ms(1234)), 2);
    });

    test('downbeat/小节结构：4/4，每小节首拍为强拍', () {
      expect(grid.beatsPerBar, 4);
      expect(grid.isDownbeat(0), isTrue);
      expect(grid.isDownbeat(3), isFalse);
      expect(grid.isDownbeat(4), isTrue);
      expect(grid.isDownbeat(8), isTrue);
    });

    test('任意 N 拍时长：1 拍 500ms、2 拍 1s、8 拍（一个八拍）4s', () {
      expect(grid.beatsDuration(1), ms(500));
      expect(grid.beatsDuration(2), const Duration(seconds: 1));
      expect(grid.beatsDuration(8), const Duration(seconds: 4));
    });

    test('开窗取拍序列：[1s, 2s] 闭窗含 1s/1.5s/2s 三拍', () {
      expect(grid.beatsInWindow(const Duration(seconds: 1), ms(2000)), [
        ms(1000),
        ms(1500),
        ms(2000),
      ]);
    });

    test('非法 bpm 被拒（断言）', () {
      expect(() => UniformBeatGrid(bpm: 0), throwsA(anything));
      expect(() => UniformBeatGrid(bpm: -1), throwsA(anything));
    });
  });

  group('首个强拍序号与末拍原语（网格点锚定）', () {
    test('占位均匀网格：首个强拍 = 0、无界（末拍为 null）', () {
      const grid = UniformBeatGrid();
      expect(grid.firstDownbeatIndex, 0);
      expect(grid.lastBeatIndex, isNull);
    });
  });

  group('网格性质与派生读面（Seam A）', () {
    const placeholder = UniformBeatGrid();
    const fallback = UnavailableBeatGrid();
    // 9 拍、每 500ms 一拍、第 0/4 拍为强拍的真实网格。
    final real = FakeRealBeatGrid(
      [for (var i = 0; i < 9; i++) ms(i * 500)],
      {0, 4},
    );
    final realNoDownbeat = FakeRealBeatGrid(
      [ms(100), ms(600), ms(1100)],
      {},
    );

    test('实现各自表态：占位/秒制兜底/真实', () {
      expect(placeholder.nature, BeatGridNature.placeholder);
      expect(fallback.nature, BeatGridNature.secondsFallback);
      expect(real.nature, BeatGridNature.ready);
    });

    test('不变式：性质为真实 ⟺ 末拍序号非空（含「就绪表态但无拍点」判别形状）', () {
      const readyEmpty = _ReadyEmptyGrid();
      for (final grid in [
        placeholder,
        fallback,
        real,
        realNoDownbeat,
        readyEmpty,
      ]) {
        expect(grid.hasRealBeats, grid.lastBeatIndex != null, reason: '$grid');
      }
      // 判别形状分岔处：就绪表态但末拍为空 → 谓词为假。
      expect(readyEmpty.hasRealBeats, isFalse);
    });

    test('可用性两谓词：就绪非空真、占位/异常假；秒制兜底仅异常真', () {
      expect(real.hasRealBeats, isTrue);
      expect(placeholder.hasRealBeats, isFalse);
      expect(fallback.hasRealBeats, isFalse);
      expect(real.isSecondsFallback, isFalse);
      expect(placeholder.isSecondsFallback, isFalse);
      expect(fallback.isSecondsFallback, isTrue);
    });

    test('有强拍：有界扫全拍（无强拍网格为假）、无界恒真', () {
      expect(real.hasStrongBeats, isTrue);
      expect(realNoDownbeat.hasStrongBeats, isFalse);
      expect(placeholder.hasStrongBeats, isTrue);
      expect(fallback.hasStrongBeats, isTrue);
    });

    test('名下单拍：占位 500ms（120bpm）、异常 = 哨兵拍长、真实按拍距', () {
      expect(placeholder.nominalBeat, ms(500));
      expect(fallback.nominalBeat, sentinelBeat);
      expect(real.nominalBeat, ms(500));
    });

    test('八拍标称：占位与异常都得 4 秒（哨兵算术，非特例）', () {
      expect(placeholder.eightBeatNominal, secondsFallbackEightBeat);
      expect(fallback.eightBeatNominal, secondsFallbackEightBeat);
      expect(secondsFallbackEightBeat, sentinelBeat * 8);
      expect(real.eightBeatNominal, ms(4000));
    });

    test('前导档位：异常态档位即秒（0 也得零）、否则档位 × 名义拍长', () {
      expect(fallback.leadTier(0), Duration.zero);
      expect(fallback.leadTier(2), const Duration(seconds: 2));
      expect(fallback.leadTier(4), const Duration(seconds: 4));
      expect(fallback.leadTier(8), const Duration(seconds: 8));
      expect(placeholder.leadTier(0), Duration.zero);
      expect(placeholder.leadTier(8), ms(4000));
      expect(real.leadTier(2), ms(1000));
    });
  });

  group('拍边界单一求值', () {
    const placeholder = UniformBeatGrid();
    const fallback = UnavailableBeatGrid();
    // 9 拍、每 500ms 一拍的真实网格（末拍 8）。
    final real = FakeRealBeatGrid(
      [for (var i = 0; i < 9; i++) ms(i * 500)],
      {0, 4},
    );

    test('占位网格：定位即拍序号，下一拍恒存在（无界）', () {
      final b = placeholder.beatBoundaryAt(ms(1100));
      expect(b.index, 2);
      expect(b.beforeFirst, isFalse);
      expect(b.beatStart, ms(1000));
      expect(b.nextBeat, ms(1500));
      expect(b.beatEnd, ms(1500));
    });

    test('真实网格：早于首拍钳到首拍（beforeFirst 置位），末拍无下一拍', () {
      final early = real.beatBoundaryAt(const Duration(milliseconds: -50));
      expect(early.index, 0);
      expect(early.beforeFirst, isTrue);
      expect(early.beatStart, Duration.zero);
      expect(early.nextBeat, ms(500));

      final last = real.beatBoundaryAt(ms(4200));
      expect(last.index, 8);
      expect(last.beforeFirst, isFalse);
      expect(last.beatStart, ms(4000));
      expect(last.nextBeat, isNull);
      expect(last.beatEnd, ms(4000));
    });

    test('秒制兜底网格：时间轴 0 对齐，无界无末拍钳制', () {
      final b = fallback.beatBoundaryAt(ms(600));
      expect(b.index, 1);
      expect(b.beforeFirst, isFalse);
      expect(b.nextBeat, sentinelBeat * 2);
    });
  });
}
