import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/edit_history.dart';
import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        AnnotationEditSnapshot,
        AnnotationEditor,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationTimelineProvider,
        learningEmphasisProvider,
        learningMasteryProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 标注编辑撤销/重做状态面：经标注编辑模块命令驱动真 store——store 写缝
/// 同 library 私有，undo/redo/clear 均走模块。
void main() {
  group('AnnotationEditHistory（撤销/重做，模块化迁移）', () {
    late ProviderContainer container;
    late FakePlaybackEngine engine;
    late AnnotationEditor editor;

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      container = ProviderContainer(
        overrides: [playbackEngineProvider.overrideWithValue(engine)],
      );
      editor = container.read(annotationEditorProvider);
    });

    tearDown(() => container.dispose());

    EditHistory<AnnotationEditSnapshot> history() =>
        container.read(annotationEditHistoryProvider);

    AnnotationTimeline timeline() => container.read(annotationTimelineProvider);

    /// 在 [position] 新建分段线（经模块命令，等同「分段」按钮路径）。
    void addLine(Duration position) {
      editor.submit(AddSegmentLine(at: position));
    }

    test('初始无历史：不可撤销/重做；编辑后可撤销回放', () {
      expect(history().canUndo, isFalse);
      expect(history().canRedo, isFalse);

      addLine(const Duration(seconds: 10));
      expect(timeline().segmentLines.length, 1);
      expect(history().canUndo, isTrue);

      editor.undo();
      expect(timeline().segmentLines, isEmpty);
      expect(history().canRedo, isTrue);

      editor.redo();
      expect(timeline().segmentLines.length, 1);
      expect(
        timeline().segmentLines.first.position,
        const Duration(seconds: 10),
      );
    });

    test('撤销删除分段线：恢复线并回放删除时的属性融合', () {
      addLine(const Duration(seconds: 10));
      // 段 1（10s..60s）设为掌握 + 重点，删除线融合后应消失。
      editor.submit(
        SetSegmentMastery(order: 1, mastery: LearningMastery.mastered),
      );
      editor.submit(ToggleSegmentEmphasis(order: 1));

      editor.submit(RemoveSegmentLine(index: 0));
      expect(timeline().segmentLines, isEmpty);
      expect(container.read(learningMasteryProvider), isNotEmpty);
      expect(container.read(learningEmphasisProvider), isNotEmpty);

      editor.undo();
      expect(timeline().segmentLines.length, 1);
      expect(container.read(learningMasteryProvider), const {
        1: LearningMastery.mastered,
      });
      expect(container.read(learningEmphasisProvider), const {1});

      editor.redo();
      expect(timeline().segmentLines, isEmpty);
    });

    test('熟练度/重点变更可撤销（非几何操作同样入史）', () {
      addLine(const Duration(seconds: 10));
      editor.submit(
        SetSegmentMastery(order: 0, mastery: LearningMastery.learning),
      );
      editor.submit(ToggleSegmentEmphasis(order: 0));
      expect(
        container.read(learningMasteryProvider)[0],
        LearningMastery.learning,
      );
      expect(container.read(learningEmphasisProvider), const {0});

      editor.undo();
      expect(container.read(learningEmphasisProvider), isEmpty);
      editor.undo();
      expect(
        container.read(learningMasteryProvider)[0],
        isNot(LearningMastery.learning),
      );
    });

    test('首/尾设置可撤销（含钳制语义）', () {
      editor.submit(SetVideoRange(start: const Duration(seconds: 10)));
      expect(timeline().rangeStart, const Duration(seconds: 10));

      editor.undo();
      expect(timeline().rangeStart, Duration.zero);
    });

    test('切割学习段：前后两新段均继承原段熟练度与重点，撤销/重做一致', () {
      addLine(const Duration(seconds: 30));
      // 原学习段 1（30s..60s）设为学习中 + 重点。
      editor.submit(
        SetSegmentMastery(order: 1, mastery: LearningMastery.learning),
      );
      editor.submit(ToggleSegmentEmphasis(order: 1));

      // 在段 1 内部（45s 处）新建分段线，模块级联完成属性拆分继承。
      addLine(const Duration(seconds: 45));

      // 前后两新段（新段序 1/2）均继承原段熟练度与重点。
      expect(container.read(learningMasteryProvider), const {
        1: LearningMastery.learning,
        2: LearningMastery.learning,
      });
      expect(container.read(learningEmphasisProvider), const {1, 2});

      editor.undo();
      expect(timeline().segmentLines.length, 1);
      expect(container.read(learningMasteryProvider), const {
        1: LearningMastery.learning,
      });
      expect(container.read(learningEmphasisProvider), const {1});

      editor.redo();
      expect(container.read(learningMasteryProvider), const {
        1: LearningMastery.learning,
        2: LearningMastery.learning,
      });
      expect(container.read(learningEmphasisProvider), const {1, 2});
    });

    test('一次拖动会话内的多次写入合并为单步撤销（拖动合并）', () {
      final session = editor.beginRangeDrag(VideoRangeBoundary.start);
      session.moveTo(const Duration(seconds: 10));
      session.moveTo(const Duration(seconds: 11));
      session.end();
      expect(timeline().rangeStart, const Duration(seconds: 11));
      expect(history().length, 1);

      editor.undo();
      expect(timeline().rangeStart, Duration.zero);
    });

    test('no-op 命令不入史', () {
      addLine(const Duration(seconds: 10));
      expect(history().canUndo, isTrue);

      // 同位移动：无净变化，状态与历史均未动。
      final entriesBefore = history().length;
      final outcome = editor.submit(
        MoveSegmentLine(index: 0, to: const Duration(seconds: 10)),
      );
      expect(outcome.applied, isFalse);
      expect(history().length, entriesBefore);
    });

    test('撤销几何变更按同一规则清除学习段激活（不入史）', () {
      addLine(const Duration(seconds: 10));
      container.read(annotationSelectionDomainProvider).selectOnly(1);
      expect(container.read(selectedLearningSegmentsProvider), const {1});

      editor.undo(); // 回到无分段线几何
      expect(timeline().segmentLines, isEmpty);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      // 激活清除本身不入史：下一步撤销跳过它回到更早的编辑。
      expect(history().canUndo, isFalse);
    });

    test('播放位置/倍速等非编辑操作不入史', () {
      engine.seek(const Duration(seconds: 5));
      engine.setRate(1.5);
      expect(history().canUndo, isFalse);
    });

    test('换视频全复位清空历史（resetForVideo）', () {
      addLine(const Duration(seconds: 10));
      editor.resetForVideo(engine.duration ?? Duration.zero);
      expect(history().canUndo, isFalse);
      expect(history().canRedo, isFalse);
    });

    test('历史超过 50 步丢弃最旧', () {
      for (var i = 0; i < 55; i++) {
        editor.submit(
          SetVideoRange(start: Duration(milliseconds: 100 * (i + 1))),
        );
      }
      expect(history().length, 50);
    });
  });
}
