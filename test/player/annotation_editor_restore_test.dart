import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/annotation/segment_selection.dart'
    show selectedLearningSegmentRange;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatGridProvider;
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        AnnotationEditor,
        AnnotationRestoreDocument,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        annotationTimelineProvider,
        learningEmphasisProvider,
        learningMasteryProvider,
        selectedSegmentLineIndexProvider,
        transitionSegmentProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 记录型保存 sink（恢复装载不触发保存 diff 断言用）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 恢复入口模块面测试：
/// ProviderContainer 直测 [AnnotationEditor] 的两个非史非存公开入口——
/// `restoreDocument`（装载：三段越界过滤 / 恢复激活旗标 / 不入史不存不动
/// 选中）与 `clearForVideoRestore`（恢复前清：激活+临时段、幂等）。
void main() {
  const total = Duration(minutes: 1);
  const ten = Duration(seconds: 10);
  const twenty = Duration(seconds: 20);
  const thirty = Duration(seconds: 30);

  late ProviderContainer container;
  late FakePlaybackEngine engine;
  late RecordingSaveSink sink;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    sink = RecordingSaveSink();
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        annotationSaveSinkProvider.overrideWithValue(sink),
        beatGridProvider.overrideWithValue(const UniformBeatGrid(bpm: 60)),
      ],
    );
  });

  tearDown(() => container.dispose());

  AnnotationEditor editor() => container.read(annotationEditorProvider);

  AnnotationSelectionDomain domain() =>
      container.read(annotationSelectionDomainProvider);

  /// 含 2 条分段线的时间线（3 个学习段）。
  AnnotationTimeline timelineWith2Lines() => AnnotationTimeline.normalized(
        videoDuration: total,
        rangeStart: Duration.zero,
        rangeEnd: total,
        segmentLines: const [
          SegmentLine(position: ten),
          SegmentLine(position: thirty),
        ],
        halfBeatLines: const [],
      );

  group('restoreDocument：装载语义', () {
    test('时间线/重点/熟练度/激活按载荷就位；激活带恢复旗标', () {
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: timelineWith2Lines(),
          emphasizedSegments: const {0, 2},
          mastery: const {
            0: LearningMastery.mastered,
            2: LearningMastery.learning,
          },
          activatedSegments: const {1},
        ),
      );

      expect(
        container.read(annotationTimelineProvider).segmentLines.map(
              (line) => line.position,
            ),
        [ten, thirty],
      );
      expect(container.read(learningEmphasisProvider), {0, 2});
      expect(container.read(learningMasteryProvider), {
        0: LearningMastery.mastered,
        2: LearningMastery.learning,
      });
      expect(container.read(selectedLearningSegmentsProvider), {1});
      expect(
        container
            .read(selectedLearningSegmentsProvider.notifier)
            .lastWriteSilent,
        isTrue,
      );
    });

    test('重点/熟练度/激活按入参时间线派生段数越界过滤（含负段序）', () {
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: timelineWith2Lines(),
          // 3 个学习段：-1 与 ≥3 丢弃。
          emphasizedSegments: const {-1, 0, 2, 3},
          mastery: const {
            -1: LearningMastery.mastered,
            2: LearningMastery.mastered,
            5: LearningMastery.learning,
          },
          activatedSegments: const {2, 3, 9},
        ),
      );

      expect(container.read(learningEmphasisProvider), {0, 2});
      expect(container.read(learningMasteryProvider), {
        2: LearningMastery.mastered,
      });
      expect(container.read(selectedLearningSegmentsProvider), {2});
    });

    test('盘上段序不连续时收紧为含最小段序的连续块；恢复不落盘', () {
      // 3 个学习段：{0, 2} 不连续 → 只留 {0}。
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: timelineWith2Lines(),
          activatedSegments: const {2, 0},
        ),
      );
      expect(container.read(selectedLearningSegmentsProvider), {0});

      // 界内连续块 + 界外碎段：越界过滤后 {1, 2} 整块保留，循环作用域
      // 按收窄后选中就位（第 1 段段首 → 第 2 段段尾）。
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: timelineWith2Lines(),
          activatedSegments: const {1, 2, 9},
        ),
      );
      expect(container.read(selectedLearningSegmentsProvider), {1, 2});
      final range = selectedLearningSegmentRange(
        container.read(annotationTimelineProvider),
        container.read(selectedLearningSegmentsProvider),
      );
      expect(range?.start, ten);
      expect(range?.end, total);

      // 收窄后为空（全部越界）→ 无选中；恢复路径不产生保存写入。
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: timelineWith2Lines(),
          activatedSegments: const {5, 9},
        ),
      );
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(sink.saved, isEmpty);
      expect(
        container
            .read(selectedLearningSegmentsProvider.notifier)
            .lastWriteSilent,
        isFalse,
        reason: '空选中集的恢复写回不置恢复静默旗标',
      );
    });

    test('空载荷为整体 no-op：不产生半写、不触碰任何面', () {
      editor().submit(AddSegmentLine(at: twenty));
      domain().select(SegmentLineSelection(0));
      sink.saved.clear();
      final timeline = container.read(annotationTimelineProvider);
      final mastery = container.read(learningMasteryProvider);
      final emphasis = container.read(learningEmphasisProvider);
      final activations = container.read(selectedLearningSegmentsProvider);
      final historyCount = container.read(annotationEditHistoryProvider).length;

      editor().restoreDocument(const AnnotationRestoreDocument());

      expect(container.read(annotationTimelineProvider), timeline);
      expect(container.read(learningMasteryProvider), mastery);
      expect(container.read(learningEmphasisProvider), emphasis);
      expect(
        container.read(selectedLearningSegmentsProvider),
        activations,
      );
      expect(container.read(annotationEditHistoryProvider).length, historyCount);
      expect(container.read(selectedSegmentLineIndexProvider), 0);
      expect(sink.saved, isEmpty);
    });

    test('不入历史、不触发保存 diff、不动选中', () {
      editor().submit(AddSegmentLine(at: twenty));
      domain().select(SegmentLineSelection(0));
      sink.saved.clear();
      final undoCount = container.read(annotationEditHistoryProvider).length;
      final canUndo = container.read(annotationEditHistoryProvider).canUndo;

      editor().restoreDocument(
        AnnotationRestoreDocument(timeline: timelineWith2Lines()),
      );

      expect(container.read(annotationEditHistoryProvider).length, undoCount);
      expect(container.read(annotationEditHistoryProvider).canUndo, canUndo);
      expect(
        container.read(selectedSegmentLineIndexProvider),
        0,
        reason: '装载不动选中（全复位已清，恢复路径不再触碰）',
      );
      expect(sink.saved, isEmpty);
    });
  });

  group('clearForVideoRestore：恢复前清', () {
    test('清激活学习段与临时衔接段；复位恢复旗标；非史非存', () {
      editor().submit(AddSegmentLine(at: thirty));
      domain().toggleLearningSegment(0);
      expect(container.read(selectedLearningSegmentsProvider), {0});
      sink.saved.clear();
      final historyCount =
          container.read(annotationEditHistoryProvider).length;

      editor().clearForVideoRestore();

      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(
        container
            .read(selectedLearningSegmentsProvider.notifier)
            .lastWriteSilent,
        isFalse,
      );
      expect(container.read(annotationEditHistoryProvider).length,
          historyCount,);
      expect(sink.saved, isEmpty);

      // 临时衔接段同清（互斥下两者不同时非空，分步验证）。
      editor().toggleTransitionSegment(0);
      expect(container.read(transitionSegmentProvider), isNotNull);

      editor().clearForVideoRestore();
      expect(container.read(transitionSegmentProvider), isNull);
    });

    test('幂等：空态重复清不抛错、状态不变', () {
      editor().clearForVideoRestore();
      editor().clearForVideoRestore();

      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(container.read(transitionSegmentProvider), isNull);
    });
  });
}
