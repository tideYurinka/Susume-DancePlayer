import 'package:dance_learning_app/beat_track_state/beat_track_state.dart';
// core 网格 seam 与 markers 文档的 BeatGrid 文档类同名，别名区分。
import 'package:dance_learning_app/core/beat_grid.dart' as grid_seam;
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

BeatGrid _readyGrid() => BeatGrid(
  model: 'madmom_downbeat_rnn_full.onnx',
  fps: 100,
  generatedAt: DateTime.utc(2026, 9, 6),
  beats: const [BeatPoint(t: 0.5, down: true), BeatPoint(t: 1.0, down: false)],
);

void main() {
  group('beat_track_state 三态/移位/预览', () {
    // 移位读写函数以 Ref 为入参（hub 内经 provider 调用）；测试经捕获
    // provider 取当前容器 Ref，直调同一公开缝。
    final refOf = Provider<Ref>((ref) => ref);

    test('默认占位态；整体替换写回三态', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(beatTrackStateProvider).phase,
        BeatTrackPhase.placeholder,
      );
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      expect(
        container.read(beatTrackStateProvider).phase,
        BeatTrackPhase.error,
      );
    });

    test('就绪态公开已应用平移量；写定平移即时生效且值未变 no-op', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(refOf);
      expect(appliedBeatShiftSeconds(ref), 0);
      container
          .read(beatTrackStateProvider.notifier)
          .replace(BeatTrackState.ready(_readyGrid()));
      expect(appliedBeatShiftSeconds(ref), 0);
      writeAppliedBeatShift(ref, 0.25);
      expect(appliedBeatShiftSeconds(ref), 0.25);
      writeAppliedBeatShift(ref, 0.25);
      expect(appliedBeatShiftSeconds(ref), 0.25);
      // 占位/异常无 beat 段，写定 no-op。
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.placeholder());
      writeAppliedBeatShift(ref, 0.5);
      expect(appliedBeatShiftSeconds(ref), 0);
    });

    test('对齐预览偏移默认 null，set 即时生效', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(beatAlignPreviewOffsetProvider), isNull);
      container.read(beatAlignPreviewOffsetProvider.notifier).set(0.125);
      expect(container.read(beatAlignPreviewOffsetProvider), 0.125);
    });
  });

  group('节拍网格映射点四象限真值表（Seam B）', () {
    // 映射点形状不变：按节拍轨三态派生网格，性质由
    // 实现自陈。逐象限断言两个谓词 + 三条基准 + 拒录阈值（名义一拍）。
    // 表行：象限名 + 三态注入 + 对派生网格的断言（直收顶层 expect）。
    (String, BeatTrackState, void Function(grid_seam.BeatGrid grid)) quadrant(
      String name,
      BeatTrackState state,
      void Function(grid_seam.BeatGrid grid) checks,
    ) => (name, state, checks);

    final doc = BeatGrid(
      model: 'madmom_downbeat_rnn_full.onnx',
      fps: 100,
      generatedAt: DateTime.utc(2026, 9, 6),
      beats: const [
        BeatPoint(t: 0.5, down: true),
        BeatPoint(t: 1.0, down: false),
      ],
    );
    final emptyBeats = BeatGrid(
      model: 'madmom_downbeat_rnn_full.onnx',
      fps: 100,
      generatedAt: DateTime.utc(2026, 9, 6),
    );

    final quadrants = [
      quadrant('就绪非空 → 真实网格', BeatTrackState.ready(doc), (
        grid_seam.BeatGrid grid,
      ) {
        expect(grid.nature, grid_seam.BeatGridNature.ready);
        expect(grid.hasRealBeats, isTrue);
        expect(grid.isSecondsFallback, isFalse);
        expect(grid.hasStrongBeats, isTrue);
        expect(grid.nominalBeat, const Duration(milliseconds: 500));
        // 2 个真实拍点（500ms 间距）+ 末段外推：8 拍标称 = 4s。
        expect(grid.eightBeatNominal, const Duration(seconds: 4));
        expect(grid.leadTier(4), const Duration(seconds: 2));
      }),
      quadrant('就绪空拍点 → 占位（网格仍可用于渲染）', BeatTrackState.ready(emptyBeats), (
        grid_seam.BeatGrid grid,
      ) {
        expect(grid.nature, grid_seam.BeatGridNature.placeholder);
        expect(grid.hasRealBeats, isFalse);
        expect(grid.isSecondsFallback, isFalse);
        expect(grid.hasStrongBeats, isTrue);
        // 占位网格照常可渲染可换算（demoBpm 语义）。
        expect(grid.beatTime(1), const Duration(milliseconds: 500));
        expect(grid.beatsInWindow(Duration.zero, const Duration(seconds: 1)), [
          Duration.zero,
          const Duration(milliseconds: 500),
          const Duration(seconds: 1),
        ]);
        expect(grid.nominalBeat, const Duration(milliseconds: 500));
        expect(grid.eightBeatNominal, const Duration(seconds: 4));
        expect(grid.leadTier(4), const Duration(seconds: 2));
      }),
      quadrant('占位 → 占位', const BeatTrackState.placeholder(), (
        grid_seam.BeatGrid grid,
      ) {
        expect(grid.nature, grid_seam.BeatGridNature.placeholder);
        expect(grid.hasRealBeats, isFalse);
        expect(grid.isSecondsFallback, isFalse);
        expect(grid.hasStrongBeats, isTrue);
        expect(grid.nominalBeat, const Duration(milliseconds: 500));
        expect(grid.eightBeatNominal, const Duration(seconds: 4));
        expect(grid.leadTier(8), const Duration(seconds: 4));
      }),
      quadrant('异常 → 哨兵（秒制兜底）', const BeatTrackState.error(), (
        grid_seam.BeatGrid grid,
      ) {
        expect(grid.nature, grid_seam.BeatGridNature.secondsFallback);
        expect(grid.hasRealBeats, isFalse);
        expect(grid.isSecondsFallback, isTrue);
        expect(grid.hasStrongBeats, isTrue);
        // 拒录阈值 = 名义一拍 = 哨兵 500ms（登记不改的取值条款）。
        expect(grid.nominalBeat, const Duration(milliseconds: 500));
        expect(grid.eightBeatNominal, const Duration(seconds: 4));
        expect(grid.leadTier(0), Duration.zero);
        expect(grid.leadTier(2), const Duration(seconds: 2));
        expect(grid.leadTier(4), const Duration(seconds: 4));
        expect(grid.leadTier(8), const Duration(seconds: 8));
      }),
    ];

    for (final (name, state, checks) in quadrants) {
      test('象限：$name', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(beatTrackStateProvider.notifier).replace(state);
        final grid = container.read(beatGridProvider);
        checks(grid);
      });
    }
  });

  group('落盘网格', () {
    test('预览偏移与预览档只改派生读面，不进落盘网格', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(beatTrackStateProvider.notifier)
          .replace(BeatTrackState.ready(_readyGrid()));
      container.read(beatAlignPreviewOffsetProvider.notifier).set(0.25);
      container.read(beatDensityPreviewProvider.notifier).set(2);

      final previewGrid = container.read(beatGridProvider);
      final committedGrid = container.read(committedBeatGridProvider);
      // 预览读面被预览偏移/档位实时改写……
      expect(previewGrid.beatTime(0), const Duration(milliseconds: 750));
      // ……落盘网格仍 = 原拍点 + 已落盘修正，不跟预览走。
      expect(committedGrid.beatTime(0), const Duration(milliseconds: 500));
    });
  });
}
