import 'package:dance_learning_app/annotation/edit_history.dart';
import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        AnnotationEditSnapshot,
        AnnotationEditor,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        learningEmphasisProvider,
        learningMasteryProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 记录型保存 sink（批量写只落一次盘的断言用）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 熟练度与重点作用于全部选中段：批量改＝一次标注编辑——
/// 一个 diff、一步撤销、一次落盘，不出现逐段中间态。
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
      ],
    );
  });

  tearDown(() => container.dispose());

  AnnotationEditor editor() => container.read(annotationEditorProvider);

  AnnotationSelectionDomain domain() =>
      container.read(annotationSelectionDomainProvider);
  EditHistory<AnnotationEditSnapshot> history() =>
      container.read(annotationEditHistoryProvider);

  /// 建出 4 个学习段（三条分段线）并清空由此产生的保存记录。
  void givenFourSegments() {
    editor().submit(AddSegmentLine(at: ten));
    editor().submit(AddSegmentLine(at: twenty));
    editor().submit(AddSegmentLine(at: thirty));
    sink.saved.clear();
  }

  /// 长按圈选段 [from] 到段 [to]（含两端）并松手提交。
  void givenDragSelection(int from, int to) {
    domain().beginDragSelect(from);
    domain().spanTo(to);
    domain().commitDragSelect();
    sink.saved.clear();
  }

  group('熟练度作用于全部选中段', () {
    test('圈选多段选一档：全部选中段同档、未选段不变', () {
      givenFourSegments();
      editor().submit(
        SetSegmentMastery(order: 3, mastery: LearningMastery.mastered),
      );
      givenDragSelection(0, 2);

      editor().submit(
        const SetSelectedSegmentsMastery(mastery: LearningMastery.learning),
      );

      expect(container.read(selectedLearningSegmentsProvider), const {0, 1, 2});
      expect(container.read(learningMasteryProvider), {
        0: LearningMastery.learning,
        1: LearningMastery.learning,
        2: LearningMastery.learning,
        3: LearningMastery.mastered,
      });
    });

    test('批量改只落一次盘：一个 diff、一次保存', () {
      givenFourSegments();
      givenDragSelection(0, 2);

      editor().submit(
        const SetSelectedSegmentsMastery(mastery: LearningMastery.learning),
      );

      expect(sink.saved, hasLength(1));
      expect(sink.saved.single.session?.mastery, {
        0: LearningMastery.learning,
        1: LearningMastery.learning,
        2: LearningMastery.learning,
      });
    });

    test('批量改算一步撤销：一步回到改前全貌，选中保留', () {
      givenFourSegments();
      editor().submit(
        SetSegmentMastery(order: 0, mastery: LearningMastery.mastered),
      );
      givenDragSelection(0, 2);

      editor().submit(
        const SetSelectedSegmentsMastery(mastery: LearningMastery.learning),
      );
      expect(history().canUndo, isTrue);
      editor().undo();

      expect(container.read(learningMasteryProvider), {
        0: LearningMastery.mastered,
      });
      expect(container.read(selectedLearningSegmentsProvider), const {0, 1, 2});
    });

    test('全部选中段已同档：EditNoop（不入史、不落盘）', () {
      givenFourSegments();
      givenDragSelection(0, 2);
      editor().submit(
        const SetSelectedSegmentsMastery(mastery: LearningMastery.learning),
      );
      final hadUndoEntry = history().canUndo;
      sink.saved.clear();

      editor().submit(
        const SetSelectedSegmentsMastery(mastery: LearningMastery.learning),
      );

      expect(history().canUndo, hadUndoEntry);
      expect(sink.saved, isEmpty);
    });

    test('无选中提交：EditNoop（不入史、不落盘）', () {
      editor().submit(
        const SetSelectedSegmentsMastery(mastery: LearningMastery.learning),
      );

      expect(history().canUndo, isFalse);
      expect(sink.saved, isEmpty);
    });
  });

  group('重点作用于全部选中段', () {
    test('不全有星：一次点亮全部选中段；一次落盘、一步撤销', () {
      givenFourSegments();
      editor().submit(ToggleSegmentEmphasis(order: 1));
      givenDragSelection(0, 2);

      editor().submit(const ToggleSelectedSegmentsEmphasis());

      expect(container.read(learningEmphasisProvider), const {0, 1, 2});
      expect(sink.saved, hasLength(1));

      editor().undo();
      expect(container.read(learningEmphasisProvider), const {1});
      expect(container.read(selectedLearningSegmentsProvider), const {0, 1, 2});
    });

    test('全部有星：一次取消全部', () {
      givenFourSegments();
      givenDragSelection(0, 2);
      editor().submit(const ToggleSelectedSegmentsEmphasis());
      sink.saved.clear();

      editor().submit(const ToggleSelectedSegmentsEmphasis());

      expect(container.read(learningEmphasisProvider), isEmpty);
      expect(sink.saved, hasLength(1));
    });

    test('无选中提交：EditNoop（不入史、不落盘）', () {
      editor().submit(const ToggleSelectedSegmentsEmphasis());

      expect(history().canUndo, isFalse);
      expect(sink.saved, isEmpty);
    });

    test('单段选中走批量入口：与改前单段表现一致', () {
      givenFourSegments();
      domain().toggleLearningSegment(2);
      sink.saved.clear();

      editor().submit(const ToggleSelectedSegmentsEmphasis());
      expect(container.read(learningEmphasisProvider), const {2});
      expect(sink.saved, hasLength(1));

      editor().submit(
        const SetSelectedSegmentsMastery(mastery: LearningMastery.familiar),
      );
      expect(container.read(learningMasteryProvider), {
        2: LearningMastery.familiar,
      });
    });
  });
}
