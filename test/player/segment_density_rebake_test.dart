import 'package:dance_learning_app/annotation/learning_segments.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationRestoreDocument,
        annotationEditorProvider,
        annotationTimelineProvider,
        segmentDensitiesProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 逐段档随几何变动的重烘焙：改分段几何时
/// 段内档跟着段走（段序重映射 / 时间重叠重烘焙 / 清空），与几何改动同为
/// 一次标注编辑（一步撤销一起回退）；节拍倍频与节拍对齐不清段内档。
void main() {
  const total = Duration(minutes: 1);
  const ten = Duration(seconds: 10);
  const twenty = Duration(seconds: 20);
  const thirty = Duration(seconds: 30);

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(
          FakePlaybackEngine(duration: total),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  editor() => container.read(annotationEditorProvider);
  Map<int, double> densities() => container.read(segmentDensitiesProvider);

  /// 注入就绪网格（节拍倍频/节拍对齐应用的前提，否则倍频命令 EditNoop）。
  void seedReadyGrid() {
    container
        .read(beatTrackStateProvider.notifier)
        .replace(
          BeatTrackState.ready(
            BeatGrid(
              model: 'madmom_downbeat_rnn_full.onnx',
              fps: 100,
              generatedAt: DateTime.utc(2026, 9, 6),
              beats: const [
                BeatPoint(t: 0.5, down: true),
                BeatPoint(t: 1.0, down: false),
                BeatPoint(t: 1.5, down: false),
                BeatPoint(t: 2.0, down: false),
              ],
            ),
          ),
        );
  }

  /// 建出 4 个学习段（三条分段线）并注入逐段档（经恢复装载，非史非存）。
  void givenSegmentsWithDensities(Map<int, double> values) {
    editor().submit(AddSegmentLine(at: ten));
    editor().submit(AddSegmentLine(at: twenty));
    editor().submit(AddSegmentLine(at: thirty));
    editor().restoreDocument(
      AnnotationRestoreDocument(segmentDensities: {...values}),
    );
  }

  test('插线：被切段的前后两新段均继承原档，撤销一步连档一起回退', () {
    givenSegmentsWithDensities(const {1: 0.5, 2: 0.5});

    editor().submit(AddSegmentLine(at: const Duration(seconds: 25)));

    // 原段 1 [10,20) 不受影响；在 2 号分段线处插线把原段 2 [20,30)（×½）
    // 切成新段 2/3，两段均 ×½。
    expect(densities(), const {1: 0.5, 2: 0.5, 3: 0.5});

    editor().undo();

    expect(
      densities(),
      const {1: 0.5, 2: 0.5},
      reason: '几何改动与段内档重烘焙同为一次标注编辑',
    );
  });

  test('删线：相邻两段融合取绝对值最大的档，撤销一步回退', () {
    givenSegmentsWithDensities(const {0: 2.0, 1: 0.5});

    editor().submit(const RemoveSegmentLine(index: 0));

    // 段 0（×2）与段 1（×½）融合为新段 0 → ×2；原段 2 前移为新段 1。
    expect(densities(), const {0: 2.0});

    editor().undo();

    expect(densities(), const {0: 2.0, 1: 0.5});
  });

  test('首尾范围变化：被裁掉的段档丢弃、保留段按段序平移，撤销一步回退', () {
    givenSegmentsWithDensities(const {0: 0.5, 2: 2.0});

    // 首界推进到 15s：原段 0 被裁掉，原段 1/2 平移为新段 0/1 → 段内档
    // 跟着段序走（×½ 被裁丢弃、×2 跟段移动到新段 1）。
    editor().submit(
      SetVideoRange(start: const Duration(seconds: 15), end: null),
    );

    expect(densities(), const {1: 2.0});

    editor().undo();

    expect(densities(), const {0: 0.5, 2: 2.0});
  });

  test('自动分段：按时间重叠继承（绝对值最大、切碎各继承），一步撤销连线和档一起回退', () {
    givenSegmentsWithDensities(const {0: 0.5, 1: 2.0});

    // 新分区 [0,8)/[8,16)/[16,24)：新段 0 ⊂ 旧段 0（×½）→ ×½；新段 1
    // 与旧段 0（×½）、旧段 1（×2）都相交 → 绝对值最大 ×2；新段 2 ⊂ 旧
    // 段 1（×2）→ ×2。
    editor().submit(
      const AutoSegment(
        start: Duration.zero,
        end: Duration(seconds: 24),
        cuts: [
          Duration(seconds: 8),
          Duration(seconds: 16),
        ],
      ),
    );

    expect(densities(), const {0: 0.5, 1: 2.0, 2: 2.0});
    expect(
      container.read(annotationTimelineProvider).segmentLines,
      hasLength(2),
    );

    editor().undo();

    expect(
      densities(),
      const {0: 0.5, 1: 2.0},
      reason: '线与段内档同一步回退',
    );
    expect(
      container.read(annotationTimelineProvider).segmentLines,
      hasLength(3),
    );
  });

  test('清空分段：段内档一并清空，撤销一步恢复', () {
    givenSegmentsWithDensities(const {0: 2.0, 2: 0.5});

    editor().submit(const ClearSegmentLines());

    expect(densities(), isEmpty, reason: '没有段就没有逐段设置');

    editor().undo();

    expect(densities(), const {0: 2.0, 2: 0.5});
  });

  test('节拍倍频应用后段内档一个键都不变（正交：倍频只调拍密度不移线）', () {
    givenSegmentsWithDensities(const {1: 2.0});
    seedReadyGrid();

    editor().submit(const ApplyBeatDensity(density: 2));

    expect(densities(), const {1: 2.0});

    editor().undo();

    expect(densities(), const {1: 2.0});
  });

  test('节拍对齐移线：段内档按段序原样跟段走（几何变动口径，不清不重排）', () {
    givenSegmentsWithDensities(const {1: 2.0, 2: 0.5});
    seedReadyGrid();

    editor().submit(
      const ApplyBeatShift(delta: Duration(seconds: 1), shiftSeconds: 1),
    );

    // 整体平移不改段数与段序，段内档逐键不变。
    expect(densities(), const {1: 2.0, 2: 0.5});

    editor().undo();

    expect(densities(), const {1: 2.0, 2: 0.5});
  });

  test('段数与几何派生对齐：恢复装载按段数过滤越界段序', () {
    editor().submit(AddSegmentLine(at: ten));
    editor().restoreDocument(
      const AnnotationRestoreDocument(segmentDensities: {0: 2.0, 9: 0.5}),
    );

    expect(densities(), const {0: 2.0}, reason: '越界段序丢弃、宁丢不挂错段');
    expect(deriveLearningSegments(container.read(annotationTimelineProvider)), hasLength(2));
  });
}
