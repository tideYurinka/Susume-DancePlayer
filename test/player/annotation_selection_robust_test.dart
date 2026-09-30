import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/learning_segments.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        AnnotationEditor,
        annotationEditorProvider,
        annotationTimelineProvider,
        selectedHalfBeatLineIndexProvider,
        selectedSegmentLineIndexProvider,
        selectedVideoRangeBoundaryProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 首尾线选中上提 + 「其它操作即清除」+ 选中索引健壮性。
///
/// 状态 seam：首尾线选中与清除规则、插入重映射/越界无效化判定。
/// 选中维护自 store replace 簿记收进模块执行管线（位置同位重映射 /
/// 越界无效化），本文件经模块命令驱动真 store 端到端验证。
void main() {
  const total = Duration(minutes: 1);

  late ProviderContainer container;
  late AnnotationEditor editor;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(
          FakePlaybackEngine(duration: total),
        ),
      ],
    );
    editor = container.read(annotationEditorProvider);
  });

  tearDown(() => container.dispose());

  AnnotationTimeline timeline() => container.read(annotationTimelineProvider);

  /// 经模块命令播种分段线（不走 store 写缝）。
  void seedLines(List<Duration> positions) {
    for (final position in positions) {
      editor.submit(AddSegmentLine(at: position));
    }
  }

  AnnotationSelectionDomain domain() =>
      container.read(annotationSelectionDomainProvider);

  group('首尾线端标选中上提', () {
    test('默认无选中；选中/切换/异端替换可带外读取', () {
      expect(container.read(selectedVideoRangeBoundaryProvider), isNull);

      domain().select(VideoRangeBoundarySelection(VideoRangeBoundary.start));
      expect(
        container.read(selectedVideoRangeBoundaryProvider),
        VideoRangeBoundary.start,
      );

      // 同端 toggle 取消。
      domain().toggle(VideoRangeBoundarySelection(VideoRangeBoundary.start));
      expect(container.read(selectedVideoRangeBoundaryProvider), isNull);

      // 异端直接替换。
      domain().toggle(VideoRangeBoundarySelection(VideoRangeBoundary.start));
      domain().toggle(VideoRangeBoundarySelection(VideoRangeBoundary.end));
      expect(
        container.read(selectedVideoRangeBoundaryProvider),
        VideoRangeBoundary.end,
      );
    });

    test('与分段线选中互斥（单一密封点选状态，双向替换）', () {
      domain().select(SegmentLineSelection(0));
      expect(container.read(selectedVideoRangeBoundaryProvider), isNull);

      domain().select(VideoRangeBoundarySelection(VideoRangeBoundary.end));
      expect(
        container.read(annotationSelectionProvider).asSegmentLineIndex,
        isNull,
      );
      expect(
        container.read(selectedVideoRangeBoundaryProvider),
        VideoRangeBoundary.end,
      );
    });
  });

  group('半拍线选中（共用「当前选中标记」单选槽）', () {
    /// 经模块命令播种一条半拍线。
    void seedHalfBeat(Duration position) {
      editor.submit(AddHalfBeatLine(at: position));
    }

    test('toggle：同线再点取消、异线替换；带外可读选中索引', () {
      seedHalfBeat(const Duration(seconds: 5, milliseconds: 250));
      seedHalfBeat(const Duration(seconds: 15, milliseconds: 250));
      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);

      domain().toggle(HalfBeatLineSelection(0));
      expect(container.read(selectedHalfBeatLineIndexProvider), 0);

      domain().toggle(HalfBeatLineSelection(0));
      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);

      domain().toggle(HalfBeatLineSelection(0));
      domain().toggle(HalfBeatLineSelection(1));
      expect(container.read(selectedHalfBeatLineIndexProvider), 1);
    });

    test('与分段线/首尾端标选中互斥（单选槽双向替换）', () {
      seedLines([const Duration(seconds: 10)]);
      seedHalfBeat(const Duration(seconds: 5, milliseconds: 250));
      domain().toggle(HalfBeatLineSelection(0));
      expect(container.read(selectedSegmentLineIndexProvider), isNull);

      domain().select(SegmentLineSelection(0));
      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);
      expect(container.read(selectedSegmentLineIndexProvider), 0);

      domain().select(VideoRangeBoundarySelection(VideoRangeBoundary.start));
      expect(container.read(selectedSegmentLineIndexProvider), isNull);
      expect(container.read(selectedVideoRangeBoundaryProvider),
          VideoRangeBoundary.start);

      domain().toggle(HalfBeatLineSelection(0));
      expect(container.read(selectedVideoRangeBoundaryProvider), isNull);
      expect(container.read(selectedHalfBeatLineIndexProvider), 0);
    });

    test('「其它操作即清除」清除半拍线选中', () {
      seedHalfBeat(const Duration(seconds: 5, milliseconds: 250));
      domain().toggle(HalfBeatLineSelection(0));

      domain().clear();

      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);
    });

    test('索引越界带外读取为 null（线表现势校验）', () {
      seedHalfBeat(const Duration(seconds: 5, milliseconds: 250));
      domain().toggle(HalfBeatLineSelection(0));
      expect(container.read(selectedHalfBeatLineIndexProvider), 0);

      // 区间收缩剔除界外半拍线后线表变短 → 选中越界无效化。
      editor.submit(const SetVideoRange(end: Duration(seconds: 3)));
      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);
    });

    test('插线后选中半拍线按位置同位重映射（插入点右侧 +1）', () {
      // 先建 15.25s、再建 5.25s → 线表 [5.25s, 15.25s]；选中 15.25s（索引 1）。
      seedHalfBeat(const Duration(seconds: 15, milliseconds: 250));
      domain().toggle(HalfBeatLineSelection(0));

      editor.submit(AddHalfBeatLine(at: const Duration(seconds: 5, milliseconds: 250)));

      expect(container.read(selectedHalfBeatLineIndexProvider), 1,
          reason: '结构性插线后选中仍指向同一条线（15.25s）');
    });

    test('删除选中半拍线（区间收缩剔除）→ 选中无效化', () {
      seedHalfBeat(const Duration(seconds: 5, milliseconds: 250));
      domain().toggle(HalfBeatLineSelection(0));
      expect(container.read(selectedHalfBeatLineIndexProvider), 0);

      // 收缩到剔除该线：同位匹配不到 → 无效化（模块内清，非仅读取侧兜底）。
      editor.submit(const SetVideoRange(start: Duration(seconds: 8)));
      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);
    });
  });

  group('「其它操作即清除」', () {
    test('清除分段线选中', () {
      seedLines([const Duration(seconds: 10)]);
      domain().select(SegmentLineSelection(0));

      domain().clear();

      expect(container.read(annotationSelectionProvider), isNull);
    });

    test('清除首尾线选中', () {
      domain().select(VideoRangeBoundarySelection(VideoRangeBoundary.start));

      domain().clear();

      expect(container.read(annotationSelectionProvider), isNull);
    });

    test('帧步进/标记视为针对选中线：标记不清（删除后自然清）', () {
      seedLines([const Duration(seconds: 10)]);
      domain().select(SegmentLineSelection(0));

      editor.submit(ToggleSegmentFlag(index: 0));

      expect(
        container.read(selectedSegmentLineIndexProvider),
        0,
        reason: '标记是针对选中线的操作，不清选中',
      );

      // 删除针对选中线：模块删除命令整体清选中。
      editor.submit(RemoveSegmentLine(index: 0));
      expect(container.read(annotationSelectionProvider), isNull);
    });
  });

  group('选中索引健壮性（模块管线口径）', () {
    test('插线后选中线按位置同位重映射（插入点右侧 +1）', () {
      // 先建 20s、再建 10s → 线表 [10s, 20s]；选中 20s（索引 1）。
      seedLines([const Duration(seconds: 20)]);
      seedLines([const Duration(seconds: 10)]);
      domain().select(SegmentLineSelection(1));
      expect(container.read(selectedSegmentLineIndexProvider), 1);

      // 在 5s 插线 → 线表 [5s, 10s, 20s]，选中的 20s 同位重映射为索引 2。
      editor.submit(AddSegmentLine(at: const Duration(seconds: 5)));
      expect(timeline().segmentLines.length, 3);
      expect(container.read(selectedSegmentLineIndexProvider), 2);
    });

    test('区间收缩删除选中线左侧的线 → 同位重映射左移', () {
      seedLines([
        const Duration(seconds: 10),
        const Duration(seconds: 20),
        const Duration(seconds: 30),
      ]);
      domain().select(SegmentLineSelection(1));

      editor.submit(SetVideoRange(start: const Duration(seconds: 15)));

      expect(timeline().segmentLines.length, 2);
      expect(container.read(selectedSegmentLineIndexProvider), 0,
          reason: '20s 线仍在，随 10s 被删左移一位');
    });

    test('撤销内部先清选中：回放后线选中不凭空保留', () {
      seedLines([const Duration(seconds: 10)]);
      domain().select(SegmentLineSelection(0));
      expect(container.read(selectedSegmentLineIndexProvider), 0);

      editor.undo();

      expect(
        container.read(annotationSelectionProvider),
        isNull,
        reason: '模块 undo 内部先清选中（store 回放不再附带重映射）',
      );

      // 重做恢复线，但选中不凭空复活。
      editor.redo();
      expect(timeline().segmentLines.length, 1);
      expect(container.read(annotationSelectionProvider), isNull);
    });

    test('时间线变化导致学习段选中越界 → 无效化', () {
      seedLines([const Duration(seconds: 10)]);
      expect(deriveLearningSegments(timeline()).length, 2);
      domain().toggleLearningSegment(1);

      editor.undo();

      expect(container.read(annotationSelectionProvider), isNull);
    });

    test('区间收缩删线 → 越界选中无效化', () {
      seedLines([const Duration(seconds: 10), const Duration(seconds: 30)]);
      domain().select(SegmentLineSelection(1));

      editor.submit(SetVideoRange(end: const Duration(seconds: 15)));

      expect(timeline().segmentLines.length, 1);
      expect(container.read(annotationSelectionProvider), isNull);
    });

    test('仍然有效的选中在几何变化后保留（拖线等逐帧写入不清选中）', () {
      seedLines([const Duration(seconds: 10), const Duration(seconds: 30)]);
      domain().select(SegmentLineSelection(0));

      // 拖线路径：模块提交移线（同线数几何变化）不清选中。
      editor.submit(MoveSegmentLine(index: 0, to: const Duration(seconds: 15)));

      expect(container.read(selectedSegmentLineIndexProvider), 0);
    });
  });
}
