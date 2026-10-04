import 'package:dance_learning_app/core/beat_grid.dart' as grid_seam;
import 'package:dance_learning_app/core/document_beat_grid.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/document_grid_of.dart';

/// 倍频派生网格（Seam A）：派生拍点与强拍结构按
/// 五档倍频求值——规则只在网格值面钉一次。
///
/// 基准网格：8 个原拍、每 0.5s 一拍（500ms 起），原首强拍在下标 0
/// （非弱起基准）；弱起基准另有一组（原首强拍在下标 2）。
List<BeatPoint> baseBeats({int firstDown = 0}) => [
  for (var i = 0; i < 8; i++)
    BeatPoint(t: 0.5 + i * 0.5, down: i == firstDown || i == firstDown + 4),
];

DocumentBeatGrid gridOf(
  List<BeatPoint> beats, {
  double shift = 0,
  double density = 1,
}) => documentGridOf(
  BeatGrid(
    model: 'm.onnx',
    fps: 100,
    generatedAt: DateTime.utc(2026, 9, 17),
    shift: shift,
    density: density,
    beats: beats,
  ),
);

List<int> timesOf(DocumentBeatGrid grid) => [
  for (var i = 0; i <= grid.lastBeatIndex; i++) grid.beatTime(i).inMilliseconds,
];

List<int> downIndicesOf(DocumentBeatGrid grid) => [
  for (var i = 0; i <= grid.lastBeatIndex; i++)
    if (grid.isDownbeat(i)) i,
];

