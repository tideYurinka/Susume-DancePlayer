import 'package:dance_learning_app/annotation/auto_segment.dart';
import 'package:dance_learning_app/core/document_beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/document_grid_of.dart';

/// 自动分段序列派生纯函数（每段 4 个整八拍区间）：切割线顺延、半八拍并入
/// 本段、尾部并入、收在首尾线开区间内。
void main() {
  /// 就绪真实网格：`beats` 个拍点、首拍 [start] 秒、每拍 [step] 秒、每 4
  /// 拍一个 downbeat。
  /// 回归基线组用旧测试的 `start: 0.5`（与旧「每 32 拍」期望值逐位对照）。
  DocumentBeatGrid gridOf({
    required int beats,
    double start = 0,
    double step = 0.5,
  }) => documentGridOf(
    marker_doc.BeatGrid(
      model: 'm',
      fps: 100,
      generatedAt: DateTime.utc(2026, 9, 10),
      beats: [
        for (var i = 0; i < beats; i++)
          marker_doc.BeatPoint(t: start + i * step, down: i % 4 == 0),
      ],
    ),
  );

  /// 以「整曲首拍..末拍」为首/尾线派生切点（既有自动首尾口径）；锚点按
  /// 生产路径由调用方给出（`beatPhaseProvider` 同源）。
  List<Duration> cutsOf(
    DocumentBeatGrid grid, {
    List<int> anchors = const [],
    Duration? startLine,
    Duration? endLine,
    int fullIntervalsPerSegment = 4,
  }) => deriveAutoSegmentCuts(
    phase: BeatPhase(grid: grid, anchors: anchors),
    startLine: startLine ?? grid.beatTime(0),
    endLine: endLine ?? grid.beatTime(grid.lastBeatIndex),
    fullIntervalsPerSegment: fullIntervalsPerSegment,
  );

  group('无锚点：与旧「每 32 拍」口径逐点等价（回归基线；首个八拍点 = 首线）', () {
    test('少于 32 个八拍区间：无切点（整段一段，收在尾线）', () {
      expect(cutsOf(gridOf(beats: 32, start: 0.5)), isEmpty);
      expect(cutsOf(gridOf(beats: 4, start: 0.5)), isEmpty);
      expect(cutsOf(gridOf(beats: 1, start: 0.5)), isEmpty);
    });

    test('33 拍：无切点（第 32 拍即尾拍，落点在开区间外不可下刀）', () {
      expect(cutsOf(gridOf(beats: 33, start: 0.5)), isEmpty);
    });

    test('34 拍：在首线相位第 32 拍下刀，尾部 2 拍并入末段', () {
      expect(cutsOf(gridOf(beats: 34, start: 0.5)), [
        const Duration(milliseconds: 16500),
      ]);
    });

    test('66 拍：两刀，尾部 2 拍并入末段', () {
      expect(cutsOf(gridOf(beats: 66, start: 0.5)), [
        const Duration(milliseconds: 16500),
        const Duration(milliseconds: 32500),
      ]);
    });

    test('恰好 64 拍：一刀，末段恰 32 拍收在尾线', () {
      expect(cutsOf(gridOf(beats: 64, start: 0.5)), [
        const Duration(milliseconds: 16500),
      ]);
    });

    test('首线相位随首拍平移（非零起拍/非整拍步长）', () {
      final grid = documentGridOf(
        marker_doc.BeatGrid(
          model: 'm',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 10),
          beats: [
            for (var i = 0; i < 34; i++)
              marker_doc.BeatPoint(t: 1.23 + i * 0.33, down: i % 4 == 0),
          ],
        ),
      );
      // 第 32 拍 → t = 1.23 + 32 × 0.33 = 11.79s。
      expect(cutsOf(grid), [const Duration(milliseconds: 11790)]);
    });
  });

  group('弱起网格（首拍非强拍）：起算点 = 首个八拍点（与旧口径的分歧域）', () {
    // 裁决记录：与「无锚点时与旧每 32 拍逐点
    // 等价」在弱起网格上互斥——旧切点（第 32/64 拍）**不落在八拍点上**，而
    // 新口径要求切割线必落八拍点，故二者在弱起网格上不可兼得；按「起算点 =
    // 首个八拍点」实现，等价性只在首拍即强拍时成立。
    test('弱起：自首个八拍点起算，切割线整体后移首个强拍偏移', () {
      DocumentBeatGrid gridWith({required int pickup}) => documentGridOf(
        marker_doc.BeatGrid(
          model: 'm',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 10),
          beats: [
            for (var i = 0; i < 70; i++)
              marker_doc.BeatPoint(
                t: i * 0.5,
                down: i >= pickup && (i - pickup) % 4 == 0,
              ),
          ],
        ),
      );
      final aligned = gridWith(pickup: 0);
      final weak = gridWith(pickup: 4); // 首强拍 = 第 4 拍（t=2s）。
      expect(aligned.beatTime(aligned.firstDownbeatIndex), Duration.zero);
      expect(
        weak.beatTime(weak.firstDownbeatIndex),
        const Duration(seconds: 2),
      );
      // 首拍即强拍：与旧口径一致（第 32 拍 = 16s）。
      expect(cutsOf(aligned).first, const Duration(seconds: 16));
      // 弱起：起算点 = 首个八拍点（t=2s）→ 第 4 个整八拍区间落在第 36 拍。
      expect(cutsOf(weak).first, const Duration(seconds: 18));
    });
  });

  group('有锚点：锚点处强制下刀并清空配额；半八拍左端顺延', () {
    test('锚点处必有一条切割线，且配额自锚点清零（锚点优先于配额刀）', () {
      // 锚点第 28 拍（14s）：八拍点 0/8/16/24 → 28 → 36/44…。自锚点重新数
      // 4 个整八拍：28→36→44→52→60 下刀（30s），再 68→76→84→92（46s）。
      // 首段 = 3 整八拍 + 1 半八拍 = 3.5 个八拍（半八拍结束于锚点）。
      final grid = gridOf(beats: 100);
      final cuts = cutsOf(grid, anchors: const [28]);
      expect(cuts, [
        const Duration(seconds: 14), // 锚点刀（拍 28）
        const Duration(seconds: 30), // 拍 60
        const Duration(seconds: 46), // 拍 92
      ]);
      // 段长（八拍数）= 3.5、4、4；其后不足 4 个整八拍并入末段。
      expect((cuts[0] - Duration.zero).inMilliseconds / 4000, 3.5);
      expect((cuts[1] - cuts[0]).inMilliseconds / 4000, 4);
      expect((cuts[2] - cuts[1]).inMilliseconds / 4000, 4);
    });

    test('配额满点落在半八拍区间左端：切割线顺延到该半八拍右端（该段 4.5，无 0.5 碎段）', () {
      // 锚点第 36 拍（18s）：八拍点 0/8/16/24/32 → 36 → 44…。配额恰在第
      // 4 个整八拍区间右端（拍 32）满，而拍 32 是半八拍区间 32→36 的左端
      // ——切割线不顺延就会在锚点前后各下一刀、切出 0.5 八拍碎段；新口径
      // 只在半八拍右端（锚点 36）下一刀，该段 4.5。
      final grid = gridOf(beats: 100);
      final cuts = cutsOf(grid, anchors: const [36]);
      expect(cuts, [
        const Duration(seconds: 18), // 拍 36（顺延后的锚点刀）
        const Duration(seconds: 34), // 拍 68
      ]);
      expect((cuts[0] - Duration.zero).inMilliseconds / 4000, 4.5);
      expect((cuts[1] - cuts[0]).inMilliseconds / 4000, 4);
      // 拍 32（半八拍左端）不是切割线。
      expect(cuts.contains(const Duration(seconds: 16)), isFalse);
    });

    test('锚点先于配额满点：该段按真实长度（含半八拍 0.5 分度）', () {
      // 锚点第 4 拍（2s）：首段只 1 个半八拍区间（0→4），锚点刀照下（短段
      // 接受）；其段长 0.5。
      final grid = gridOf(beats: 100);
      final cuts = cutsOf(grid, anchors: const [4]);
      expect(cuts, [
        const Duration(seconds: 2), // 锚点刀（拍 4，首段 0.5 个八拍）
        const Duration(seconds: 18), // 拍 36：自锚点重新数 4 个整八拍
        const Duration(seconds: 34), // 拍 68
      ]);
      expect((cuts[0] - Duration.zero).inMilliseconds / 4000, 0.5);
      expect((cuts[1] - cuts[0]).inMilliseconds / 4000, 4.0);
    });

    test('锚点密集产生的 1.0／2.0 短段接受（无最短段限制）', () {
      // 锚点第 8、24 拍：段 0→8 = 1.0 个八拍（两个半八拍区间）、段 8→24 =
      // 2.0 个八拍；其后自 24 重新数 4 个整八拍在拍 56 下刀。
      final grid = gridOf(beats: 100);
      final cuts = cutsOf(grid, anchors: const [8, 24]);
      expect(cuts, [
        const Duration(seconds: 4), // 锚点 8
        const Duration(seconds: 12), // 锚点 24
        const Duration(seconds: 28), // 拍 56
        const Duration(seconds: 44), // 拍 88
      ]);
      expect((cuts[0] - Duration.zero).inMilliseconds / 4000, 1.0);
      expect((cuts[1] - cuts[0]).inMilliseconds / 4000, 2.0);
      expect((cuts[2] - cuts[1]).inMilliseconds / 4000, 4.0);
      expect((cuts[3] - cuts[2]).inMilliseconds / 4000, 4.0);
    });

    test('切割线只落首/尾线开区间内（末段不足并入最后一段；锚点刀同守卫）', () {
      // 锚点第 36 拍（18s）、41 拍（尾 = 拍 40 = 20s）：拍 40 是尾拍 → 该刀
      // 不可下；锚点刀 18s 在开区间内照下。
      expect(cutsOf(gridOf(beats: 41), anchors: const [36]), [
        const Duration(seconds: 18),
      ]);
      // 锚点恰在尾拍：锚点刀同样不落（无法产生非零末段）。
      expect(cutsOf(gridOf(beats: 37), anchors: const [36]), isEmpty);
    });
  });

  group('档位参数：每段 N 个整八拍区间由入参给出', () {
    test('每段 8 个整八拍：第 64 拍下刀，尾部 2 拍并入末段', () {
      expect(cutsOf(gridOf(beats: 66), fullIntervalsPerSegment: 8), [
        const Duration(seconds: 32), // 拍 64
      ]);
    });

    test('每段 8 个整八拍：不足 8 个区间无切点', () {
      expect(cutsOf(gridOf(beats: 65), fullIntervalsPerSegment: 8), isEmpty);
    });

    test('锚点刀与档位无关：锚点处必下刀并清空配额，其后重新数 N 个整八拍', () {
      // 锚点第 16 拍（8s）：锚点刀一刀，其后 8 个整八拍在第 80 拍（40s）下刀。
      expect(
        cutsOf(
          gridOf(beats: 98),
          anchors: const [16],
          fullIntervalsPerSegment: 8,
        ),
        [const Duration(seconds: 8), const Duration(seconds: 40)],
      );
    });
  });
}
