import 'package:dance_learning_app/core/document_beat_grid.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/document_grid_of.dart';

/// 均匀原始网格：1.0s 起每 1s 一拍共 5 拍，强拍在第 1、5 拍（4/4）。
BeatGrid rawGrid({double density = 1}) => BeatGrid(
  model: 'm.onnx',
  fps: 100,
  generatedAt: DateTime.utc(2026, 9, 17),
  density: density,
  beats: [
    BeatPoint(t: 1.0, down: true),
    BeatPoint(t: 2.0, down: false),
    BeatPoint(t: 3.0, down: false),
    BeatPoint(t: 4.0, down: false),
    BeatPoint(t: 5.0, down: true),
  ],
);

List<int> times(List<(int, bool)> points) => [for (final p in points) p.$1];
List<bool> downs(List<(int, bool)> points) => [for (final p in points) p.$2];

/// 整曲档派生（无逐段档）。
List<(int, bool)> basePoints({double density = 1}) => deriveBeatPoints(
  beats: rawGrid(density: density).beats,
  shiftMs: 0,
  density: density,
);

void main() {
  group('逐段派生：整曲原样 + 单段 ×2', () {
    // 段序 0 = [2000, 4000)。
    final points = deriveBeatPoints(
      beats: rawGrid().beats,
      shiftMs: 0,
      density: 1,
      segmentDensities: const {0: 2},
      segments: const [(startMs: 2000, endMs: 4000)],
    );

    test('段内拍数翻倍、拍长减半：[2000,4000) 得 4 拍、拍距 500ms', () {
      final inside = times(points).where((t) => t >= 2000 && t < 4000);
      expect(inside, [2000, 2500, 3000, 3500]);
    });

    test('段首是段内第一个拍且为该段第一个强拍', () {
      expect(points.firstWhere((p) => p.$1 >= 2000).$1, 2000);
      expect(points.firstWhere((p) => p.$1 >= 2000).$2, isTrue);
    });

    test('段外回到整曲档：派生拍序列与整曲原样逐位一致', () {
      final outside = [
        for (final p in points)
          if (p.$1 < 2000 || p.$1 >= 4000) p,
      ];
      expect(times(outside), [1000, 4000, 5000]);
      expect(downs(outside), [true, false, true]);
    });

    test('整条派生序列按时刻升序', () {
      final sorted = times(points).toList()..sort();
      expect(times(points), sorted);
    });
  });

  group('逐段派生：生效倍数 = 整曲档 × 段内档', () {
    test('整曲 ×2 加段内 ×2：段内为 ×4（拍距 250ms）', () {
      final points = deriveBeatPoints(
        beats: rawGrid(density: 2).beats,
        shiftMs: 0,
        density: 2,
        segmentDensities: const {0: 2},
        segments: const [(startMs: 2000, endMs: 3000)],
      );
      final inside = times(points).where((t) => t >= 2000 && t < 3000);
      expect(inside, [2000, 2250, 2500, 2750]);
    });

    test('整曲 ×½ 加段内 ×2：段内为 ×1（拍距与原网格一致）', () {
      final points = deriveBeatPoints(
        beats: rawGrid(density: 0.5).beats,
        shiftMs: 0,
        density: 0.5,
        segmentDensities: const {0: 2},
        segments: const [(startMs: 2000, endMs: 4000)],
      );
      final inside = times(points).where((t) => t >= 2000 && t < 4000);
      expect(inside, [2000, 3000]);
      // 段外回到整曲 ×½ 档。
      expect(times(points).where((t) => t < 2000), [1000]);
      expect(times(points).where((t) => t >= 4000), [5000]);
    });

    test('整曲 ×4 加段内 ×2 = 生效 ×8：超五档范围不做钳制（每原拍 8 等分）', () {
      final points = deriveBeatPoints(
        beats: rawGrid(density: 4).beats,
        shiftMs: 0,
        density: 4,
        segmentDensities: const {0: 2},
        segments: const [(startMs: 2000, endMs: 3000)],
      );
      final inside = times(points).where((t) => t >= 2000 && t < 3000).toList();
      expect(inside.length, 8);
      expect(inside.first, 2000);
      expect(inside[1] - inside[0], 125);
      expect(inside.last, 2875);
    });
  });

  group('逐段派生：慢方向（×½）与段尾', () {
    test('慢方向按段首定相等距抽样：自段首所在原拍起隔一原拍取一', () {
      final points = deriveBeatPoints(
        beats: rawGrid().beats,
        shiftMs: 0,
        density: 1,
        segmentDensities: const {0: 0.5},
        segments: const [(startMs: 2000, endMs: 5000)],
      );
      final inside = times(points).where((t) => t >= 2000 && t < 5000);
      // 相位取段首（原拍 2000，下标 1）：抽样 2000、4000（6000 越段尾）。
      expect(inside, [2000, 4000]);
    });

    test('段尾不是整拍时收在段尾之前最后一拍', () {
      final points = deriveBeatPoints(
        beats: rawGrid().beats,
        shiftMs: 0,
        density: 1,
        segmentDensities: const {0: 2},
        segments: const [(startMs: 2000, endMs: 3200)],
      );
      final inside = times(points).where((t) => t >= 2000 && t < 3200).toList();
      expect(inside, [2000, 2500, 3000]);
      expect(inside.last, lessThan(3200));
    });

    test('段首不在拍点上时补段首拍，段首即第一个强拍', () {
      final points = deriveBeatPoints(
        beats: rawGrid().beats,
        shiftMs: 0,
        density: 1,
        segmentDensities: const {0: 2},
        segments: const [(startMs: 2200, endMs: 4000)],
      );
      final inside = times(points).where((t) => t >= 2200 && t < 4000);
      expect(inside, [2200, 2500, 3000, 3500]);
      expect(points.firstWhere((p) => p.$1 >= 2200).$2, isTrue);
    });
  });

  group('逐段派生：相位与互不串', () {
    test('段内强拍自段首每 4 拍一个：整曲强拍位不伸入段内', () {
      final points = deriveBeatPoints(
        beats: rawGrid().beats,
        shiftMs: 0,
        density: 1,
        segmentDensities: const {0: 2},
        segments: const [(startMs: 2000, endMs: 8000)],
      );
      bool downAt(int t) =>
          points.firstWhere((p) => p.$1 == t, orElse: () => (t, false)).$2;
      // 段内局部下标 0/4 = 2000/4000 为强拍；整曲强拍位 5000
      //（局部下标 6）不是段内强拍——段内相位一律自段首起。
      expect(downAt(2000), isTrue);
      expect(downAt(4000), isTrue);
      expect(downAt(5000), isFalse);
    });

    test('相邻两段各设一档互不串；各自结果与单独设置一致', () {
      List<(int, bool)> derive(Map<int, double> densities) => deriveBeatPoints(
        beats: rawGrid().beats,
        shiftMs: 0,
        density: 1,
        segmentDensities: densities,
        segments: const [
          (startMs: 2000, endMs: 3000),
          (startMs: 3000, endMs: 4000),
        ],
      );
      final both = derive(const {0: 2, 1: 0.5});
      final onlyFast = derive(const {0: 2});
      final onlySlow = derive(const {1: 0.5});
      List<int> inWindow(List<(int, bool)> points, int start, int end) => [
        for (final p in points)
          if (p.$1 >= start && p.$1 < end) p.$1,
      ];
      // 快段 [2000,3000)：同时设置与单独设置逐位一致。
      expect(inWindow(both, 2000, 3000), inWindow(onlyFast, 2000, 3000));
      expect(inWindow(both, 2000, 3000), [2000, 2500]);
      // 慢段 [3000,4000)：同时设置与单独设置逐位一致。
      expect(inWindow(both, 3000, 4000), inWindow(onlySlow, 3000, 4000));
      expect(inWindow(both, 3000, 4000), [3000]);
    });

    test('多段同档与单段同档派生一致（快段结果不因另一段同档改变）', () {
      List<(int, bool)> derive(Map<int, double> densities) => deriveBeatPoints(
        beats: rawGrid().beats,
        shiftMs: 0,
        density: 1,
        segmentDensities: densities,
        segments: const [
          (startMs: 2000, endMs: 3000),
          (startMs: 4000, endMs: 5000),
        ],
      );
      final one = derive(const {0: 2});
      final both = derive(const {0: 2, 1: 2});
      final onlySeg1 = derive(const {1: 2});
      List<int> inWindow(List<(int, bool)> points, int start, int end) => [
        for (final p in points)
          if (p.$1 >= start && p.$1 < end) p.$1,
      ];
      expect(inWindow(both, 2000, 3000), inWindow(one, 2000, 3000));
      expect(inWindow(both, 4000, 5000), inWindow(onlySeg1, 4000, 5000));
    });

    test('无逐段档的段不受影响：空档集合 = 整曲档派生恒等', () {
      expect(
        deriveBeatPoints(
          beats: rawGrid().beats,
          shiftMs: 0,
          density: 1,
          segmentDensities: const {},
          segments: const [(startMs: 2000, endMs: 4000)],
        ),
        basePoints(),
      );
      // 档集合里的段序没有对应几何（越界）时同样不产生任何拍。
      expect(
        deriveBeatPoints(
          beats: rawGrid().beats,
          shiftMs: 0,
          density: 1,
          segmentDensities: const {3: 2},
          segments: const [(startMs: 2000, endMs: 4000)],
        ),
        basePoints(),
      );
    });
  });

  group('DocumentBeatGrid 装配逐段档', () {
    test('构造时传入逐段档与分段几何，读面原语读派生后的拍序列', () {
      final grid = documentGridOf(
        rawGrid(),
        segmentDensities: const {0: 2},
        segments: const [(startMs: 2000, endMs: 4000)],
      );
      expect(grid.segmentDensities, {0: 2});
      // 段内 [2000,4000) 为 ×2：2000 强拍起每 500ms 一拍。
      expect(grid.beatTime(1), const Duration(milliseconds: 2000));
      expect(grid.beatTime(2), const Duration(milliseconds: 2500));
      expect(grid.beatTime(3), const Duration(milliseconds: 3000));
      expect(grid.isDownbeat(1), isTrue);
      expect(grid.isDownbeat(2), isFalse);
      // 段外恢复整曲档拍序：段尾外回到原网格 1s 间距。
      expect(grid.beatTime(5), const Duration(milliseconds: 4000));
      expect(grid.beatTime(6), const Duration(milliseconds: 5000));
      expect(grid.lastBeatIndex, 6);
    });

    test('缺省构造与整曲派生逐位一致（既有消费方零变化）', () {
      final grid = documentGridOf(rawGrid());
      expect(grid.segmentDensities, isEmpty);
      final beats = grid.beatsInWindow(
        Duration.zero,
        const Duration(seconds: 6),
      );
      expect(beats.map((d) => d.inMilliseconds).toList(), [
        1000,
        2000,
        3000,
        4000,
        5000,
      ]);
    });
  });
}