void main() {
  group('倍频派生拍点（快方向：相邻原拍间插等分中点）', () {
    test('×2：拍数约翻倍（首末原拍固定 → (N−1)×2+1），插入的 750ms 恰为中点', () {
      final grid = gridOf(baseBeats(), density: 2);
      expect(grid.lastBeatIndex, 14);
      expect(timesOf(grid), [
        500, 750, 1000, 1250, 1500, 1750, 2000, 2250, //
        2500, 2750, 3000, 3250, 3500, 3750, 4000,
      ]);
    });

    test('×4：拍数取四倍，四等分插入', () {
      final grid = gridOf(baseBeats(), density: 4);
      expect(grid.lastBeatIndex, 28);
      expect(grid.beatTime(1).inMilliseconds, 625);
      expect(grid.beatTime(3).inMilliseconds, 875);
      // 原拍点全部保留。
      expect(grid.beatTime(4).inMilliseconds, 1000);
    });
  });

  group('倍频派生拍点（慢方向：按原首个强拍定相位等距抽样）', () {
    test('×½：隔一原拍取一，拍数约减半', () {
      final grid = gridOf(baseBeats(), density: 0.5);
      expect(grid.lastBeatIndex, 3);
      expect(timesOf(grid), [500, 1500, 2500, 3500]);
    });

    test('×¼：每四个原拍取一，拍数取四分之一', () {
      final grid = gridOf(baseBeats(), density: 0.25);
      expect(grid.lastBeatIndex, 1);
      expect(timesOf(grid), [500, 2500]);
    });
  });

  group('新强拍 = 自原首个强拍的派生序号起每 4 个派生拍一个', () {
    test('×2：强拍每 4 个派生拍一次（新小节 = 4 个派生拍）', () {
      final grid = gridOf(baseBeats(), density: 2);
      expect(downIndicesOf(grid), [0, 4, 8, 12]);
    });

    test('×½：强拍每 4 个派生拍一次', () {
      final grid = gridOf(baseBeats(), density: 0.5);
      expect(downIndicesOf(grid), [0]);
    });

    test('弱起：原首强拍在下标 2，×2 后首强拍时刻不动、派生序号 = 4', () {
      final grid = gridOf(baseBeats(firstDown: 2), density: 2);
      expect(grid.firstDownbeatIndex, 4);
      expect(grid.beatTime(4), const Duration(milliseconds: 1500));
      expect(downIndicesOf(grid), [4, 8, 12]);
    });

    test('弱起：×½ 抽样自原首强拍起，首强拍时刻不动', () {
      final grid = gridOf(baseBeats(firstDown: 2), density: 0.5);
      expect(timesOf(grid), [1500, 2500, 3500]);
      expect(grid.firstDownbeatIndex, 0);
      expect(grid.beatTime(0), const Duration(milliseconds: 1500));
    });

    test('弱起：×¼ 自原首强拍起每四原拍取一，末拍序号随档位', () {
      final grid = gridOf(baseBeats(firstDown: 2), density: 0.25);
      expect(grid.lastBeatIndex, 1);
      expect(timesOf(grid), [1500, 3500]);
      expect(grid.firstDownbeatIndex, 0);
      expect(downIndicesOf(grid), [0]);
    });

    test('回归反例：照搬原强拍标记会让小节仍长一倍——派生强拍每 4 拍、'
        '时长是原小节的一半', () {
      final grid = gridOf(baseBeats(), density: 2);
      // 派生小节 = 4 个派生拍 = 2 个原拍时长（原小节的一半）。
      expect(grid.beatsDuration(4), const Duration(milliseconds: 1000));
      // 照搬原 down 位（原强拍每 4 个原拍 = 每 8 个派生拍）会让派生小节
      // 仍是 8 个派生拍 = 原小节长度——本网格必须不是那个口径。
      expect(grid.beatsDuration(8), const Duration(milliseconds: 2000));
      expect(downIndicesOf(grid).length, 4);
    });
  });

  group('档位关系（拍数、拍长、八拍标称、开窗）', () {
    test('×2 拍数约翻倍、×¼ 拍数取四分之一（首末原拍固定口径）', () {
      expect(gridOf(baseBeats(), density: 1).lastBeatIndex, 7);
      expect(gridOf(baseBeats(), density: 2).lastBeatIndex, 14);
      expect(gridOf(baseBeats(), density: 0.25).lastBeatIndex, 1);
    });

    test('×2 后八拍标称只覆盖原来一半时长', () {
      final normal = gridOf(baseBeats(), density: 1);
      final doubled = gridOf(baseBeats(), density: 2);
      expect(doubled.eightBeatNominal, normal.eightBeatNominal * 0.5);
      expect(doubled.eightBeatNominal, const Duration(milliseconds: 2000));
    });

    test('开窗取拍随档位', () {
      final grid = gridOf(baseBeats(), density: 2);
      expect(
        grid.beatsInWindow(
          const Duration(milliseconds: 900),
          const Duration(milliseconds: 1600),
        ),
        [
          const Duration(milliseconds: 1000),
          const Duration(milliseconds: 1250),
          const Duration(milliseconds: 1500),
        ],
      );
      final slow = gridOf(baseBeats(), density: 0.5);
      expect(slow.beatsInWindow(Duration.zero, const Duration(seconds: 3)), [
        const Duration(milliseconds: 500),
        const Duration(milliseconds: 1500),
        const Duration(milliseconds: 2500),
      ]);
    });

    test('定位换算按派生拍序列', () {
      final grid = gridOf(baseBeats(), density: 2);
      expect(grid.beatIndexAt(const Duration(milliseconds: 800)), 1);
      expect(grid.beatIndexAt(const Duration(milliseconds: 499)), -1);
    });
  });

  group('派生是「原始拍点 + 平移量 + 倍频」的纯函数', () {
    test('可不经文档字段按任意档位求值（统计投影重建记录时桶格的入口）', () {
      final points = deriveBeatPoints(
        beats: baseBeats(),
        shiftMs: 100,
        density: 2,
      );
      expect(points.first.$1, 600);
      expect(points.length, 15);
      expect(points[1].$1, 850);
      expect(
        [
          for (var i = 0; i < points.length; i++)
            if (points[i].$2) i,
        ],
        [0, 4, 8, 12],
      );
    });

    test('平移量与倍频可交换：先平移后重采样 = 先重采样后平移', () {
      final a = deriveBeatPoints(beats: baseBeats(), shiftMs: 100, density: 2);
      final shiftedFirst = [
        for (final b in baseBeats()) BeatPoint(t: b.t + 0.1, down: b.down),
      ];
      final b = deriveBeatPoints(beats: shiftedFirst, shiftMs: 0, density: 2);
      expect(a, b);
    });

    test('缺省倍频 = 原样：派生拍点与原拍点（加平移）逐位一致', () {
      final points = deriveBeatPoints(
        beats: baseBeats(),
        shiftMs: 0,
        density: 1,
      );
      expect(points.length, 8);
      expect(points[0].$1, 500);
      expect(points[0].$2, isTrue);
      expect(points[1].$2, isFalse);
    });
  });
}
