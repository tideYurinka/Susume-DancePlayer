import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/annotation/auto_segment.dart'
    show durationFromSeconds;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show
        BeatTrackState,
        beatAlignPreviewOffsetProvider,
        beatGridProvider,
        beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationEditor,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkStateProvider,
        annotationTimelineProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 记录 diff 的假保存编排（编辑器 → sink 链路断言用）。
class RecordingSink implements AnnotationSaveSink {
  final diffs = <AnnotationSectionDiff>[];

  @override
  void save(AnnotationSectionDiff diff) => diffs.add(diff);

  @override
  Future<void> flush() async {}
}

/// 节拍对齐应用 seam 测试：ProviderContainer 直测模块 interface
/// （submitBeatShift 命令 / 预览派生 / 一步撤销 / 平移后自动分段），仿
/// annotation_editor_test 模板。
void main() {
  const total = Duration(minutes: 1);

  late ProviderContainer container;
  late FakePlaybackEngine engine;

  /// 就绪网格文档：拍点 0.5/1.0/1.5/2.0s，第 1 拍 downbeat，平移量 0。
  void seedReadyGrid({double shift = 0}) {
    final track = BeatTrackState.ready(
      BeatGrid(
        model: 'madmom_downbeat_rnn_full.onnx',
        fps: 100,
        generatedAt: DateTime.utc(2026, 9, 6),
        shift: shift,
        beats: const [
          BeatPoint(t: 0.5, down: true),
          BeatPoint(t: 1.0, down: false),
          BeatPoint(t: 1.5, down: false),
          BeatPoint(t: 2.0, down: false),
        ],
      ),
    );
    container.read(beatTrackStateProvider.notifier).replace(track);
  }

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    container = ProviderContainer(
      overrides: [playbackEngineProvider.overrideWithValue(engine)],
    );
  });

  tearDown(() => container.dispose());

  AnnotationEditor editor() => container.read(annotationEditorProvider);
  AnnotationTimeline timeline() => container.read(annotationTimelineProvider);

  /// 经模块命令播种分段线与半拍线（半拍线播种请求 5s 在占位
  /// 均匀网格上吸附到半拍格点 5.25s，非直通；分段线播种仍直通）。
  void seedLines() {
    editor().submit(const AddSegmentLine(at: Duration(seconds: 10)));
    editor().submit(const AddSegmentLine(at: Duration(seconds: 20)));
    editor().submit(const AddHalfBeatLine(at: Duration(seconds: 5)));
  }

  group('submitBeatShift（应用命令）', () {
    test('非就绪网格抛 StateError（占位/异常不适用）', () {
      // 默认占位态。
      expect(() => editor().submitBeatShift(0.5), throwsStateError);
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      expect(() => editor().submitBeatShift(0.5), throwsStateError);
    });

    test('应用：线整体平移差值 + beat 段平移量写定为预览值，一步入史', () {
      // 先播种线（就绪网格未注入 → 加线不经吸附直通）、后注入
      // 就绪网格；既有线不回溯吸附，后续只验平移语义。
      seedLines();
      seedReadyGrid();
      final historyLength = container
          .read(annotationEditHistoryProvider)
          .length;
      expect(historyLength, 3);

      final outcome = editor().submitBeatShift(0.25);
      expect(outcome.applied, isTrue);
      // 差值 = 0.25 − 0 = +250ms。
      expect(timeline().segmentLines.map((l) => l.position), [
        const Duration(milliseconds: 10250),
        const Duration(milliseconds: 20250),
      ]);
      expect(timeline().halfBeatLines.map((l) => l.position), [
        // 播种值 5.25s（半拍格点）+ 250ms 平移。
        const Duration(milliseconds: 5500),
      ]);
      expect(timeline().rangeStart, const Duration(milliseconds: 250));
      // beat 段平移量写定为预览值。
      expect(container.read(beatTrackStateProvider).grid!.shift, 0.25);
      // 整次应用 = 一次标注编辑。
      expect(container.read(annotationEditHistoryProvider).length, 4);
    });

    test('再次应用：只平移「预览 − 已应用」差值', () {
      // 先播种线（就绪网格未注入 → 加线不经吸附直通）、后注入
      // 就绪网格；既有线不回溯吸附，后续只验平移语义。
      seedLines();
      seedReadyGrid();
      editor().submitBeatShift(0.25);
      final lines = timeline().segmentLines;
      editor().submitBeatShift(0.5);
      expect(
        timeline().segmentLines[0].position,
        lines[0].position + const Duration(milliseconds: 250),
      );
      expect(container.read(beatTrackStateProvider).grid!.shift, 0.5);
    });

    test('一步撤销：线位置与平移量字段同时回退', () {
      // 先播种线（就绪网格未注入 → 加线不经吸附直通）、后注入
      // 就绪网格；既有线不回溯吸附，后续只验平移语义。
      seedLines();
      seedReadyGrid();
      editor().submitBeatShift(0.25);
      expect(container.read(beatTrackStateProvider).grid!.shift, 0.25);
      editor().undo();
      expect(timeline().segmentLines.map((l) => l.position), [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      expect(timeline().halfBeatLines.map((l) => l.position), [
        // 撤销回到播种值 5.25s（半拍格点）。
        const Duration(seconds: 5, milliseconds: 250),
      ]);
      expect(container.read(beatTrackStateProvider).grid!.shift, 0);
    });

    test('越界钳制：平移差值使线越出 0..total 时按归一化钳制/剔除，不变式保持', () {
      // 先播种线（不经吸附直通）、后注入就绪网格。
      seedLines();
      seedReadyGrid(shift: 0);
      // −30s：首线钳 0，5s/10s/20s 线平移到 −25s/−20s/−10s 全部剔除。
      final outcome = editor().submitBeatShift(-30);
      expect(outcome.applied, isTrue);
      expect(timeline().rangeStart, Duration.zero);
      expect(timeline().segmentLines, isEmpty);
      expect(timeline().halfBeatLines, isEmpty);
      expect(timeline().rangeEnd, lessThanOrEqualTo(total));
      // 不变式保持。
      expect(timeline().rangeStart <= timeline().rangeEnd, isTrue);
    });

    test('应用后自动分段按平移后网格落线（首线 = 平移后网格首拍）', () {
      seedReadyGrid();
      editor().submitBeatShift(0.25);
      final shifted = container.read(beatTrackStateProvider).grid!;
      editor().submitAutoSegment(shifted, fullIntervalsPerSegment: 4);
      final t = timeline();
      expect(t.rangeStart, durationFromSeconds(0.5 + 0.25));
      expect(t.rangeEnd, durationFromSeconds(2.0 + 0.25));
    });

    test('线差值为零而平移量变化的纯字段写定是 applied 而非 no-op（边界）', () {
      // 先播种线（就绪网格未注入 → 加线不经吸附直通）、后注入
      // 就绪网格；既有线不回溯吸附，后续只验平移语义。
      seedLines();
      seedReadyGrid();
      final before = timeline();
      // 预览 − 已应用 = 0.0004s，毫秒取整为 0 → 时间线不动；平移量字段
      // 仍须写定（一次标注编辑，不入 no-op）。
      final outcome = editor().submitBeatShift(0.0004);
      expect(outcome.applied, isTrue);
      expect(timeline(), before);
      expect(
        container.read(beatTrackStateProvider).grid!.shift,
        closeTo(0.0004, 1e-9),
      );
      expect(container.read(annotationEditHistoryProvider).length, 4);
      // 一步撤销仍回退平移量字段。
      editor().undo();
      expect(container.read(beatTrackStateProvider).grid!.shift, 0);
    });

    test('同值重复应用为 EditNoop（不入史）', () {
      seedReadyGrid();
      editor().submitBeatShift(0.25);
      final historyLength = container
          .read(annotationEditHistoryProvider)
          .length;
      final outcome = editor().submitBeatShift(0.25);
      expect(outcome.applied, isFalse);
      expect(
        container.read(annotationEditHistoryProvider).length,
        historyLength,
      );
    });

    test('应用成功后预览态清空（派生网格回落已应用平移量）', () {
      seedReadyGrid();
      container.read(beatAlignPreviewOffsetProvider.notifier).set(0.25);
      editor().submitBeatShift(0.25);
      expect(container.read(beatAlignPreviewOffsetProvider), isNull);
      // 派生网格仍读平移后拍点（来自已应用平移量，非预览）。
      expect(
        container.read(beatGridProvider).beatTime(0),
        const Duration(milliseconds: 750),
      );
    });
  });

  group('编辑器 → 保存编排链路（sink diff）', () {
    test('submitBeatShift 入队含 corrections 段的段级 diff；undo 回退 0', () {
      final sink = RecordingSink();
      container.read(annotationSaveSinkStateProvider.notifier).set(sink);
      // 先播种线（就绪网格未注入 → 加线不经吸附直通）、后注入
      // 就绪网格；既有线不回溯吸附，后续只验平移语义。
      seedLines();
      seedReadyGrid();
      sink.diffs.clear();

      editor().submitBeatShift(0.25);
      final applyDiff = sink.diffs.last;
      expect(applyDiff.corrections?.shiftSeconds, 0.25);
      // 同一次 diff 的 annotations 段携带平移后的线绝对终值。
      expect(applyDiff.annotations?.segmentLines, isNotNull);
      expect(
        applyDiff.annotations?.rangeStart,
        const Duration(milliseconds: 250),
      );

      editor().undo();
      expect(sink.diffs.last.corrections?.shiftSeconds, 0);
      expect(sink.diffs.last.annotations?.rangeStart, Duration.zero);
    });
  });

  group('预览派生（单一来源，不改线不写盘）', () {
    test('预览偏移驱动 beatGridProvider 派生网格；已落盘线不动、不入史', () {
      // 先播种线（就绪网格未注入 → 加线不经吸附直通）、后注入
      // 就绪网格；既有线不回溯吸附，后续只验平移语义。
      seedLines();
      seedReadyGrid();
      final linesBefore = timeline().segmentLines;
      final historyBefore = container
          .read(annotationEditHistoryProvider)
          .length;

      container.read(beatAlignPreviewOffsetProvider.notifier).set(0.25);
      final grid = container.read(beatGridProvider);
      expect(grid.beatTime(0), const Duration(milliseconds: 750));
      expect(grid.beatIndexAt(const Duration(milliseconds: 749)), -1);

      // 非破坏：文档平移量与线均未动。
      expect(container.read(beatTrackStateProvider).grid!.shift, 0);
      expect(timeline().segmentLines, linesBefore);
      expect(
        container.read(annotationEditHistoryProvider).length,
        historyBefore,
      );
    });

    test('无预览时派生网格消费已应用平移量；清预览回落', () {
      seedReadyGrid(shift: 0.25);
      expect(
        container.read(beatGridProvider).beatTime(0),
        const Duration(milliseconds: 750),
      );
      container.read(beatAlignPreviewOffsetProvider.notifier).set(0.5);
      expect(
        container.read(beatGridProvider).beatTime(0),
        const Duration(seconds: 1),
      );
      container.read(beatAlignPreviewOffsetProvider.notifier).set(null);
      expect(
        container.read(beatGridProvider).beatTime(0),
        const Duration(milliseconds: 750),
      );
    });

    test('重置为 null 即弃预览；占位/异常态派生不受预览影响', () {
      container.read(beatAlignPreviewOffsetProvider.notifier).set(0.25);
      expect(
        container.read(beatGridProvider).beatTime(1),
        const Duration(milliseconds: 500), // 占位 120bpm 恒等
      );
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      expect(
        container.read(beatGridProvider).beatTime(1),
        const Duration(milliseconds: 500), // 异常兜底恒等
      );
    });
  });
}
